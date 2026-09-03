# SIGCM — INIT

**Este es el documento de entrada. Si vas a tocar cualquiera de los tres
repositorios, empieza aquí.** Lo lee tanto una persona nueva como una sesión de
IA que arranca sin contexto, y por eso está escrito para que en una lectura se
sepa: qué es el sistema, qué reglas no se negocian, en qué estado está cada
módulo y qué está roto ahora mismo.

Última actualización: **2026-09-03**.

> **No es el único documento, es el índice.** Lo que aquí se resume en tres
> líneas está desarrollado en los documentos de la sección 8. Cuando algo de
> aquí y algo de allá se contradigan, gana el documento específico y **hay que
> corregir este**.

---

## 1. Qué es el sistema

SIGCM (Sistema de Gestión de Contratos Menores) cubre las contrataciones de
hasta 8 UIT de la ANIN, según la Directiva N.° 0007-2025-EF/54.01 y la Directiva
N.° 002-2026-ANIN. Cuatro módulos encadenados:

```
  Gestión CMN            Anexo 3 (solicitud) → Anexo 4 (aprobación)
        │                 escribe la modificación del cuadro en SIGA
        ▼
  Requerimiento          registro → conformidad → indagación → filtros →
  a Notificación         CCP → cuadro de adquisición → orden de servicio
        │
        ▼
  Entregables y pagos    presentación → conformidad → liquidación →
                         devengado → giro
```

No son independientes: **el expediente de pago nace de la orden de servicio**, y
**el requerimiento sólo puede pedir ítems que el CMN dejó disponibles en SIGA**.
Ese segundo enlace es el que más confusión genera y está explicado entero en
`SIGA/integracion/FLUJO_CMN_A_REQUERIMIENTO.md`.

### Los tres repositorios

| Repo | Qué es | Rama de trabajo |
|---|---|---|
| `sgcm_script` | Base de datos, semillas, integración SIGA, **toda la documentación** | `dev_work_mrz` |
| `sgcm_back` | API .NET 8. Es un puente: no tiene lógica de negocio | `dev_work_mrz` |
| `sgcm_front` | Angular 18 standalone | `dev_work_mrz` |

Se integran en `dev_back` / `dev_front` / `dev_script`, una por repo. Jack
trabaja en `jack`, `jack2`, `jack3`; nosotros en `dev_work_mrz`. **Reparto
actual:** nosotros llevamos SSO y CMN, Jack lleva Requerimiento y Pagos.

---

## 2. La regla que gobierna todo

**La lógica de negocio vive en la base de datos.** El backend es un puente que
resuelve la sesión y llama a un procedimiento; el frontend pinta lo que la base
le dice que se puede hacer. Si una regla se puede escribir en SQL, va en SQL.

De ahí salen las tres que más se violan:

- **La pantalla no decide qué se puede hacer: lo pregunta.** Los botones de
  acción salen del arreglo `Transiciones` que devuelve cada fila. Deducir la
  acción a partir del estado es reimplementar la máquina de estados en
  TypeScript y confiar en que las dos copias no se separen.
- **El backend no interpreta el JSON del negocio.** Lo pasa. La excepción son
  los correos: SMTP no corre en SQL, así que la rutina arma el sobre y el
  controlador lo envía.
- **El bloque `Actor` lo completa el backend desde la sesión**, nunca el
  navegador. Si el cliente pudiera declararlo, podría declararse jefe de otra
  unidad.

---

## 3. Reglas que no se negocian

Están todas en `ESTANDARES.md`. Éstas son las que se han roto en la práctica,
con lo que costó cada una:

### 3.1 No se agrega texto informativo que nadie pidió · `ESTANDARES.md §4.7`
En una pantalla van **campos, etiquetas y mensajes de error. Nada más.** Nada de
notas explicativas bajo un campo, subtítulos que cuentan cómo funciona el
formulario ni ayudas que describen las consecuencias de cada opción. La
explicación va en un **comentario del código**, que la lee quien la necesita.

### 3.2 Tocar el backend obliga a matar el proceso y relevantarlo
`anin_scm` sirve desde `bin/Debug/net8.0/` y **bloquea sus DLL mientras corre**,
así que `dotnet build` falla en el copiado (`MSB3021`) sin que eso parezca un
error de compilación. El síntoma es un **404 en el endpoint nuevo**, que es
idéntico a una ruta mal escrita.

```bash
powershell -NoProfile -Command "Stop-Process -Name anin_scm -Force -ErrorAction SilentlyContinue"
```
```bash
dotnet build ../sgcm_back/anin_scm.sln --nologo
```
```bash
dotnet run --project ../sgcm_back/anin.scm --launch-profile https --no-build
```

**Cómo comprobarlo, en vez de suponerlo:** un endpoint que existe y pide sesión
responde **401**; sólo una ruta inexistente responde **404**.

### 3.3 Tener el `.sql` en el repo no es tenerlo en la base
Es el mismo error que 3.2, con la base en vez del proceso. Antes de afirmar que
algo "quedó probado en desarrollo", **comprobar que el objeto existe**:

```bash
sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -Q "SELECT OBJECT_ID('pago.paListarPago')"
```

### 3.4 Las semillas se aplican por orden alfabético
`instalar.ps1` recorre `V*.sql`, `F*.sql` y `S*.sql` ordenados por nombre. Una
semilla **no puede** sembrar el permiso de una transición que crea otra semilla
posterior: revienta con `547` contra `FK_sigcm_TransicionRol_Transicion`. En una
base que arrastra filas de una instalación vieja no se nota; en una base al día
con el repositorio, sí. Si el permiso puede llegar antes que la transición,
guardar el `INSERT` con `AND EXISTS (SELECT 1 FROM sigcm.Transicion ...)`.

### 3.5 Todo cambio de flujo termina con su script de prueba
En `db/90_pruebas/`. Si no toca SIGA, que se limpie solo y sea repetible, como
`S903` o `S909`.

### 3.6 Los formatos oficiales son réplicas
El PDF de un Anexo replica el formato de la Directiva. No se le agregan campos,
filas ni leyendas porque al sistema le resulten informativos.

### 3.7 Comprobar antes de afirmar
Hay acceso de lectura a las dos bases y a los servicios. Ante una duda sobre
estados, tablas, conteos o el contrato de un servicio externo, **consultarlo**.
Los comentarios de los scripts han resultado estar desactualizados más de una
vez: el filtro `TipoPedido` y los nombres de campo de SUNAT se documentaron al
revés de lo que devuelven los datos.

---

## 4. Estado por módulo

### Gestión CMN — operativo
Flujo completo del Anexo 3 al Anexo 4, con escritura real en SIGA. La firma del
Anexo 4 aprueba la solicitud de modificación en SIGA y **deja el ítem pedible**.

- Bandeja: acciones como iconos de tamaño uniforme; lo pendiente para el perfil
  se marca y sube al inicio (`MeToca`), sin el check «Solo mi bandeja».
- El jefe del área usuaria puede **devolver al especialista** (`CMN_AU_JEFE_DEVOLVER`).
- Al firmar el Anexo 4 se avisa por correo al área usuaria (`V028` + `F013`).

### Requerimiento a Notificación — **cortado en dos puntos**
Ver sección 5. Llega hasta `REQ_CCP_SOLICITADO` y ahí se detiene.

### Entregables y pagos — operativo con datos sembrados
10 estados, 12 transiciones. La bandeja ya sigue el sistema visual y el detalle
abre en modal. El paso 1 lo da el rol `PROVEEDOR` desde el portal externo.

### Transversal
SSO institucional como única puerta (`acceso_local = "false"`), selector de
perfil, panel de accesos, firma en cadena, trazabilidad, cola hacia SIGA.

---

## 5. Defectos abiertos

Comprobados contra la base el 2026-09-03. **Ninguno es una suposición.**

| # | Qué | Dónde | Efecto |
|---|---|---|---|
| 1 | Falta la transición `REQ_REGISTRAR_CCP` | ninguna semilla la define | `REQ_CCP_SOLICITADO` no tiene salida. `paRegistrarCcp` graba la CCP pero **no mueve el estado**. Sin esto no hay cuadro, ni orden, ni pagos desde un requerimiento real. |
| 2 | Falta `REQ_NOTIFICAR_OS` | ninguna semilla la define | `F008` la ejecuta en su línea 1024; reventaría con `CONFLICTO_TRANSICION`. |
| 3 | El combo de pedidos filtra `TipoPedido = '1'` | `F001`, maestro `PEDIDO`; comentado igual en `V012` | Debe ser `'2'`. En `SIGA_1750` el tipo 2 tiene 7 523 líneas **todas** enlazadas al CMN y el tipo 1 tiene 3 261 **ninguna**. Tal como está, el combo lista pedidos de almacén y nunca muestra el que nació del CMN. |
| 4 | Numeración duplicada | dos `S006`, dos `F008` | Corren los dos porque el orden es alfabético, pero conviene renumerar. |

Los tres primeros son del módulo de Requerimiento. **Definir una transición es
fijar una regla de negocio** —qué estados une, qué roles, si encola hacia
SIGA—, así que 1 y 2 le tocan a quien lleva ese módulo.

---

## 6. Cómo levantar el ambiente

```bash
./instalar.ps1 -Servidor "192.168.40.75" -Usuario developer_anin
```

Idempotente; sin `-Recrear` respeta los datos. Con `-Recrear` **borra DBSIGCM**.
La contraseña se pasa por `SQLCMDPASSWORD`, o usa `desa.ps1`, que la pide.

```bash
./instalar.ps1 -SoloVerificar
```

- **Base de desarrollo:** `192.168.40.75` · `DBSIGCM` y `SIGA_1750`. Credenciales
  en `D:\SGCM_SIGA\CNX_BASEDATOS_DESA.txt` y en el `appsettings.json` del back.
- **Front:** `ng serve` en `http://localhost:4200`.
- **Back:** perfil `https` en `https://localhost:7182`. Ver regla 3.2.
- **SSO:** redirige a `http://192.168.20.111:9047/sso-acceso`; el front tiene que
  estar servido ahí o hay que cambiar `url_sistema` del sistema 73.

### Usuarios de prueba
Clave `123456` para todos. El recorrido completo, paso a paso y con los dos
cortes señalados, está en `D:\SGCM_SIGA\recorrido pruebas requerimiento y pagos.txt`.

| Rol | Cuenta |
|---|---|
| Área usuaria — Especialista | `46183970` |
| Área usuaria — Jefe (y Administrador) | `44687266` |
| Oficina de Administración | `46025999` |
| Abastecimiento — Jefe / Coordinador / Especialista | `09086695` / `42551460` / `45648851` |
| Contabilidad / Tesorería | `17400217` / `10712503` |
| Proveedor (locador de prueba, lo crea `S909`) | `locador.prueba` |

```bash
sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -i db/90_pruebas/S909__datos_prueba_pago.sql
```

Deja `REQ-PRU-PAGO-0001` con su orden emitida y tres expedientes de pago, dos ya
presentados. Es lo que destraba la prueba de pagos mientras siga el defecto 1.

---

## 7. Cómo trabajamos

1. **Antes de investigar, buscar.** El orden es este documento → `CONTEXTO.md` →
   `SIGA_APLICATIVO.md` → `ANALISIS_CMN.md`. Si la respuesta no está, entonces sí
   investigar, **y escribirla** donde corresponda.
2. **Editar sólo dentro de los repos.**
3. **Al cerrar una iteración, anotarla en la bitácora** de `CONTEXTO.md` §6, y
   actualizar de este documento la sección 4 (estado) y la 5 (defectos).
4. **Hay que cambiar de usuario en cada transferencia del flujo.**
5. **Lo que se descubre sobre SIGA se escribe.** Ese conocimiento no está en
   ningún manual y volver a descubrirlo cuesta días.

---

## 8. Mapa de documentos

Este archivo no los reemplaza: los ordena.

| Documento | Para qué |
|---|---|
| `ESTANDARES.md` | **Normativo.** Cómo se escribe un procedimiento, un endpoint, un componente. Léelo entero antes de escribir código nuevo. |
| `CONTEXTO.md` | Qué es el sistema, las decisiones de arquitectura y la **bitácora de iteraciones**. |
| `LEEME.md` | Los cuatro bloques del proyecto y el estado de las copias de trabajo. |
| `README.md` | La base de datos: estructura de carpetas y cómo instalar. |
| `SIGA_APLICATIVO.md` | Cómo se navega el SIGA: menús, rutas, pantallas. |
| `SIGA/integracion/ANALISIS_CMN.md` | **El CMN dentro de SIGA.** Los dos cuadros, el ciclo del ítem, el saldo. Todo verificado contra datos. |
| `SIGA/integracion/FLUJO_CMN_A_REQUERIMIENTO.md` | El paso del Anexo 4 aprobado al combo del requerimiento, con los conteos que lo prueban. |
| `Analisis/mapa-implementacion.md` · `continuidad.md` | Cronología e histórico. Pueden estar desactualizados: contrastar con la sección 4. |
| `db/README.md` · `sso/README.md` | Convenciones de las migraciones y del acceso al SSO. |

---

## 9. Bitácora corta

Lo último, para que una sesión nueva sepa dónde se quedó. El detalle va en
`CONTEXTO.md` §6.

**2026-09-03 · Observaciones de pantalla, SUNAT y puesta al día de la base**
- Siete observaciones de CMN y Requerimiento: botones uniformes en la bandeja,
  reordenado del formulario, devolución jefe → especialista, retirada del check
  «Solo mi bandeja» a favor de `MeToca`, «Derivar a» obligatorio, aviso por
  correo del Anexo 4 (`V028` + `F013`) y consulta de RUC por SUNAT.
- El proveedor pasa a tener **razón social**: el RUC salió del combo de tipo de
  documento y tiene campo propio con su buscador. Cuatro sitios componían el
  nombre por su cuenta y quedaban vacíos con una persona jurídica; se unificaron
  en `nombreProveedor()`. Respaldo por `RazonSocial` en `F011` y `F012`.
- La bandeja de pagos usaba `tabla-app`, una clase **que no existe**: por eso se
  veía sin estilos. Corregida a `table scm-table`, con píldora de estado con
  tono, celdas de dos líneas y el detalle movido a modal.
- `instalar.ps1` completo contra desarrollo: **81 scripts, 0 fallidos**. Antes
  fallaba en `S004` por la regla 3.4; corregido en `S004` y `S007`.
- `S909` siembra un requerimiento con orden emitida y entregables presentados,
  usando las rutinas reales y no `UPDATE` de estados.
- En paralelo se cerró el **ciclo de vida de las observaciones** (`V029`, `S018`,
  `sigcm.fnEstadoDestinoTransicion`): antes nacían `PENDIENTE` y no morían nunca,
  y un expediente observado una vez no podía volver a observarse.
