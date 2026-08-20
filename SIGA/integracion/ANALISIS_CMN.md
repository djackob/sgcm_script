# El CMN en SIGA: cómo funciona y qué le falta a nuestra integración

Verificado contra `localhost\SQLSERVER25` / `SIGA_1750` (ejecutora 1750) y contra
el SQL embebido en los módulos PowerBuilder de `C:\SIGA_MEF\SIGA_ML`, el
**2026-08-19**. Todo lo que se afirma aquí tiene detrás una consulta o una
cadena extraída del cliente; donde algo es inferencia, se dice.

---

## 1. Los dos cuadros

Éste es el punto que reordena todo lo demás. En SIGA el CMN no vive en una
tabla: vive en **dos rutas distintas que se usan en momentos distintos del año**.

| | Formulación | Modificación |
|---|---|---|
| Cabecera | `SIG_CUADRO_NECESIDAD` | `SIG_CUADRO_MODIFICADO` |
| Detalle | `SIG_CUADRO_NECESIDAD_DET` | `SIG_CUADRO_MODIFICADO_DET` |
| Saldos | — | `SIG_CUADRO_MODIFICADO_SALDO` |
| Foto previa | — | `SIG_CUADRO_MODIFICADO_DET_ORI` |
| Solicitudes | — | `SIG_SOLICITUD_MODIFICACION` (+ `_DET`) |
| Clave | `ANO_EJE + SEC_EJEC + CENTRO_COSTO + SECUENCIA + FASE_CUADRO` (+ `ITEM_SEC`) | `SEC_EJEC + ANNO_EJEC + CENTRO_COSTO + SEC_CUADRO` (+ `SEC_ITEM + ANNO_PROG`) |
| Multianualidad | 1 fila con 48 columnas (`CANT_01` … `CANT_12_ANNO_03`) | **4 filas**, una por `ANNO_PROG` |

Las fechas de `SIGA_1750` muestran que no compiten, se relevan:

```
SIG_CUADRO_NECESIDAD_DET  2026 : del 2025-12-29 al 2026-01-07   (formulación)
SIG_CUADRO_MODIFICADO_DET 2026 : del 2026-01-08 al 2026-07-20   (modificación)
```

La formulación del ejercicio 2026 se cerró el 7 de enero. Desde el 8 de enero
**todo lo que las áreas usuarias hacen con su cuadro ocurre en la ruta de
modificación**, y son 32 876 filas de detalle contra 4 083 de la formulación.

> **Consecuencia directa.** `usp_ext_registrar_item_cmn` escribe en
> `SIG_CUADRO_NECESIDAD`, o sea en la ruta de formulación. El ADR-002 fija el
> MVP en la modificación del cuadro. `usp_ext_excluir_item_cmn` sí escribe en la
> ruta correcta. **Las dos operaciones de W001 no escribían en el mismo cuadro.**
> Resuelto con `usp_ext_incluir_item_cmn` (sección 4.5).

### Qué lee cada pantalla, que no es lo mismo que dónde se escribe

Esto **no** es inferencia: son las consultas que el aplicativo envió, capturadas
con Extended Events.

**"Fase Consolidación y Aprobación del C.M.N." → grilla *Presentación por
Items*** — lee la ruta de FORMULACIÓN:

```sql
select distinct a.centro_costo, a.secuencia, a.tipo_bien, a.grupo_bien,
       a.clase_bien, a.familia_bien, a.item_bien, b.clasificador, b.sec_func,
       b.codigo_tarea, b.tipo_tarea, b.nivel_tarea, b.fuente_financ, b.tipo_uso
  from sig_cuadro_necesidad_det a
  JOIN sig_cuadro_necesidad b ON (...)
 where a.ano_eje = 2026 and a.sec_ejec = 1750
   and a.centro_costo = '01.07.05.03' and a.fase_cuadro = 5
   and a.tipo_bien = 'B'
   and EXISTS (SELECT m.ANO_EJE FROM META m WHERE ... )
 union ...   -- la segunda rama es para metas de estrategia (FLAG_ESTRATEGIA='S')
```

**"Demanda Adicional"** — lee la ruta de MODIFICACIÓN:

```sql
SELECT SEC_EJEC, ANNO_EJEC, CENTRO_COSTO, SEC_CUADRO, SEC_ITEM, ORIGEN,
       PROCEDENCIA, ..., ESTADO, FLAG_MODIFICADO, FLAG_SOLICITUD, ...,
       SUM(CASE WHEN ANNO_EJEC     = ANNO_PROG THEN CANT_01+...+CANT_12 ELSE 0 END) AS CANT_ANNO_01,
       SUM(CASE WHEN ANNO_EJEC + 1 = ANNO_PROG THEN CANT_01+...+CANT_12 ELSE 0 END) AS CANT_ANNO_02,
       ...
  FROM SIG_CUADRO_MODIFICADO_DET
       -- + CATALOGO_BIEN_SERV, FUENTE_FINANC, SIG_CENTRO_COSTO_TAREA,
       --   SIG_CLASIFICADOR_GASTO
 WHERE SEC_EJEC = 1750 AND ANNO_EJEC = 2026 AND CENTRO_COSTO = '...'
   AND TIPO_BIEN LIKE 'B'
 GROUP BY ...
```

Ahí está el pivote inverso al nuestro: la Demanda Adicional agrega las cuatro
filas de `ANNO_PROG` en cuatro columnas `CANT_ANNO_01..04`.

### El menú tiene tres ramas, y sólo una es la nuestra

Esto costó varias vueltas. El módulo Logística separa las tres etapas del CMN en
ramas distintas del menú:

```
Programación > Programación del C.M.N. > Bienes, Servicios y Obras     (id 10019)
Programación > Modificación de C.M.N.  > Gastos Generales              (id 10026)
                                       > Bienes, Servicios y Obras     (id 10027)
                                       > Solicitud de Modificación     (id 10028)
                                       > Transferencia de Modificación (id 10029)
Programación > Consolidado del C.M.N.  > Consolidado C.M.N. Actualizado (id 10031)
                                       > Aprobación de Solicitud de Modificación (id 10032)
```

Y el mapeo con las tablas es exacto:

| Rama del menú | Tabla |
|---|---|
| Programación del C.M.N. | `SIG_CUADRO_NECESIDAD` / `_DET` |
| **Modificación de C.M.N. → Bienes, Servicios y Obras** | **`SIG_CUADRO_MODIFICADO_DET`** |
| **Modificación de C.M.N. → Solicitud de Modificación** | **`SIG_SOLICITUD_MODIFICACION`** |
| Consolidado del C.M.N. | `SIG_CUADRO_MODIFICADO_CMN` + PAAC |

"Demanda Adicional" es un **botón dentro** de la pantalla de formulación, no la
vista del cuadro modificado. Buscar ahí los ítems del SIGCM fue un error: la
vista correcta es *Modificación de C.M.N. → Bienes, Servicios y Obras*, que ni
siquiera pide la habilitación `flag_da_aprob`.

| Pantalla | Lee de |
|---|---|
| Fase Consolidación y Aprobación → *Presentación por Items* | **`SIG_CUADRO_NECESIDAD_DET`** (cuadro formulado) |
| **Modificación de C.M.N. por Área Usuaria** | **`SIG_CUADRO_MODIFICADO_DET`** |
| **Registro de Solicitud de Modificación** | **`SIG_SOLICITUD_MODIFICACION`** |
| Selector de ítems de un requerimiento | `SIG_CUADRO_MODIFICADO_DET` + `_SALDO` |

### Los dos momentos, vistos en el aplicativo

En *Modificación de C.M.N. por Área Usuaria* (Tipo: Servicio) los ítems que
registró el SIGCM aparecen con **`I`** en la columna **Incl / Excl**, junto a los
que registraron usuarios reales.

En *Registro de Solicitud de Modificación* se distinguen los dos momentos:

| Solicitud | Estado en pantalla | `ESTADO` en base | Qué la produjo |
|---|---|---|---|
| 519 | **V.B. Jefe** | `2` | Anexo 3 firmado y validado |
| 518 | **Aprobado** | `3` | Anexo 4 firmado |

La pantalla muestra *Fecha de V.B. Jefe* para las dos, y **añade *Fecha de
Aprobación* sólo cuando el Anexo 4 se firmó**. El detalle lleva `Motivo = Inc.`
(inclusión), meta `0015`, actividad `C0104`, valor `4,000.00`.

Es decir, la equivalencia es literal:

```
Anexo 3 firmado y validado  ->  solicitud SIGA en "V.B. Jefe"
Anexo 4 firmado             ->  solicitud SIGA en "Aprobado"
```

**Por eso una inclusión hecha durante el año no aparece en *Presentación por
Items*, y eso es correcto.** Esa grilla muestra el cuadro tal como se formuló y
aprobó; es una foto que ya no cambia. Lo que se agrega después vive en la rama
de **Modificación de C.M.N.**, y ahí es donde hay que mirarlo.

> No en *Demanda Adicional*. Ese botón está dentro de la pantalla de
> formulación, exige `flag_da_aprob` y no muestra el cuadro modificado. Se
> perdió tiempo buscando ahí más de una vez; la ruta buena es la de la tabla de
> arriba y está desarrollada en `Proyecto/SIGA_APLICATIVO.md`.

Se comprueba con los conteos de OTI: la formulación tiene **14** ítems y la
modificación **17**. Los tres de diferencia se agregaron durante el año — uno de
ellos por un usuario real (`IRIVERA`, junio) y el nuestro.

> **Detalle práctico:** las dos grillas filtran por el desplegable *Tipo*, que
> viene en "Bien". Para ver un servicio hay que cambiarlo a **Servicio**.

### Por qué el detalle de modificación tiene cuatro filas

`SIG_CUADRO_MODIFICADO_DET` reparte el multianual en filas, no en columnas:

```
ANNO_EJEC | ANNO_PROG | filas
2026      | 2026      | 8219
2026      | 2027      | 8219
2026      | 2028      | 8219
2026      | 2029      | 8219
```

8 219 ítems × 4 años. Cualquier operación sobre un ítem toca las cuatro filas o
deja el cuadro incoherente. `usp_ext_excluir_item_cmn` lo respeta y de hecho lo
exige (`IF @Filas<>4 OR @Anios<>4 → error`).

---

## 2. El ciclo de vida de un ítem en la ruta de modificación

Tres columnas lo codifican: `ESTADO`, `PROCEDENCIA` y `MOTIVO_SOLICITUD`, más
la bandera `FLAG_MODIFICADO`.

**`PROCEDENCIA`** — de dónde vino el ítem. No cambia.

| | |
|---|---|
| `C` | venía del cuadro formulado |
| `N` | nuevo, incluido durante el año |
| `T` | vino por transferencia entre centros |

**`ESTADO`** — en qué situación está.

| | |
|---|---|
| `C` | del cuadro, vigente |
| `I` | incluido, vigente |
| `IT` | incluido por transferencia |
| `E` | excluido |
| `ET` | excluido por transferencia |
| `IC` | anulado (no aparece en 2026, sí en el filtro del cliente) |

**`MOTIVO_SOLICITUD`** — si hay una solicitud abierta encima.

| | |
|---|---|
| `0` | ninguna: el ítem está estable |
| `1` | inclusión pendiente |
| `2` | exclusión pendiente |
| `3` | modificación de cantidades pendiente |

La combinación real en 2026 (`ANNO_PROG = ANNO_EJEC`):

```
ESTADO PROC FLAG_MOD MOTIVO  filas
C      C    0        0       4038   estable, del cuadro
I      N    0        0       3670   estable, incluido y ya aprobado
E      C    1        2        174   exclusión solicitada, aún no consolidada
E      C    0        0         91   exclusión ya consolidada
I      N    1        1         82   inclusión solicitada, aún no aprobada
IT     T    0        0         43   transferencia recibida
```

El ciclo, entonces:

```
      ┌── el usuario solicita ──┐
      │                          │
  MOTIVO=0  ──────────────►  MOTIVO=1/2/3      ──────────►  MOTIVO=0
  ESTADO C/I                FLAG_MODIFICADO=1              ESTADO nuevo
  pedible                   NO pedible                     pedible otra vez
                                   │
                                   └── SIG_SOLICITUD_MODIFICACION
                                       ESTADO 2 (enviada) → 3 (aprobada)
```

### La solicitud de modificación

Una exclusión no es un `UPDATE`: es un expediente. `usp_ext_excluir_item_cmn`
escribe, en orden, en cinco tablas, y eso coincide con lo que hace el cliente:

1. `SIG_CUADRO_MODIFICADO_DET_ORI` — la foto de las cantidades anteriores, para
   que la pantalla de Demanda Adicional pueda mostrar la diferencia.
2. `SIG_SOLICITUD_MODIFICACION` — el expediente, `ESTADO='2'` (enviada).
3. `SIG_SOLICITUD_MODIFICACION_DET` — una fila por año, `MOTIVO='2'`.
4. `SIG_DOCUMENTO_ESTADO` — el movimiento del documento.
5. `SIG_CUADRO_MODIFICADO_DET` — recién ahora el ítem pasa a `E`.

El estado de la solicitud recorre `2` (enviada) → `3` (aprobada). En 2026 hay
490 solicitudes en `3` y 8 en `5`. Ninguna real quedó en `2`: se aprueban el
mismo día o al siguiente.

`FLAG_ULT_MOV` en `SIG_DOCUMENTO_ESTADO` **no** marca el último movimiento de la
solicitud, marca el último de cada *estado*. La solicitud 70 de `01.02.02` tiene
cuatro filas y tres con `FLAG_ULT_MOV='1'`. El procedimiento lo maneja bien.

---

## 3. El saldo: cómo el CMN se convierte en algo consumible

`SIG_CUADRO_MODIFICADO_SALDO` lleva, por mes y en total, tres cubetas:

| | |
|---|---|
| `CANT_xx` | lo programado en el CMN |
| `CANT_xx_CMN` | lo ya comprometido por requerimientos |
| `CANT_xx_SC` | "sin cuadro" |

**Saldo disponible = `CANT_TOTAL − CANT_TOTAL_CMN`.** No es una interpretación:
es literalmente el `HAVING` de la ventana del cliente que elige ítems para un
pedido (`sig_aba_dawi21_te.pbd`):

```sql
AND EXISTS (
    SELECT 1 FROM SIG_CUADRO_MODIFICADO_SALDO
     WHERE ... SEC_CUA_MOD_SAL = SIG_CUADRO_MODIFICADO_DET.SEC_CUA_MOD_SAL
       AND (SIG_CUADRO_MODIFICADO_SALDO.CANT_TOTAL
          - SIG_CUADRO_MODIFICADO_SALDO.CANT_TOTAL_CMN) > 0 )
AND SIG_CUADRO_MODIFICADO_DET.MOTIVO_SOLICITUD IN ('0','3')
AND SIG_CUADRO_MODIFICADO_DET.ESTADO NOT IN ('E','ET','IC')
```

Y el cliente acumula el consumo con `CANT_xx_CMN = CANT_xx_CMN + n`
(`sig_aba_wind30.pbd`).

### Dos invariantes que se cumplen sin excepción

Sobre las 28 904 filas de saldo del 2026, cero violaciones:

```
CANT_TOTAL     = suma de los doce CANT_xx
CANT_TOTAL_CMN = suma de los doce CANT_xx_CMN
```

### Una que no se cumple, y conviene saberlo

`CANT_xx_CMN ≤ CANT_xx` **falla mes a mes** en cerca del 1 % de los saldos
(372 filas en enero, 331 en abril, 213 en julio, 2 en diciembre). SIGA solo
controla el total. Cualquier integración que valide mes a mes rechazará
operaciones que SIGA acepta.

### El mes que se descuenta no es el mes del pedido

Un pedido de julio descuenta de mayo y junio. SIGA llena los meses programados
desde el primero con saldo, no el mes del pedido:

```
NRO_PEDIDO 007662  MES_PEDIDO 07  cantidad 44000
  → CANT_05_CMN 38000 (de un pedido anterior), CANT_06_CMN 44000
```

### Sobre la exclusión y el saldo

`usp_ext_excluir_item_cmn` no toca `SIG_CUADRO_MODIFICADO_SALDO`, y **está
bien**. De las 896 filas realmente excluidas en 2026 por usuarios de SIGA, 577
quedaron con saldo en cero y 319 con saldo residual: el cliente tampoco lo
normaliza. El ítem deja de ser consumible por el filtro de `ESTADO` y
`MOTIVO_SOLICITUD`, no por el saldo. Dejarlo como está es lo fiel.

---

## 4. Defectos encontrados en los scripts de integración

### 4.1 `usp_ext_excluir_item_cmn` escribe `DET_ORI.TIPO = '2'` — corregido

SIGA solo usa dos valores en `SIG_CUADRO_MODIFICADO_DET_ORI.TIPO`:

```
ANNO_EJEC  TIPO  filas
2024       1     1368     ← solicitud de modificación
2024       3        4     ← transferencia
2025       1     1560
2025       3        4
2026       1     1280
2026       2        4     ← SOLO las 4 filas de nuestra prueba
2026       3       16
```

`TIPO='2'` es un valor que SIGA no produce. Con él, la pantalla de Demanda
Adicional no encuentra la foto previa y no puede mostrar la cantidad anterior ni
calcular la diferencia. Corregido a `'1'` en
`C:\SIGA_MEF\integracion\usp_ext_excluir_item_cmn.sql`.

**El procedimiento instalado hoy en `SIGA_1750` todavía tiene `'2'`.** Hay que
reinstalarlo con el archivo corregido.

### 4.2 El fuente de `usp_ext_excluir_item_cmn` no existía en disco

Estaba solo dentro de `SIGA_1750`, instalado el 2026-08-19 a las 11:40.
Recuperado desde `sys.sql_modules` a
`C:\SIGA_MEF\integracion\usp_ext_excluir_item_cmn.sql` y copiado al proyecto.

### 4.3 `W001` en disco estaba atrasado respecto de la base

`db/15_siga/W001__escritor_cuadro_modificado.sql`, tal como estaba commiteado
en `e415170`, decía *"W001 solo implementa INCLUIR_ITEM. EXCLUIR_ITEM …
pendientes"*. El procedimiento instalado en `DBSIGCM` (21 738 caracteres) ya
soportaba `EXCLUIR_ITEM`. El trabajo se hizo contra la base y no se volcó al
archivo; `git status` estaba limpio, o sea nadie lo notó.

Reconstruido desde la base. Además, la sección 1 del archivo solo creaba el
sinónimo de inclusión, mientras el cuerpo instalado ya consultaba
`@haySinonimoExclusion`: ahora crea los dos. Reinstalado y verificado.

### 4.4 Falta `SET QUOTED_IDENTIFIER ON` antes del `CREATE`

Los tres procedimientos usan métodos del tipo XML (`@Periodos.nodes`,
`@Items.nodes`). SQL Server exige `QUOTED_IDENTIFIER ON` **en el momento de
crear** el procedimiento; la opción queda grabada con el objeto. `sqlcmd` abre
la sesión con la opción en `OFF`, así que instalar con `sqlcmd` produce un
procedimiento que compila pero falla en ejecución con el error 1934.

Detectado al probar el script de requerimiento, que falló exactamente así.
Agregado a los tres archivos. Los dos procedimientos ya instalados en
`SIGA_1750` tienen `uses_quoted_identifier = 1` porque se instalaron desde otro
cliente; el defecto era del archivo, no de la base.

### 4.5 Ruta de escritura de `INCLUIR_ITEM` — resuelto

Se escribió `usp_ext_incluir_item_cmn`, que hace la inclusión contra
`SIG_CUADRO_MODIFICADO` y deja el item simétrico con la exclusión: mismo cuadro,
misma solicitud, misma foto previa. `W001` ya no invoca
`usp_ext_registrar_item_cmn`; ese procedimiento queda como está, sin uso.

### 4.6 Los procedimientos de SIGA devolvían filas y rompían el contrato

`W001` llama a los procedimientos de SIGA dentro de un `INSERT ... EXEC`. Ese
patrón exige que el procedimiento llamado devuelva **un solo** conjunto de
resultados con la forma que el destino espera. Los tres procedimientos
terminaban con un `SELECT` de diez columnas "para homologación", así que la
inserción fallaba y la operación se quedaba colgada en la cola sin error visible
en el drenaje.

Lo mismo rompe el contrato del backend, que lee una sola columna de texto.

Corregido: los tres reciben `@Detalle bit = 0` y sólo emiten el `SELECT` cuando
se les pide explícitamente. Todo lo que hace falta sale por parámetros `OUTPUT`.

### 4.7 `ROLLBACK` dentro de una transacción ajena

Mismo origen, distinto síntoma. `INSERT ... EXEC` abre una transacción
implícita, así que los procedimientos de SIGA entran con `@@TRANCOUNT = 1`. Al
fallar, su `CATCH` hacía `ROLLBACK TRANSACTION`, que **no deshace sólo lo
propio: deshace todo**, incluida la transacción del llamador. W001 quedaba
entonces sin poder registrar el error:

```
Transaction count after EXECUTE indicates a mismatching number of
BEGIN and COMMIT statements. Previous count = 1, current count = 2.
The current transaction cannot be committed and cannot support
operations that write to the log file.
```

Corregido en los tres: `@trnPropia` recuerda si `@@TRANCOUNT` era cero al
entrar, y sólo entonces se abre, confirma o revierte la transacción. Si es
ajena, el error se propaga y decide el llamador. La atomicidad no se pierde
porque la transacción del llamador cubre todo.

### 4.8 El techo bloqueaba años a los que la inclusión no agregaba nada

La validación comparaba `usado + nuevo > techo` en los cuatro años. En SIGA hay
techos ya sobregirados de antes: OTI, meta 15, tiene el techo de los años 1 a 3
en cero y un ítem del cuadro con 1.00 en el año 1. Con eso, **cualquier**
inclusión fallaba —incluso una que sólo toca el año base— con el mensaje
*"excede el techo del anio 1. Disponible: -1.00"*, por un sobregiro que ya
existía y del que no era responsable.

Corregido: un año sólo se valida si la inclusión le suma monto. La regla es que
la inclusión no puede **empeorar** el techo de un año; si le suma cero, no lo
empeora.

---

## 4bis. Los dos momentos en que el SIGCM escribe en SIGA

Esto es lo que hay que entender para no pedirle al sistema algo que no
corresponde.

```
   SIGCM                                    SIGA
   ─────────────────────────────────────    ──────────────────────────────────
   Anexo 3 firmado por el área usuaria
   → enviado a OA → derivado a UA
   → CMN_VALIDAR_UA  ────────────────────▶  usp_ext_incluir_item_cmn
                                            SIG_CUADRO_MODIFICADO_DET   I/N/1/0/1
                                            SIG_CUADRO_MODIFICADO_SALDO
                                            SIG_CUADRO_MODIFICADO_DET_ORI TIPO 1
                                            SIG_SOLICITUD_MODIFICACION  estado 2
                                            SIG_DOCUMENTO_ESTADO        estado 2

                                            El item EXISTE pero NO ES PEDIBLE.

   Anexo 4 firmado por Abastecimiento
   → CMN_FIRMAR_A4   ────────────────────▶  usp_ext_aprobar_solicitud_cmn
                                            SIG_SOLICITUD_MODIFICACION  estado 3
                                            SIG_DOCUMENTO_ESTADO        estado 3
                                            SIG_CUADRO_MODIFICADO_DET   I/N/0/0/0

                                            Ahora SÍ es pedible.
```

Lo que separa los dos momentos es `MOTIVO_SOLICITUD`. Mientras valga `'1'`, el
selector de items de un requerimiento no lo muestra. La firma del Anexo 4 es lo
que lo lleva a `'0'`.

### Hasta dónde llega el Anexo 4, y por qué no más allá

La primera versión de la aprobación intentaba además escribir la fila de
consolidación en `SIG_CUADRO_MODIFICADO_CMN`. SIGA la rechazó:

```
The INSERT statement conflicted with the FOREIGN KEY constraint
"FK_SIG_CUA_MOD_CMN_02" ... table "dbo.SIG_PAAC_CENTRO_COSTO"
```

Esa tabla tiene una clave foránea de **diez columnas** contra
`SIG_PAAC_CENTRO_COSTO`: una fila de consolidación sólo existe si el nodo del
PAAC ya existe. Consolidar el CMN es generar el árbol del PAAC
(`SIG_PAAC_CONSOLIDADO` 13 779 filas, `SIG_PAAC_METAS` 43 077,
`SIG_PAAC_CENTRO_COSTO` 43 181, `SIG_PAAC_ITEM` 26 117) con su numeración
propia. Es un proceso por lotes de Abastecimiento dentro de SIGA, no el efecto
de firmar un documento.

Los datos lo confirman: de las 5 837 inclusiones aprobadas de 2026, sólo 4 406
están consolidadas. Aprobación y consolidación no van uno a uno.

**La firma del Anexo 4 llega hasta la aprobación.** Es lo que el SIGCM puede
garantizar y lo que el área usuaria necesita para poder pedir. La generación del
PAAC se queda en SIGA.

### La firma del Anexo 4

`sigcm.paFirmarDocumento` ya era genérica: lee quién puede firmar de
`sigcm.TipoDocumentoFirma`. Lo que faltaba no era la rutina, era la coherencia
del dato.

La semilla declaraba **dos** firmantes para el Anexo 4, `ABAST_JEFE` y
`MAX_AUT_ADMIN`, pero `paFirmarDocumento` marca la versión como `FIRMADO` en la
**primera** firma, sin llevar cuenta de las que faltan. El primero que entraba
daba el documento por firmado y el segundo recibía *"la versión vigente ya está
firmada"*. La segunda firma no existía: sólo estaba escrita.

Se dejó **un firmante: `ABAST_JEFE`**. Si más adelante hiciera falta firma
conjunta, el cambio no es agregar la fila: es que `paFirmarDocumento` registre
firma por firma y sólo cierre la versión cuando estén todas.

La firma sigue siendo un asiento —queda constancia de quién firmó y cuándo—, en
el Anexo 3 y en el Anexo 4 por igual. Cuando entre el firmador institucional,
devolverá el PDF firmado y su huella por `GeneradoDocumento` y `ArchivoHash`, y
no cambia nada más: todas las pantallas preguntan por el **estado** de la
versión, no por cómo se firmó.

---

## 4ter. Elegir un área usuaria que sí admita una inclusión

Dos condiciones, y ninguna es obvia.

**1. El centro tiene que estar en "Consolidación y Aprobación".**
`SIG_CUADRO_X_CENTRO.estado` es lo que la pantalla "Registro de C.M.N. por Área
Usuaria" muestra en la columna *Estado C.M.N.*:

| estado | lo que dice la pantalla | centros en 2026 | ¿abre Demanda Adicional? |
|---|---|---|---|
| `4` | Consolidación y Aprobación | 26 | **sí** |
| `6` | C.C.M.N. | 17 | no |

> **Corrección.** La primera versión de este documento afirmaba lo contrario:
> que el estado `6` era el cuadro abierto. Es al revés. El aplicativo lo dice
> literalmente al intentar entrar con un centro en `6`:
>
> > *El Área Usuaria debe estar en estado Consolidación y Aprobación.*
>
> El mensaje está en `sig_aba_wind20_te.pbd` (para el área usuaria) y en
> `sig_aba_wind22_te.pbd` (para el centro de costo). El error costó una prueba
> completa: la inclusión llegó igual a `SIG_CUADRO_MODIFICADO` —la base no
> valida el estado del cuadro— pero no había forma de verla desde el aplicativo,
> que era el objetivo.

**1bis. El área usuaria tiene que estar HABILITADA para Demanda Adicional.**
Con el estado correcto aparece un segundo control:

> *Verificar Habilitación de Demanda Adicional.*

La captura con Extended Events mostró la consulta exacta que el aplicativo hace
justo antes de ese mensaje:

```sql
select flag_da_aprob from sig_cuadro_x_centro
 WHERE ano_eje = 2026 AND sec_ejec = 1750 AND centro_costo = '01.07.05.03'
```

`SIG_CUADRO_X_CENTRO` tiene dos banderas, una por fase:

| columna | fase |
|---|---|
| `flag_da_prog` | Demanda Adicional de la Fase Clasificación |
| `flag_da_aprob` | Demanda Adicional de la Fase Consolidación |

**En esta copia las dos están en `NULL` en los 131 registros de 2024, 2025 y
2026.** Nunca se habilitó para ningún centro, y por eso la pantalla no abría
para nadie — no era un problema del área elegida.

Quien la otorga es **Abastecimiento, desde el propio SIGA**: el `UPDATE` vive en
el mismo módulo que muestra el mensaje.

> **El SIGCM no debe escribir nunca esta bandera.** Equivaldría a auto-otorgarse
> el permiso para modificar el cuadro. Es una decisión de gestión, no un dato
> técnico. Para la copia local existe
> `habilitar_demanda_adicional.sql`, que la enciende para un centro y trae su
> propio deshacer.

Con esto son **tres** condiciones, no dos, y ninguna la valida la base:

1. `SIG_CUADRO_X_CENTRO.estado = '4'`
2. `SIG_CUADRO_X_CENTRO.flag_da_aprob` habilitado
3. techo libre en la meta y el clasificador

**2. Tiene que quedar techo libre**, y el techo se compara por
`CENTRO_COSTO + SEC_FUNC + CLASIFICADOR + ORIGEN + FUENTE_FINANC`, no por centro
entero.

```sql
WITH techo AS (
  SELECT t.CENTRO_COSTO, t.sec_func, t.CLASIFICADOR, t.ORIGEN, t.FUENTE_FINANC,
         t0 = SUM(COALESCE(t.MNTO_APROB,0)),
         t1 = SUM(COALESCE(t.MNTO_ANNO_01,0)),
         t2 = SUM(COALESCE(t.MNTO_ANNO_02,0))
    FROM dbo.SIG_TECHO_PRESUPUESTO t
   WHERE t.ANO_EJE=2026 AND t.SEC_EJEC=1750 AND t.FASE_CUADRO=5
     AND t.CENTRO_COSTO IS NOT NULL
   GROUP BY t.CENTRO_COSTO, t.sec_func, t.CLASIFICADOR, t.ORIGEN, t.FUENTE_FINANC),
usado AS (
  SELECT d.CENTRO_COSTO, d.SEC_FUNC, d.CLASIFICADOR, d.ORIGEN, d.FUENTE_FINANC,
         u0 = SUM(CASE WHEN d.ANNO_PROG=2026 THEN d.MNTO_TOTAL ELSE 0 END),
         u1 = SUM(CASE WHEN d.ANNO_PROG=2027 THEN d.MNTO_TOTAL ELSE 0 END),
         u2 = SUM(CASE WHEN d.ANNO_PROG=2028 THEN d.MNTO_TOTAL ELSE 0 END)
    FROM dbo.SIG_CUADRO_MODIFICADO_DET d
   WHERE d.ANNO_EJEC=2026 AND d.SEC_EJEC=1750 AND d.ESTADO NOT IN ('E','ET','IC')
   GROUP BY d.CENTRO_COSTO, d.SEC_FUNC, d.CLASIFICADOR, d.ORIGEN, d.FUENTE_FINANC)
SELECT t.CENTRO_COSTO, cc.ABREVIADO_DEPEND, t.sec_func, t.CLASIFICADOR,
       libre0 = t.t0 - COALESCE(u.u0,0),
       libre1 = t.t1 - COALESCE(u.u1,0),
       libre2 = t.t2 - COALESCE(u.u2,0)
  FROM techo t
  JOIN dbo.SIG_CUADRO_X_CENTRO x
    ON x.ano_eje=2026 AND x.sec_ejec=1750
   AND x.centro_costo=t.CENTRO_COSTO AND x.estado='6'      -- cuadro abierto
  LEFT JOIN dbo.SIG_CENTRO_COSTO cc
    ON cc.ANO_EJE=2026 AND cc.SEC_EJEC=1750 AND cc.CENTRO_COSTO=t.CENTRO_COSTO
  LEFT JOIN usado u
    ON u.CENTRO_COSTO=t.CENTRO_COSTO AND u.SEC_FUNC=t.sec_func
   AND u.CLASIFICADOR=t.CLASIFICADOR AND u.ORIGEN=t.ORIGEN
   AND u.FUENTE_FINANC=t.FUENTE_FINANC
 ORDER BY libre0 DESC;
```

Al 2026-08-19, entre los centros en estado `4`, los de más holgura eran los
grandes: SEI `01.02.02` con 20 millones libres en la meta 194, SEI `01.02.01`
con 12 millones en la meta 22. Entre los pequeños, el único con margen cómodo
era:

| centro | | meta | clasificador | libre año base | ítems del cuadro |
|---|---|---|---|---|---|
| 01.07.05.03 | OTI | 15 | `2.3. 2  9. 1  1` | 131 994 | 16 |

Se eligió **OTI** y no uno de los grandes: en una pantalla con 4 175 líneas no
se distingue la que acaba de registrarse. Quedó sembrado en `S900`.

---

## 4quater. La prueba de punta a punta

`SIGCM_SERVER/db/90_pruebas/S901__prueba_e2e_cmn_siga.sql` recorre el flujo
completo desde el SIGCM; `S902__continuar_anexo4.sql` retoma un expediente ya
validado y lo lleva sólo por el Anexo 4.

Resultado de la corrida del 2026-08-19, expediente **CMN-2026-000009**, en OTI:

| | Anexo 3 validado | Anexo 4 firmado |
|---|---|---|
| `ESTADO` | `I` | `I` |
| `FLAG_MODIFICADO` | `1` | `0` |
| `MOTIVO_SOLICITUD` | `1` | `0` |
| Solicitud SIGA 518 | estado `2` | estado `3` |
| **pedible en SIGA** | **0** | **1** |

El ítem quedó en SIGA como:

```
01.07.05.03 (OTI) / cuadro 1 / item 17
S-21-01-0001-0579  SERVICIO DE SEGUIMIENTO Y MONITOREO DE ACTIVIDADES
                   DE GESTION Y/O ADMINISTRATIVAS
Actividad operativa 1/C/104  GESTION DE LOS SISTEMAS DE INFORMACION
                             E INFRAESTRUCTURA TECNOLOGIA
Meta 15, clasificador 2.3. 2  9. 1  1
4 000 unidades a S/ 1.00 = S/ 4 000, 1 000 por mes de setiembre a diciembre
saldo disponible 4 000, foto previa TIPO='1'
techo de OTI en la meta 15: 312 000 de techo, 184 006 usado
```

Para verlo en el aplicativo: **Logística → Programación → Programación del
C.M.N. → Bienes, Servicios y Obras**, año 2026, área usuaria `01.07.05.03`,
botón *Demanda Adicional - Identificación*. El centro está en estado `4`, así
que la pantalla abre.

Setiembre a diciembre es a propósito: los ítems que OTI ya tenía están cargados
en meses anteriores, así que el nuevo se distingue de un vistazo.

**Queda además `CMN-2026-000008` en OGP** (`01.06.03` / cuadro 1 / ítem 98), de
la corrida anterior. Los datos son correctos y están en la ruta de modificación,
pero ese centro está en estado `6` y su Demanda Adicional no abre. Sirve como
prueba de la escritura, no como demostración visual.

---

## 5. El requerimiento

### Qué es, en tablas

```
Cabecera : SIG_PEDIDOS          con TIPO_PEDIDO='2'
Detalle  : SIG_DETALLE_PEDIDOS
Enlace   : CENTRO_COSTO, SEC_CUADRO, SEC_ITEM, ANNO_PROG, SEC_CUA_MOD_SAL
           (columnas 59 a 63 del detalle) → SIG_CUADRO_MODIFICADO_DET
```

`TIPO_PEDIDO='1'` es el pedido de almacén y **no** se enlaza al CMN. La
diferencia es tajante en 2026:

```
TIPO_PEDIDO  TIPO_BIEN  líneas  con enlace al CMN
2            S            6855       6855
2            B             423        423
1            B            3101          0
```

O sea: **un requerimiento siempre nace de un ítem del CMN**. Sin
`SEC_CUA_MOD_SAL` no hay requerimiento válido.

`SIG_DETALLE_PEDIDO_CUADRO` (124 filas) es el enlace antiguo, hacia el cuadro
de formulación. No se usa en el flujo vigente.

### Qué ítem se puede pedir

Las tres condiciones de la sección 3, que son las del propio cliente. La
segunda es la que más sorprende: **un ítem recién incluido no es pedible**.
Queda en `MOTIVO_SOLICITUD='1'` hasta que la solicitud se aprueba y SIGA lo
devuelve a `'0'`. En 2026 hay 82 ítems en esa situación.

### Valores por defecto, de los 7 278 detalles reales de 2026

```
ESTADO (cabecera) = '0'   registrado; '1' aprobado
ESTADO_PED        = '0'   sigue al de la cabecera
ESTADO_ATEND      = '0'
ESTADO_CONFOR     = '0'
ESTADO_COMPRA     = '0'
ESTADO_PROG       = '1'
FLAG_CAJA         = '0'
CANT_APROBADA     = 0     SIGA no la llena al registrar
VALOR_TOTAL       = 0     7278 de 7278
ANNO_PROG         = ANO_EJE   7278 de 7278
INDICADOR_PEDIDO  = '0'
PROCEDENCIA       = 'M'
tipo_recurso      = '1'
ORIGEN, FUENTE_FINANC = NULL en la cabecera (el rubro vive en el ítem del CMN)
```

`ID_CLASIFICADOR` es obligatorio y sale de `SIG_CLASIFICADOR_GASTO`
(`ANO_EJE + CLASIFICADOR`). No está en `SIG_CUADRO_MODIFICADO_DET`: hay que
buscarlo.

El correlativo `NRO_PEDIDO` es `varchar(6)` con ceros a la izquierda y su
alcance es `ANO_EJE + SEC_EJEC + TIPO_BIEN + TIPO_PEDIDO`: en 2026 la serie
`S/2` va por 7662 mientras la `B/2` va por 109.

### El script

`C:\SIGA_MEF\integracion\usp_ext_registrar_requerimiento.sql`

Recibe la cabecera y un XML de ítems con solo `secCuadro`, `secItem` y
`cantidad`. **No recibe catálogo, unidad, precio, clasificador, meta ni tarea**:
los lee del CMN, que es la única fuente que no puede contradecirse a sí misma.
Si los ítems pertenecen a metas o tareas distintas, rechaza el requerimiento en
vez de grabar una cabecera que miente sobre su detalle.

Descuenta el saldo con el mismo reparto codicioso de enero a diciembre que hace
SIGA, y antes de confirmar comprueba que las dos invariantes del saldo siguen
en pie.

Probado contra un ítem real (`01.02.02` / cuadro 1 / ítem 74) dentro de una
transacción revertida: generó el pedido `007663`, heredó meta 29 y tarea
`2/C/340` del CMN, resolvió `ID_CLASIFICADOR = ACbcxSj`, bajó el disponible de
34 035,76 a 33 535,76 y dejó los totales cuadrando. Después del `ROLLBACK` no
quedó nada.

---

## 6. Datos de prueba: revertidos

Los rastros que habían quedado en `SIGA_1750` se revirtieron el 2026-08-19 con
`revertir_datos_prueba_20260819.sql`, que se autoverifica antes de confirmar.

| Qué | Resultado |
|---|---|
| Ítem `w001` en `SIG_CUADRO_NECESIDAD_DET` `01.09`/170/1 y su cabecera | borrados |
| Ítem real `01.01`/1/1 excluido por `PRUEBA_W001` | **restaurado** a `C`/`C`/`0`/`0` con sus 300 unidades y S/ 3 300, reconstruido desde su propia foto previa |
| Solicitud 442, su detalle y su movimiento de documento | borrados |
| Foto previa con `TIPO='2'` | borrada; ya no queda ninguna en la base |
| Mapeo del SIGCM hacia esa exclusión | retirado de `integracion.MapeoCmn` |

Lo único que no se pudo devolver es `CUSER_MOD` / `FECHA_MOD` / `EQUIPO_MOD`:
la prueba los sobrescribió y su valor anterior no quedaba registrado en ninguna
parte. Se dejaron en `NULL`, que es lo que significa "no modificado".

El saldo nunca hizo falta tocarlo: la exclusión no lo había modificado.

Lo que **sí** queda ahora en la copia local, a propósito, es el resultado de la
prueba de punta a punta: el ítem `01.06.03`/1/98 del expediente
`CMN-2026-000008`. Está para poder abrirlo en el aplicativo.

---

## 7. Qué falta

1. **`MODIFICAR_CANTIDADES`** — la tercera operación del Anexo 3. `W001` la
   encola pero todavía no la expande.
2. **Instalar y homologar `usp_ext_registrar_requerimiento`**, y darle su
   operación en `W001`.
3. **La consolidación del PAAC** queda fuera del SIGCM (sección 4bis). Si el
   ANIN quiere que el SIGCM la dispare, hay que estudiar primero cómo SIGA
   numera el árbol del PAAC.
4. **La firma real.** Hoy es un asiento. Cuando entre el firmador institucional,
   el único punto que cambia es `sigcm.paFirmarDocumento`.
5. Depurar los expedientes de prueba viejos en `DBSIGCM`
   (`CMN-2026-000003`, `000004`, `000006`, `000007`), cuyas operaciones quedaron
   desactivadas al reordenar la integración.

---

## Apéndice: cómo reproducir la evidencia

```sql
-- Las dos rutas y sus fechas
SELECT 'CN' t, MIN(FECHA_REG), MAX(FECHA_REG), COUNT(*)
  FROM dbo.SIG_CUADRO_NECESIDAD_DET WHERE ANO_EJE=2026
UNION ALL
SELECT 'MOD', MIN(FECHA_REG), MAX(FECHA_REG), COUNT(*)
  FROM dbo.SIG_CUADRO_MODIFICADO_DET WHERE ANNO_EJEC=2026;

-- El ciclo de vida, tal como está en los datos
SELECT ESTADO, PROCEDENCIA, FLAG_MODIFICADO, MOTIVO_SOLICITUD, COUNT(*)
  FROM dbo.SIG_CUADRO_MODIFICADO_DET
 WHERE ANNO_EJEC=2026 AND ANNO_PROG=ANNO_EJEC
 GROUP BY ESTADO, PROCEDENCIA, FLAG_MODIFICADO, MOTIVO_SOLICITUD;

-- TIPO en la foto previa
SELECT ANNO_EJEC, TIPO, COUNT(*)
  FROM dbo.SIG_CUADRO_MODIFICADO_DET_ORI GROUP BY ANNO_EJEC, TIPO;

-- Las dos invariantes del saldo
SELECT viola_total = SUM(CASE WHEN CANT_TOTAL <>
         CANT_01+CANT_02+CANT_03+CANT_04+CANT_05+CANT_06+
         CANT_07+CANT_08+CANT_09+CANT_10+CANT_11+CANT_12 THEN 1 ELSE 0 END),
       viola_cmn = SUM(CASE WHEN CANT_TOTAL_CMN <>
         CANT_01_CMN+CANT_02_CMN+CANT_03_CMN+CANT_04_CMN+CANT_05_CMN+CANT_06_CMN+
         CANT_07_CMN+CANT_08_CMN+CANT_09_CMN+CANT_10_CMN+CANT_11_CMN+CANT_12_CMN
         THEN 1 ELSE 0 END)
  FROM dbo.SIG_CUADRO_MODIFICADO_SALDO WHERE ANNO_EJEC=2026 AND SEC_EJEC=1750;

-- El enlace del requerimiento al CMN
SELECT TIPO_BIEN, TIPO_PEDIDO, COUNT(*) lineas,
       con_enlace = SUM(CASE WHEN SEC_CUA_MOD_SAL IS NOT NULL
                             AND SEC_CUA_MOD_SAL<>0 THEN 1 ELSE 0 END)
  FROM dbo.SIG_DETALLE_PEDIDOS WHERE ANO_EJE=2026 AND sec_ejec=1750
 GROUP BY TIPO_BIEN, TIPO_PEDIDO;
```

El SQL del cliente se extrae de los `.pbd` con
`scratchpad/pbdgrep.py <patrón> "C:/SIGA_MEF/SIGA_ML/*.pbd"`. Los módulos que
importan son `sig_aba_dawi21_te.pbd` (elección de ítems para el pedido) y
`sig_aba_wind30.pbd` (exclusión y consumo del saldo).
