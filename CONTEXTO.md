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

### 2026-08-27 — El SSO trae el padrón, y el árbol de derivación es dato

**Qué pidió el negocio.** Integrar el SSO institucional de verdad: traer su data
con el centro de costo y relacionarla con nuestro sistema. Y registrar el árbol
de perfiles **jefe → coordinador → especialista**, con dos reglas: en CMN el área
usuaria **no** pasa por el coordinador, en Requerimiento sí; y el jefe puede
derivar a un coordinador o directamente a un especialista.

**Lo que había que entender primero.** El `centro_costo` **no identifica a una
persona: identifica al área.** Es el código presupuestal de la unidad orgánica
(`01.07.03.01` = Unidad de Abastecimiento), y el jefe, el coordinador y el
especialista de esa unidad lo comparten. De ahí sale la unidad de razonamiento
del árbol:

> **puesto = (`cod_perfil`, `centro_costo`)**

Un puesto puede tener varios ocupantes —`ESPECIALISTA UA @ 01.07.03.01` son
dos—. Por eso **la derivación se configura por perfil y se resuelve a persona en
el momento de derivar**. En la configuración no hay un solo nombre propio.

**Qué se construyó:**

| Pieza | Dónde |
|---|---|
| `sigcm.PerfilSso`, `sigcm.RolDerivacion`, `sigcm.UnidadTramitadora`, `sigcm.SincronizacionSso`, `IdUsuarioSso` / `IdDependenciaSso` | `db/00_ddl/V016` |
| Reconciliación del padrón, `fnDestinatarioDerivacion`, listado de perfiles y de destinatarios | `db/10_api/F008` |
| `paEjecutarTransicion` acepta `IdResponsableDestino` y lo valida contra el árbol | `db/10_api/F004` |
| `paObtenerSesion` marca el `Origen` de la sesión | `db/10_api/F006` |
| Mapeo de los 14 `cod_perfil` y las 10 aristas del árbol | `db/20_seed/S005` |
| Las dos transiciones del salto directo jefe→especialista | `db/20_seed/S006` |
| Panel de accesos y perfiles, solo lectura | `db/10_api/F009`, `db/20_seed/S007` |
| Pantalla del panel | `../../anin_scm_front/…/modules/mantenimiento-sso/` |
| Prueba de alta, baja, re-alta, los dos flujos y la derivación (15 comprobaciones) | `db/90_pruebas/S907` |
| Modal de derivación en la bandeja de CMN | `../../anin_scm_front/…/gestion-cmn/` |
| Cadena `cnx_saa_` y lector del padrón | `../../anin_scm_back/…/appsettings.json`, `DaProcesoSso.cs` |
| Ingreso por SSO de punta a punta | `../../anin_scm_back/…/SsoAccesoService.cs`, `TokenController.cs` |
| Selector de perfil cuando la persona ejerce varias ternas | `../../anin_scm_front/…/modules/sso/` |

**Decisiones que no hay que volver a discutir:**

- **La sincronización es por diferencia de conjuntos, no un upsert.** El SSO da
  de baja poniendo `td_login_acceso.activo` en `false`, y su vista filtra por esa
  columna: **la persona dada de baja no llega marcada como inactiva, desaparece
  del resultado.** Un upsert de lo que llega jamás se enteraría, porque quien se
  fue ya no vuelve a entrar. Se trata el padrón como la verdad completa y lo que
  falta se cierra con `VigenteHasta`. Hay 43 accesos inactivos contra 20 activos:
  la baja es la operación frecuente, no la rara.
- **Se sincroniza en cada ingreso.** Son veinte filas; cuesta menos que validar
  el token. Lo caro es una lista de derivación que ofrece a quien renunció.
- **Tres salvaguardas, y las tres son necesarias.** Un padrón vacío **aborta**
  (51603) en vez de dar de baja a la entidad entera; solo se cierran asignaciones
  de usuarios con `IdUsuarioSso`, así que los ficticios de S900 y las cuentas
  técnicas quedan fuera; y `Completo = 0` permite sincronizar sin cerrar nada.
- **El módulo es columna de `sigcm.RolDerivacion`.** Que en CMN el área usuaria
  no pase por el coordinador no es un `if`: es que **esa fila no existe** para
  ese módulo. El salto directo del jefe al especialista tampoco es una excepción,
  es otra arista con `Orden` 2.
- **`IdResponsableActual` es una indicación, nunca el único filtro de la
  bandeja.** La bandeja sigue resolviendo por unidad y rol (`F002`), así que el
  expediente de quien se va lo ve su reemplazo sin que nadie lo reasigne.
  Filtrarla solo por responsable recrearía el expediente huérfano.
- **La misma función valida y alimenta la pantalla.** `fnDestinatarioDerivacion`
  la usan el listado y `paEjecutarTransicion`. Si la pantalla lo ofrece, la
  transición lo acepta: no pueden discrepar.
- **`sigcm.Unidad` se sincroniza del SSO, emparejando por centro de costo.**
  `tm_login_dependencia` trae sigla, nombre, centro de costo e `id_padre`, así
  que el árbol de áreas viene armado. El emparejamiento va por centro de costo
  **antes** que por el id del SSO: si no, una base con `UO-UDS` de S900 acabaría
  con dos unidades para el mismo centro de costo y la bandeja partida en dos.
- **`EsAreaUsuaria` vive en `sigcm.UnidadTramitadora`, no en un `UPDATE` de la
  semilla.** Cuando S005 corre, las unidades todavía no existen: las crea la
  primera sincronización. El `UPDATE` no encontraba nada y Abastecimiento quedaba
  marcado como área usuaria —pasó, y así se descubrió—.
- **`PE019 EXTERNO` no se mapea a propósito.** Darle un rol del flujo por
  descarte sería inventarle una autorización. Queda reportado en `Descartes` de
  cada sincronización, que es la visibilidad que corresponde.
- **La identidad se ancla en `id_usuario` del SSO**, no en el DNI ni en el
  nombre: si le corrigen el documento, sigue siendo la misma persona.
- **Un re-alta abre una fila nueva y conserva la cerrada.** El historial es lo
  que permite responder quién ejercía qué rol el día que se firmó un Anexo 3.
- **La baja cierra con `VigenteHasta` Y con `Activo = 0`.** El predicado de
  vigencia de todo el sistema es `VigenteHasta IS NULL OR VigenteHasta >= hoy`,
  o sea que *«vigente hasta hoy» todavía vale hoy*: una baja y un re-alta el
  mismo día dejaban a la persona **duplicada** en la lista de derivación. Se vio
  contra el padrón real. Adelantar la fecha un día violaría
  `CK_sigcm_UsuarioRol_Vigencia`, y cambiar el predicado obligaría a tocar F001,
  F004 y F006 por un caso de borde; `Activo` es el borrado lógico que la tabla ya
  declara y que todos los consumidores ya filtran.
- **La lista de destinatarios llega acotada al rol del estado destino.** El
  filtro vive en `paListarDestinatarioDerivacion`, no en el cliente: cruzarlo en
  TypeScript sería reimplementar un pedazo de la máquina de estados. Una acción
  que no es derivación devuelve lista vacía y la pantalla no pregunta nada.
- **El salto directo necesitaba dos transiciones que no existían** (`S006`). El
  árbol de `S005` ya declaraba la arista, pero desde `CMN_EN_ABAST_JEFE` la única
  salida era hacia el coordinador. No hubo inconsistencia visible —el filtro por
  rol destino no ofrecía lo que no se podía cumplir—, sólo una capacidad que
  faltaba. Los estados destino ya existían: fueron dos filas.
- **El camino largo no se retira.** Las dos rutas conviven y el jefe elige, que
  es la lectura literal de lo que pidió el negocio. Quitar el escalón del
  coordinador es una decisión distinta, que afecta expedientes en curso.
- **Elegir persona es opcional aunque haya lista.** Sin elección el expediente
  queda a nombre del puesto, como siempre. Con un solo puesto y un solo ocupante
  la pantalla lo preselecciona, pero lo muestra: el jefe tiene que ver a quién se
  lo está pasando.
- **Un fallo al listar destinatarios no bloquea la acción.** Sin lista, la
  derivación se comporta como antes. Impedir una acción del flujo porque no se
  pudo pintar un desplegable opcional cambiaría una comodidad por una
  interrupción.
- **El panel de accesos es de solo lectura, a propósito.** El mapeo de perfiles y
  el árbol se editan en la semilla, que es la que viaja a producción versionada y
  la que un revisor lee en un PR. Volverlos editables por pantalla exige antes
  decidir quién manda cuando la semilla y la pantalla discrepan: hoy `S005` hace
  `UPDATE` sobre las tres tablas en cada corrida, así que una edición por
  pantalla la pisaría el siguiente `instalar.ps1`.
- **Los descartes se muestran fuera de las pestañas.** Son la respuesta a la
  pregunta que trae a alguien al panel —por qué una persona no puede entrar—;
  esconderlos obligaría a buscarlos a quien ya viene buscando.
- **El panel es un módulo de `sigcm.Modulo`, no una opción suelta del menú.** El
  menú se arma exclusivamente de `RolModulo` × `Modulo` (F006); una opción fuera
  de ahí necesitaría una segunda lista paralela que se desincroniza.
- **El rol se valida dos veces**: `RolModulo` decide qué se *muestra*,
  `paObtenerPanelSso` decide qué se *puede* (51701). Un menú sin la opción no
  impide llamar al endpoint.

**Cómo se prueba.** `db/90_pruebas/S907`: 12 comprobaciones en verde contra
desarrollo, con padrón sintético, dentro de una transacción que termina en
`ROLLBACK`. No necesita red al SSO y no deja rastro.

Verificado además contra el SSO **real** (`192.168.20.111:5434/saa_`): 21 puestos
recibidos, 25 unidades y 20 usuarios dados de alta, `PE019` descartado; segunda
corrida 0/0/0/0; sacar a una especialista del padrón produjo `AsignacionesBaja:1`
y desapareció de la lista de derivación del jefe; devolverla abrió una asignación
nueva conservando la cerrada.

**Sobre el catálogo de perfiles del SSO.** La familia `PE079`–`PE092` la creó
**el propio equipo** —César Ortiz (46183970), de la OTI— en junio de 2026, y
creció por incorporación: `PE091` entró el 25 y `PE092` el 29. Agregar un perfil
no es un trámite con terceros. La asimetría que queda es que sólo Abastecimiento
tiene los tres escalones (`PE082`/`PE083`/`PE084`); el área usuaria está en pares
(`PE079`/`PE080`, `PE091`/`PE092`), sin coordinador.

**El administrador del sistema: un huevo y gallina.** Al 2026-08-27 no había
**ninguna** fila con `ADMIN_SISTEMA` en `sigcm.UsuarioRol`. Sin administrador no
hay quien abra el panel; sin panel no hay dónde ver por qué nadie entra. El SSO
trae media solución: el perfil `P0001 ADMINISTRADOR` **ya existe y ya está ligado
al sistema 73**, pero sus dos accesos (`32885691` y `43552822`) están en
`activo = false`. `S007` deja las dos puertas listas:

- **La principal**: el mapeo `P0001 → ADMIN_SISTEMA`. En cuanto el SSO active ese
  acceso para alguien, entra como administrador sin tocar nada más aquí. No crea
  una segunda autoridad. **Resuelto el 2026-08-28**: se le dio ese acceso a
  Gustavo Cruz (`44687266`, `id_usuario` 6) sobre la dependencia OTI — una fila
  en `login.td_login_acceso` y otra en `login.td_login_acceso_dependencia`, sin
  crear usuarios ni tocar contraseñas. La sincronización lo recogió sola
  (`AsignacionesAlta: 1`) y hoy entra por SSO con dos perfiles: área usuaria jefe
  y administrador. Ojo con el detalle que costó encontrar: Cruz **ya tenía** un
  `P0001` activo, pero del `id_perfil_sistema` 184, que es del sistema 66; el del
  SGCM es el **194**. Para deshacerlo, `activo = false` en ese acceso y la
  siguiente reconciliación cierra la terna.
- **La de respaldo**: la cuenta local `admin.sigcm`, con `IdUsuarioSso` en nulo
  —así la reconciliación no la toca—. **Es inerte mientras `acceso_local` sea
  `"false"`**: el SIGCM no guarda contraseñas, así que sólo se puede usar por
  `api/acceso`, que responde 404. Existe porque el panel es justamente la
  herramienta para diagnosticar por qué nadie puede entrar, y dejarla accesible
  sólo por SSO significa que si el SSO falla, la herramienta para averiguar por
  qué falla tampoco está.

**Pendientes:**

- **Registrar `COORDINADOR DE UNIDAD` en el SSO** (opción recomendada de cuatro
  evaluadas: crearlo, reutilizar el genérico `P0003`, designarlo desde el SIGCM,
  o no hacer nada). Es una fila en `tm_login_perfil`, una en
  `td_login_perfil_sistema` para el sistema 73, los accesos de cada persona, y
  una fila en `S005`. **No bloquea nada hoy**: CMN no usa ese escalón y
  Requerimiento aún no está en construcción. Designarlo desde el SIGCM se
  descartó porque partiría la autoridad en dos padrones, que es lo que esta
  iteración vino a cerrar.
- La cadena `cnx_saa_` apunta al SSO de **desarrollo** con `postgres/postgres`.
  Producción necesita su propia cadena y **una cuenta de solo lectura** sobre el
  esquema `login`: la integración únicamente lee.
- `PE019 EXTERNO` sigue sin mapear a propósito. Si ese consultor debe operar, la
  pregunta es con qué autoridad; cuando se decida es una fila en `S005`.

---

### 2026-08-26 — La base en desarrollo y la integración con SIGA verificada allí

**Qué se hizo.** Instalar el SIGCM en el servidor de desarrollo del ANIN
(`192.168.40.75`) y probar contra su `SIGA_1750` real —33 292 líneas en el
cuadro modificado 2026, no la copia local— que el CMN escribe en los dos
momentos. Se trabajó por escritorio remoto desde `172.16.3.66`: la VPN no llega
a la subred de servidores (ver `docs/instalar-en-desarrollo.md`).

**El bug que sólo aparece en una instalación limpia.** `S002` apuntaba la regla
de plazo `CMN_REVISION_UA` al estado `CMN_EN_EVAL_UA`, que `S001` había retirado
del flujo y ya no inserta —sólo lo remapea a `CMN_EN_ABAST_ESP` para reubicar
expedientes viejos—. La FK `FK_sigcm_PlazoRegla_Estado` no tenía a qué apuntar y
la serie moría en el script 29 de 31.

No se veía en local porque allí la base arrastraba la fila vieja de
`sigcm.Estado` de una instalación anterior, que satisfacía la FK por accidente.
**Un bug latente que cualquier instalación desde cero —QA, producción, un clon
nuevo— habría encontrado.** Se corrigió siguiendo la equivalencia que `S001` ya
documenta; la regla sigue con `Activo = 0`, así que no cambia comportamiento.

**No era un trámite, era una instalación pendiente.** La documentación anterior
daba por bloqueada la escritura en SIGA «hasta que el equipo de SIGA autorice».
Somos ese equipo: la cuenta de desarrollo ya tenía **`db_owner` sobre
`SIGA_1750`**. Lo que faltaba era instalar los tres procedimientos —estaban en
el repo, sin aplicar—. En la base sólo existía `usp_ext_registrar_item_cmn`, que
es el viejo y escribe en la ruta de formulación, cerrada desde enero.

| Pieza | Dónde |
|---|---|
| `CMN_REVISION_UA` apunta al estado vigente | `db/20_seed/S002` |
| Los tres `usp_ext_*` instalados en `SIGA_1750` | `SIGA/integracion/` |
| Ruta de verificación corregida en los scripts de prueba | `db/90_pruebas/S901`, `S902` |
| Procedimientos, verificación y acceso de red | `docs/instalar-en-desarrollo.md` |

**Decisiones que no hay que volver a discutir:**

- **`DBSIGCM` de desarrollo se recreó desde cero**, con acuerdo explícito y con
  el inventario a la vista: 22 expedientes, 20 documentos y su auditoría. Se
  perdieron a propósito. Lo que ya estaba escrito en `SIGA_1750` sigue ahí,
  porque sobre SIGA sólo escribe el flujo.
- **La ruta de verificación es `Modificación de C.M.N.`, también después del
  Anexo 3.** `S901` y `S902` imprimían *Demanda Adicional*, que además de colgar
  de la rama equivocada exige `flag_da_aprob` —en `NULL` para todos los
  centros— y pierde el ítem al firmar el Anexo 4. Siguiendo esas instrucciones
  uno encontraba la pantalla vacía y concluía que la escritura había fallado:
  exactamente el error que motivó `SIGA_APLICATIVO.md`.
- **El worker sigue deshabilitado por defecto.** Que la escritura esté
  verificada no la vuelve automática: `Habilitado=true` y `Modo=real` se
  encienden a propósito.

**Cómo se prueba.** `S901` (Anexo 3) y `S902` (Anexo 4) contra el servidor de
desarrollo. Expediente `CMN-2026-000001`, OTI, `SEC_CUADRO=1`, `SEC_ITEM=17`,
solicitud SIGA **518**. `MOTIVO_SOLICITUD` pasó de `1` a `0` y el ítem quedó
pedible; `TIPO_USO` en `'C'` y el snapshot en `_DET_ORI` con `TIPO='1'`. Las dos
operaciones `COMPLETADO` en modo real, un intento cada una.

**Pendiente:** el frontend no se pudo levantar en la máquina remota —no tiene
Node instalado—. El backend sí: compila y sirve contra `192.168.40.75` sin
cambiarle la configuración.

---

### 2026-08-24 (tarde) — Corregir y anular: el pendiente que llevaba cuatro días

**Qué pidió el negocio.** Cuatro cosas, sobre lo entregado esa mañana:

1. Quitar del formulario del Anexo 3 los textos de indicaciones.
2. Que esa no vuelva a ser una decisión del programador: **no se agrega texto
   informativo que nadie pidió.**
3. Devolver el PDF del Anexo 3 a su formato: no se le agregan tipo ni
   justificación, porque el formato de la Directiva no los tiene.
4. Editar y eliminar: **puede hacerlo quien lo creó —el especialista del área
   usuaria o su jefe— mientras no esté firmado y no haya pasado a OA**; y si OA
   o Abastecimiento observan y el expediente vuelve, el área tiene que poder
   corregirlo, normalmente después de que el jefe lo derive al especialista.
   Y, si se podía, borrar la data de prueba en vez de arrastrarla.

**Qué se construyó:**

| Pieza | Dónde |
|---|---|
| `cmn.fnPuedeEditar` — quién, desde qué estado, en qué unidad | `db/10_api/F002` |
| `paRegistrarSolicitud` aprende a **corregir** cuando llega `IdSolicitud` | `db/10_api/F002` |
| `PuedeEditar` en la bandeja y en el detalle | `db/10_api/F002` |
| Retirar los expedientes CMN y reiniciar el correlativo | `db/90_pruebas/S905__limpiar_expedientes_cmn.sql` |
| Prueba de corregir y anular, repetible y que se limpia sola | `db/90_pruebas/S906__prueba_edicion_cmn.sql` |
| La regla: no se agrega texto informativo que nadie pidió | `ESTANDARES.md`, sección 4.7 |
| Formulario sin notas; el PDF del Anexo 3, como estaba | `../../anin_scm_front/…/gestion-cmn/` |

**Decisiones que no hay que volver a discutir:**

- **Corregir no es registrar de nuevo, y por eso no consume correlativo.** El
  expediente conserva su código: es el número con el que circula y con el que un
  auditor lo pide. Antes `IdSolicitud` se leía y se descartaba en silencio, así
  que subsanar creaba un expediente nuevo y dejaba el observado vivo. Era el
  pendiente 1 del 2026-08-20.
- **Es la misma rutina y no una nueva.** Crear y corregir comparten las quince
  validaciones contra los maestros de SIGA; partirlas en dos procedimientos
  habría dejado dos copias que terminan diciendo cosas distintas. Lo único que
  se ramifica es dónde aterriza el resultado.
- **Corregir no mueve el expediente.** Estado, unidad y responsable actual son de
  la máquina de transiciones; esto es contenido. Tampoco cambia `IdResponsable`:
  que el jefe corrija una línea no lo convierte en el área que pidió.
- **Los ítems se reescriben en bloque.** Nada cuelga de un `IdSolicitudItem`
  fuera de sus 48 períodos —el mapeo hacia SIGA nace al encolar, y eso ocurre
  después de la firma, cuando ya no se puede corregir—, así que reconciliar línea
  por línea sería complejidad sin ganancia.
- **Los estados editables son cinco**, y la lista vive una sola vez en
  `cmn.fnPuedeEditar`: `CMN_BORRADOR`, `CMN_PEND_FIRMA_A3` y los tres del retorno
  observado (`CMN_OBS_AU_JEFE`, `CMN_OBS_AU_COORD`, `CMN_OBSERVADO`). Fuera
  quedan `CMN_A3_FIRMADO` —corregir después de la firma es rehacer el documento,
  no editarlo— y los `CMN_SUBS_*`, donde el área ya declaró subsanado.
- **El jefe corrige aunque el turno sea del especialista.** Lo pidió el negocio:
  el jefe que encuentra un error al ir a firmar no tiene que devolverlo para que
  se lo arreglen. Los tres candados son estar en un estado editable, que el
  expediente esté **en la unidad** del actor y que el actor ejerza un rol del
  área usuaria.
- **La pantalla pregunta si puede editar; no lo deduce.** `PuedeEditar` sale de
  la misma función que aplica la rutina al guardar. La regla que vivía en el
  front —estado `CMN_OBSERVADO` y rol especialista— era más estrecha que el
  flujo real.
- **Eliminar no hizo falta construirlo.** `CMN_ANULAR_BORRADOR` y
  `CMN_ANULAR_FIRMA_PEND` están en la semilla desde el principio, con sus roles,
  y la bandeja las pinta como cualquier otra acción. Agregar un «borrar» aparte
  habría sido una segunda forma de anular, fuera de la máquina de estados.

**Cómo se prueba.** `db/90_pruebas/S906__prueba_edicion_cmn.sql`: registra,
corrige como especialista y como jefe, comprueba que Abastecimiento no puede,
que después de la firma tampoco, que devuelto observado vuelve a poder, y que la
anulación está habilitada. No toca SIGA y se limpia sola. `S903` sigue en verde.

**Sobre la data de prueba.** Se corrió `S905` y la base quedó con **cero
expedientes CMN**: con eso desaparece el pendiente de los expedientes sin
tipificar, porque ya no hay ninguno. Lo que la integración escribió en su día en
`SIGA_1750` **sigue ahí**, a propósito: sobre SIGA solo escribe el flujo.

---

### 2026-08-24 — El Anexo 3 se tipifica al nacer y los combos ven solo lo del área

**Qué pidió el negocio.** Cuatro observaciones sobre el registro del CMN:

1. Retirar «Modificación» del combo de ítem.
2. Que el combo de tarea arranque en «Seleccione».
3. Filtrar los desplegables según el perfil con que se ingresó, usando
   `SIG_METAS_X_CENTRO`, que es la tabla con la que SIGA relaciona el centro de
   costo con sus metas y fuentes. En palabras del cliente: *«si ingresa el
   usuario de Soporte, solo debe visualizar las fuentes asociadas a su meta —RO—
   y no canon o donaciones»*.
4. Tipificar la solicitud como **ordinaria o extraordinaria desde el inicio**,
   exigir justificación escrita a la extraordinaria y habilitar un archivo de
   sustento para que Abastecimiento valide la urgencia. Y **quitar esa elección
   del formulario de Abastecimiento**, que es donde estaba.

**Qué se construyó:**

| Pieza | Dónde |
|---|---|
| Sinónimo y vista `siga.vwMetaXCentro` sobre `SIG_METAS_X_CENTRO` | `00_servidor/C003`, `db/00_ddl/V004` |
| `JustificacionUrgencia`; `URGENTE` → `EXTRAORDINARIA` en las dos tablas | `db/00_ddl/V015__cmn_tipificacion_solicitud.sql` |
| `META` y `FUENTE_FINANC` delimitados por `CentroCosto`; maestro `META_X_CENTRO` | `db/10_api/F001` |
| Rechazo de `MODIFICACION` (51125), tipificación obligatoria (51122-51124), meta/fuente del centro (51126) | `db/10_api/F002` |
| `TipoInclusion` deja de escribirse en la transición | `db/10_api/F004` |
| Tipo de documento `CMN_SUSTENTO_URGENCIA`, sin firmas | `db/20_seed/S001` |
| Tipo de solicitud, justificación y adjunto en el registro | `../../anin_scm_front/…/modals/modal-registro/` |
| El panel de Abastecimiento muestra el tipo, ya no lo elige | `../../anin_scm_front/…/gestion-cmn.component.{ts,html}` |
| Tipo y justificación impresos en el Anexo 3 | `../../anin_scm_front/…/documentos/anexo3.pdfmake.ts` |

**Decisiones que no hay que volver a discutir:**

- **«Modificación» no era un valor erróneo, era una vía que el formato no tiene.**
  El Anexo 3 oficial trae dos pares de columnas —exclusión e inclusión— y ninguna
  tercera. Cambiar la cantidad de un ítem programado se expresa excluyendo la
  línea vigente e incluyéndola con la cantidad nueva, que es lo que el área
  usuaria firma tal como se imprime. El valor **sigue vivo en el modelo** y W001
  sabe proyectarlo, porque hay expedientes históricos con esa marca; lo que se
  rechaza es registrar uno nuevo, y el mensaje dice qué hacer en su lugar.
- **El combo de tarea no estaba «sin opción por defecto»: la opción no encajaba.**
  El `<option>` valía `"null|null|null"` y un ítem recién creado producía la clave
  `"||null"`. Angular no encontraba coincidencia y pintaba un blanco implícito.
  Ahora ambos lados valen cadena vacía.
- **La delimitación por perfil es de SIGA, no nuestra.** `SIG_METAS_X_CENTRO` es
  la misma tabla con la que el propio SIGA arma esos combos: 574 filas para 38
  centros en 2026. Verificado que las metas que declara por centro coinciden una
  a una con las de `SIG_TECHO_PRESUPUESTO`, así que filtrar por ahí no esconde
  ninguna combinación con techo. Sin `CentroCosto` los maestros siguen
  devolviendo la lista completa: Abastecimiento consulta transversalmente.
- **Filtrar en el combo no basta: la rutina también valida.** `paRegistrarSolicitud`
  comprueba meta + fuente contra el centro de costo (51126) y solo sobre
  inclusiones —en una exclusión la clasificación se copia de la línea vigente del
  cuadro, y una línea histórica programada bajo otra asignación sigue siendo
  excluible—.
- **`URGENTE` pasó a llamarse `EXTRAORDINARIA`.** Es el mismo eje con dos nombres:
  el de la regla del viernes y el de la Directiva. Mantener los dos obligaría a
  traducir entre pantalla y tabla. Se renombró el valor, no la columna, y la regla
  del calendario no cambió.
- **La tipificación se mudó al registro y no se acepta «por si viene».** F004 ya
  no la escribe ni siquiera cuando llega en el POST: una transición que pudiera
  sobrescribirla borraría la justificación que la respalda —son un solo hecho—.
- **El archivo de sustento es un documento del expediente, no un adjunto.** Sube
  por el mismo file server y se registra con `sigcm.paRegistrarDocumento`, así
  hereda versionado, trazabilidad y el visor que Abastecimiento ya usa. Es
  **opcional**: obligatorio es el texto. Si el archivo falla, la solicitud no se
  deshace; se avisa y puede readjuntarse editando el borrador.
- **`TipoInclusion` sigue admitiendo nulo.** Ninguna solicitud nueva nace sin
  tipo, pero volver la columna `NOT NULL` obligaría a inventarle uno a las
  anteriores. Un dato inventado en una columna que decide un plazo es peor que un
  nulo que la rutina rechaza al primer intento de avanzar. Por lo mismo, la
  restricción de la justificación entra `WITH NOCHECK`.

**Cómo se prueba.** Sin SIGA. `instalar.ps1` aplica los 28 scripts (dos pasadas,
idempotente) y `db/90_pruebas/S903` recorre el circuito completo con dos áreas y
se limpia sola. Comprobado además que `META` sin centro devuelve 487 metas y con
`01.01` una sola; `FUENTE_FINANC`, 9 y una (`1-00`, Recursos Ordinarios); y que
el registro rechaza con 51125, 51122, 51124 y 51126 sin que nazca ninguna
solicitud.

---

### 2026-08-20 (noche) — La firma: el PDF que la bandeja no sabía encontrar

**Qué pidió el negocio.** Integrar lo que el otro desarrollador hizo con la
firma. Trabajó sobre la copia del front de la semana pasada
(`CAMBIOS_ANIN/sgcm_front_anin`) y entregó dos procedimientos,
`paListarSolicitud` y `paObtenerSolicitud`.

**Cuál era el defecto real.** No faltaba pantalla ni faltaba botón: el front ya
tenía el visor, los dos botones de Anexo y `SolicitudCmn.DocumentoSistemaAnexo3`
/ `Anexo4` en el modelo. Lo que faltaba era que **la base devolviera esos dos
campos**. El front solo conocía el archivo dentro de la sesión en que lo había
generado; al recargar la bandeja el botón se quedaba sin nada que abrir, y quien
tenía que firmar no veía el documento que estaba firmando.

**Qué se construyó:**

| Pieza | Dónde |
|---|---|
| `cmn.fnDocumentoVigente` — versión vigente del documento vivo de un tipo | `db/10_api/F002__cmn_solicitud.sql` |
| `DocumentoSistemaAnexo3` / `Anexo4` en la bandeja y en el detalle | `db/10_api/F002__cmn_solicitud.sql` |
| `blobParaVisor` — repone el MIME cuando el file server no lo declara | `../../anin_scm_front/…/gestion-cmn/gestion-cmn.component.ts` |
| El borrador ya no deja PDF en el file server; el aviso ya no lo promete | `../../anin_scm_front/…/modals/modal-registro/` |
| El icono del Anexo 3 aparece sólo si hay archivo; el visor abre el del servidor | `../../anin_scm_front/…/gestion-cmn/` |
| La entrega original, tal como llegó, y por qué no se ejecutó | `_snapshot/cambios-anin-20260820/` |

**El momento en que nace el PDF.** El registro de la solicitud armaba y subía el
Anexo 3 en el acto. Adelantaba un paso que el flujo tiene aparte: el expediente
nacía en `BORRADOR` pero ya con documento, la bandeja ofrecía el icono de un
Anexo 3 que nadie había generado, y el aviso prometía un archivo «guardado en el
servidor» que no correspondía a ningún estado del trámite. Ahora el PDF lo emite
`CMN_GENERAR_A3`, que es la transición que lo declara hecho, y el icono aparece
recién entonces. La subsanación es la excepción deliberada: ahí el documento ya
existe, se corrigió lo observado y `CMN_SUBSANAR` no produce documento, así que
el modal lo rehace.

**El visor muestra el archivo, no una reconstrucción.** Para los estados
anteriores a la firma el navegador rearmaba el PDF con la plantilla vigente en
vez de bajarlo. La intención era no mostrar algo desactualizado; el efecto era
peor, porque lo que se veía —y lo que se firmaba— no era el archivo registrado
en el expediente. Se retiraron `generarYMostrarAnexo3` y
`ESTADOS_ANEXO3_ARCHIVO_OFICIAL`.

**Decisiones que no hay que volver a discutir:**

- **La entrega se portó, no se aplicó.** Los dos scripts vienen en el dialecto
  del volcado `desarrollo-20260818`: usan `sigcm.fnEsJson`, `fnJsonTexto`,
  `fnJsonEntero`, `fnJsonValorTexto` y `fnTryGuid`, que **no existen en
  `DBSIGCM`**, y arman el JSON con `FOR XML PATH`. Habrían compilado y fallado
  en la primera llamada. Además son de antes del Anexo 4 múltiple: su bandeja no
  trae `AreaUsuaria`, `SiglaArea`, `IdPaquete` ni `CodigoAnexo4`, y aplicarlos
  habría deshecho la iteración anterior a cambio de dos campos.
- **Una función inline en vez de cuatro `OUTER APPLY`.** Dos rutinas por dos
  tipos de documento es la misma consulta de tres tablas repetida cuatro veces.
  `cmn.fnDocumentoVigente` la define una vez; el optimizador la expande igual.
- **`blobParaVisor` se porta aunque local no lo necesite.** El backend local
  sirve el PDF con su tipo real, pero el file server de la ANIN responde
  `application/octet-stream` y con ese tipo el `<iframe>` descarga en vez de
  dibujar. Es la diferencia entre los dos ambientes, y el mismo código tiene que
  servir para los dos.
- **El file server local ya estaba resuelto.** `appsettings.Local.json` apunta
  `rutafile` a `anin_scm_back/.local-files` con `file_servicio_externo: false`,
  y `UT_File.TryRutaFisica` resuelve la subcarpeta `cmn`. No hacía falta tocar
  nada del backend.

**Cómo se prueba.** Sin SIGA. Con la base instalada, `cmn.paListarSolicitud`
devuelve `DocumentoSistemaAnexo3` en los expedientes que ya generaron su Anexo 3
y `DocumentoSistemaAnexo4` en los que tienen paquete; los archivos que nombra
existen bajo `.local-files/cmn/`. En pantalla: recargar la bandeja y abrir el
Anexo de una fila firmada —antes del cambio, el botón no tenía qué abrir.

**Pendientes — dos defectos abiertos y una pieza que no llegó:**

1. ~~**`cmn.paRegistrarSolicitud` no sabe actualizar.**~~ **Resuelto el
   2026-08-24 (tarde).** Su `OPENJSON` no leía `IdSolicitud` y el `INSERT INTO
   sigcm.Expediente` era incondicional, así que subsanar una observación creaba
   un expediente nuevo con correlativo nuevo. Ahora la rutina distingue registrar
   de corregir y `cmn.fnPuedeEditar` decide quién puede hacerlo y desde qué
   estado.
2. **La firma digital ONPE no está en la entrega.** El bloque `firma`
   (`ruta_js`, `ruta_metodo`, `ruta_iframe`, `ruta_carpeta`, `ruta_respuesta`,
   `ruta_archivo`) está **declarado en `AppConfig` de los dos proyectos pero no
   lo lee ningún código**, y no aparece en ningún `config.json`. En desarrollo
   el visor abre `sfirma.anin.gob.pe` y desde ahí el cliente FIRMA ONPE firma el
   PDF; ese código va en una versión posterior a la de `CAMBIOS_ANIN`. Lo
   resuelve el otro desarrollador. **Ojo con el límite físico:** `sfirma` lee el
   PDF de la carpeta compartida, y en local los archivos viven en
   `anin_scm_back/.local-files/cmn/`, que ese host no alcanza.
   Distíngase de `sigcm.paFirmarDocumento`, que sí funciona y es otra capa: la
   firma **del trámite** —quién firmó, en qué orden, `PARCIAL` hasta la última—,
   no la firma criptográfica sobre el PDF.
3. Las filas semilla de `CMN-2026-000008/9/10` guardan una URL
   (`http://localhost/files/cmn/…-anexo3.pdf`) en vez de un id, y esos archivos
   no existen en disco: el visor responderá «no fue posible descargar». Es dato
   de semilla anterior, no del flujo; se corrige regenerando esos casos.

**Nota de datos para probar.** El desplegable de Meta trae las 487 metas de la
entidad, pero cada área usuaria tiene techo en **una sola**; con cualquier otra
el clasificador queda vacío y la pantalla no explica por qué. Las combinaciones
válidas en 2026 (fuente `1-00` en todas) son: US `01.07.05.02` meta 14 (13
clasificadores), ORH `01.07.04` meta 18 (11), OGP `01.06.03` metas 257 y 6,
UDS `01.07.05.01` meta 11, UOP `01.01` meta 5, OTI `01.07.05.03` meta 15 (2).
~~Filtrar las metas por techo del centro de costo queda pendiente.~~ **Resuelto el
2026-08-24**: el desplegable ya solo trae las metas y fuentes que
`SIG_METAS_X_CENTRO` asigna al centro de costo del perfil.

---

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
