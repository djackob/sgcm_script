# Base de datos SIGCM — SQL Server

Segunda encarnación del SIGCM, sobre **SQL Server 2022**, en una base
`DBSIGCM` que **convive con la base SIGA en la misma instancia**.

La versión PostgreSQL vive en `../SIGCM/db` y se conserva intacta como referencia.
Ésta no es una traducción mecánica: compartir instancia cambió una decisión
estructural, y varias suposiciones del espejo resultaron ser falsas contra los
datos reales.

## Orden de aplicación

**El orden importa**: el DDL crea las tablas, la API las usa y la semilla las
puebla. Dentro de cada bloque, el orden numérico.

| # | Script | Base | Qué hace |
|---|---|---|---|
| 1 | `00_servidor/C000__preflight.sql` | master | Solo lectura, verifica el entorno |
| 2 | `00_servidor/C001__crear_dbsigcm.sql` | master | `CREATE DATABASE` con la intercalación de SIGA |
| 3 | `00_servidor/C002__acceso_lectura_siga.sql` | master | Permisos (requiere autorización) |
| 4 | `00_servidor/C003__sinonimos_siga.sql` | DBSIGCM | Apunta a la base SIGA |
| 5 | `db/00_ddl/V001__nucleo_organizacion_seguridad.sql` | DBSIGCM | Esquemas, organización, seguridad |
| 6 | `db/00_ddl/V002__nucleo_workflow_documentos.sql` | DBSIGCM | Expediente, estados, documentos |
| 7 | `db/00_ddl/V003__nucleo_observaciones_plazos_auditoria.sql` | DBSIGCM | Observaciones, plazos, auditoría |
| 8 | `db/00_ddl/V004__maestros_siga_vistas.sql` | DBSIGCM | Las 11 vistas sobre SIGA |
| 9 | `db/00_ddl/V005__cmn_solicitud_item_periodo.sql` | DBSIGCM | Módulo CMN |
| 10 | `db/00_ddl/V006__integracion_outbox_mapeo.sql` | DBSIGCM | Cola hacia SIGA |
| 11 | `db/00_ddl/V007__modulo_ruta.sql` | DBSIGCM | Ruta e icono por módulo, para el menú |
| 12 | `db/00_ddl/V008__documento_archivo.sql` | DBSIGCM | Columnas de archivo del documento |
| 13 | `db/00_ddl/V009__requerimiento_registro.sql` | DBSIGCM | Módulo Requerimiento, núcleo |
| 13b | `db/00_ddl/V010__correlativo.sql` | DBSIGCM | Correlativos del código de expediente |
| 13c | `db/00_ddl/V011__cmn_paquete_anexo4.sql` | DBSIGCM | Anexo 4 múltiple y firma en cadena |
| 13d | `db/00_ddl/V012__siga_vw_pedido.sql` | DBSIGCM | Vista `siga.vwPedido` (combo REQ-02) |
| 13e | `db/00_ddl/V013__siga_vw_pedido_item.sql` | DBSIGCM | Vista `siga.vwPedidoItem` (lineas del pedido SIGA) |
| 13f | `db/00_ddl/V014__siga_vw_pedido_fuente_programa.sql` | DBSIGCM | `vwPedido`: FF/RR desde `fuente_fto` y programa de la meta |
| 13g | `db/00_ddl/V015__cmn_tipificacion_solicitud.sql` | DBSIGCM | Solicitud ordinaria / extraordinaria con justificación |
| 13h | `db/00_ddl/V016__requerimiento_locacion_ccp_os.sql` | DBSIGCM | Filtros de idoneidad, CCP y orden de servicio |
| 13i | `db/00_ddl/V017__integracion_orden_servicio.sql` | DBSIGCM | Outbox CREAR_ORDEN_SERVICIO y vista cuadro/pedido |
| 13j | `db/00_ddl/V018__filtro_idoneidad_catalogo.sql` | DBSIGCM | Catálogo RNSSC, REDAM, RPS_TCP, REDJUM, debida diligencia |
| 13k | `db/00_ddl/V019__filtro_evidencia_memo_ccp.sql` | DBSIGCM | Evidencias PDF por filtro y cuerpo del memorando CCP |
| 13l | `db/00_ddl/V020__ccp_carga_presupuestaria.sql` | DBSIGCM | Carga CCP / previsión presupuestal |
| 13m | `db/00_ddl/V021__tipo_documento_ccp.sql` | DBSIGCM | Tipo de documento CCP |
| 13n | `db/00_ddl/V022__vw_cuadro_pedido_siga.sql` | DBSIGCM | Vista cuadro de adquisición ↔ pedido |
| 13o | `db/00_ddl/V023__crear_cuadro_adquisicion.sql` | DBSIGCM | Outbox `CREAR_CUADRO_ADQUISICION` |
| 22b | `db/20_seed/S005__requerimiento_filtros_jerarquia.sql` | DBSIGCM | Jerarquía filtros: especialista → coordinador → jefe → OPP |
| 22c | `db/20_seed/S006__opp_oa_solo_jefe.sql` | DBSIGCM | CCP solo OPP; OA/OPP sin jerarquía interna |
| 14 | `db/10_api/F001__utilitarios_contrato.sql` | DBSIGCM | Actor, auditoría, correlativo, maestros |
| 15 | `db/10_api/F002__cmn_solicitud.sql` | DBSIGCM | CMN: registrar, obtener, listar |
| 16 | `db/10_api/F003__documentos_firmas.sql` | DBSIGCM | Documentos, firmas, versionado |
| 17 | `db/10_api/F004__transicion_encolado.sql` | DBSIGCM | Motor de estados y trazabilidad |
| 18 | `db/10_api/F005__requerimiento.sql` | DBSIGCM | Requerimiento: registrar, obtener, listar |
| 19 | `db/10_api/F006__acceso_sesion.sql` | DBSIGCM | Acceso y armado de la sesión |
| 19b | `db/10_api/F007__cmn_anexo4.sql` | DBSIGCM | Anexo 4: generar, obtener, anular |
| 19c | `db/10_api/F008__requerimiento_locacion.sql` | DBSIGCM | Locación: filtros, CCP, O/S, sobre de correo |
| 20 | `db/15_siga/W001__escritor_cuadro_modificado.sql` | DBSIGCM | Escritor SIGA (CMN) |
| 20b | `db/15_siga/W002__escritor_orden_servicio.sql` | DBSIGCM | Escritor SIGA (orden de servicio) |
| 20c | `db/15_siga/W003__escritor_cuadro_adquisicion.sql` | DBSIGCM | Escritor SIGA (cuadro de adquisición + copia TDR) |
| 21 | `db/20_seed/S000__numeros.sql` | DBSIGCM | Tabla de números |
| 22 | `db/20_seed/S001__roles_estados_transiciones.sql` | DBSIGCM | Configuración de CMN |
| 23 | `db/20_seed/S002__plazos_directiva.sql` | DBSIGCM | Plazos de la Directiva |
| 24 | `db/20_seed/S003__requerimiento_estados.sql` | DBSIGCM | Configuración de Requerimiento (AU + OA/DEC) |
| 25 | `db/20_seed/S004__requerimiento_locacion_post_au.sql` | DBSIGCM | Filtros, CCP, cuadro, orden de servicio y plazos de la ERF |
| 26 | `db/20_seed/S007__ccp_carga_dec.sql` | DBSIGCM | Carga de CCP por DEC |

Pendiente: indagación competitiva (Anexo 8) para bienes y servicios. La locación por invitación directa no la usa.

El instalador descubre los scripts por patrón (`V*`, `F*`, `W*`, `S*`) y los
aplica ordenados por nombre, así que agregar uno nuevo no obliga a tocar
`instalar.ps1`; sí conviene anotarlo en esta tabla.

### Pruebas

| Script | Qué prueba | Escribe en SIGA | Deja rastro |
|---|---|---|---|
| `S900__datos_prueba.sql` | Usuarios y unidades ficticios | no | sí, es la semilla |
| `S901__prueba_e2e_cmn_siga.sql` | Flujo completo contra SIGA, los dos momentos de escritura | **sí** | sí, a propósito |
| `S902__continuar_anexo4.sql` | Continúa un expediente detenido en `CMN_A3_APROBADO` | **sí** | sí |
| `S903__prueba_anexo4_multiple.sql` | Anexo 4 que agrupa Anexos 3 de **dos áreas usuarias** | no | no, se limpia sola |
| `S904__casos_anexo4_multiple.sql` | Deja 4 Anexos 3 en borrador, uno por área usuaria real, para recorrer el flujo a mano desde la pantalla | no | sí, esa es la idea |
| `S905__limpiar_expedientes_cmn.sql` | **Borra** todos los expedientes CMN de DBSIGCM y reinicia el correlativo. Exige `-v confirmar="SI"` | no | sí: deja la base sin expedientes |
| `S906__prueba_edicion_cmn.sql` | Corregir y anular un Anexo 3: quién puede, desde qué estado, y que no duplique el expediente | no | no, se limpia sola |

`S903` es la que conviene correr después de tocar el flujo: no toca SIGA, se
limpia al terminar y es repetible. Comprueba la firma en cadena, la regla del
viernes, que un Anexo 3 no entre en dos Anexos 4, el registro múltiple de
aprobaciones y que cada expediente vuelva a su propia área usuaria.

### Scripts fuera de la serie

No son migraciones: no cambian el modelo y se ejecutan cuando hacen falta.

| Script | Base | Qué hace |
|---|---|---|
| `00_servidor/C000B__diagnostico_motor.sql` | master | Mide versión, intercalación y las 44 construcciones T-SQL que usa el proyecto. Solo lectura. Se corre contra un servidor **antes** de instalar en él |
| `00_servidor/C001R__recrear_dbsigcm.sql` | master | **Borra** `DBSIGCM` y la recrea igual a desarrollo. Solo entorno local. Exige `-v recrear="SI"` |
| `00_servidor/C002__acceso_lectura_siga.sql` | master + SIGA | Permisos dentro de SIGA. Requiere autorización del propietario |
| `00_servidor/C900__inventario.sql` | DBSIGCM | Verificación posterior: parámetros de la base, inventario, sinónimos que resuelven, semilla, ausencia del tipo `json` nativo. Falla si algo no cuadra |

`C000B` corre en cualquier motor desde 2012: sus pruebas van en SQL dinámico
dentro de `TRY/CATCH`, así que ninguna sintaxis nueva rompe el lote. Lleva una
fila de control (`ALTER TABLE ADD IF NOT EXISTS`, que no existe en ningún T-SQL)
que debe salir `NO` siempre; si sale `SI`, el mecanismo está mintiendo.

### Levantar un ambiente (la forma recomendada)

`../instalar.ps1` aplica toda la serie en orden, aborta al primer error y deja
bitácora con fecha en `../_bitacora/`. Antes de conectarse a nada revisa el
código fuente contra la línea base 2022:

```powershell
.\instalar.ps1
```

Rearmar la base desde cero — **borra `DBSIGCM`** y la recrea con la
intercalación, el compat y el RCSI de desarrollo:

```powershell
.\instalar.ps1 -Recrear -ConDatosPrueba
```

Solo revisar el código, sin tocar ninguna base (sirve para un hook de
pre-commit o para CI):

```powershell
.\instalar.ps1 -SoloVerificar
```

Contra otro servidor, con autenticación SQL:

```powershell
.\instalar.ps1 -Servidor "192.168.40.71" -Usuario developer_anin
```

`C002` no forma parte de la serie: concede permisos dentro de la base SIGA,
requiere autorización del propietario y en local no hace falta.

Los `usp_ext_*.sql` de `SIGA/integracion/` **sí** van en el golpe: `instalar.ps1`
los aplica sobre `SIGA_1750` **antes** de C003 y de las migraciones de DBSIGCM.
No recrean SIGA (esa base es del MEF); solo (re)crean los procedimientos de
integración. Tras restaurar un backup limpio de SIGA basta el mismo
`.\instalar.ps1 -Recrear -ConDatosPrueba`.

A mano, si hiciera falta, la serie es la de la tabla de arriba:

```bash
for f in db/00_ddl/V*.sql db/10_api/F*.sql db/15_siga/W*.sql db/20_seed/S*.sql; do sqlcmd -S "$SERVIDOR" -d DBSIGCM -E -b -I -i "$f" || break; done
```

El orden alfabético de los comodines coincide con el de la tabla; por eso los
archivos van numerados. `-b` aborta al primer error y `-I` fija
`QUOTED_IDENTIFIER ON`, que los índices filtrados exigen.

**`db/90_pruebas/S900__datos_prueba.sql` NO va en QA ni en producción**: crea
cuatro usuarios ficticios para recorrer el flujo sin SSO. Instálalo solo en la
máquina de desarrollo, junto con `appSettings:acceso_local` en `"true"`.

Todos los archivos son **idempotentes**: reejecutar la serie completa no duplica
objetos ni datos. Verificado con dos pasadas seguidas de cada uno.

```bash
sqlcmd -S "localhost\SQLSERVER25" -d DBSIGCM -E -b -i db/00_ddl/V001__nucleo_organizacion_seguridad.sql
```

`-b` hace que `sqlcmd` devuelva código de error distinto de cero si el script
falla, que es el equivalente de `psql -v ON_ERROR_STOP=1`.

Migraciones previstas con **DbUp**, que es .NET y vive en la misma solución que
el backend.

## Esquemas

La versión PostgreSQL usaba **trece esquemas de tres letras** (`org`, `seg`,
`cat`, `exp`, `wf`, `doc`, `obs`, `plz`, `aud`, `mst`, `itg`, `api`) con una o
dos tablas cada uno. Eso no organiza: fragmenta, y obliga a un diccionario para
leer el modelo. Aquí se consolidan según la única división que sí es real —la
**autoridad sobre el dato**— más un esquema por módulo del sistema.

| Esquema | Contenido | Autoridad | Tablas |
|---|---|---|---|
| `sigcm` | Núcleo transversal: organización, seguridad, catálogos, expediente, máquina de estados, documentos, firmas, observaciones, plazos, auditoría | SIGCM | 23 |
| `integracion` | Outbox, mapeo de identificadores, conciliación | Compartida | 3 |
| `siga` | **Sinónimos y vistas sobre la base SIGA** | **SIGA** — solo lectura | 0 (14 sinónimos, 10 vistas) |
| `cmn` | Módulo Gestión CMN | SIGCM | 3 |
| `requerimiento` | Requerimiento a Notificación | SIGCM | vacío |
| `ejecucion` | Ejecución | SIGCM | vacío |
| `pago` | Pago | SIGCM | vacío |
| `ampliacion` | Modificación-Ampliación | SIGCM | vacío |
| `resolucion` | Resolución | SIGCM | vacío |
| `dbo` | `Numero` (tabla de números) | — | 1 |

Los cinco esquemas de módulo se crean **vacíos a propósito**: declaran la
estructura del sistema desde el principio, de modo que cada módulo futuro
aterrice en su sitio sin discusión. Corresponden uno a uno con las filas de
`sigcm.Modulo` que siembra `S001`.

En PostgreSQL la regla era *"nada del anillo institucional escribe en `mst`"*.
Aquí la impone el motor: `siga` son vistas y sinónimos de otra base, y nadie
tiene permiso de escritura sobre ella.

## Las seis diferencias que importan frente a PostgreSQL

### 1. Los maestros son vistas, no espejo (y los esquemas se consolidaron)

El esquema de maestros pasó de ocho tablas más una bitácora de sincronización a **diez vistas**.
Los maestros de SIGA suman unas 17 000 filas; replicarlas dentro del mismo
servidor no compra nada y cuesta un sincronizador que hay que escribir y operar.

Desaparecen `mst.sincronizacion` y `itg.pa_sincronizar_maestros` de la versión PostgreSQL.

Dos vistas son nuevas y no tienen equivalente en PostgreSQL:
`siga.vwCuadroEtapaCentro` y `siga.vwParametroEjecutoraAnio`. Cubren los hallazgos
5.3 y 5.4 del mapa funcional, que ninguna propuesta anterior consideraba: la fase
no debe fijarse por constante, y `SIG_CUADRO_X_CENTRO` gobierna la etapa de cada
área usuaria.

### 2. La intercalación se descubre, no se cablea

`C001` lee la intercalación real de la base SIGA y crea `DBSIGCM` con esa misma.
Además, cada columna de texto de las vistas `siga` sale con `COLLATE
DATABASE_DEFAULT`. Sin lo primero, todo join cruzado falla con el error 468; lo
segundo es la red por si en producción las dos bases no coinciden.

Regla derivada: **toda columna `varchar` de una tabla `#temporal` debe declararse
`COLLATE DATABASE_DEFAULT`**, porque las `#temp` heredan la intercalación de
`tempdb`, no la de la base actual. Las variables de tabla sí heredan la de la
base y no necesitan nada.

### 3. Línea base SQL Server 2022, aunque en local haya 2025

Tres motores distintos, y el más nuevo es el del programador — que es el orden
peligroso, porque lo que aquí pasa allá puede fallar:

| Entorno | Motor | SO | Collation servidor |
|---|---|---|---|
| Equipo local | 2025 — 17.0.1000.7 | Windows | `SQL_Latin1_General_CP1_CI_AS` |
| Desarrollo ANIN (`192.168.40.71`) | **2022 — 16.0.4262.2 CU25** | Linux (Rocky 10.2) | `Modern_Spanish_CI_AS` |
| Producción ANIN | 2022 (confirmado por el equipo) | — | por medir |

Medido el 2026-08-18 con `00_servidor/C000B__diagnostico_motor.sql`, que prueba
una por una las 44 construcciones T-SQL que usa el proyecto contra el motor
real. Resultado en desarrollo: **cero incompatibilidades**. Todo lo que los
scripts usan —`CREATE OR ALTER`, `STRING_AGG`, `CONCAT_WS`, `TRIM`,
`GENERATE_SERIES`, `JSON_OBJECT`, `OPENJSON`, `FOR JSON`— está disponible ahí.

La base se crea y se prueba en **compat 160**, que es lo que impide que el motor
local acepte construcciones que desarrollo rechazaría.

Quedan prohibidas las construcciones de 2025. La principal es el **tipo `json`
nativo**: el JSON se guarda como `nvarchar(max)` con `CHECK (ISJSON(...) = 1)`,
que además evita la trampa de `GetString(0)` sobre un tipo especializado.
También quedan fuera `REGEXP_LIKE` y familia, `JSON_ARRAYAGG`/`JSON_OBJECTAGG`,
las funciones de vector y las de IA.

Esto **no depende de la disciplina de nadie**: `instalar.ps1` revisa el código
fuente antes de tocar la base y aborta si encuentra alguna. El compat 160 es la
segunda red, y `C900__inventario.sql` la tercera —verifica que ninguna columna
haya quedado con el tipo `json` nativo.

`STRING_AGG`, `TRIM`, `CONCAT_WS`, `GENERATE_SERIES` y `JSON_OBJECT` sí están
disponibles y se usan. `dbo.Numero` (`S000`) se conserva porque se lee mejor que
`GENERATE_SERIES` en la materialización de los 48 periodos, no porque haga falta.

> Antes de esa confirmación la línea base era 2016/compat 130, por precaución.
> `C000__preflight.sql` valida el mínimo y aborta si no se cumple.

### 4. Las rutinas son procedimientos, no funciones

SQL Server prohíbe DML dentro de una función, y tampoco deja lanzar errores desde
ellas. Todo lo que en PostgreSQL era `cmn.pa_registrar_solicitud(jsonb) → text`
pasa a ser un **procedimiento** que recibe `@parametro nvarchar(max)` y devuelve
**una fila y una columna**.

Nomenclatura de la ANIN: esquemas en minúscula, tablas y columnas en
`PascalCase` con clave primaria `Id<Entidad>`, rutinas `esquema.paVerboEntidad`,
vistas `esquema.vwEntidad`.

### 5. Auditoría: el cuarteto de la casa, más `sigcm.EventoAuditoria`

Toda tabla transaccional lleva `Activo` bit y el cuarteto por operación —
`Usuario`/`Fecha`/`Equipo`/`Programa` con sufijo `CreacionAuditoria`,
`ModificacionAuditoria` y `EliminacionAuditoria` — igual que el resto de los
sistemas de la ANIN. El usuario va como texto, no como FK: la auditoría debe
sobrevivir a la baja de una persona.

Los catálogos puros (`Modulo`, `TipoContratacion`, `Rol`, `Estado`, `Transicion`)
no llevan cuarteto: son configuración que se despliega con la semilla, no dato
capturado por un usuario. Sí llevan `Activo`.

`sigcm.EventoAuditoria` se conserva y **no es redundante**: el cuarteto registra quién tocó
una fila; `sigcm.EventoAuditoria` registra qué se intentó hacer, con qué resultado y bajo
qué correlación — incluidos los intentos denegados, que nunca llegan a modificar
ninguna fila. Por eso tampoco lleva `Activo` ni cuarteto: un evento de auditoría
no se modifica, no se anula y no se borra.

En `sigcm.Expediente`, `Anulado` convive con `Activo` y tampoco es redundante:
`Activo = 0` es baja lógica de mantenimiento; `Anulado = 1` es un estado del
trámite, con motivo obligatorio, que sigue siendo visible y auditable.

### 6. Los arreglos se volvieron tablas hijas

`wf.transicion.roles_permitidos` y `cat.tipo_documento.firmas_requeridas` de PostgreSQL eran
`varchar(40)[]`. Ahora son `sigcm.TransicionRol` y `sigcm.TipoDocumentoFirma`, con
clave foránea real contra `sigcm.Rol`. Una cadena delimitada habría sido más corta
pero no puede impedir que se escriba un rol inexistente.

## Contrato con el backend .NET

Una rutina invocable = **un parámetro JSON, una fila con una columna de texto**.

```csharp
// Microsoft.Data.SqlClient. El JSON va como parámetro, nunca concatenado.
using var cmd = new SqlCommand("cmn.paRegistrarSolicitud", cn)
{
    CommandType = CommandType.StoredProcedure
};
cmd.Parameters.Add("@parametro", SqlDbType.NVarChar, -1).Value = json;
var payload = (string)cmd.ExecuteScalar();
```

Se devuelve `nvarchar(max)` y no el tipo `json` nativo por dos razones: es de
SQL Server 2025 y viola la línea base, y repite la misma trampa que hizo evitar
`jsonb` de salida en PostgreSQL — `GetString(0)` sobre una columna de tipo
especializado puede fallar según el proveedor.

### Sobre de entrada

```json
{
  "actor":     { "usuario": "…", "rol": "…", "unidad": "…",
                 "ip": "…", "correlacion_id": "…" },
  "solicitud": { … },
  "items":     [ … ]
}
```

El bloque `actor` lo completa **el backend desde la sesión SSO**, sobrescribiendo
lo que venga del navegador. `sigcm.paResolverActor` valida que la terna
usuario-rol-unidad esté vigente hoy: haber sido autenticado no implica ejercer
ese rol.

### Errores: la excepción no sale del procedimiento

Se adopta el formato vigente en la ANIN. El error se **lanza internamente** con
`THROW` para saltar al `CATCH`, y allí se **convierte en payload**:

```sql
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT @resultado = (
        SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, @codigo AS codigo, @campo AS campo
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    SELECT @resultado;
END CATCH
```

De modo que el cliente siempre recibe una fila con JSON válido:

```json
{"estado":1,"IdSolicitud":"…","mensaje":"Se realizó el registro satisfactoriamente."}
{"estado":0,"codigo":"MAESTRO_CATALOGO","campo":"items.ItemBien","mensaje":"El item … no existe …"}
```

`SET XACT_ABORT ON` más el `ROLLBACK` del `CATCH` garantizan que un error no deje
datos a medio escribir. Es el mismo efecto que buscaba `RAISE EXCEPTION` en
PostgreSQL, pero sin que la excepción cruce la frontera del procedimiento.

| Prefijo de `codigo` | Significado | HTTP sugerido |
|---|---|---|
| `VALIDACION_*` | Dato inválido o faltante | 422 |
| `MAESTRO_*` | Ausente en los maestros de SIGA | 422 |
| `NO_ENCONTRADO` | Entidad inexistente | 404 |
| `NO_AUTORIZADO` | Rol sin permiso | 403 |
| `CONFLICTO_*` | Estado o versión incompatible | 409 |

**Consecuencia para el backend:** el mapeo de `SqlState == "P0001"` que hoy tiene
`DaProceso` **no hace falta**. Los errores de negocio llegan como payload normal;
solo los fallos de infraestructura (conexión caída, timeout) siguen siendo
excepciones de SqlClient. Esto es más simple que lo previsto en el plan, que
esperaba propagar `THROW 50001` hasta el cliente.

## Convivencia con SIGA: medidas que aquí no se notan

La base SIGA tiene RCSI desactivado. En la copia local no hay nadie más
conectado, así que nada de esto cambia el comportamiento; en producción sí.

- `DBSIGCM` se crea con `READ_COMMITTED_SNAPSHOT ON`.
- Las seis vistas de maestros cuasi estáticos llevan `WITH (NOLOCK)`. Las que
  leen datos que sí se mueven —techo, cuadro vigente, etapa por centro— no.
- Toda rutina que lea SIGA abre con `SET LOCK_TIMEOUT 5000` y
  `SET DEADLOCK_PRIORITY LOW`: ante un interbloqueo, la víctima somos nosotros y
  nunca SIGA.
- Prohibido consultar SIGA sin filtro por `ANO_EJE` + `SEC_EJEC` + `CENTRO_COSTO`.

Ver `../docs/entornos.md` y `../docs/convivencia-siga.md`.

## Estado de verificación

Reconstrucción completa el 2026-08-18 sobre `localhost\SQLSERVER25` contra
`SIGA_1750`, con `instalar.ps1 -Recrear -ConDatosPrueba`:

| Prueba | Resultado |
|---|---|
| Verificación de fuentes contra la línea base 2022 | OK — 27 archivos, 0 construcciones de 2025 |
| Serie completa desde base borrada | OK — 24 scripts, 0 fallos |
| Segunda pasada sin `-Recrear` (idempotencia) | OK — inventario y conteos sin variación |
| Inventario `C900` | 34 tablas, 14 vistas, 18 procedimientos, 2 funciones, 14 sinónimos, 2 secuencias, 9 esquemas |
| Semilla | `Numero` 1024, `Estado` 23, `Transicion` 31, `Rol` 16, `Modulo` 6 |
| Los 14 sinónimos resuelven | OK |
| Columnas con tipo `json` nativo | 0 |
| Prueba funcional `t1.sql` | OK — contrato JSON correcto en los tres casos y en `fnSumarDiasHabiles` |

Verificación anterior, misma instancia:

| Prueba | Resultado |
|---|---|
| Preflight del entorno | OK — 0 errores, 5 avisos esperados |
| `CREATE DATABASE` con intercalación descubierta | OK — `Modern_Spanish_CI_AS`, compat 160, RCSI activo |
| Inventario tras la reconstrucción | 30 tablas, 13 vistas, 14 sinónimos, 1 secuencia |
| Join cruzado con variable de tabla y con `#temp` | OK — sin error 468 |
| Aplicación limpia de las 13 migraciones | OK |
| Reejecución completa (idempotencia) | OK, conteos sin variación |
| 14 sinónimos resuelven | OK |
| Conteo de cada vista frente a su tabla origen | OK, coincide |
| `vwCuadroVigenteItem` | 25 688 ítems desde 102 752 filas de detalle — exactamente 4 filas por ítem |
| Pivote del ítem 3194 | OK — `sec_cua_mod_sal` 22765, INCLUSIÓN/NUEVO, 4 años |
| Tiempo: un ítem del cuadro | 7 ms |
| Tiempo: los 4 175 ítems de un centro de costo | 17 ms |
| Tiempo: búsqueda por texto en el catálogo | 28 ms |

## Pendiente

- `F003` documentos, firmas e invalidación por versión.
- La escritura real a SIGA. `W001` corre solo en modo simulación (ADR-003), y el
  procedimiento homologado *dentro* de SIGA es un entregable aparte que requiere
  autorización formal del propietario.
- Roles de base de datos y permisos mínimos por esquema.
- El techo multianual: ver la nota extensa en `siga.vwTechoPresupuesto`.
  `PPTO_ANNO_01..03` está en cero en las 2 375 filas de 2026, así que **el techo
  de los años 1 a 3 no está donde el espejo suponía y sigue sin localizarse**.
  Hoy el control de techo solo puede hacerse sobre el año base.
