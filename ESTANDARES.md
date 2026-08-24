# SIGCM — Estándares de trabajo

Cómo se escribe código en este sistema: la base de datos, el backend .NET y el
frontend Angular. No es un manual de estilo; es el conjunto de decisiones que ya
están tomadas y que no hay que volver a discutir en cada tarea.

> **Este documento es un capítulo, no la entrada.** El contexto del proyecto, la
> integración con SIGA y la bitácora de lo implementado en cada iteración están
> en [`CONTEXTO.md`](CONTEXTO.md). Para verificar en el aplicativo SIGA lo que el
> sistema registra, [`SIGA_APLICATIVO.md`](SIGA_APLICATIVO.md).

La regla que gobierna todo lo demás está en el título de la sección siguiente.

---

## 1. El backend es un puente

**Toda la lógica de negocio vive en la base de datos.** El backend .NET no valida
reglas, no arma SQL, no mapea entidades y no interpreta respuestas. Recibe un
JSON, completa la identidad del actor, llama a un procedimiento y devuelve lo que
ese procedimiento conteste.

Esto no es una preferencia de estilo. Es lo que permite que:

- la máquina de estados exista **una sola vez**. Si el frontend dedujera qué
  acciones ofrecer y la base decidiera cuáles permitir, serían dos máquinas de
  estados, y se separan;
- una regla nueva de la Directiva se aplique modificando un procedimiento, sin
  desplegar backend ni frontend;
- las validaciones contra los maestros de SIGA ocurran donde están los datos, en
  la misma transacción, y no a través de una copia en memoria del servidor web.

Consecuencia práctica: **si estás escribiendo un `if` de negocio en C# o en
TypeScript, está en el lugar equivocado.**

### El contrato

Una rutina invocable recibe **un parámetro** `@parametro nvarchar(max)` con JSON
y devuelve **una fila con una columna** de texto, también JSON. Es el formato
vigente en la ANIN, el mismo de `seguimiento.paListarAsignarProyectoFase`.

La respuesta **siempre** trae `estado`:

```json
{"estado":1,"IdSolicitud":"…","mensaje":"Se realizó el registro satisfactoriamente."}
{"estado":0,"codigo":51115,"mensaje":"MAESTRO_CATALOGO: el item 1 … no existe …"}
```

`estado = 1` la operación se realizó · `estado = 0` no se realizó y `mensaje`
explica por qué.

---

## 2. Base de datos — creación de procedimientos

Motor: **SQL Server 2022, compat 160**. Los scripts viven en `SIGCM_SERVER/db` y
el orden de aplicación está en su `README.md`.

### 2.1 Nomenclatura

| Objeto | Forma | Ejemplo |
|---|---|---|
| Esquema | minúscula | `cmn`, `sigcm`, `integracion` |
| Tabla y columna | PascalCase | `cmn.SolicitudItem`, `PrecioUnitario` |
| Clave primaria | `Id<Entidad>` | `IdSolicitud` |
| Procedimiento | `esquema.paVerboEntidad` | `cmn.paRegistrarSolicitud` |
| Función | `esquema.fnVerbo` | `sigcm.fnEsDiaHabil` |
| Vista | `esquema.vwEntidad` | `siga.vwCatalogoItem` |

Las claves del JSON van en **PascalCase**, igual que las columnas. Un solo
vocabulario de la pantalla a la tabla.

### 2.2 Esqueleto obligatorio

```sql
CREATE OR ALTER PROCEDURE cmn.paRegistrarSolicitud
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;        -- solo si la rutina lee SIGA
    SET DEADLOCK_PRIORITY LOW;    -- solo si la rutina lee SIGA

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51100, 'JSON incorrecto.', 1;

        -- 1. Actor
        EXEC sigcm.paResolverActor @parametro, … OUTPUT;

        -- 2. Leer el payload con OPENJSON … WITH
        -- 3. Validar
        -- 4. Escribir dentro de BEGIN TRANSACTION … COMMIT
        -- 5. sigcm.paRegistrarAuditoria

        SELECT @resultado = (
            SELECT 1 AS estado, …, N'…' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO
```

### 2.3 Las reglas que no se negocian

**La excepción no sale del procedimiento.** Se lanza internamente con `THROW`
para saltar al `CATCH`, y ahí se convierte en payload. El cliente siempre recibe
JSON válido. Por eso el puente .NET no mapea códigos de error de SqlClient.

**Toda rutina de negocio empieza por `sigcm.paResolverActor`.** Haber sido
autenticado no implica ejercer ese rol en esa unidad hoy. Es el único lugar donde
eso se comprueba.

**Prefijos de `codigo` en el mensaje**, que el frontend puede leer para decidir
cómo presentar el error:

| Prefijo | Significado | HTTP sugerido |
|---|---|---|
| `VALIDACION_*` | Dato inválido o faltante | 422 |
| `MAESTRO_*` | Ausente en los maestros de SIGA | 422 |
| `NO_ENCONTRADO` | Entidad inexistente | 404 |
| `NO_AUTORIZADO` | Rol sin permiso | 403 |
| `CONFLICTO_*` | Estado o versión incompatible | 409 |

**Bloques de numeración de error.** Se reservan por adelantado para que dos
módulos escritos en momentos distintos no colisionen:

```
51000-51099  utilitarios y resolución del actor   (F001)
51100-51199  módulo CMN                           (F002)
51200-51299  transiciones de estado y encolado    (F004)
51300-51399  integración con SIGA                 (W001)
51400-51499  módulo Requerimiento a Notificación  (F005)
51500-51599  acceso y armado de la sesión         (F006)
```

**Idempotencia.** Todo script debe poder reejecutarse sin duplicar objetos ni
datos. Se verifica con dos pasadas seguidas.

**Prohibido el tipo `json` nativo.** Es de SQL Server 2025 y producción es 2022.
El JSON se guarda como `nvarchar(max)` con `CHECK (ISJSON(...) = 1)`.

**Toda columna `varchar` de una tabla `#temporal` lleva `COLLATE
DATABASE_DEFAULT`.** Las `#temp` heredan la intercalación de `tempdb`, no la de
la base; sin esto, compararlas con las vistas de SIGA falla con el error 468. Las
variables de tabla no lo necesitan.

**Convivencia con SIGA.** Toda rutina que lea SIGA abre con `LOCK_TIMEOUT 5000` y
`DEADLOCK_PRIORITY LOW`: ante un interbloqueo, la víctima somos nosotros y nunca
SIGA. Prohibido consultar SIGA sin filtrar por `AnoEje` + `SecEjec` (+
`CentroCosto` cuando el maestro lo admite).

**Auditoría.** Toda tabla transaccional lleva `Activo` y el cuarteto
`Usuario`/`Fecha`/`Equipo`/`Programa` por operación. Además, toda rutina que
cambie algo llama a `sigcm.paRegistrarAuditoria`: el cuarteto registra quién tocó
una fila, `sigcm.EventoAuditoria` registra qué se intentó hacer y con qué
resultado, incluidos los intentos denegados.

### 2.4 Dónde va cada rutina

| Esquema | Qué contiene |
|---|---|
| `sigcm` | Núcleo transversal: actor, auditoría, maestros de SIGA, máquina de estados, documentos, plazos, sesión |
| `cmn` | Lo propio de Gestión CMN: registrar, obtener y listar solicitudes |
| `integracion` | Cola hacia SIGA, mapeo, conciliación |
| `siga` | **Solo lectura.** Sinónimos y vistas sobre la base SIGA. Aquí no se escribe nunca |
| `requerimiento`, `ejecucion`, `pago`, `ampliacion`, `resolucion` | Un esquema por módulo, declarados vacíos a propósito |

**Las acciones del flujo no son rutinas del módulo.** Firmar, observar, derivar,
validar y recepcionar son transiciones de estado y se ejecutan con
`sigcm.paEjecutarTransicion`. El módulo aporta sus datos; el motor es común.

---

## 3. Backend .NET

Solución en `Proyecto/anin_scm_back`. Tres proyectos: `anin.scm` (API),
`anin.dataAccess` (el ejecutor) y `anin.util` (utilitarios).

### 3.1 Un controlador por esquema

| Controlador | Esquema | Estado |
|---|---|---|
| `SigcmController` | `sigcm` | Maestros, transiciones, trazabilidad |
| `CmnController` | `cmn` | Anexo 3 |
| `IntegracionController` | `integracion` | Sin endpoints; la cola la mueve el worker |
| `RequerimientoController`, `EjecucionController`, `PagoController`, `AmpliacionController`, `ResolucionController` | módulos | Declarados vacíos, como sus esquemas |
| `AccesoController` | — | Ingreso local sin SSO. Apagado en producción |
| `TokenController` | — | Ingreso por SSO institucional |

Buscar de dónde sale una pantalla es buscar el esquema, no leer código.

### 3.2 Cómo se escribe un endpoint

Hereda de `ControladorPuente`, lleva `[Authorize]`, y **una sola línea de
cuerpo**. El nombre del endpoint es el verbo de la rutina sin el prefijo `pa`.

```csharp
/// <summary>
/// Bandeja del módulo. Entrada: { "Filtro": { … } }
/// </summary>
[HttpGet]
public IActionResult listarSolicitud(string ipInput)
{
    return EjecutarConActor("cmn.paListarSolicitud", ipInput);
}
```

`EjecutarConActor` es el único camino: reescribe el bloque `Actor` con la
identidad de la sesión y llama a la rutina. Las rutinas que ocurren **antes** de
tener sesión —el listado de perfiles de acceso— no pasan por aquí, y por eso
`AccesoController` no hereda de `ControladorPuente`.

**`[HttpGet]` para consultas, `[HttpPost]` para todo lo que cambie algo.** El
parámetro se llama siempre `ipInput`, que es lo que envía `MetodoService`.

### 3.3 El bloque Actor

Lo completa **el backend desde la sesión**, sobrescribiendo lo que venga del
navegador. Está centralizado en `ControladorPuente` justamente para que no pueda
olvidarse: si un solo endpoint lo armara por su cuenta y se olvidara, un cliente
podría declararse jefe de otra unidad.

```json
{ "Actor": { "Usuario": "…", "Rol": "…", "Unidad": "…",
             "Ip": "…", "Equipo": "…", "Programa": "…",
             "CorrelacionId": "…" } }
```

La terna sale del claim `Name` del JWT, que lleva el payload de sesión completo.
`CorrelacionId` es nuevo por petición: es lo que permite seguir en
`sigcm.EventoAuditoria` todo lo que provocó un solo clic.

### 3.4 Códigos HTTP

**Se devuelve 200 aunque el payload traiga `estado: 0`.** El estado del protocolo
es correcto: la rutina respondió. El estado del negocio viaja dentro, y el
frontend lo lee de un solo lugar en vez de repartirlo entre código HTTP y cuerpo.

Solo hay 500 cuando la rutina devuelve algo que no es JSON, es decir, cuando
incumple el contrato.

### 3.5 Acceso a datos

`DaProceso.ejecutarProceso(conexión, rutina, json, timeout)` es **la totalidad**
del acceso a datos. No hay ORM, no hay repositorios, no hay otra clase que abra
una conexión.

El JSON viaja como `SqlParameter`, **nunca concatenado**. La versión PostgreSQL
lo interpolaba duplicando comillas simples; eso convertía cada sustento escrito
por un usuario en una posible inyección y rompía los payloads con apóstrofes.

### 3.6 Configuración

`appsettings.json`, nodo `ConnectionStrings` y `appSettings`. Se lee con
`UT_Configuracion.AppSettings(nodo, clave)`. Las claves que empiezan con `//` son
la documentación del valor que sigue.

---

## 4. Frontend Angular

Proyecto en `Proyecto/anin_scm_front`. Angular 18, componentes **standalone**.

### 4.1 Estructura

```
src/app/
  core/            servicios transversales, guard, interceptores, sesión
    services/      metodo.service (HTTP), acceso.service, session.service, config.service
  modules/
    <modulo>/
      <modulo>.component.{ts,html,scss}   pantalla principal
      models/<modulo>.model.ts            formas que devuelven las rutinas
      services/<modulo>.service.ts        un método por endpoint
      modals/<nombre>/                    un modal por carpeta
  shared/          breadcrumb, funciones, directivas, pipes
  styles/          sistema visual global: page, tables, buttons, forms, modals
```

### 4.2 Toda llamada pasa por `MetodoService`

```typescript
// GET  → ?ipInput={json}
this.apiService.GET('api/cmn/listarSolicitud', { Filtro: filtro });
// POST → form-urlencoded, campo ipInput
this.apiService.POST('api/cmn/registrarSolicitud', { Solicitud: …, Items: … });
```

No se usa `HttpClient` directamente en un componente. El interceptor agrega el
`Bearer` y traduce el 401 en un retorno al login.

### 4.3 El servicio del módulo no tiene lógica

Un método por endpoint y nada más. **No arma el bloque `Actor`**: lo completa el
backend desde la sesión. Enviarlo desde el cliente sería, en el mejor de los
casos, inútil.

### 4.4 Los modelos llevan los nombres de la base

PascalCase, igual que las columnas. Renombrarlos a camelCase obligaría a mantener
un traductor en el medio y a leer dos vocabularios para seguir un dato de la
pantalla a la tabla.

### 4.5 La pantalla no decide qué se puede hacer: lo pregunta

Los botones de acción salen de `sigcm.paListarTransicionDisponible`, expediente
por expediente. **Está prohibido deducir la acción a partir del estado.** El
mockup lo hace porque no tiene backend; el sistema no.

Lo mismo con las validaciones: en el formulario se valida solo lo necesario para
no gastar un viaje al servidor con un formulario evidentemente incompleto
(campos vacíos, cantidades en cero). Que el ítem exista en el catálogo, que la
tarea esté activa para ese centro de costo o que la referencia exista en el
cuadro vigente **lo valida la rutina**, y no se replica: dos validaciones que
dicen lo mismo terminan diciendo cosas distintas.

### 4.6 Manejo de la respuesta

Siempre igual:

```typescript
this.servicio.hacerAlgo(datos).subscribe({
  next: (respuesta: any) => {
    if (respuesta?.estado !== 1) {
      this.funciones.mensaje('error', respuesta?.mensaje || 'No fue posible …');
      return;
    }
    // camino feliz
  },
  error: () => this.funciones.mensaje('error', 'No fue posible comunicarse con el servicio.')
});
```

El `mensaje` de la rutina se muestra tal cual: está escrito para el usuario y
dice exactamente qué falló. Sustituirlo por un texto genérico pierde información
que la base ya se tomó el trabajo de producir.

### 4.7 Estilos

El sistema visual es global (`src/styles/components`). El `.scss` del componente
lleva **solo lo propio de esa pantalla**. Clases disponibles: `page-title`,
`content-card`, `scm-table`, `status-pill--{warning,info,success,neutral}`,
`btn-app-primary`, `btn-app-secundario`, `btn-icon-outline`, `campo`,
`campo-control`, `campo-etiqueta`, `modal-fondo`, `modal-app`, `modal-cabecera`,
`modal-cuerpo`, `modal-footer`.

### 4.8 Confirmación antes de actuar

Toda acción del flujo pasa por confirmación, incluso las que no exigen
comentario: son cambios de estado con efectos fuera de la pantalla —firmas,
envíos a otra unidad, encolado hacia SIGA— y no deben depender de un clic
accidental.

---

## 5. Ambiente local: probar sin SSO

Fuera de la red de la ANIN el SSO institucional no responde, y sin identidad no
se puede recorrer un solo paso del flujo. El ingreso local resuelve eso **sin
tocar la integración con el SSO**, que sigue siendo la puerta por defecto.

### 5.1 Qué es y qué no es

`api/acceso/*` no autentica: no pide contraseña porque el SIGCM **nunca almacena
contraseñas** (la identidad la certifica el SSO). Ofrece la lista de ternas
usuario-rol-unidad vigentes y arma una sesión con la misma forma que el SSO —
mismo JWT, misma clave de `sessionStorage`, mismo cifrado— de modo que ninguna
otra pieza del sistema sabe por dónde entró el usuario.

**En producción va apagado.** Con `appSettings:acceso_local` distinto de `"true"`
los tres endpoints responden 404. La bandera se comprueba en cada llamada, no al
arrancar.

### 5.2 Puesta en marcha

```bash
sqlcmd -S "localhost\SQLSERVER25" -d DBSIGCM -E -b -I -i SIGCM_SERVER/db/90_pruebas/S900__datos_prueba.sql
```

```bash
cd Proyecto/anin_scm_back/anin.scm && dotnet run --urls http://localhost:5120
```

```bash
cd Proyecto/anin_scm_front && npm install && npx ng serve --port 4200
```

Y abrir **http://localhost:4200/acceso-local**.

### 5.3 Los perfiles de prueba

Salen de `sigcm.Usuario` y `sigcm.UsuarioRol`; para agregar más se edita
`S900__datos_prueba.sql`. Una fila por terna y no por persona: la misma cuenta
puede ejercer dos roles y son dos ingresos con acciones distintas.

| Cuenta | Rol | Unidad |
|---|---|---|
| `prueba.especialista` | Área usuaria · Especialista | UO-PRUEBA (centro de costo 01.01) |
| `prueba.jefe` | Área usuaria · Jefe | UO-PRUEBA (centro de costo 01.01) |
| `prueba.oa` | Oficina de Administración | UO-OA |
| `prueba.abastecim` | Abastecimiento · Coordinador | UO-ABAST |
| `prueba.abastecim` | Abastecimiento · Jefe | UO-ABAST |

### 5.4 Cómo se recorre el circuito

Igual que en el mockup: **cerrar sesión y cambiar de perfil en cada
transferencia**. El expediente conserva su estado en la base, así que el cambio
de perfil no pierde nada.

1. Especialista registra el Anexo 3 → `Registrar Anexo 3`
2. Especialista genera el Anexo 3 → `Por firmar Anexo 3`
3. **Jefe** firma y envía a OA → `En evaluación OA`
4. **OA** observa (vuelve al área usuaria) o deriva → `En evaluación UA`
5. **Abastecimiento** observa o valida → `Validado por Abastecimiento`
6. Abastecimiento genera, firma y envía el Anexo 4
7. **Jefe** recepciona el Anexo 4 → `Fin`

Si la bandeja aparece vacía, es porque el expediente espera a **otro** rol:
desmarcar «Solo mi bandeja» lo muestra en modo consulta, sin acciones.

### 5.5 Configuración por ambiente

Los valores que cambian entre la máquina de desarrollo y producción están
marcados **dentro de los propios archivos**, con el valor de producción
preparado al lado. No hay que recordarlos: hay que buscarlos.

```bash
grep -n "AMBIENTE" Proyecto/anin_scm_back/anin.scm/appsettings.json
```

| Archivo | Clave | Local | Producción |
|---|---|---|---|
| `anin.scm/appsettings.json` | `ConnectionStrings:cnx_sigcm` | `localhost\SQLSERVER25` | servidor de la ANIN |
| `anin.scm/appsettings.json` | `appSettings:acceso_local` | `"true"` | **`"false"`** |
| `src/assets/config/config.json` | `apiUrl` | `http://localhost:5120/` | `http://192.168.40.72:9004/` |
| `src/assets/config/config.json` | `secEjec` | `1750` | confirmar con Abastecimiento |

**Los dos archivos se marcan distinto, y no es un descuido.** `appsettings.json`
lo lee el proveedor de configuración de .NET, que ignora los comentarios `//`:
ahí la línea de producción va comentada y se descomenta al desplegar.
`config.json` lo lee el navegador con `JSON.parse`, que **rechaza** los
comentarios y dejaría la aplicación sin configuración: ahí el valor de
producción viaja como una clave gemela (`apiUrl_PRODUCCION`) que se mueve a su
lugar.

De los cuatro, el que no se puede olvidar es **`acceso_local`**: en `"true"`
cualquiera que alcance el servicio elige con qué usuario entrar, sin contraseña.

---

## 6. Al agregar un módulo nuevo

En este orden, sin saltarse pasos:

1. **Base**: tablas en su esquema (ya creado y vacío), estados y transiciones en
   la semilla `S001`, rutinas en un archivo `F00n` con su bloque de errores
   reservado. Aplicar dos veces para comprobar idempotencia.
2. **Ruta del módulo**: `UPDATE sigcm.Modulo SET Ruta = '…'` y su fila en
   `sigcm.RolModulo`. Eso, y solo eso, hace aparecer la opción en el menú de los
   roles que corresponda.
3. **Backend**: endpoints en el controlador del esquema, que ya existe. Una línea
   por endpoint.
4. **Frontend**: carpeta del módulo con su modelo, su servicio y su componente;
   ruta en `plantilla.routes.ts` con el mismo path que `sigcm.Modulo.Ruta`.

Si el paso 3 te lleva más de una línea por endpoint, o el paso 4 te obliga a
escribir una regla de negocio, el paso 1 está incompleto.
