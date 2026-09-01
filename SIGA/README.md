# SIGA — qué se ejecuta aquí y qué no

Esta carpeta contiene lo que toca la base **`SIGA_1750`**, que **no es nuestra**:
es del producto SIGA, del MEF. Todo lo de aquí se trata con esa regla en mente.

> **Sólo estos archivos de esta carpeta se ejecutan en `SIGA_1750`**, y
> requieren autorización del propietario en entornos compartidos. En local los
> aplica `../instalar.ps1` en el mismo golpe que DBSIGCM. El resto de `.sql`
> son referencia, descubrimiento o pruebas de homologación: ejecutarlos puede
> escribir datos de prueba.

---

## Tabla de decisión

| Archivo | ¿Se ejecuta? | Dónde | Qué es |
|---|---|---|---|
| `integracion/usp_ext_incluir_item_cmn.sql` | **SÍ** (`instalar.ps1`) | `SIGA_1750` | Inclusión CMN (ruta de modificación) |
| `integracion/usp_ext_excluir_item_cmn.sql` | **SÍ** (`instalar.ps1`) | `SIGA_1750` | Exclusión CMN |
| `integracion/usp_ext_aprobar_solicitud_cmn.sql` | **SÍ** (`instalar.ps1`) | `SIGA_1750` | Aprobación / consolidación de la solicitud CMN |
| `integracion/usp_ext_crear_cuadro_adquisicion_desde_pedido.sql` | **SÍ** (`instalar.ps1`) | `SIGA_1750` | Autoriza el pedido de servicio y genera el cuadro |
| `integracion/usp_ext_crear_orden_servicio_desde_cuadro.sql` | **SÍ** (`instalar.ps1`) | `SIGA_1750` | Emite la O/S pendiente desde el cuadro |
| `integracion/usp_ext_registrar_item_cmn.sql` | **SÍ** (`instalar.ps1`) | `SIGA_1750` | Inclusión por ruta de formulación (legado; W001 ya no lo llama) |
| `integracion/usp_ext_registrar_requerimiento.sql` | **SÍ** (`instalar.ps1`) | `SIGA_1750` | Alta de pedido SIGA desde CMN (disponible, no lo usa el worker de locación) |
| `integracion/descubrimiento/01_perfilado_cmn.sql` | Opcional | `SIGA_1750` | **Sólo lectura.** |
| `integracion/ESQUEMA_dbo.sql` | **NO. NUNCA** | — | Volcado de Navicat. Documentación, no un script para correr |
| `integracion/solo_desarrollo/*.sql` | **NO. Nunca en producción** | copia local | Usuarios, menús, privilegios y claves de SIGA (`GLUNA`, `IRIVERA`, `HBOJORQUEZ`). Exigen `-v entorno="DESARROLLO"` |

Los scripts que **solo mueven data de un expediente concreto** de esta máquina
(`copiar_tdr_cuadro_3562.sql`, `preparar_prueba_cuadro_pedido_007662.sql`,
`homologar_cuadro_adquisicion_pedido_001067.sql` y similares) **no van a git**:
están en `.gitignore`. En el ANIN el TDR y el cuadro salen del flujo
(`Generar cuadro` / `Emitir O/S` + `usp_ext_*`).

`entregables/` son los manuales en Word y PDF, más sus imágenes. No hay nada que
ejecutar ahí.

---

## Los procedimientos que se instalan

```
integracion/usp_ext_*.sql
```

`instalar.ps1` los descubre por nombre y los aplica **todos** sobre `SIGA_1750`
antes de crear los sinónimos de DBSIGCM. Son `DROP`+`CREATE` (o equivalentes)
idempotentes: reejecutar no duplica objetos.

```bash
# Lo normal: un solo comando. Recrea DBSIGCM y reescribe los usp_ext en SIGA.
.\instalar.ps1 -Recrear -ConDatosPrueba
```

Si SIGA se restauró desde un backup del MEF, el mismo comando vuelve a dejar
los siete procedimientos. **El instalador no borra ni crea `SIGA_1750`.**

**Usuarios de SIGA.** Menús, roles, privilegios y claves (`GLUNA`, `IRIVERA`,
`HBOJORQUEZ`, `SIGAMEF`) se tocan solo en la copia local, con los scripts de
`integracion/solo_desarrollo/`. No entran en `instalar.ps1` y **no pasan a
producción**. En el ANIN esos usuarios los administra el dueño de SIGA.

A mano, si hiciera falta:

```bash
sqlcmd -S "<servidor>" -d SIGA_1750 -E -b -I -i SIGA/integracion/usp_ext_incluir_item_cmn.sql
sqlcmd -S "<servidor>" -d SIGA_1750 -E -b -I -i SIGA/integracion/usp_ext_excluir_item_cmn.sql
sqlcmd -S "<servidor>" -d SIGA_1750 -E -b -I -i SIGA/integracion/usp_ext_aprobar_solicitud_cmn.sql
sqlcmd -S "<servidor>" -d SIGA_1750 -E -b -I -i SIGA/integracion/usp_ext_crear_cuadro_adquisicion_desde_pedido.sql
sqlcmd -S "<servidor>" -d SIGA_1750 -E -b -I -i SIGA/integracion/usp_ext_crear_orden_servicio_desde_cuadro.sql
```

### En local vs. en el ANIN

En la máquina de desarrollo `instalar.ps1` aplica los `usp_ext_*` en el mismo
golpe. En desarrollo compartido, QA y producción sigue siendo un trámite: el
propietario de SIGA autoriza y el DBA los instala (o corre el instalador con
cuenta que pueda escribir en SIGA).

Sin esos procedimientos, el SIGCM funciona igual y la escritura queda en
**modo simulación**.

---

## Cómo se conectan las dos bases

Las dos bases viven en la **misma instancia** de SQL Server, y por eso no hay
servicios web, colas externas ni servidores enlazados en el medio. Pero tienen
niveles de compatibilidad distintos, y eso define toda la arquitectura:

```
   DBSIGCM  (compat 160)                    SIGA_1750  (compat 100)
   nuestra, se puede cambiar                del MEF, no se toca
   ─────────────────────────                ───────────────────────────

   LECTURA   ──── siga.vw*  ────────────►   14 tablas maestras
             (10 vistas sobre sinónimos)     catálogo, metas, centros de
                                             costo, fuentes, techo…
                                             SELECT y nada más (ADR-004)

   ESCRITURA ──── W001 ─────────────────►   usp_ext_registrar_item_cmn
             traduce JSON → XML              inserta en el cuadro
             y llama al procedimiento        (ADR-003: arranca simulado)
```

**Lectura.** `C003` crea 14 sinónimos en el esquema `siga` de `DBSIGCM`, y `V004`
crea 10 vistas encima. El SIGCM lee los maestros de SIGA en la misma consulta y
la misma transacción, sin copiarlos: no hay tablas espejo ni sincronizador que
operar. Los maestros de SIGA **se leen, nunca se escriben** (ADR-004).

**Escritura.** Es de una sola vía y pasa por un solo lugar. Cuando un expediente
CMN llega a `CMN_VALIDAR_UA`, la transición **encola** una operación en
`integracion.Operacion` — no escribe en SIGA en ese momento. Después, `W001`
drena esa cola: toma las operaciones pendientes, traduce y llama al procedimiento
de SIGA.

### Por qué hay una traducción en el medio

Es la parte que más confunde y en realidad es simple. Del lado del SIGCM todo
viaja como **JSON**, porque `DBSIGCM` está en compat 160 y tiene `OPENJSON`.
`SIGA_1750` está en compat 100: ahí `OPENJSON` no existe, ni `JSON_VALUE`, ni
nada de JSON. Y no hace falta que exista, porque a SIGA no se le manda JSON: se
le manda lo que entiende desde 2005, que son **parámetros tipados y XML**.

`W001` es el único lugar del sistema donde el JSON deja de existir:

| SIGCM (JSON) | SIGA (parámetro) |
|---|---|
| `"AnoEje": 2026` | `@AnoEje numeric(4,0)` |
| `"CentroCosto": "01.01"` | `@CentroCosto varchar(15)` |
| `"PrecioUnitario": 12.5` | `@PrecioUnit numeric(16,6)` |
| `"Periodos": [ 48 filas `{AnoOffset, Mes, Cantidad}` ]` | `@Periodos xml` — 4 filas `<Periodo codigo c01…c12>` |

Ese pivote de 48 períodos a 4 filas de 12 columnas es el corazón del asunto: es
literalmente donde el modelo del SIGCM se convierte en el modelo del producto
SIGA.

### El JSON nunca entra a SIGA

Vale la pena decirlo aparte porque es la duda que siempre vuelve: **que SIGA esté
en compat 100 no obliga a bajar `DBSIGCM` a 100.** El nivel de compatibilidad es
una propiedad de cada base, y lo que gobierna una consulta es el compat de la
base **desde la que se ejecuta**, no el de la base cuyas tablas toca.

El procedimiento vive en `DBSIGCM` (160), ahí desarma el JSON con `OPENJSON`, y
lo que cruza hacia SIGA son columnas normales: `varchar`, `int`, `numeric`,
`datetime`. SIGA no necesita saber que existe el JSON, igual que no necesita
saber que existe el SIGCM.

Bajar `DBSIGCM` a 100 rompería el sistema entero: sin `OPENJSON` no compila
ninguna rutina del contrato. El detalle está medido en
[`docs/comparacion-desarrollo-vs-local.md`](../docs/comparacion-desarrollo-vs-local.md).

---

## Orden completo, de cero a que los datos lleguen a SIGA

| # | Qué | Dónde | Quién |
|---|---|---|---|
| 0 | Restaurar `SIGA_1750` desde el backup del MEF | instancia | DBA — **nunca** se crea con nuestros scripts |
| 1 | `instalar.ps1 -Recrear -ConDatosPrueba` | `SIGA_1750` + `DBSIGCM` | nosotros: `usp_ext_*`, sinónimos, V/F/W/S |
| 2 | `C002__acceso_lectura_siga.sql` | `SIGA_1750` | DBA del ANIN (en local no hace falta) |
| 3 | Worker .NET con `IntegracionSiga:Habilitado=true` y `Modo=real` | API | nosotros |

`C002` concede lectura: rol `sigcm_lector_siga` con `SELECT` sobre tablas
nominadas. En local no hace falta, porque se trabaja con una cuenta sysadmin.

---

## Cómo comprobar en qué punto está un entorno

```sql
-- ¿Los procedimientos de integracion estan en SIGA?
SELECT name
  FROM SIGA_1750.sys.procedures
 WHERE name LIKE 'usp_ext_%'
 ORDER BY name;

-- ¿DBSIGCM tiene los sinonimos? (los crea W001/W002/W003 si el proc existe)
SELECT name, base_object_name
  FROM sys.synonyms
 WHERE name LIKE 'usp_ext_%'
 ORDER BY name;
```

Si la primera consulta no devuelve las cinco rutinas que usa el worker
(`incluir`, `excluir`, `aprobar`, `crear_cuadro`, `crear_orden`), falta correr
`instalar.ps1` (o se omitió con `-OmitirSigaExt`).
