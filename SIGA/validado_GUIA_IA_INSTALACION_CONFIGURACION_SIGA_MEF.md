# Guía para una IA: instalación y configuración de SIGA MEF con SQL Server en Windows 10/11

## 1. Objetivo

Esta guía permite a una IA instalar, conectar y validar una instalación local de SIGA MEF en otra PC con Windows 10 u 11 y Microsoft SQL Server.

El resultado esperado es:

- SQL Server iniciado y con la base SIGA restaurada y en línea.
- SIGA conectado a la instancia local mediante autenticación SQL Server.
- `C:\conex_siga.ini` generado con el formato cifrado y la codificación que SIGA espera.
- La MAC del archivo de conexión y la MAC devuelta por la base deben coincidir exactamente.
- Un usuario funcional de SIGA con contraseña vigente, rol y opciones de menú.
- Acceso al selector de módulos sin `ERROR-03`, “acceso no autorizado” ni “El conex_siga no corresponde a la BD”.

> Esta aplicación es antigua y está construida con PowerBuilder. Algunos comportamientos no son intuitivos: convierte el usuario a mayúsculas, usa texto ANSI, valida una MAC obtenida por SQL Server y separa las credenciales de conexión SQL de los usuarios funcionales de SIGA.

## 2. Instrucciones obligatorias para la IA

La IA que siga este documento debe cumplir estas reglas:

1. Realizar primero comprobaciones de solo lectura.
2. No asumir nombres de instancia, base, rutas, MAC, usuarios ni contraseñas. Descubrirlos o solicitarlos.
3. No mostrar contraseñas en consola, registros, capturas ni respuesta final.
4. Solicitar autorización explícita antes de:
   - reiniciar SQL Server o Windows;
   - cambiar el modo de autenticación de SQL Server;
   - habilitar `xp_cmdshell`;
   - reemplazar un procedimiento cifrado;
   - restablecer una contraseña funcional de SIGA;
   - copiar permisos o menús de otro usuario;
   - cambiar la configuración regional de Windows.
5. Crear copias de seguridad antes de modificar la base, el registro o `C:\conex_siga.ini`.
6. No desactivar adaptadores de red ni cambiar su MAC si se puede alinear la configuración de SIGA.
7. No dejar `USERS_T1` desactivado. Si se suspende, debe reactivarse en la misma transacción y comprobarse al final.
8. No devolver varias MAC desde `dbo.usp_Leer_xp_cadena`. SIGA espera una sola fila.
9. Detenerse si los nombres de tablas, columnas o procedimientos no coinciden con esta guía; pueden variar entre versiones.
10. Pedir al usuario que escriba manualmente las credenciales de SIGA. La automatización de los controles de PowerBuilder puede parecer exitosa aunque los campos internos permanezcan vacíos.

## 3. Variables que deben recopilarse

Usar variables y nunca incorporar contraseñas reales en scripts permanentes:

| Variable | Ejemplo de esta instalación | Descripción |
|---|---|---|
| `SIGA_HOME` | `C:\SIGA_MEF` | Carpeta donde está `siga.exe` |
| `SQL_INSTANCE` | `localhost\SQLSERVER25` | Instancia local de SQL Server |
| `DATABASE` | `SIGA_1750` | Base restaurada de SIGA |
| `SQL_LOGIN` | `admin_siga` | Inicio de sesión usado por SIGA para conectarse |
| `SQL_PASSWORD` | No documentar | Contraseña del inicio de sesión SQL |
| `DATABASE_OWNER` | Descubrir o solicitar | Propietario de la base en la PC de destino; depende del equipo, dominio y cuenta instaladora |
| `SIGA_USER` | `admin` | Usuario funcional de SIGA |
| `SIGA_PASSWORD` | No documentar | Contraseña funcional cifrada en las tablas SIGA |
| `CONFIG_PATH` | `C:\conex_siga.ini` | Archivo activo que lee `siga.exe` |
| `SIGA_VERSION` | `26.01.00` | Versión del ejecutable/configuración |
| `EFFECTIVE_MAC` | Descubrir | Primera MAC que obtiene el proceso de SQL Server |

Los valores anteriores son únicamente una referencia de la PC original. En otra PC deben descubrirse nuevamente. En particular, nunca se debe copiar el owner `MRZ-PC\Miroz`: ese identificador pertenece solamente a la máquina donde se elaboró esta guía.

Para determinar `DATABASE_OWNER`, la IA debe consultar primero:

```sql
SELECT d.name AS base_datos,
       SUSER_SNAME(d.owner_sid) AS owner_actual
FROM sys.databases AS d
WHERE d.name = '<DATABASE>';
```

Si el owner es válido en la instancia de destino, debe conservarlo. Si aparece como `NULL`, está huérfano o debe cambiarse, la IA tiene que solicitar al usuario instalador una cuenta local o de dominio válida. No debe asumir que el usuario actual de Windows será el owner ni construir el nombre copiando el de otra PC. Antes de cualquier cambio debe verificar que la cuenta exista en `sys.server_principals` y pedir autorización explícita.

## 4. Conceptos que no deben confundirse

SIGA usa dos niveles de autenticación:

1. **Conexión a SQL Server**: instancia, base, inicio de sesión SQL y contraseña almacenados cifrados en `C:\conex_siga.ini`.
2. **Acceso funcional a SIGA**: usuario como `ADMIN` o `GLUNA`, validado principalmente contra `dbo.USERS` y, según la versión, también contra `dbo.SEG_USUARIO`, roles y menús.

La carpeta que contiene `.mdf` y `.ldf` no es una cadena de conexión. SIGA se conecta a una **instancia de SQL Server** y a un **nombre de base**.

Una conexión de Navicat cuya base inicial sea `master` solo demuestra que el servidor responde. No demuestra que SIGA esté usando la base restaurada.

## 5. Fase A: inventario y copias de seguridad

### 5.1 Confirmar los archivos de SIGA

Verificar al menos:

```text
<SIGA_HOME>\siga.exe
<SIGA_HOME>\FUENTES_CONEXION\...
```

En la instalación usada para elaborar esta guía, las herramientas estaban en:

```text
C:\SIGA_MEF\FUENTES_CONEXION\ConexSiga (1)\ConexSiga (1)\ConexSiga (1)\Debug\ConexSiga.exe
C:\SIGA_MEF\FUENTES_CONEXION\ConexSiga (1)\ConexSiga (1)\ConexSiga (1)\Debug\ConexionSiga.dll
C:\SIGA_MEF\FUENTES_CONEXION\ConexSiga (1)\ConexSiga (1)\MODIFICA_CONEX_DIRECCION_MAC.sql
```

No asumir que las rutas serán idénticas. Localizarlas recursivamente.

### 5.2 Descubrir la instancia y el servicio

Comprobar:

```powershell
Get-Service | Where-Object Name -Like 'MSSQL*' |
    Select-Object Name, Status, DisplayName
```

Para una instancia con nombre `SQLSERVER25`, el servicio suele ser:

```text
MSSQL$SQLSERVER25
```

### 5.3 Comprobar servidor y base

Usar inicialmente autenticación de Windows con una cuenta administradora de SQL Server:

```powershell
sqlcmd -S '<SQL_INSTANCE>' -E -d master -Q `
"SELECT @@SERVERNAME AS servidor, @@VERSION AS version;
 SELECT name, state_desc, user_access_desc
 FROM sys.databases
 WHERE name='<DATABASE>';"
```

En la base, comprobar una cantidad razonable de tablas:

```sql
USE [<DATABASE>];
SELECT COUNT(*) AS tablas
FROM sys.tables;
```

La base usada en esta experiencia contenía aproximadamente 939 tablas. La cifra puede variar según la versión.

### 5.4 Hacer respaldo de la base

Antes de reemplazar procedimientos cifrados o modificar seguridad, hacer un `BACKUP DATABASE` completo a una ruta donde la cuenta del servicio SQL tenga escritura:

```sql
BACKUP DATABASE [<DATABASE>]
TO DISK = N'<RUTA_BACKUP>\<DATABASE>_antes_configurar_siga.bak'
WITH COPY_ONLY, INIT, CHECKSUM, STATS = 10;
```

Comprobar el respaldo:

```sql
RESTORE VERIFYONLY
FROM DISK = N'<RUTA_BACKUP>\<DATABASE>_antes_configurar_siga.bak'
WITH CHECKSUM;
```

También copiar, si existe:

```text
C:\conex_siga.ini
```

a una ruta de respaldo dentro de `SIGA_HOME`.

## 6. Fase B: restaurar o adjuntar la base

Si la base ya figura `ONLINE`, no volver a restaurarla.

Si se dispone de un `.bak`, usar primero:

```sql
RESTORE FILELISTONLY FROM DISK = N'<ARCHIVO_BAK>';
```

Después restaurar usando los nombres lógicos obtenidos y rutas válidas de datos/log de la instancia. No copiar ciegamente rutas de otra PC.

Si solo existen `.mdf` y `.ldf`, adjuntarlos únicamente después de verificar que no estén ya usados por otra base y que sean una pareja consistente.

Tras restaurar o adjuntar:

```sql
SELECT name, state_desc, recovery_model_desc
FROM sys.databases
WHERE name = '<DATABASE>';

DBCC CHECKDB ([<DATABASE>]) WITH PHYSICAL_ONLY, NO_INFOMSGS;
```

## 7. Fase C: habilitar la conexión SQL de SIGA

### 7.1 Modo mixto

SIGA usa un inicio de sesión SQL, por lo que la instancia debe admitir autenticación de Windows y SQL Server.

Comprobar:

```sql
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS solo_windows;
```

- `1`: solo Windows; se requiere habilitar modo mixto.
- `0`: modo mixto ya activo.

Si se cambia, solicitar autorización y reiniciar únicamente el servicio de esa instancia. Una forma habitual, ejecutada como `sysadmin`, es:

```sql
EXEC master.dbo.xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'LoginMode',
    REG_DWORD,
    2;
```

Después reiniciar el servicio correspondiente y volver a comprobar `IsIntegratedSecurityOnly`.

### 7.2 Crear o reparar el inicio de sesión SQL

No imprimir la contraseña. Crear el login y mapearlo en la base:

```sql
USE [master];

IF SUSER_ID(N'<SQL_LOGIN>') IS NULL
    CREATE LOGIN [<SQL_LOGIN>]
    WITH PASSWORD = N'<SQL_PASSWORD>', CHECK_POLICY = ON;
ELSE
    ALTER LOGIN [<SQL_LOGIN>] ENABLE;

USE [<DATABASE>];

IF USER_ID(N'<SQL_LOGIN>') IS NULL
    CREATE USER [<SQL_LOGIN>] FOR LOGIN [<SQL_LOGIN>];
ELSE
    ALTER USER [<SQL_LOGIN>] WITH LOGIN = [<SQL_LOGIN>];

IF IS_ROLEMEMBER(N'db_owner', N'<SQL_LOGIN>') <> 1
    ALTER ROLE [db_owner] ADD MEMBER [<SQL_LOGIN>];
```

`db_owner` es un permiso amplio. Usarlo solo si esta versión de SIGA lo requiere y con autorización.

Probar expresamente el login SQL contra la base, no contra `master`:

```powershell
sqlcmd -S '<SQL_INSTANCE>' -U '<SQL_LOGIN>' -P '<SQL_PASSWORD>' `
    -d '<DATABASE>' -Q "SELECT DB_NAME(), COUNT(*) FROM sys.tables;"
```

## 8. Fase D: configuración regional y codificación

Esta versión de SIGA/PowerBuilder y el generador de conexión trabajan correctamente con ANSI de Windows, no con UTF-8 como página de códigos global.

En la PC original fue necesario:

- configuración regional del sistema: `Español (Perú)` / `es-PE`;
- página ANSI: Windows-1252;
- desactivar la opción beta “Usar Unicode UTF-8 para compatibilidad mundial”; 
- reiniciar Windows.

Comprobar después del reinicio:

```powershell
Get-WinSystemLocale
[Text.Encoding]::Default
```

El resultado esperado para la codificación predeterminada es `Windows-1252`.

No cambiar la región si el sistema ya genera y lee correctamente el archivo. Si se cambia, respaldar antes las claves regionales del Registro y pedir autorización para reiniciar Windows.

## 9. Fase E: generar `C:\conex_siga.ini`

### 9.1 Usar preferentemente el generador oficial

Ejecutar `ConexSiga.exe` desde su carpeta `Debug` y suministrar:

- versión exacta de SIGA;
- host/instancia SQL, por ejemplo `localhost\SQLSERVER25`;
- nombre del equipo local;
- base, por ejemplo `SIGA_1750`;
- login SQL;
- contraseña SQL;
- proveedor compatible;
- criterio de base;
- MAC efectiva;
- nombre del equipo.

Para esta versión funcionó el proveedor histórico:

```text
MSS Microsoft SQL Server 2012
```

aunque la instancia sea una versión más reciente de SQL Server.

El criterio siguió este formato:

```text
tablecriteria='%,<DATABASE>'
```

El archivo generado tiene 100 líneas cifradas. En numeración humana:

| Línea | Contenido descifrado esperado |
|---:|---|
| 1 | Versión de SIGA |
| 62 | Host/instancia SQL |
| 63 | Nombre del servidor/equipo |
| 64 | Base de datos |
| 65 | Login SQL |
| 66 | Contraseña SQL |
| 67 | Proveedor |
| 68 | Criterio de la base |
| 69 | MAC efectiva |
| 70 | Nombre del equipo |

Las demás líneas contienen datos de relleno. No alterar el número de líneas.

### 9.2 Ubicación y codificación

SIGA busca el archivo activo en:

```text
C:\conex_siga.ini
```

No basta con dejarlo en `SIGA_HOME`.

Debe guardarse con la codificación ANSI predeterminada de Windows, normalmente Windows-1252. No usar UTF-8, ni siquiera UTF-8 sin BOM.

Si `C:\conex_siga.ini` requiere privilegios administrativos, preparar primero una copia verificada dentro de `SIGA_HOME`, cerrar SIGA y copiarla mediante una operación elevada. Verificar después que la fecha y el contenido cifrado realmente cambiaron; una solicitud de elevación cancelada puede parecer finalizada sin haber reemplazado el archivo.

### 9.3 Inspección avanzada del formato

Solo si el generador no funciona y la IA necesita verificar el archivo, `ConexionSiga.dll` expone métodos como `of_encriptar`, `of_decriptar` y `f_encripta_password`.

La clave incorporada por esta versión del generador para las líneas de conexión fue:

```text
F6deZRg1yBhCEAmgu8aW
```

Esto es un detalle interno de compatibilidad, no una contraseña del usuario. No debe usarse para registrar ni mostrar la contraseña SQL descifrada.

Ejemplo de verificación de la MAC sin imprimir otros secretos:

```powershell
$dll = '<RUTA>\ConexionSiga.dll'
[Reflection.Assembly]::LoadFrom($dll) | Out-Null
$crypto = New-Object ConexionSiga.Siga
$key = 'F6deZRg1yBhCEAmgu8aW'
$lines = [IO.File]::ReadAllLines('C:\conex_siga.ini', [Text.Encoding]::Default)

if ($lines.Count -ne 100) { throw 'Formato inesperado de conex_siga.ini' }

$mac = [string]$crypto.of_decriptar($lines[68], $key) # índice 0
$mac
```

## 10. Fase F: descubrir la MAC que realmente usa SIGA

Esta fue la causa principal de los errores encontrados.

SIGA crea temporalmente un procedimiento que ejecuta `ipconfig /all` mediante `xp_cmdshell` y selecciona la **primera** línea que contiene `Physical Address` o `Dirección física`.

Eso significa que puede tomar un adaptador virtual desconectado antes que la tarjeta física. En la PC original:

- Realtek física: `F4-8E-38-F2-2B-87`.
- Fortinet virtual, detectada primero: `00-09-0F-FE-00-01`.
- La MAC efectiva para SIGA terminó siendo la de Fortinet porque aparecía primero en la salida vista por SQL Server.

No elegir la MAC basándose solamente en `Get-NetAdapter`. Reproducir la selección desde el contexto de SQL Server.

### 10.1 Habilitar `xp_cmdshell`

`xp_cmdshell` amplía la superficie de seguridad de SQL Server. Solicitar autorización explícita antes de habilitarlo.

```sql
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1;
RECONFIGURE;

SELECT name, value_in_use
FROM sys.configurations
WHERE name IN ('show advanced options', 'xp_cmdshell');
```

En esta versión, deshabilitarlo nuevamente provocó `ERROR-03`; por tanto, confirmar que siga en `1` antes de probar SIGA.

### 10.2 Obtener la primera MAC desde SQL Server

La salida puede estar en inglés o español:

```sql
CREATE TABLE #ipconfig
(
    id     int IDENTITY(1,1),
    linea  varchar(455)
);

INSERT #ipconfig(linea)
EXEC master..xp_cmdshell 'ipconfig /all';

SELECT TOP (1)
       LTRIM(RTRIM(SUBSTRING(linea, CHARINDEX(':', linea) + 1, 20))) AS mac_efectiva
FROM #ipconfig
WHERE linea LIKE '%Physical Address%'
   OR linea LIKE '%Direcci%n f%sica%'
ORDER BY id;
```

Guardar el resultado como `EFFECTIVE_MAC`.

## 11. Fase G: alinear la MAC de la base con el archivo

Debe cumplirse:

```text
MAC descifrada de C:\conex_siga.ini
    = única fila devuelta por dbo.usp_Leer_xp_cadena
    = primera MAC detectada por SQL Server
```

### 11.1 Regla crítica: una sola fila

En una prueba se configuró el procedimiento para devolver tanto la MAC física como la virtual. Eso permitió pasar una validación inicial, pero después SIGA mostró:

```text
El conex_siga no corresponde a la BD.
```

La solución fue devolver **una sola MAC**, exactamente la misma que estaba cifrada en `C:\conex_siga.ini`.

### 11.2 Procedimiento de validación

En la base evaluada, `dbo.usp_Leer_xp_cadena` estaba cifrado. No se puede recuperar su definición original mediante `OBJECT_DEFINITION`. Antes de reemplazarlo debe existir un respaldo completo de la base y autorización explícita.

Versión mínima compatible:

```sql
USE [<DATABASE>];
GO

ALTER PROCEDURE dbo.usp_Leer_xp_cadena
WITH ENCRYPTION
AS
BEGIN
    SET NOCOUNT ON;
    SELECT '<EFFECTIVE_MAC>' AS dato;
    RETURN;
END;
GO

EXEC dbo.usp_Leer_xp_cadena;
```

La ejecución final debe producir exactamente una fila y una columna llamada `dato`.

### 11.3 Verificación exacta

Descifrar solo la línea MAC del archivo con `ConexionSiga.dll`, ejecutar el procedimiento y comparar como cadenas exactas. No continuar si hay espacios, otra MAC o más de una fila.

## 12. Fase H: usuario funcional de SIGA

### 12.1 Comprobación de solo lectura

El nombre escrito en la pantalla se convierte a mayúsculas. Es normal que `admin` se muestre `ADMIN` o `Gluna` se muestre `GLUNA`. No es la causa de un rechazo.

Comprobar el usuario sin mostrar su contraseña:

```sql
SELECT CUSER_ID,
       CESTADO,
       LEN(CPASSWORD) AS longitud_password,
       DT_VIGEN_FECHA,
       CMENU_ID,
       SEC_EJEC,
       LSUPERVISOR
FROM dbo.USERS
WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = UPPER('<SIGA_USER>');

SELECT USUARIO, ESTADO, BLOQUEO, CADUCIDAD,
       FE_ULTIMO_PWD, FECHA_BLOQUEO
FROM dbo.SEG_USUARIO
WHERE UPPER(LTRIM(RTRIM(USUARIO))) = UPPER('<SIGA_USER>');

SELECT USUARIO, ROL
FROM dbo.SEG_ROL_USUARIO
WHERE UPPER(LTRIM(RTRIM(USUARIO))) = UPPER('<SIGA_USER>');

SELECT COUNT(*) AS opciones_menu
FROM dbo.USERS_MENU
WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = UPPER('<SIGA_USER>');
```

En esta experiencia, `admin` estaba activo pero tenía la vigencia vencida y cero filas en `USERS_MENU`.

### 12.2 Reglas observadas para una contraseña nueva

La versión probada exigía:

- entre 7 y 15 caracteres;
- al menos una mayúscula;
- al menos una minúscula;
- al menos un número;
- sin caracteres especiales.

Confirmar estas reglas en la versión instalada antes de cambiarla.

### 12.3 Cifrar la contraseña con la biblioteca oficial

No guardar texto plano directamente en las tablas. Usar:

```powershell
$dll = '<RUTA>\ConexionSiga.dll'
[Reflection.Assembly]::LoadFrom($dll) | Out-Null
$crypto = New-Object ConexionSiga.Siga
$passwordCifrado = [string]$crypto.f_encripta_password($passwordPlano)
```

La IA debe recibir `passwordPlano` de forma segura y no imprimirlo. Después debe actualizar `USERS.CPASSWORD` y `SEG_USUARIO.PASSWORD` mediante parámetros de ADO.NET, no concatenando el valor dentro del SQL.

### 12.4 Evitar el efecto destructivo de `USERS_T1`

En la base examinada, el trigger `dbo.USERS_T1` reconstruía tablas de seguridad ante cambios en `USERS`. Una actualización directa podía alterar masivamente:

- `SEG_USUARIO`;
- `SEG_ROL_USUARIO`;
- `SEG_ROL_PAGINA_PRIVILEGIO`.

Por eso el cambio de contraseña debe:

1. registrar conteos previos;
2. iniciar una transacción con `XACT_ABORT ON`;
3. desactivar temporalmente `dbo.USERS_T1`;
4. actualizar exactamente una fila en `dbo.USERS`;
5. actualizar exactamente una fila en `dbo.SEG_USUARIO`;
6. reactivar el trigger;
7. confirmar la transacción;
8. comprobar que el trigger esté activo y que los conteos globales no hayan cambiado.

Esqueleto SQL; `@PasswordCifrado` debe enviarse como parámetro:

```sql
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DISABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;

    UPDATE dbo.USERS
    SET CPASSWORD = @PasswordCifrado
    WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = UPPER(@Usuario);

    IF @@ROWCOUNT <> 1
        THROW 51000, 'No se actualizó exactamente una fila en USERS.', 1;

    UPDATE dbo.SEG_USUARIO
    SET PASSWORD = @PasswordCifrado
    WHERE UPPER(LTRIM(RTRIM(USUARIO))) = UPPER(@Usuario);

    IF @@ROWCOUNT <> 1
        THROW 51001, 'No se actualizó exactamente una fila en SEG_USUARIO.', 1;

    ENABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

    IF EXISTS
    (
        SELECT 1
        FROM sys.triggers
        WHERE object_id = OBJECT_ID('dbo.USERS_T1')
          AND is_disabled = 1
    )
        ENABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;

    THROW;
END CATCH;
```

No registrar el valor de `@PasswordCifrado` en la salida.

## 13. Fase I: vigencia, rol y opciones de menú

Solo realizar esta fase si las comprobaciones muestran que el usuario está vencido o no tiene menús, y después de pedir autorización porque copiar un perfil concede permisos amplios.

### 13.1 Extender la vigencia

Desactivar `USERS_T1` solo durante la actualización y volver a activarlo en la misma transacción:

```sql
DISABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;

UPDATE dbo.USERS
SET DT_VIGEN_FECHA = '<FECHA_FUTURA>'
WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = UPPER('<SIGA_USER>');

ENABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;
```

Exigir `@@ROWCOUNT = 1` y envolverlo con el mismo patrón `TRY/CATCH` anterior.

### 13.2 Copiar un perfil de menú conocido

No asumir que `SIGAMEF` existe ni que siempre tiene 44 filas. Elegir un usuario plantilla validado por el responsable de la instalación.

Las columnas observadas fueron:

```text
CUSER_ID, CMENU_ID, ESTADO, NOMBRE, ORDEN,
SEC_EJEC, TIPO, TITULO, TITULO_SEC
```

Ejemplo idempotente:

```sql
INSERT dbo.USERS_MENU
(
    CUSER_ID, CMENU_ID, ESTADO, NOMBRE, ORDEN,
    SEC_EJEC, TIPO, TITULO, TITULO_SEC
)
SELECT
    '<SIGA_USER>', p.CMENU_ID, p.ESTADO, p.NOMBRE, p.ORDEN,
    p.SEC_EJEC, p.TIPO, p.TITULO, p.TITULO_SEC
FROM dbo.USERS_MENU AS p
WHERE UPPER(LTRIM(RTRIM(p.CUSER_ID))) = UPPER('<USUARIO_PLANTILLA>')
  AND p.ESTADO = 0
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.USERS_MENU AS d
      WHERE UPPER(LTRIM(RTRIM(d.CUSER_ID))) = UPPER('<SIGA_USER>')
        AND ISNULL(d.CMENU_ID, '') = ISNULL(p.CMENU_ID, '')
        AND ISNULL(d.SEC_EJEC, 0) = ISNULL(p.SEC_EJEC, 0)
        AND ISNULL(d.TIPO, '') = ISNULL(p.TIPO, '')
  );
```

Después comprobar:

```sql
SELECT COUNT(*)
FROM dbo.USERS_MENU
WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = UPPER('<SIGA_USER>');

SELECT name, is_disabled
FROM sys.triggers
WHERE object_id = OBJECT_ID('dbo.USERS_T1');
```

`is_disabled` debe ser `0`.

Comparar también los conteos globales antes y después:

```sql
SELECT COUNT(*) FROM dbo.SEG_USUARIO;
SELECT COUNT(*) FROM dbo.SEG_ROL_USUARIO;
SELECT COUNT(*) FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO;
```

## 14. Fase J: prueba final

1. Cerrar todas las instancias previas de `siga.exe`.
2. Abrir `<SIGA_HOME>\siga.exe` con directorio de trabajo `SIGA_HOME`.
3. Pedir al usuario que escriba manualmente el usuario y la contraseña.
4. Pulsar el botón azul con el check, no el botón rojo de salida.
5. Confirmar que aparece el selector de módulos.
6. Abrir un módulo autorizado y confirmar que carga información de la base.
7. Opcionalmente comprobar una sesión SQL del login de conexión:

```sql
SELECT session_id, login_name, host_name, program_name, status
FROM sys.dm_exec_sessions
WHERE login_name = '<SQL_LOGIN>';
```

Que el proceso no mantenga una sesión persistente mientras está solo en la pantalla inicial no demuestra por sí mismo un fallo; algunas conexiones se abren y cierran rápidamente.

## 15. Tabla de diagnóstico

| Síntoma | Causa más probable | Acción correcta |
|---|---|---|
| `ERROR-03` | `xp_cmdshell` está deshabilitado o SIGA no pudo crear/ejecutar su validación | Verificar `value_in_use = 1` y permisos del login SQL |
| “Se ha detectado un acceso no autorizado” | La primera MAC vista por SQL Server no coincide con la MAC cifrada/autorizada | Obtener la primera MAC mediante `xp_cmdshell`, actualizar el INI y devolver esa única MAC desde la base |
| “El conex_siga no corresponde a la BD” | El procedimiento devuelve otra MAC o varias filas | Hacer que `usp_Leer_xp_cadena` devuelva exactamente una fila idéntica al INI |
| El usuario aparece en mayúsculas | Comportamiento normal del campo PowerBuilder | No modificar la cuenta por este motivo |
| “Falta ingresar el Usuario/Password” durante automatización | Las pulsaciones sintéticas no actualizaron el valor interno del control | Pedir escritura manual |
| La pantalla limpia usuario y clave sin entrar | Credenciales vacías por automatización, contraseña incorrecta, vigencia o permisos | Probar manualmente y revisar `USERS`, `SEG_USUARIO` y `USERS_MENU` |
| El generador produce datos ilegibles | UTF-8 global o archivo guardado en UTF-8 | Usar `es-PE`, Windows-1252 y regenerar el archivo |
| El login SQL funciona en `master` pero SIGA no carga | Base inicial/configuración incorrecta o usuario sin permisos en la base | Probar directamente contra `<DATABASE>` y revisar el mapeo del login |
| El cambio en `C:\conex_siga.ini` no surte efecto | Se modificó una copia en `SIGA_HOME`, SIGA estaba abierto o la elevación se canceló | Cerrar SIGA, reemplazar el archivo raíz con elevación y verificarlo descifrado |
| Desaparecen roles/privilegios al cambiar `USERS` | Se disparó `USERS_T1` | Restaurar desde respaldo o transacción; repetir con suspensión temporal controlada |

## 16. Secuencia recomendada resumida

La IA debe seguir este orden exacto:

1. Inventariar archivos, instancia, servicio y versión.
2. Confirmar que la base está `ONLINE` y hacer respaldo.
3. Confirmar modo mixto y crear/mapear el login SQL.
4. Probar el login SQL directamente contra la base SIGA.
5. Corregir región/codificación solo si es necesario; reiniciar Windows si se cambió.
6. Habilitar `xp_cmdshell` con autorización.
7. Obtener la primera MAC desde el contexto de SQL Server.
8. Generar `C:\conex_siga.ini` en Windows-1252 con esa MAC.
9. Configurar `dbo.usp_Leer_xp_cadena` para devolver una sola MAC idéntica.
10. Verificar igualdad exacta entre archivo, procedimiento y MAC detectada.
11. Revisar el usuario funcional, contraseña cifrada, vigencia, rol y menús.
12. Modificar seguridad solo con respaldo, autorización y transacción.
13. Pedir al usuario que escriba manualmente las credenciales.
14. Confirmar selector de módulos y carga de datos.

## 17. Criterios de aceptación

La instalación solo se considera terminada cuando todos estos puntos se cumplen:

- [ ] El servicio de la instancia SQL está iniciado.
- [ ] La base SIGA está `ONLINE` y pasó la comprobación básica.
- [ ] El login SQL conecta directamente a la base.
- [ ] `C:\conex_siga.ini` tiene 100 líneas y codificación Windows-1252.
- [ ] El INI contiene la instancia y base correctas.
- [ ] `xp_cmdshell` está habilitado si esta versión lo necesita.
- [ ] La MAC del INI coincide con la primera MAC obtenida por SQL Server.
- [ ] `usp_Leer_xp_cadena` devuelve exactamente esa MAC y una sola fila.
- [ ] El usuario SIGA existe, está activo y no está bloqueado.
- [ ] La contraseña está cifrada consistentemente en las tablas requeridas.
- [ ] La vigencia del usuario no está vencida.
- [ ] El usuario tiene rol y opciones de menú autorizadas.
- [ ] `USERS_T1` está activo.
- [ ] Los conteos de roles y privilegios no cambiaron inesperadamente.
- [ ] El usuario puede entrar manualmente y ver el selector de módulos.
- [ ] Un módulo autorizado carga datos de `<DATABASE>`.

## 18. Estado de referencia de la PC donde se elaboró esta guía

Esta sección sirve solo para comparar, no para copiar ciegamente:

```text
Windows: configuración regional es-PE, ANSI Windows-1252
SIGA: 26.01.00
Ejecutable: C:\SIGA_MEF\siga.exe
Archivo activo: C:\conex_siga.ini
Instancia: localhost\SQLSERVER25
Base: SIGA_1750
Login SQL: admin_siga
Owner de base en esta PC de referencia: MRZ-PC\Miroz
Owner para otra PC: descubrir con SUSER_SNAME(owner_sid) o solicitarlo al instalador; no copiar el valor anterior
MAC física Realtek: F4-8E-38-F2-2B-87
MAC efectiva detectada primero por SQL/Fortinet: 00-09-0F-FE-00-01
MAC final en INI y procedimiento: 00-09-0F-FE-00-01
Procedimiento MAC: dbo.usp_Leer_xp_cadena, una sola fila
Usuario funcional probado: admin/ADMIN
```

Las contraseñas fueron omitidas intencionalmente. En cada nueva PC deben establecerse y transmitirse de forma segura.
