# Instalar la base en desarrollo

Guía para aplicar la serie de migraciones contra el servidor de desarrollo del
ANIN (`192.168.40.75`). Léela entera antes de correr nada: hay un modo que borra
la base.

---

## Antes que nada: ¿basta con hacer pull?

**No.** El `git pull` te trae los scripts; no toca ninguna base de datos. Los
scripts hay que aplicarlos, y eso lo hace `instalar.ps1`.

### Sobre la numeración de expedientes

Hubo un momento en que instalar esta serie en desarrollo era peligroso: el
código de expediente salía de una `SEQUENCE`, y una secuencia recién creada
arranca en 1, así que en una base con expedientes ya registrados los códigos
nuevos habrían chocado contra `UQ_sigcm_Expediente_Codigo`.

**Ya está resuelto.** `V010` reemplaza las secuencias por `sigcm.Correlativo` y
—esto es lo que importa— **siembra cada contador con el código más alto que ya
exista** en `sigcm.Expediente`. La numeración continúa donde iba; no reinicia.

Probado en local sobre una base que ya tenía `CMN-2026-000001` a `000003`: el
contador quedó en 3 y el siguiente registro emitió `CMN-2026-000004`.

`V010` también retira las dos secuencias, para que no queden dos fuentes de
numeración compitiendo.

---

## Requisitos

| Qué | Cómo se comprueba |
|---|---|
| PowerShell | `$PSVersionTable.PSVersion` |
| `sqlcmd` en el PATH | `(Get-Command sqlcmd).Source` |
| Acceso de red a `192.168.40.75` | `Test-NetConnection 192.168.40.75 -Port 1433` |
| Un login con permiso en el servidor | lo da el DBA; en desarrollo se usa `developer_anin` |

Si falta `sqlcmd`, viene con *SQL Server Command Line Utilities* o con SSMS.

---

## Paso 1 — Traer los scripts

```bash
git pull
git checkout bd_mrz
```

---

## Paso 2 — Revisar sin tocar nada

```powershell
.\instalar.ps1 -SoloVerificar
```

No se conecta a ninguna base. Recorre todos los `.sql` del repositorio y falla
si alguno usa construcciones de SQL Server 2025 (el tipo `json` nativo,
`JSON_ARRAYAGG`, `REGEXP_LIKE`, funciones de vector o de IA), que en desarrollo
—que es 2022— no existen. Debe terminar con:

```
  [OK] Ningun script usa construcciones de SQL Server 2025.
```

Este es el paso que impide que algo que funciona en una máquina con 2025 llegue
roto a desarrollo. Córrelo siempre antes de subir un script.

---

## Paso 3 — Diagnosticar el servidor de destino

Opcional pero recomendado la primera vez, y obligatorio si el servidor cambió:

```powershell
sqlcmd -S "192.168.40.75" -d master -U developer_anin -i 00_servidor\C000B__diagnostico_motor.sql -o diagnostico.txt -W -s "|"
```

Pide la contraseña por teclado. Reporta versión, edición, intercalación,
compatibilidad de cada base y prueba una por una las 44 construcciones T-SQL que
usan los scripts. Es solo lectura: no crea, altera ni borra nada.

La salida de referencia del 2026-08-18 está en `entorno-desarrollo-20260818.txt`.

---

## Paso 4 — Instalar

```powershell
.\instalar.ps1 -Servidor "192.168.40.75" -Usuario developer_anin
```

`sqlcmd` pedirá la contraseña por teclado, una vez por script. **Nunca la pases
por línea de comandos**: queda en el historial de PowerShell y en la bitácora.

Si omites `-Usuario`, el instalador usa autenticación integrada de Windows
(`-E`), que solo funciona si tu equipo está en el dominio ANIN.

### Qué hace, en orden

1. Verifica el código fuente (paso 2).
2. `C000__preflight` sobre `master`: comprueba versión, intercalación, que
   existan las 14 tablas de SIGA que consumen las vistas, y los permisos.
3. `C001__crear_dbsigcm`: crea `DBSIGCM` si no existe, **con la intercalación
   que descubre de SIGA** —no una escrita a mano— y la fija en compatibilidad
   160. Si ya existe, no la recrea.
4. `C003__sinonimos_siga`: los 14 sinónimos hacia `SIGA_1750`.
5. Las migraciones en orden: `db\00_ddl\V*` → `db\10_api\F*` →
   `db\15_siga\W*` → `db\20_seed\S*`.
6. `C900__inventario`: lista lo que quedó instalado.

Aborta al primer error y deja la bitácora completa en `_bitacora\`.

### Modificadores

| Modificador | Qué hace | Dónde usarlo |
|---|---|---|
| *(ninguno)* | Actualiza respetando la base existente | local y desarrollo |
| `-SoloVerificar` | Solo revisa el código fuente | siempre, antes de subir |
| `-ConDatosPrueba` | Agrega usuarios ficticios para probar sin SSO | **solo local** |
| `-Recrear` | **BORRA `DBSIGCM` y la rehace desde cero** | **solo local** |

> ### ⚠ `-Recrear` contra desarrollo destruye el trabajo de los dos
>
> Borra la base compartida entera: expedientes, solicitudes, documentos, cola de
> integración. El front y el back se quedan sin datos y hay que rehacer las
> pruebas desde cero. No lo uses contra `192.168.40.75` sin avisar al otro y
> ponerse de acuerdo.

---

## Lo que el instalador NO hace

`00_servidor\C002__acceso_lectura_siga.sql` **no forma parte de la serie**, a
propósito. Concede permisos de lectura *dentro de* `SIGA_1750`, que es base de
otro dueño, y eso requiere autorización del propietario. Se ejecuta a mano donde
corresponda. En local no hace falta porque se trabaja con cuenta sysadmin.

Tampoco instala nada en SIGA.

---

## Para que los datos lleguen a SIGA

Instalar la serie **no** hace que el CMN se escriba en SIGA. Hasta aquí, cuando
un expediente pasa por `CMN_VALIDAR_UA`, las operaciones quedan encoladas en
`integracion.Operacion` y nadie las vacía. Eso es por diseño (ADR-003).

Para que se escriban de verdad hacen falta tres cosas, en este orden:

### 1. Los procedimientos del lado de SIGA

Corren **dentro de `SIGA_1750`**, no en nuestra base. Reciben parámetros
tipados y XML —nada de JSON, porque SIGA está en compatibilidad 100—. Son tres,
y viven en `SIGA/integracion/`:

| Procedimiento | Qué momento resuelve |
|---|---|
| `usp_ext_incluir_item_cmn` | inclusión por el Anexo 3 |
| `usp_ext_excluir_item_cmn` | exclusión por el Anexo 3 |
| `usp_ext_aprobar_solicitud_cmn` | aprobación por el Anexo 4 |

**Instalados en desarrollo el 2026-08-26.** Se aplican con `sqlcmd -d SIGA_1750`
y requieren `db_owner` sobre esa base, que la cuenta de desarrollo ya tiene.

> **`usp_ext_registrar_item_cmn` es el procedimiento viejo y no se usa.** Escribe
> en `SIG_CUADRO_NECESIDAD`, o sea en la ruta de **formulación**, que en la
> ejecutora 1750 se cerró el 2026-01-07. W001 lo dejó de invocar: un ítem
> registrado por ahí no aparece en la pantalla que el área usuaria usa hoy ni
> puede consumirlo un requerimiento. Sigue enlazado sólo por compatibilidad.

Después de instalarlos hay que **reaplicar `W001`** para que cree los sinónimos
—los enlaza sólo si el procedimiento existe—. Reejecutar `instalar.ps1` basta.

### 2. W001, que ya viene en la serie

`db\15_siga\W001__escritor_cuadro_modificado.sql` se instala con todo lo demás.
Es el que traduce: desarma el JSON con `OPENJSON`, pivotea los 48 periodos
`{AnoOffset, Mes, Cantidad}` a las cuatro filas `<Periodo codigo c01..c12>` que
SIGA espera, y llama al procedimiento.

**Por defecto corre en simulación y no toca SIGA.** Hace toda la traducción y
deja en `ResponseJson` exactamente lo que habría mandado, para poder revisarlo.

```sql
-- Simulación: no escribe nada en SIGA, solo muestra qué mandaría
EXEC integracion.paEscribirCuadroModificado
     N'{"Actor":{"Usuario":"w001"},"Modo":"simulacion"}';

-- Real: escribe en SIGA. Exige el paso 1.
EXEC integracion.paEscribirCuadroModificado
     N'{"Actor":{"Usuario":"w001"},"Modo":"real"}';
```

Si se pide `"real"` y el procedimiento de SIGA no está instalado, responde con
un error explícito (`INTEGRACION_NO_DISPONIBLE`) y no escribe nada. No falla en
silencio.

En `ModoEjecucion` de cada operación se graba lo que **efectivamente** se hizo,
no lo que se pidió.

Hoy `W001` implementa `INCLUIR_ITEM` y `EXCLUIR_ITEM`. La exclusión llama a
`usp_ext_excluir_item_cmn`, conserva el original en
`SIG_CUADRO_MODIFICADO_DET_ORI`, crea la solicitud de modificación en estado
`2` (V.B. Jefe) con sus cuatro detalles y estado documental, actualiza las
cuatro filas anuales del cuadro modificado y es idempotente.
`MODIFICAR_CANTIDADES` y `CONSOLIDAR_CMN` continúan devolviendo un error
explícito.

### 3. El worker .NET

La cola la vacía `IntegracionSigaWorker`, un `BackgroundService` que forma parte
del backend. No es un servicio ni un despliegue adicional. Cada réplica intenta
tomar un `sp_getapplock`; sólo la que obtiene el bloqueo ejecuta W001, por lo que
es seguro desplegar más de una réplica de la API.

Está **deshabilitado por defecto** en `appsettings.json`. Las opciones son:

```json
"IntegracionSiga": {
  "Habilitado": false,
  "Modo": "simulacion",
  "Conexion": "cnx_integracion",
  "IntervaloSegundos": 30,
  "EsperaInicialSegundos": 5,
  "Limite": 20,
  "TimeoutSegundos": 90,
  "UsuarioAuditoria": "sigcm-worker"
}
```

La cadena indicada por `Conexion` debe abrir **DBSIGCM**, no `SIGA_1750`: W001
se ejecuta en DBSIGCM y cruza a SIGA mediante el sinónimo homologado. La cuenta
técnica debe tener acceso a DBSIGCM, `EXECUTE` sobre W001 y permiso efectivo
sobre el procedimiento de SIGA. Las credenciales se configuran por variables de
entorno o en un `appsettings.Local.json` excluido de Git; nunca en este manual.

Para habilitar escritura deben configurarse `Habilitado=true` y `Modo=real`, y
tienen que estar instalados los procedimientos del paso 1.

### Cómo verificar que llegó

```sql
-- Del lado del SIGCM: la correspondencia de identificadores
SELECT AnoEje, CentroCosto, SecCuadro, SecItem, EstadoSiga, RegistradoEnSiga
  FROM integracion.MapeoCmn;

-- Del lado de SIGA: el item, por la ruta de MODIFICACION
SELECT SEC_CUADRO, SEC_ITEM, ANNO_PROG, ESTADO, FLAG_MODIFICADO,
       MOTIVO_SOLICITUD, CANT_TOTAL, MNTO_TOTAL
  FROM siga.SIG_CUADRO_MODIFICADO_DET
 WHERE ANNO_EJEC = 2026 AND SEC_EJEC = 1750 AND SEC_ITEM = <SecItem>;
-- MOTIVO_SOLICITUD 1 = Anexo 3 firmado    0 = Anexo 4 firmado, item pedible
```

No consultes `SIG_CUADRO_NECESIDAD`: es la ruta de formulación y ahí no hay
nada nuestro.

### Errores de negocio que devuelve SIGA

No son fallas del SIGCM; son las reglas de SIGA rechazando el dato. Se ven en
`ErrorMensaje` de `integracion.Operacion` y la operación queda en `REINTENTO`:

| Mensaje | Qué significa |
|---|---|
| `No existe techo presupuestal compatible con la cabecera CMN` | La combinación centro de costo + fase + origen + fuente + `sec_func` + clasificador no tiene techo. Ojo con el formato del clasificador, que lleva espacios significativos: `2.3. 2  9. 1  1` |
| `El item excede el techo CMN de uno de los cuatro periodos` | El techo existe pero ya está consumido, o el monto no cabe |
| `El item no existe o esta inactivo en CATALOGO_BIEN_SERV` | El ítem del catálogo no es válido para esa ejecutora |
| `Este procedimiento fue homologado solo para FASE_CUADRO=5` | Se intentó escribir en otra fase |

---

## Si algo falla

| Mensaje | Qué pasa |
|---|---|
| `Login failed for user` | Contraseña incorrecta, o el login no existe en ese servidor |
| `El inicio de sesión se realiza desde un dominio que no es de confianza` | Usaste `-E` desde un equipo fuera del dominio. Usa `-Usuario` |
| `sqlcmd : The term 'sqlcmd' is not recognized` | No está instalado o no está en el PATH |
| `Cannot resolve the collation conflict` (error 468) | `DBSIGCM` se creó con una intercalación distinta a la de SIGA. Hay que recrearla |
| `[PROHIBIDO] ... tipo json nativo` | Un script usa algo de 2025. Corrígelo antes de instalar |
| `Faltan N tabla(s) de origen` | La base SIGA de ese servidor no tiene las tablas que esperan las vistas. Revisa el nombre con `-BaseSiga` |

La bitácora de `_bitacora\` guarda la salida completa de cada script, incluida
la de los que fallaron. Es lo primero que hay que mirar.

---

## Resumen

```powershell
# 1. traer
git pull; git checkout bd_mrz

# 2. revisar el codigo, sin tocar ninguna base
.\instalar.ps1 -SoloVerificar

# 3. probar en local desde cero
.\instalar.ps1 -Recrear -ConDatosPrueba

# 4. aplicar en desarrollo (respeta los datos existentes)
.\instalar.ps1 -Servidor "192.168.40.75" -Usuario developer_anin
```

La escritura hacia SIGA está **verificada de punta a punta en desarrollo** desde
el 2026-08-26 (expediente `CMN-2026-000001`, OTI, solicitud SIGA 518). Aun así,
el worker sigue **deshabilitado por defecto**: la cola se drena a propósito, no
por accidente.

---

## Trabajar desde una máquina de la red del ANIN

`192.168.40.0/24` está **cerrada entera para el perfil externo de la VPN**. Con
GlobalProtect conectado y funcionando —túnel arriba, DNS interno resolviendo—,
medido el 2026-08-26:

| Destino | Puerto | Resultado |
|---|---|---|
| `192.168.40.75` (SQL desa) | 1433 | bloqueado |
| `192.168.40.75` | 3389 / 445 | bloqueado |
| `192.168.40.71` | 3389 | bloqueado |
| `192.168.20.13` (DNS interno) | 53 | abierto |
| `172.16.3.66` (escritorio remoto) | 3389 | abierto |

El error típico es `Named Pipes Provider ... 64`, y engaña: el driver intenta
TCP, no pasa, y cae a named pipes antes de rendirse. **No es problema de
Navicat, del driver ODBC ni de la red.** No pierdas tiempo depurando ese lado.

Mientras no salga la regla de firewall —pedida por User-ID, no por IP de túnel,
porque GlobalProtect asigna la IP desde un pool y cambia entre reconexiones—, se
trabaja por escritorio remoto desde `172.16.3.66`, que sí alcanza la subred.
