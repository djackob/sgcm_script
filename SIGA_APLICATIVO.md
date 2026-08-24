# SIGA — Manual del aplicativo para el equipo del SIGCM

**Qué es este documento.** Dónde se ve, dentro del aplicativo SIGA, lo que el
SIGCM escribe. Nada más. No explica SIGA entero: explica las cuatro pantallas
que tocamos y cómo distinguir en ellas el momento del Anexo 3 del momento del
Anexo 4.

**Por qué existe.** Se perdieron horas buscando los ítems en *Demanda
Adicional — Identificación*, que es la pantalla equivocada, en más de una
sesión. La ruta correcta ya estaba en el análisis y aun así se volvió a errar.
Este archivo es la respuesta corta, para no volver a abrirlo.

---

## 1. La regla de una línea

> Lo que el SIGCM registra se ve en
> **Logística → Programación → Modificación de C.M.N. → Bienes, Servicios y Obras**.

No en *Programación del C.M.N.* Y no en *Demanda Adicional*.

---

## 2. Por qué no es donde uno cree

El módulo Logística separa las **tres etapas** del CMN en ramas distintas del
menú, y cada rama lee una tabla distinta. Ese es todo el enredo:

```
Programación ─┬─ Techo Presupuestal
              ├─ Programación del C.M.N.  ──► el cuadro tal como se FORMULÓ
              │                              SIG_CUADRO_NECESIDAD / _DET
              ├─ Modificación de C.M.N.   ──► lo que se MODIFICA durante el año
              │                              SIG_CUADRO_MODIFICADO_DET   ◄── AQUÍ
              └─ Consolidado del C.M.N.   ──► el consolidado y el PAAC
                                             SIG_CUADRO_MODIFICADO_CMN
```

| Rama del menú | Id | Tabla que lee |
|---|---|---|
| Programación del C.M.N. → Bienes, Servicios y Obras | 10019 | `SIG_CUADRO_NECESIDAD_DET` |
| Modificación de C.M.N. → Gastos Generales | 10026 | `SIG_CUADRO_MODIFICADO_DET` |
| **Modificación de C.M.N. → Bienes, Servicios y Obras** | **10027** | **`SIG_CUADRO_MODIFICADO_DET`** |
| **Modificación de C.M.N. → Solicitud de Modificación** | **10028** | **`SIG_SOLICITUD_MODIFICACION`** |
| Modificación de C.M.N. → Transferencia de Modificación | 10029 | — |
| Consolidado del C.M.N. → Consolidado C.M.N. Actualizado | 10031 | `SIG_CUADRO_MODIFICADO_CMN` + PAAC |

### El error que hay que dejar de cometer

**«Demanda Adicional» es un BOTÓN dentro de la pantalla de formulación**, no la
vista del cuadro modificado. Tiene tres problemas para lo nuestro:

1. cuelga de *Programación del C.M.N.*, que lee la tabla equivocada;
2. exige la habilitación `SIG_CUADRO_X_CENTRO.flag_da_aprob`, que en la copia
   local está en `NULL` para todos los centros y que **sólo otorga
   Abastecimiento desde SIGA**;
3. muestra la demanda adicional **en curso**: en cuanto el Anexo 4 se firma, el
   ítem pasa a `MOTIVO_SOLICITUD='0'` y **desaparece de ahí**. O sea que en el
   único momento en que uno quiere confirmar que todo salió bien, esa pantalla
   está vacía.

La ruta de *Modificación de C.M.N.* no pide `flag_da_aprob` y muestra el ítem en
los dos momentos. Es la que sirve.

---

## 3. Las dos pantallas que usamos

### 3.1 Modificación de C.M.N. por Área Usuaria

`Logística → Programación → Modificación de C.M.N. → Bienes, Servicios y Obras`

Cómo llegar al ítem:

1. **Año**: `2026`
2. **Área Usuaria**: el centro de costo (`01.07.05.03`, `01.07.05.01`, …). Si el
   combo está vacío, se busca con el binocular; el filtro admite código o
   descripción.
3. **Tipo**: `Servicio` (o `Bien`, según lo registrado). Sin esto la grilla no
   trae nada.
4. La grilla se agrupa por **Actividad Operativa** (`C0104 : GESTIÓN DE LOS
   SISTEMAS DE INFORMACIÓN…`).

Qué mirar en la fila:

| Columna | Qué debe decir | Sale de |
|---|---|---|
| **Incl / Excl** | **`I`** para una inclusión, `E` para una exclusión | `ESTADO` del detalle |
| Item | el código de catálogo, p. ej. `210100010579` | `TIPO_BIEN`+`GRUPO`+`CLASE`+`FAMILIA`+`ITEM` |
| Descripción | la del ítem de catálogo | `CATALOGO_BIEN_SERV.NOMBRE_ITEM` |
| Clasificador | el que se envió, p. ej. `2.3. 2  9. 1  1` | `CLASIFICADOR` |
| Meta | p. ej. `0015` | `SEC_FUNC` |
| 2026 → Mnto. Total | el monto de la inclusión | `MNTO_TOTAL` del `ANNO_PROG` 2026 |

Las filas con `I` en *Incl / Excl* y sin marca en *Cert* son las que puso el
SIGCM. Conviven con las que registraron usuarios reales; se distinguen por el
código de ítem y por el monto.

> **Truco para encontrarlas rápido:** las cargamos de **setiembre a diciembre**
> a propósito. Lo que las áreas ya tenían está en meses anteriores, así que la
> línea nueva salta a la vista.

### 3.2 Registro de Solicitud de Modificación

`Logística → Programación → Modificación de C.M.N. → Solicitud de Modificación`

Cómo llegar:

1. **Año** `2026`, **Mes** el de la prueba (o marcar **Todos**).
2. **Nº Solicitud**: marcar **Todos**.
3. **Área Usuaria**: el binocular abre *Filtro para Búsqueda de Datos*; buscar
   por **Descripción** (`TEC` trae las tres que contienen «TECNOLOG»).
   Ojo: `01.07.05` y `01.07.05.03` se llaman casi igual — la que usamos es la
   que **termina en punto**, `01.07.05.03 OFICINA DE TECNOLOGÍAS DE LA
   INFORMACIÓN.`
4. La lista de la izquierda trae **Número · Fecha · Estado**. Doble clic (o el
   icono de la derecha) abre *Registro de Solicitud*.

Las solicitudes del SIGCM se reconocen por el **Sustento**:

```
INCLUSION CMN INTEGRADA DESDE SIGCM
```

---

## 4. Cómo distinguir el Anexo 3 del Anexo 4

Ésta es la tabla que cierra la duda. Los dos momentos escriben en SIGA; lo que
cambia es el estado.

| | **Después del Anexo 3** | **Después del Anexo 4** |
|---|---|---|
| Transición del SIGCM que lo produce | `CMN_ABAST_JEFE_FIRMAR_A3` | `CMN_ABAST_JEFE_FIRMAR_A4` |
| Procedimiento de SIGA | `usp_ext_incluir_item_cmn` | `usp_ext_aprobar_solicitud_cmn` |
| **Pantalla *Solicitud de Modificación* → Estado** | **`V.B. Jefe`** | **`Aprobado`** |
| **Fecha de V.B. Jefe** | con fecha | con fecha |
| **Fecha de Aprobación** | **vacía** | **con fecha** |
| `SIG_SOLICITUD_MODIFICACION.ESTADO` | `2` (enviada) | `3` (aprobada) |
| Pantalla *Bienes, Servicios y Obras* → Incl/Excl | `I` | `I` (no cambia) |
| `SIG_CUADRO_MODIFICADO_DET.ESTADO` | `I` | `I` (no cambia) |
| `FLAG_MODIFICADO` | `1` | `0` |
| **`MOTIVO_SOLICITUD`** | **`1`** | **`0`** |
| ¿El ítem se puede pedir en un requerimiento? | **NO** | **SÍ** |

**La columna que decide es `MOTIVO_SOLICITUD`.** El selector de ítems de un
requerimiento exige `MOTIVO_SOLICITUD IN ('0','3')`. Mientras valga `1`, el
ítem existe en SIGA pero SIGA no lo deja pedir. Eso no es un defecto: es
exactamente lo que significa «Anexo 3 firmado, Anexo 4 pendiente».

En una línea:

```
Anexo 3 firmado  ->  el ítem EXISTE en SIGA, pero no es pedible   (V.B. Jefe)
Anexo 4 firmado  ->  el ítem queda HABILITADO                      (Aprobado)
```

### Lo que el Anexo 4 NO hace

**No consolida.** `SIG_CUADRO_MODIFICADO_CMN` tiene una clave foránea de diez
columnas contra `SIG_PAAC_CENTRO_COSTO`: consolidar es generar el árbol del
PAAC, un proceso por lotes de SIGA. De las 5 837 inclusiones aprobadas de 2026,
sólo 4 406 están consolidadas. Buscar lo nuestro en *Consolidado del C.M.N.* y
no encontrarlo **es lo esperado**.

---

## 4bis. Si el ítem «no aparece»

Antes de dar por fallida la escritura, **mirar la cola**. La transición responde
`OperacionesEncoladas`, no «escritas»: si el worker de integración no la drenó,
la operación sigue `PENDIENTE` y en SIGA no hay nada todavía.

```sql
-- DBSIGCM: en qué quedó la operación de ese expediente
SELECT o.Operacion, o.Estado, o.Intentos, o.ErrorCodigo,
       LEFT(ISNULL(o.ErrorMensaje,''), 250) AS Error, o.CompletadoEn
  FROM integracion.Operacion AS o
 WHERE o.IdExpediente = '<guid>'
 ORDER BY o.FechaCreacionAuditoria;
```

| Estado | Qué significa |
|---|---|
| `PENDIENTE` | Todavía no salió. El worker no corrió, o está apagado. |
| `COMPLETADO` | **Sí se escribió.** Si no lo ves, es un problema de la pantalla, no de la escritura. Sigue leyendo. |
| `ERROR` | SIGA rechazó. `ErrorMensaje` trae el motivo: techo, maestro, catálogo. |

### La trampa del Tipo Uso  *(2026-08-20)*

La grilla de *Modificación de C.M.N. por Área Usuaria* **agrupa por Actividad
Operativa Y por Tipo Uso**. Un ítem con un `TIPO_USO` distinto al del resto cae
en un **grupo aparte al final**, con su propio subtotal, lejos de donde lo
buscas — aunque esté perfectamente registrado.

Pasó una vez y costó un rato: el frontend copiaba el `TipoUso` de la **tarea** a
la línea del cuadro. Son dos conceptos que se llaman igual. La tarea `1/C/104`
de la OTI trae `'X'`; las 8 222 líneas del cuadro modificado de 2026 llevan
`'C'`. El ítem se registró bien —estado, techo y solicitud correctos— pero
quedó visualmente huérfano.

Corregido en `elegirTarea` del frontend. **Las líneas que ya quedaron con `'X'`
se dejan como están**: no se corrige data dentro de `SIGA_1750` (ver la regla al
final de esta sección). Se comprobó que el `'X'` no rompe nada —el Anexo 4 las
aprueba igual, y ni el saldo ni la consolidación tienen esa columna—, así que lo
único que provoca es que salgan en un grupo aparte de la grilla. Para tener el
caso limpio, se rehace desde el SIGCM con el frontend ya corregido.

```sql
-- ¿Alguna línea nuestra quedó con un Tipo Uso raro?  (solo lectura)
SELECT d.CENTRO_COSTO, d.SEC_ITEM, d.TIPO_USO, COUNT(*) AS filas
  FROM dbo.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC = 2026 AND d.SEC_EJEC = 1750 AND d.TIPO_USO <> 'C'
 GROUP BY d.CENTRO_COSTO, d.SEC_ITEM, d.TIPO_USO;
```

### Regla: no se corrige data dentro de SIGA_1750

**Sobre `SIGA_1750` sólo escribe el flujo**, a través de los `usp_ext_*`
homologados. Nada de `UPDATE` ni `DELETE` a mano, ni siquiera sobre filas que
escribió nuestra propia integración.

El motivo es que un parche a mano deja la base en un estado que ningún camino
del sistema puede reproducir: la próxima vez que algo no cuadre, no se sabrá si
fue el flujo o el parche. Y si la data está mal, el defecto está en quien la
escribió, no en la fila.

Cuando algo salga mal:

1. corregir el sistema —frontend, rutina o procedimiento—;
2. dejar la fila mala donde está, y anotar por qué es inofensiva;
3. rehacer el caso de prueba desde el SIGCM, que es el único camino válido.

Consultar `SIGA_1750` cuanto haga falta. Escribir, nunca fuera del flujo.

Otras dos razones por las que un ítem parece no estar, y no es cierto:

- **El filtro `Tipo` está en el valor equivocado.** Si registraste un servicio y
  la pantalla está en `Bien`, la grilla no lo trae.
- **Estás mirando la rama equivocada del menú.** Ver la sección 2.

---

## 5. Verificación por consulta, cuando la pantalla no basta

Para confirmar sin abrir el aplicativo (`SIGA_1750`):

```sql
-- ¿En qué momento está la solicitud?
SELECT SEC_SOL_MOD, CENTRO_COSTO, ESTADO, FECHA, LEFT(GLOSA,45) AS GLOSA
  FROM dbo.SIG_SOLICITUD_MODIFICACION
 WHERE ANNO_EJEC = 2026 AND SEC_EJEC = 1750
   AND GLOSA LIKE '%SIGCM%' COLLATE Modern_Spanish_CI_AI
 ORDER BY SEC_SOL_MOD DESC;
-- ESTADO 2 = V.B. Jefe (Anexo 3)   ESTADO 3 = Aprobado (Anexo 4)

-- ¿Cómo quedó el ítem?
SELECT SEC_CUADRO, SEC_ITEM, ANNO_PROG, ESTADO, PROCEDENCIA,
       FLAG_MODIFICADO, MOTIVO_SOLICITUD, CANT_TOTAL, MNTO_TOTAL
  FROM dbo.SIG_CUADRO_MODIFICADO_DET
 WHERE ANNO_EJEC = 2026 AND SEC_EJEC = 1750
   AND CENTRO_COSTO = '01.07.05.03'
 ORDER BY SEC_ITEM DESC, ANNO_PROG;
-- MOTIVO_SOLICITUD 1 = Anexo 3     0 = Anexo 4
```

Y desde el lado del SIGCM, el puente entre ambos mundos:

```sql
-- DBSIGCM: qué expediente produjo qué registro en SIGA
SELECT s.Codigo, m.SecCuadro, m.SecItem, m.SecSolicitud
  FROM integracion.MapeoCmn AS m
  JOIN cmn.Solicitud AS s ON s.IdSolicitud = m.IdSolicitud
 ORDER BY s.Codigo DESC;
```

---

## 6. Las tres condiciones para que un área usuaria sirva de prueba

Ninguna la valida la base. Si falta alguna, la escritura funciona igual pero el
registro queda invisible o el techo lo rechaza.

1. **`SIG_CUADRO_X_CENTRO.estado = '4'`** — se muestra como *Consolidación y
   Aprobación*. El `'6'` se muestra como *C.C.M.N.* y **no sirve**, aunque suene
   a lo contrario; ya se leyó al revés una vez.
2. **Techo libre** en esa meta y clasificador. El techo se compara por
   `CENTRO_COSTO + SEC_FUNC + CLASIFICADOR + ORIGEN + FUENTE_FINANC`, no por
   centro entero.
3. **Tarea activa** en ese centro (`SIG_CENTRO_COSTO_TAREA.estado = 'A'`).

`flag_da_aprob` **no** hace falta para la ruta de Modificación. Sólo la pide
*Demanda Adicional*, que no usamos.

Áreas verificadas al **2026-08-20** (las que siembra
`db/90_pruebas/S904__casos_anexo4_multiple.sql`):

| Centro | Área | Meta | Clasificador | Libre 2026 | Ítems del cuadro |
|---|---|---|---|---|---|
| `01.07.05.03` | OTI | 15 | `2.3. 2  9. 1  1` | 123 994 | 18 |
| `01.07.05.01` | UDS | 11 | `2.3. 2  5. 1 99` | 360 731 | 36 |
| `01.07.05.02` | US | 14 | `2.3. 2  9. 1  1` | 102 999 | 192 |
| `01.07.04` | ORH | 18 | `2.3. 2  7. 3  1` | 68 700 | 147 |

> **`01.01` (JEFATURA) no sirve para verificar en el aplicativo**: su cuadro
> está en estado `6`. Se puede usar para ejercitar el SIGCM —`S903` lo hace—
> pero lo que se registre ahí no se verá nunca en SIGA.

---

## 7. Referencias

| Documento | Qué tiene |
|---|---|
| `CONTEXTO.md` | El contexto del proyecto y la bitácora de iteraciones |
| `SIGA/integracion/ANALISIS_CMN.md` | El análisis completo de la integración, con la evidencia |
| `SIGA/entregables/Manual_Verificacion_SIGCM_en_SIGA.docx` | Este mismo recorrido con las capturas de pantalla |
| `SIGA/integracion/captura_siga_xe.sql` | Extended Events, para ver el SQL real que envía el aplicativo |
