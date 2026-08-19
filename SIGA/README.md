# SIGA — qué se ejecuta aquí y qué no

Esta carpeta contiene lo que toca la base **`SIGA_1750`**, que **no es nuestra**:
es del producto SIGA, del MEF. Todo lo de aquí se trata con esa regla en mente.

> **Sólo un archivo de esta carpeta se ejecuta en `SIGA_1750`**, y requiere
> autorización del propietario. Los otros cuatro `.sql` son referencia,
> descubrimiento o historia. Ejecutar el que no es puede hacer daño.

---

## Tabla de decisión

| Archivo | ¿Se ejecuta? | Dónde | Qué es |
|---|---|---|---|
| `integracion/usp_ext_registrar_item_cmn.sql` | **SÍ**, previa autorización | `SIGA_1750` | El único entregable. Crea `dbo.usp_ext_registrar_item_cmn` |
| `integracion/usp_ext_crear_orden_servicio_desde_cuadro.sql` | Todavía no | `SIGA_1750` | Propuesta para la Orden de Servicio. Es del módulo Ejecución, fuera del alcance de la v1 |
| `integracion/descubrimiento/01_perfilado_cmn.sql` | Opcional | `SIGA_1750` | **Sólo lectura.** Sin `INSERT`/`UPDATE`/`DELETE`/DDL. Sirve para verificar qué par de tablas usa el CMN en esa instancia |
| `integracion/ESQUEMA_dbo.sql` | **NO. NUNCA** | — | Volcado de Navicat del esquema completo de `SIGA_1750`, 139 000 líneas. Es documentación para leer, no un script para correr |
| `integracion/script.sql` | **NO** | — | La primera encarnación del SIGCM en PostgreSQL. Se conserva como referencia histórica (etapa 2 del mapa de implementación) |

`entregables/` son los manuales en Word y PDF, más sus imágenes. No hay nada que
ejecutar ahí.

---

## El único que se instala

```
integracion/usp_ext_registrar_item_cmn.sql
```

Se ejecuta **dentro de `SIGA_1750`** y crea un procedimiento almacenado. Qué
hace, en una línea: recibe un ítem del Cuadro Multianual de Necesidades con sus
cantidades mensuales y lo inserta en `SIG_CUADRO_NECESIDAD` y
`SIG_CUADRO_NECESIDAD_DET`.

Lo que **no** hace, y es tan importante como lo que hace:

- deja el ítem en `ESTADO = '5'` (pendiente de consolidación), **no** lo pasa a `'6'`
- no consolida el cuadro
- no toca el techo presupuestal
- no modifica ninguna tabla que no sean esas dos

Está escrito para el nivel de compatibilidad **100** de `SIGA_1750`: parámetros
tipados y XML, nada de JSON. Esa es la frontera del diseño (ver más abajo).

```bash
sqlcmd -S "<servidor>" -d SIGA_1750 -E -b -I -i SIGA/integracion/usp_ext_registrar_item_cmn.sql
```

### Antes de ejecutarlo

Es un cambio dentro de una base de otro dueño. **Es un trámite, no una tarea de
programación.** El orden es:

1. El ANIN revisa el procedimiento y autoriza su instalación.
2. El equipo de SIGA lo instala en el entorno que corresponda.
3. Del lado nuestro no hay que hacer nada más: la próxima corrida de
   `instalar.ps1` detecta que el procedimiento existe y `W001` crea solo el
   sinónimo hacia él.

Mientras no ocurra, el SIGCM sigue funcionando: la escritura hacia SIGA queda en
**modo simulación**, que hace toda la traducción y muestra qué habría mandado,
sin tocar nada.

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
| 1 | `instalar.ps1` — la serie completa | `DBSIGCM` | nosotros |
| 2 | `00_servidor/C002__acceso_lectura_siga.sql` | `SIGA_1750` | DBA del ANIN, con autorización |
| 3 | `SIGA/integracion/usp_ext_registrar_item_cmn.sql` | `SIGA_1750` | equipo de SIGA, con autorización |
| 4 | `instalar.ps1` otra vez | `DBSIGCM` | nosotros — ahora `W001` sí crea el sinónimo |
| 5 | El worker .NET que drene la cola | — | **no existe todavía** |

Los pasos 2 y 3 son los únicos que tocan `SIGA_1750`, y **ninguno de los dos se
ejecuta sin permiso del propietario de la base.**

- **C002** concede lectura: crea el rol `sigcm_lector_siga` con `SELECT` sobre 14
  tablas nominadas. Cero escritura, cero `db_datareader`, cero cambios de
  esquema. No crea logins ni maneja contraseñas — eso lo hace el DBA. **En local
  no hace falta**, porque se trabaja con una cuenta sysadmin.
- **usp_ext_registrar_item_cmn** habilita la escritura, y sólo la del CMN.

Sin el paso 3, todo lo demás funciona igual y la escritura queda en simulación.
Sin el paso 5, las operaciones se quedan en `integracion.Operacion` esperando; se
pueden drenar a mano con `EXEC integracion.paEscribirCuadroModificado`.

---

## Cómo comprobar en qué punto está un entorno

```sql
-- ¿El procedimiento está instalado en SIGA?
SELECT name FROM SIGA_1750.sys.procedures WHERE name = 'usp_ext_registrar_item_cmn';

-- ¿DBSIGCM tiene el sinónimo hacia él? (lo crea W001, y sólo si el de arriba existe)
SELECT name, base_object_name FROM sys.synonyms WHERE name = 'usp_ext_registrar_item_cmn';
```

Si la primera consulta no devuelve nada, ese entorno está en modo simulación y es
lo esperado.
