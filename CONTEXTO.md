# SIGCM — Documento de contexto

**Punto de entrada del proyecto.** Lo que hay que saber antes de tocar nada, y
dónde está cada cosa. Si algo se decidió y ya no se discute, está aquí o en uno
de los documentos que este enlaza.

Regla de uso: **antes de investigar algo del aplicativo SIGA o de un flujo ya
implementado, buscarlo aquí.** Se ha perdido tiempo más de una vez re-descubriendo
cosas que ya estaban escritas.

---

## 1. Los documentos

| Documento | Qué contiene | Cuándo abrirlo |
|---|---|---|
| [`LEEME.md`](LEEME.md) | El mapa de los cuatro bloques, el **prompt de arranque** y el estado de las copias | Al abrir una ventana nueva |
| **Este** | Contexto, arquitectura y **bitácora de iteraciones** | Siempre, después del LEEME |
| [`ESTANDARES.md`](ESTANDARES.md) | Cómo se escribe el código: BD, backend .NET, frontend Angular | Antes de escribir código |
| [`SIGA_APLICATIVO.md`](SIGA_APLICATIVO.md) | Dónde se ve en SIGA lo que el SIGCM escribe | Al verificar un registro en SIGA |
| [`SIGA/integracion/ANALISIS_CMN.md`](SIGA/integracion/ANALISIS_CMN.md) | El análisis de la integración con SIGA, con la evidencia | Al tocar la integración |

Complementos: [`Analisis/`](Analisis) (las directivas, los modelos Bizagi y las
reglas de negocio derivadas de ellos),
[`db/README.md`](db/README.md)
(orden de instalación y pruebas) y
[`README.md`](README.md).

El repositorio está organizado en **cuatro bloques** —análisis, SIGA, nuestro
proyecto y QA—; el mapa con las rutas de cada uno está en
[`LEEME.md`](LEEME.md), sección 2.

---

## 2. Qué es el sistema

El **SIGCM** gestiona, para la ANIN, el circuito de contrataciones menores a
8 UIT según la Directiva N.° 0007-2025-EF/54.01 y la Directiva N.° 002-2026-ANIN.
Los módulos previstos son CMN, Requerimiento, Ejecución, Pago, Ampliación y
Resolución; hoy están implementados **CMN** y **Requerimiento**.

**No reemplaza a SIGA: lo alimenta.** El SIGCM lleva el trámite —firmas,
derivaciones, plazos, trazabilidad— y en dos momentos concretos escribe en la
base de SIGA a través de procedimientos homologados.

### Los tres repositorios

Cada uno es un repositorio git independiente, con su propio remoto. **Ojo con el
nivel**: el de la base de datos no es `anin_bdsgmc`, sino la carpeta
`sgcm_script` que está dentro.

| Repositorio | Qué es | Rama |
|---|---|---|
| `anin_bdsgmc/sgcm_script` | **Este repo**: documentación del proyecto, análisis, integración SIGA y toda la base de datos | `bd_mrz` |
| `anin_scm_back` | Backend C# / .NET 8 | `dev_mrz` |
| `anin_scm_front` | Frontend Angular | `dev_mrz` |

> **La deriva de agosto no fue por falta de control de versiones.** Convivieron
> dos copias del mismo árbol de scripts —`SIGCM_SERVER/`, fuera del repo, y
> `.` (este repo), dentro— y una sesión editó la de fuera. Git no
> podía ayudar: esa copia nunca estuvo bajo su control. El remedio no es más
> git, es **una sola copia de trabajo**; ver [`LEEME.md`](LEEME.md), sección 3.

---

## 3. La decisión que gobierna todo

**Toda la lógica de negocio vive en la base de datos.** El backend .NET es un
puente: recibe un JSON, completa la identidad del actor desde la sesión, llama a
un procedimiento y devuelve lo que ese procedimiento conteste.

Consecuencia práctica: **si estás escribiendo un `if` de negocio en C# o en
TypeScript, está en el lugar equivocado.** El desarrollo completo está en
[`ESTANDARES.md`](ESTANDARES.md), sección 1.

Corolarios que se dan por sentados:

- La máquina de estados existe **una sola vez**, en `sigcm.Estado` /
  `sigcm.Transicion` / `sigcm.TransicionRol`. La pantalla **no deduce** qué
  acciones ofrecer: se las pregunta a `sigcm.paListarTransicionDisponible`.
- Agregar un escalón a un flujo es **agregar filas**, no desplegar código.
- El motor de transiciones no sabe nada de CMN ni de Requerimiento. Lo único
  específico por módulo es la expansión del encolado hacia SIGA.

---

## 4. Entorno

| | Local | Desarrollo ANIN |
|---|---|---|
| Motor | SQL Server **2025** (`localhost\SQLSERVER25`) | SQL Server **2022** (16.0.4262.2) |
| Base | `DBSIGCM` | `DBSIGCM` |
| Compat level | **160** | **160** |
| Intercalación | `Modern_Spanish_CI_AS` | `Modern_Spanish_CI_AS` |
| Copia de SIGA | `SIGA_1750` | — |

**La línea base es compat 160**, aunque el motor local sea más nuevo. Ningún
script puede usar construcciones de SQL Server 2025 —en particular el tipo
`json` nativo—: el JSON se guarda como `nvarchar(max)` con `CHECK ISJSON`. El
instalador lo verifica antes de tocar la base y aborta si encuentra alguna.

Instalación:

```bash
# desde la raíz de este repo
./instalar.ps1 -ConDatosPrueba
```

Ingreso sin SSO para probar: `/acceso-local`, eligiendo perfil. **Hay que
cambiar de perfil en cada transferencia del flujo.**

---

## 5. La integración con SIGA

Lo esencial en cinco puntos. El detalle está en
[`SIGA_APLICATIVO.md`](SIGA_APLICATIVO.md) y en `ANALISIS_CMN.md`.

1. **Se escribe en dos momentos, no en uno.** La firma del jefe de Abastecimiento
   sobre el **Anexo 3** registra el ítem; la firma sobre el **Anexo 4** lo
   habilita.
2. **La diferencia entre los dos la marca `MOTIVO_SOLICITUD`**: `1` = existe pero
   no es pedible; `0` = pedible. El selector de ítems de un requerimiento exige
   `MOTIVO_SOLICITUD IN ('0','3')`.
3. **Dónde se ve:** `Logística → Programación → **Modificación de C.M.N.** →
   Bienes, Servicios y Obras`. **No** en *Programación del C.M.N.* y **no** en
   *Demanda Adicional*.
4. **El Anexo 4 no consolida.** Consolidar es generar el árbol del PAAC, un
   proceso por lotes de SIGA. No encontrar lo nuestro en *Consolidado del
   C.M.N.* es lo esperado.
5. **La escritura pasa por un outbox.** `sigcm.paEjecutarTransicion` encola en
   `integracion.Operacion` con una clave de idempotencia determinista; un worker
   del backend la drena llamando a `integracion.paEscribirCuadroModificado`
   (W001), que a su vez invoca los procedimientos de SIGA por sinónimo.

### Regla: sobre `SIGA_1750` sólo escribe el flujo

**Nada de `UPDATE` ni `DELETE` a mano en la base de SIGA**, ni siquiera sobre
filas que escribió nuestra propia integración. La única escritura legítima es la
que pasa por los `usp_ext_*` homologados, invocados desde W001.

Un parche a mano deja la base en un estado que ningún camino del sistema puede
reproducir: la próxima vez que algo no cuadre, no se sabrá si fue el flujo o el
parche. Y si la data quedó mal, el defecto está en quien la escribió.

Cuando algo salga mal: **corregir el sistema, dejar la fila donde está, y rehacer
el caso desde el SIGCM.** Consultar `SIGA_1750` cuanto haga falta; escribir,
nunca fuera del flujo.

Esto alcanza también a `flag_da_aprob`: es una decisión de gestión que otorga
Abastecimiento desde SIGA, y además **no hace falta** para la ruta de
Modificación de C.M.N., que es la que usamos.

### Restricciones de SIGA que ya nos mordieron

- Los procedimientos de SIGA se llaman con `INSERT ... EXEC`, y eso impone dos
  cosas: **no pueden devolver filas** (llevan `@Detalle bit = 0`) y **no pueden
  hacer `ROLLBACK`** de una transacción que no abrieron (llevan `@trnPropia`).
- Por la misma razón, **una rutina del SIGCM no puede fallar bajo
  `INSERT ... EXEC`** en una prueba: la transacción implícita queda no
  confirmable y el script muere con un 3915/3930 que no dice nada. Para probar
  rechazos hay que llamarla con `EXEC` a secas y comprobar el efecto.
- Todas las rutinas llevan `XACT_ABORT ON`, y su `CATCH` **sólo deshace la
  transacción propia** (`@TranPropia`). Antes deshacía también la del llamador.

---

## 6. Bitácora de iteraciones

Qué se implementó en cada una y qué quedó decidido. **Se agrega una entrada por
iteración**, arriba del todo.

### 2026-08-20 — Flujo CMN con tres perfiles de Abastecimiento y Anexo 4 múltiple

**Qué pidió el negocio.** Que el circuito de Abastecimiento pase por sus tres
escalones —jefe, coordinador, especialista— y que el Anexo 4 pueda agrupar
Anexos 3 de varias áreas usuarias en un solo documento.

**El flujo, en una línea por escalón:**

```
área usuaria    BORRADOR → PEND_FIRMA_A3 → A3_FIRMADO
OA              EN_EVAL_OA
Abastecimiento  EN_ABAST_JEFE → EN_ABAST_COORD → EN_ABAST_ESP
  con obs.      OBS_ABAST_COORD → OBS_ABAST_JEFE
                → OBS_AU_JEFE → OBS_AU_COORD → OBSERVADO
                → SUBS_AU_COORD → SUBS_AU_JEFE → EN_ABAST_JEFE
  sin obs.      A3_FIRMA_COORD → A3_FIRMA_JEFE → A3_APROBADO   ◄ escribe en SIGA
Anexo 4         A4_FIRMA_COORD → A4_FIRMA_JEFE                 ◄ aprueba en SIGA
cierre          A4_ENVIADO → FINALIZADO
```

**Qué se construyó:**

| Pieza | Dónde |
|---|---|
| `cmn.Paquete` + `cmn.PaqueteSolicitud`, firma parcial, `RolFirmaRequerida` | `db/00_ddl/V011__cmn_paquete_anexo4.sql` |
| Generar / obtener / anular el Anexo 4 | `db/10_api/F007__cmn_anexo4.sql` |
| Firma en cadena sobre `sigcm.Firma`; documento consolidado N:M | `db/10_api/F003__documentos_firmas.sql` |
| Transición sobre un **lote** de expedientes; enrutamiento por unidad de origen | `db/10_api/F004__transicion_encolado.sql` |
| 23 estados y 24 transiciones; las 7 del flujo anterior quedan desactivadas | `db/20_seed/S001__roles_estados_transiciones.sql` |
| Endpoints `generarAnexo4`, `obtenerAnexo4`, `anularAnexo4` | `../../anin_scm_back/…/CmnController.cs` |
| Selección múltiple, «Generar Anexo 4 múltiple», PDF agrupado por área | `../../anin_scm_front/…/gestion-cmn/` |

**Decisiones que no hay que volver a discutir:**

- **El Anexo 4 no tiene expediente propio.** El expediente es la unidad de
  trazabilidad frente al área usuaria, y ella sigue preguntando por *su* Anexo 3.
  La máquina de estados corre sobre los expedientes de los Anexos 3 y
  `paEjecutarTransicion` los mueve **todos en una transacción** cuando recibe
  `IdExpedientes`. Un Anexo 4 con tres expedientes movidos y dos sin mover no
  corresponde a ningún estado del trámite.
- **El Anexo 3 lleva cuatro firmas y el Anexo 4 tres.** Fue posible sólo tras
  arreglar `sigcm.paFirmarDocumento`, que cerraba la versión en la **primera**
  firma. Ahora registra firma por firma en `sigcm.Firma` —tabla que siempre
  estuvo diseñada para eso— y la versión queda `PARCIAL` hasta la última.
- **Un Anexo 4 ordinario sólo se genera los viernes**; el urgente, cualquier
  día. El tipo se declara al conformar el Anexo 3 y se comprueba con `DATEDIFF`,
  no con `DATEPART(weekday)`, que depende de `SET DATEFIRST`.
- **Un Anexo 3 no puede integrar dos Anexos 4** (índice único filtrado sobre
  `cmn.PaqueteSolicitud.IdSolicitud`).
- La asimetría es deliberada: el **coordinador del área usuaria** participa en la
  devolución de observaciones y en la subsanación, **no** en el envío inicial.
  Es lo que especificó el negocio.

**Cómo se prueba:**

| Script | Qué hace | Toca SIGA |
|---|---|---|
| `db/90_pruebas/S903__prueba_anexo4_multiple.sql` | Circuito completo con dos áreas; se limpia sola, repetible | no |
| `db/90_pruebas/S904__casos_anexo4_multiple.sql` | Deja 4 Anexos 3 en borrador, uno por área real, para recorrer a mano | no |
| `db/90_pruebas/S901__prueba_e2e_cmn_siga.sql` | Punta a punta contra SIGA | **sí** |

**Pendiente:** commitear el trabajo de la iteración en los tres repositorios, y
retirar del disco las copias de trabajo duplicadas (`SIGCM_SERVER/`,
`SistemaSIGCM/SIGA/`, `SistemaSIGCM/Analisis/`), ya consolidadas.

---

### 2026-08-20 (tarde) — El Tipo Uso que escondía el ítem

**Síntoma.** Firmado el Anexo 3, el ítem «no aparecía» en SIGA. La transición
respondía `estado: 1` y `OperacionesEncoladas: 1`.

**Qué pasaba en realidad.** Sí se había registrado. La operación estaba
`COMPLETADO`, el ítem en SIGA con `ESTADO='I'` y `MOTIVO_SOLICITUD='1'`, y la
solicitud de modificación creada en estado `2`. Todo correcto.

Lo que fallaba era **dónde salía en pantalla**. La grilla de *Modificación de
C.M.N. por Área Usuaria* agrupa por Actividad Operativa **y por Tipo Uso**, y el
ítem tenía `TIPO_USO='X'` mientras las otras 8 222 líneas del cuadro 2026 llevan
`'C'`. Caía en un grupo aparte al final, con su propio subtotal.

**La causa.** El frontend copiaba el `TipoUso` de la **tarea** a la línea del
cuadro: `item.TipoUso = tarea?.TipoUso || item.TipoUso`. Son dos conceptos
distintos que se llaman igual — uno clasifica la tarea, el otro el ítem del
cuadro. La tarea `1/C/104` de la OTI trae `'X'`.

**Arreglo.** Se quitó esa línea de `elegirTarea`. Para una inclusión el valor lo
pone el `DEFAULT` de `cmn.SolicitudItem` (`'C'`); para exclusión o modificación
se copia de la línea vigente del cuadro, que ya es lo que hacían `elegirCuadro`
y `elegirCatalogo`. Corrección de lo ya escrito:
`SIGA/integracion/corregir_tipo_uso_20260820.sql`.

**Lo que hay que recordar.** `OperacionesEncoladas` no es «escritas». Antes de
dar por fallida una escritura, mirar `integracion.Operacion`: el estado ahí
distingue «no salió» de «salió y no lo estás viendo». Quedó documentado en
[`SIGA_APLICATIVO.md`](SIGA_APLICATIVO.md), sección 4bis.

---

### 2026-08-19 — Integración con SIGA operativa

Los dos momentos de escritura funcionando de punta a punta contra `SIGA_1750`.
Se homologaron `usp_ext_incluir_item_cmn`, `usp_ext_excluir_item_cmn` y
`usp_ext_aprobar_solicitud_cmn`; W001 los invoca por sinónimo. Expediente de
referencia: `CMN-2026-000009`, OTI. Detalle y evidencia en `ANALISIS_CMN.md`.

Quedó establecido que la vista correcta es **Modificación de C.M.N.**, no
*Demanda Adicional* — y aun así se volvió a errar después, que es lo que motivó
[`SIGA_APLICATIVO.md`](SIGA_APLICATIVO.md).

---

### 2026-08-18 — Gestión documental y requerimientos

Documentos con versionado e invalidación de firma, subida al file server,
módulo Requerimiento, ingreso local sin SSO y correlativos por tabla en lugar de
`SEQUENCE` (una secuencia entrega el número fuera de la transacción y deja
huecos en la numeración de un expediente).

---

### 2026-08-12 — Migración a SQL Server y ADR

Cuatro decisiones de arquitectura aprobadas y el paso de PostgreSQL a SQL
Server, con compat 160 como línea base.

---

## 7. Cómo agregar una iteración a esta bitácora

Al cerrar un cambio de flujo o de módulo, agregar arriba una entrada con:

1. **qué pidió el negocio**, en sus términos;
2. **el flujo resultante**, en forma de cadena de estados;
3. **qué se construyó**, con la tabla de piezas y archivos;
4. **las decisiones que no hay que volver a discutir**, con el porqué —esto es
   lo que evita rehacer el análisis en tres meses—;
5. **cómo se prueba**, y si el script toca SIGA o no;
6. **lo que quedó pendiente**.
