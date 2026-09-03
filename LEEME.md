# SIGCM — Mapa del repositorio

> **El documento de entrada es [`INIT.md`](INIT.md).** Ahí están las reglas que
> no se negocian, el estado de cada módulo, los defectos abiertos y cómo levantar
> el ambiente. Empieza por ese; éste desarrolla el mapa del repositorio y el
> prompt de arranque.

---

## 1. El prompt comodín

Copiar y pegar tal cual al abrir una ventana nueva. Después, continuar con la
instrucción concreta.

```text
Proyecto SIGCM (ANIN).
Espacio de trabajo:  D:\PROYECTOS\ANIN\2026\SistemaSIGCM\Proyecto
Documentación y BD:  D:\PROYECTOS\ANIN\2026\SistemaSIGCM\Proyecto\anin_bdsgmc\sgcm_script

Las rutas de abajo son relativas a esa segunda, que es donde vive todo salvo el
código del front y del back (que cuelgan de la primera).

Antes de responder, lee en este orden:
  1. LEEME.md            el mapa de los 4 bloques y el estado de las copias
  2. CONTEXTO.md         arquitectura, integración con SIGA y bitácora de iteraciones
  3. ESTANDARES.md       cómo se escribe el código: BD, backend .NET, frontend Angular
  4. SIGA_APLICATIVO.md  dónde se verifica en SIGA lo que registramos

REGLA 1 — Sobre SIGA_1750 sólo escribe el flujo.
La única data que entra a SIGA es la que envía nuestro sistema a través de los
procedimientos usp_ext_* homologados. NUNCA un UPDATE, DELETE o INSERT a mano
sobre SIGA_1750, ni para corregir filas que escribió nuestra propia integración,
ni para habilitar banderas, ni para limpiar datos de prueba. Si algo salió mal:
se corrige el sistema, la fila mala se deja donde está y el caso se rehace desde
el SIGCM. A SIGA se le CONSULTA cuanto haga falta; escribir, sólo por el flujo.
Para armar casos de prueba se BUSCA en SIGA lo que ya se adecúe a lo que
necesitamos —áreas con techo libre, tareas activas, ítems de catálogo—; no se
prepara el terreno modificándolo.

REGLA 2 — NO investigues nada del aplicativo SIGA ni de un flujo ya implementado
sin buscarlo primero en esos archivos. Está documentado, y ya se perdió tiempo
más de una vez redescubriendo lo que ya estaba escrito.

Según lo que te pida, lee además:
  análisis o reglas de negocio  -> Analisis/reglas-negocio-mockup.md
                                   Analisis/mapa-implementacion.md
  integración con SIGA          -> SIGA/integracion/ANALISIS_CMN.md
  instalar o configurar SIGA    -> SIGA/validado_GUIA_IA_INSTALACION_CONFIGURACION_SIGA_MEF.md
  base de datos del SIGCM       -> db/README.md
  datos de prueba / QA          -> db/90_pruebas/

Son tres repositorios git independientes, cada uno con su remoto:
  anin_bdsgmc/sgcm_script  (rama bd_mrz)   <- OJO: el repo es sgcm_script,
  anin_scm_back            (rama dev_mrz)     no la carpeta anin_bdsgmc
  anin_scm_front           (rama dev_mrz)

Dime en tres líneas qué leíste y qué entendiste del estado actual.
Luego espera mi instrucción: no toques nada hasta que te lo pida.
```

> Si la tarea es de un solo bloque, se puede recortar a los archivos de ese
> bloque. Los cuatro primeros conviene leerlos siempre: son los que evitan
> repetir análisis.

---

## 2. Los cuatro bloques

Tu división es la correcta. Así queda aterrizada en carpetas, todas dentro del
repo salvo lo que es instalación de terceros.

### Bloque 1 — Análisis  · `Analisis/`

De dónde salen los requisitos. **Fuentes y artefactos juntos**, porque un
artefacto sin su fuente no se puede auditar.

| | Archivo |
|---|---|
| **Fuentes** | `7675020-directiva-002-2026-anin (1).pdf` — Directiva ANIN |
| | `8198485-directiva-n-0007-2025-ef-54-01-…pdf` — Directiva del MEF |
| | `Analisis SIGCM.docx` |
| | `Flujo de Proceso - Contratacion menor a 8 UIT v 5.0/` — los seis modelos Bizagi (CMN, Requerimiento, Pago, Ejecución, Modificación-Ampliación, Resolución) |
| **Artefactos** | `reglas-negocio-mockup.md` — las reglas funcionales, contrastadas contra el mockup |
| | `mapa-implementacion.md` — qué se construyó, en qué orden y por qué |
| | `continuidad.md` — estado y pendientes |

### Bloque 2 — SIGA  · `SIGA/`

Todo lo referente al SIGA: instalarlo, entenderlo e integrarse con su base.

| | Archivo |
|---|---|
| **Instalación** | `validado_GUIA_IA_INSTALACION_CONFIGURACION_SIGA_MEF.md` — la guía validada |
| | `conexion.md` — cadenas de conexión y accesos |
| **Uso y verificación** | `SIGA_APLICATIVO.md` — dónde se ve lo que registramos |
| | `entregables/Manual_Verificacion_SIGCM_en_SIGA.docx` — el mismo recorrido con capturas |
| | `entregables/Manual_SIGA_CMN.docx`, `Manual_SIGA_Orden_de_Servicio.docx` |
| **Integración** | `integracion/ANALISIS_CMN.md` — el análisis completo, con evidencia |
| | `integracion/usp_ext_*.sql` — los procedimientos homologados de SIGA |
| | `integracion/captura_siga_xe.sql` — Extended Events, para ver el SQL real del aplicativo |
| | `integracion/descubrimiento/` — cómo se exploró el aplicativo (`pbdgrep.py`, `menu_logistica.ps1`) |

> **El runtime del SIGA vive en `C:\SIGA_MEF` y no se versiona**: son binarios,
> JRE y los módulos PowerBuilder. Lo que sí se versiona es la documentación y
> los scripts, y su copia buena es la del repo.

### Bloque 3 — Nuestro proyecto  · este repo, `../../anin_scm_front/`, `../../anin_scm_back/`

| | Dónde |
|---|---|
| **Contexto y estándares** | `CONTEXTO.md`, `ESTANDARES.md` — en la raíz de este repo |
| **Frontend** | `../../anin_scm_front/` — Angular. Git, rama `dev_mrz` |
| **Backend** | `../../anin_scm_back/` — .NET 8. Git, rama `dev_mrz` |
| **Base de datos** | `.` (este repo) — DDL, API, semillas, instalador |
| | `db/README.md` — orden de instalación |

### Bloque 4 — QA y datos de prueba  · `db/90_pruebas/`

| Script | Qué hace | ¿Toca SIGA? | ¿Deja rastro? |
|---|---|---|---|
| `S900__datos_prueba.sql` | Unidades, usuarios y perfiles de `/acceso-local` | no | sí, es la semilla |
| `S901__prueba_e2e_cmn_siga.sql` | Flujo completo contra SIGA, los dos momentos | **sí** | sí, a propósito |
| `S902__continuar_anexo4.sql` | Retoma un expediente en `CMN_A3_APROBADO` | **sí** | sí |
| `S903__prueba_anexo4_multiple.sql` | Anexo 4 con dos áreas; regresión del flujo | no | no, se limpia sola |
| `S904__casos_anexo4_multiple.sql` | Deja 4 Anexos 3 en borrador, uno por área real | no | sí, esa es la idea |
| `S905__limpiar_expedientes_cmn.sql` | **Borra** los expedientes CMN y reinicia el correlativo. Exige `-v confirmar="SI"` | no | sí: los retira |
| `S906__prueba_edicion_cmn.sql` | Corregir y anular un Anexo 3: quién, desde qué estado | no | no, se limpia sola |

**Por qué el bloque 4 no es una carpeta aparte.** Los casos de prueba son
scripts de base de datos que el instalador ejecuta (`instalar.ps1
-ConDatosPrueba`). Sacarlos a otro sitio los separaría de lo que los corre y
volveríamos a tener dos copias desincronizadas, que es el problema que este
documento intenta cerrar. El bloque 4 es una **disciplina**, no un directorio:
generar los casos leyendo `SIGA_1750` y dejarlos como script versionado.

Cómo se generan: se consulta `SIGA_1750` buscando áreas usuarias que cumplan las
tres condiciones —cuadro en estado `4`, techo libre en esa meta y clasificador,
tarea activa— y con eso se arma el `S90x`. El procedimiento está en
`SIGA_APLICATIVO.md`, sección 6.

---

## 3. Estado de las copias — leer antes de editar

Hay **tres copias** del material de SIGA y han derivado en tres direcciones
distintas. Al **2026-08-20** quedaron consolidadas así:

| Ruta | Qué es | Estado |
|---|---|---|
| `sgcm_script/SIGA/` (este repo) | **La copia buena** | ✅ canónica |
| `C:\SIGA_MEF\` | Instalación del SIGA + copia de trabajo | runtime; sincronizada hoy |
| `D:\…\SistemaSIGCM\SIGA\` | Copia intermedia | ⚠️ **retirada**, no usar |
| `D:\…\SistemaSIGCM\Analisis\` | Origen del bloque 1 | ⚠️ **retirada**, ahora en `Analisis/` |
| `D:\…\SistemaSIGCM\SIGCM_SERVER\` | Árbol de scripts anterior | ⚠️ **retirada**, ya consolidada |

**Regla: se edita en el repo.** Si algo hace falta en `C:\SIGA_MEF`, se copia
desde aquí hacia allá, nunca al revés.

Las tres carpetas retiradas se pueden borrar cuando confirmes que no queda nada
que rescatar; se dejaron en su sitio para no destruir nada sin tu visto bueno.

### Los tres repositorios

Los tres bloques de código están versionados, cada uno con su remoto. **Ojo con
el nivel del de base de datos**: el repositorio no es `anin_bdsgmc`, sino
`sgcm_script`, que está dentro.

| Repositorio | Rama |
|---|---|
| `anin_bdsgmc/sgcm_script` | `bd_mrz` |
| `anin_scm_back` | `dev_mrz` |
| `anin_scm_front` | `dev_mrz` |

### Lo que sigue sin resolver

**Copias de trabajo duplicadas fuera del repo.** La deriva de agosto no fue por
falta de git: fue porque existían dos copias del mismo árbol de scripts
—`SIGCM_SERVER/`, fuera del repo, y `.` (este repo), dentro— y una
sesión editó la de fuera. Git no podía ayudar, porque esa copia nunca estuvo
bajo su control.

El remedio no es más git: es **borrar las copias retiradas** de la tabla de
arriba, para que no haya dónde equivocarse. Están consolidadas y a la espera de
tu visto bueno.

---

## 4. Cómo trabajamos

1. **Abrir la ventana con el prompt comodín.** Sin eso, se re-descubre lo ya
   escrito; ha pasado.
2. **Antes de investigar, buscar.** El orden es: `CONTEXTO.md` →
   `SIGA_APLICATIVO.md` → `ANALISIS_CMN.md`. Si la respuesta no está, entonces
   sí investigar, **y escribirla** en el archivo que le corresponda.
3. **Editar sólo dentro de los repos**, nunca en las copias retiradas.
4. **Al cerrar una iteración, agregar la entrada a la bitácora** de
   `CONTEXTO.md`, sección 6. La plantilla de qué debe llevar está al final de
   ese archivo: qué pidió el negocio, el flujo resultante, qué se construyó, las
   decisiones que no hay que volver a discutir, cómo se prueba y qué quedó
   pendiente.
5. **Todo cambio de flujo termina con su script de prueba** en `db/90_pruebas/`.
   Si no toca SIGA, que se limpie solo y sea repetible, como `S903`.
6. **Tocar el backend obliga a matar el proceso y volver a levantarlo.** Ver
   abajo; es la regla que más tiempo ha costado por no estar escrita.

---

## 4bis. Al tocar el backend: matar el proceso y relevantarlo

`anin_scm` sirve desde `bin/Debug/net8.0/`, así que **el código nuevo no existe
hasta que se recompila, y no se recompila mientras el proceso esté vivo**:
MSBuild no puede sobrescribir un DLL en uso y termina con `MSB3021` /
`MSB3027`. Lo peligroso es que eso *no* se parece a un error de compilación —
sale «Compilación correcta» en los proyectos y sólo falla el copiado— así que es
fácil dar por desplegado algo que sigue corriendo con el binario viejo.

El síntoma es siempre el mismo y despista mucho: **el endpoint nuevo responde
404**. Como 404 es también lo que devuelve una ruta mal escrita, se pierde el
tiempo revisando el `[HttpGet]`, el nombre del método y la URL del front, cuando
lo único que pasa es que ese código no está en el proceso que atiende.

Pasó el 2026-09-02: `ConsultaRucSunat` y `ListarDepartamento` daban 404 contra
`https://localhost:7182`. Los dos estaban en el repo —uno recién escrito, el otro
traído en el merge de `jack3`—, pero el proceso llevaba levantado desde el 28 de
agosto. Al reiniciarlo, ambos pasaron a **401**, que es lo correcto sin sesión.

```bash
# 1. Matar el proceso (deja libres los DLL)
powershell -NoProfile -Command "Stop-Process -Name anin_scm -Force -ErrorAction SilentlyContinue"
```

```bash
# 2. Recompilar. Sin el paso 1 esto termina en MSB3021 y el binario no cambia.
dotnet build ../sgcm_back/anin_scm.sln --nologo
```

```bash
# 3. Levantar de nuevo en https://localhost:7182 (perfil "https")
dotnet run --project ../sgcm_back/anin.scm --launch-profile https --no-build
```

**Cómo comprobar que de verdad se relevantó**, en vez de suponerlo: un endpoint
que existe y pide sesión responde **401**; una ruta inexistente responde **404**.
Si lo nuevo sigue en 404, el proceso viejo sigue arriba.

```bash
curl -k -s -o /dev/null -w '%{http_code}\n' https://localhost:7182/api/General/ListarDepartamento
```

Comprobar además la fecha del binario contra la hora de arranque del proceso;
si el DLL es más nuevo que el proceso, lo que está sirviendo es código viejo:

```bash
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='anin_scm.exe'\" | Select-Object ProcessId,CreationDate; (Get-Item 'D:\SGCM_SIGA\proyectos\sgcm_back\anin.scm\bin\Debug\net8.0\anin_scm.dll').LastWriteTime"
```

El frontend no tiene este problema con `ng serve`, que recompila solo. Sí lo
tiene si se está sirviendo `dist/`: ahí hay que volver a construir con
`ng build`.

---

## 5. Arranque rápido

```bash
# Instalar la base con datos de prueba (desde la raíz de este repo)
./instalar.ps1 -ConDatosPrueba
```

```bash
# Regresión del flujo CMN — no toca SIGA, se limpia sola
sqlcmd -S "localhost\SQLSERVER25" -d DBSIGCM -E -b -I -i db/90_pruebas/S903__prueba_anexo4_multiple.sql
```

```bash
# Dejar 4 Anexos 3 listos para recorrer a mano desde la pantalla
sqlcmd -S "localhost\SQLSERVER25" -d DBSIGCM -E -b -I -i db/90_pruebas/S904__casos_anexo4_multiple.sql
```

Frontend en `http://localhost:4200`, ingreso sin SSO por `/acceso-local`.
**Hay que cambiar de perfil en cada transferencia del flujo.**
