/*
===============================================================================
  SIGA - Clonar perfil SIGAMEF -> GLUNA (homologacion / desarrollo)
  Ambito : [SIGA_1750]  (ejecutar DENTRO de la base SIGA, no en DBSIGCM)

  Que hace:
    1. Prolonga la vigencia de GLUNA.
    2. Copia menu (USERS_MENU) y opciones (USERS_OPCION) de SIGAMEF a GLUNA.
    3. Asigna el rol SIGAMEF a GLUNA (ademas del rol GLUNA existente).
    4. Copia privilegios de pagina del rol SIGAMEF al rol GLUNA (sin quitar los
       que GLUNA ya tenia).
    5. Alinea banderas operativas de USERS (lok2*) con SIGAMEF y deja
       CESTADO=1 (activo en el cliente SIGA; no copiar desde SIGAMEF).

  IMPORTANTE:
    - SOLO DESARROLLO LOCAL. No forma parte de instalar.ps1. No se despliega a produccion.
    - No modifica contrasenas.
    - Suspende temporalmente el trigger dbo.USERS_T1 (patron guia SIGA MEF).
    - Requiere permisos de escritura sobre tablas de seguridad SIGA.

  Uso:
    sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" -i solo_desarrollo/clonar_perfil_sigamef_a_gluna.sql
===============================================================================
*/

IF N'$(entorno)' <> N'DESARROLLO'
BEGIN
    RAISERROR(N'Solo desarrollo local. Este script no forma parte de instalar.ps1 y no pasa a produccion. Ejecute con -v entorno="DESARROLLO".', 16, 1);
    SET NOEXEC ON;
END
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Plantilla   varchar(30) = 'SIGAMEF';
DECLARE @Destino     varchar(30) = 'GLUNA';
DECLARE @Vigencia    datetime    = '2027-12-31T23:59:59';
DECLARE @SecEjec     decimal(6,0) = 1750;

DECLARE @menuPlantilla int;
DECLARE @menuDestinoAntes int;
DECLARE @menuDestinoDespues int;
DECLARE @opcionPlantilla int;
DECLARE @opcionDestinoDespues int;
DECLARE @privCopiados int;

/* ---- Comprobaciones previas ---------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM dbo.USERS WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = @Plantilla)
BEGIN
    RAISERROR('PLANTILLA_INEXISTENTE: no existe el usuario %s en dbo.USERS.', 16, 1, @Plantilla);
    RETURN;
END;

IF NOT EXISTS (SELECT 1 FROM dbo.USERS WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = @Destino)
BEGIN
    RAISERROR('DESTINO_INEXISTENTE: no existe el usuario %s en dbo.USERS.', 16, 1, @Destino);
    RETURN;
END;

IF NOT EXISTS (SELECT 1 FROM dbo.SEG_USUARIO WHERE UPPER(LTRIM(RTRIM(USUARIO))) = @Destino)
BEGIN
    RAISERROR('DESTINO_INEXISTENTE: no existe %s en dbo.SEG_USUARIO.', 16, 1, @Destino);
    RETURN;
END;

SELECT @menuPlantilla = COUNT(*)
  FROM dbo.USERS_MENU
 WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = @Plantilla;

IF @menuPlantilla = 0
BEGIN
    RAISERROR('PLANTILLA_SIN_MENU: %s no tiene filas en USERS_MENU.', 16, 1, @Plantilla);
    RETURN;
END;

SELECT @menuDestinoAntes = COUNT(*)
  FROM dbo.USERS_MENU
 WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = @Destino;

SELECT @opcionPlantilla = COUNT(*)
  FROM dbo.USERS_OPCION
 WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = @Plantilla;

PRINT '=== Antes ===';
PRINT CONCAT('Menu ', @Plantilla, ': ', @menuPlantilla);
PRINT CONCAT('Opciones ', @Plantilla, ': ', @opcionPlantilla);
PRINT CONCAT('Menu ', @Destino, ' (antes): ', @menuDestinoAntes);

BEGIN TRY
    BEGIN TRANSACTION;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE object_id = OBJECT_ID('dbo.USERS_T1') AND is_disabled = 0)
        DISABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;

    /* ---- 1. Vigencia y banderas de cabecera -------------------------------- */

    UPDATE d
       SET d.DT_VIGEN_FECHA = @Vigencia,
           d.CESTADO        = 1,
           d.CMENU_ID       = p.CMENU_ID,
           d.SEC_EJEC       = p.SEC_EJEC,
           d.LSUPERVISOR    = p.LSUPERVISOR,
           d.LOK2CUSTLIMIT  = NULL,
           d.LOK2CUSTVIEW   = NULL,
           d.LOK2CUSTADD    = NULL,
           d.LOK2CUSTEDIT   = NULL,
           d.LOK2CUSTDEL    = NULL,
           d.LOK2ORDADD     = NULL,
           d.LOK2ORDDEL     = NULL,
           d.LOK2ORDEDIT    = NULL,
           d.LOK2TBLEDIT    = NULL,
           d.LOK2RPTEDIT    = NULL,
           d.LOK2LBLEDIT    = NULL,
           d.LOK2MAINT      = NULL,
           d.LOK2FILT       = NULL
      FROM dbo.USERS AS d
      JOIN dbo.USERS AS p
        ON UPPER(LTRIM(RTRIM(p.CUSER_ID))) = @Plantilla
     WHERE UPPER(LTRIM(RTRIM(d.CUSER_ID))) = @Destino;

    IF @@ROWCOUNT <> 1
        THROW 51010, 'No se actualizo exactamente una fila en dbo.USERS.', 1;

    /* ---- 2. Menu y opciones: reemplazo completo desde plantilla ------------ */
    /* USERS_OPCION referencia USERS_MENU (FK_USERS_MENU_USERS_OPCION): primero
       opciones, luego menu; al insertar, menu y despues opciones. */

    DELETE FROM dbo.USERS_OPCION
     WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = @Destino;

    DELETE FROM dbo.USERS_MENU
     WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = @Destino;

    INSERT INTO dbo.USERS_MENU
        (CUSER_ID, CMENU_ID, ESTADO, NOMBRE, ORDEN, SEC_EJEC, TIPO, TITULO, TITULO_SEC)
    SELECT
        @Destino,
        p.CMENU_ID, NULL, NULL, p.ORDEN,
        @SecEjec, NULL, p.TITULO, p.TITULO_SEC
      FROM dbo.USERS_MENU AS p
     WHERE UPPER(LTRIM(RTRIM(p.CUSER_ID))) = @Plantilla;

    SET @menuDestinoDespues = @@ROWCOUNT;

    IF @menuDestinoDespues <> @menuPlantilla
        THROW 51011, 'El menu copiado no coincide en cantidad con la plantilla.', 1;

    INSERT INTO dbo.USERS_OPCION
        (CUSER_ID, CMENU_ID, TITULO, TITULO_SEC, OPCION, SEC_EJEC,
         TIPO, ORDEN, NOMBRE, COMANDO, CONDICION,
         TITULO1, TITULO_SEC1, SALTO_TABLA, SALTO_CAMPO, MANTENIMIENTO, ESTADO, FLAG_WEB)
    SELECT
        @Destino,
        o.CMENU_ID, o.TITULO, o.TITULO_SEC, o.OPCION, @SecEjec,
        o.TIPO, o.ORDEN, o.NOMBRE, o.COMANDO, o.CONDICION,
        o.TITULO1, o.TITULO_SEC1, o.SALTO_TABLA, o.SALTO_CAMPO, o.MANTENIMIENTO, o.ESTADO, o.FLAG_WEB
      FROM dbo.USERS_OPCION AS o
     WHERE UPPER(LTRIM(RTRIM(o.CUSER_ID))) = @Plantilla;

    SET @opcionDestinoDespues = @@ROWCOUNT;

    IF @opcionDestinoDespues <> @opcionPlantilla
        THROW 51012, 'Las opciones copiadas no coinciden en cantidad con la plantilla.', 1;

    /* SIGAMEF trae MANTENIMIENTO=1 (basico). Usuarios operativos usan 2+ en
       pantallas de autorizacion (ej. Pedidos de Compra B/S = 03010200). */
    UPDATE d
       SET d.MANTENIMIENTO = r.MANTENIMIENTO
      FROM dbo.USERS_OPCION AS d
      JOIN dbo.USERS_OPCION AS r
        ON r.CUSER_ID = 'JMARINO'
       AND d.CUSER_ID = @Destino
       AND d.CMENU_ID = r.CMENU_ID
       AND d.TITULO = r.TITULO
       AND d.TITULO_SEC = r.TITULO_SEC
       AND d.OPCION = r.OPCION
       AND d.SEC_EJEC = r.SEC_EJEC
     WHERE r.MANTENIMIENTO > d.MANTENIMIENTO;

    /* ---- 3. Rol SIGAMEF asignado a GLUNA ---------------------------------- */

    IF NOT EXISTS (
        SELECT 1
          FROM dbo.SEG_ROL_USUARIO
         WHERE UPPER(LTRIM(RTRIM(USUARIO))) = @Destino
           AND UPPER(LTRIM(RTRIM(ROL)))     = @Plantilla)
    BEGIN
        INSERT INTO dbo.SEG_ROL_USUARIO (USUARIO, ROL)
        VALUES (@Destino, @Plantilla);
    END;

    /* ---- 4. Privilegios de pagina del rol destino (logica USERS_T1) -------- */

    DELETE FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO
     WHERE UPPER(LTRIM(RTRIM(ROL))) = @Destino
       AND SEC_EJEC IN (0, @SecEjec);

    INSERT INTO dbo.SEG_ROL_PAGINA_PRIVILEGIO (PRIVILEGIO, ROL, PAGINA, SEC_EJEC)
    SELECT DISTINCT
           A.MANTENIMIENTO, @Destino, B.ORDEN, @SecEjec
      FROM dbo.USERS_OPCION AS A
      JOIN dbo.USERS_OPCION AS B
        ON B.CUSER_ID = @Plantilla
       AND A.CUSER_ID = @Destino
       AND A.TITULO = B.TITULO
       AND B.CMENU_ID = 20
       AND A.CMENU_ID = 20
       AND A.TITULO_SEC = B.TITULO_SEC
       AND A.OPCION = B.OPCION
     WHERE NOT A.MANTENIMIENTO IS NULL;

    INSERT INTO dbo.SEG_ROL_PAGINA_PRIVILEGIO (PRIVILEGIO, ROL, PAGINA, SEC_EJEC)
    SELECT 2, @Destino, 1020000, e.SEC_EJEC
      FROM dbo.SIG_EJECUTORA AS e
     WHERE e.SEC_EJEC = @SecEjec
       AND NOT EXISTS (
           SELECT 1
             FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO AS p
            WHERE p.ROL = @Destino
              AND p.PAGINA = 1020000
              AND p.SEC_EJEC = e.SEC_EJEC);

    SET @privCopiados = @@ROWCOUNT;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE object_id = OBJECT_ID('dbo.USERS_T1') AND is_disabled = 1)
        ENABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;

    COMMIT TRANSACTION;

    PRINT '';
    PRINT '=== Clonacion completada ===';
    PRINT CONCAT('Vigencia ', @Destino, ' hasta: ', CONVERT(varchar(30), @Vigencia, 120));
    PRINT CONCAT('Menu copiado: ', @menuDestinoDespues, ' filas');
    PRINT CONCAT('Opciones copiadas: ', @opcionDestinoDespues, ' filas');
    PRINT CONCAT('Privilegios de pagina agregados al rol ', @Destino, ': ', @privCopiados);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE object_id = OBJECT_ID('dbo.USERS_T1') AND is_disabled = 1)
        ENABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;

    DECLARE @err nvarchar(4000) = ERROR_MESSAGE();
    RAISERROR('CLONACION_FALLIDA: %s', 16, 1, @err);
    RETURN;
END CATCH;
GO

/* ---- Verificacion posterior (solo lectura) ------------------------------- */

PRINT '';
PRINT '=== Verificacion ===';

SELECT u.CUSER_ID, u.CESTADO, u.DT_VIGEN_FECHA, u.CMENU_ID, u.SEC_EJEC
  FROM dbo.USERS AS u
 WHERE UPPER(u.CUSER_ID) IN ('GLUNA', 'SIGAMEF')
 ORDER BY u.CUSER_ID;

SELECT ru.USUARIO, ru.ROL
  FROM dbo.SEG_ROL_USUARIO AS ru
 WHERE UPPER(ru.USUARIO) = 'GLUNA'
 ORDER BY ru.ROL;

SELECT CUSER_ID = 'GLUNA', sec_ejec, total_menu = COUNT(*)
  FROM dbo.USERS_MENU
 WHERE UPPER(CUSER_ID) = 'GLUNA'
 GROUP BY sec_ejec;

SELECT CUSER_ID = 'GLUNA', sec_ejec, total_opciones = COUNT(*)
  FROM dbo.USERS_OPCION
 WHERE UPPER(CUSER_ID) = 'GLUNA'
 GROUP BY sec_ejec;

SELECT rol, sec_ejec, paginas = COUNT(*)
  FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO
 WHERE UPPER(ROL) = 'GLUNA'
 GROUP BY rol, sec_ejec;

SELECT TOP 10 CUSER_ID, CMENU_ID, TITULO, NOMBRE, ESTADO
  FROM dbo.USERS_MENU
 WHERE UPPER(CUSER_ID) = 'GLUNA'
 ORDER BY CMENU_ID, TITULO;

SELECT name AS trigger_name, is_disabled
  FROM sys.triggers
 WHERE object_id = OBJECT_ID('dbo.USERS_T1');

PRINT '';
PRINT 'Cierre SIGA (siga.exe) y vuelva a ingresar con GLUNA para refrescar menus.';
GO
