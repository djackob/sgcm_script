/*
===============================================================================
  SIGA - Reparar menus de GLUNA para ejecutora 1750
  Ambito : [SIGA_1750]

  Problema:
    Tras clonar desde SIGAMEF, menu/opciones quedan con SEC_EJEC=0 (plantilla
    global). Al ingresar a la ejecutora 001750, SIGA no muestra menus.

  Solucion:
    1. Recrear USERS_MENU y USERS_OPCION con SEC_EJEC=1750.
    2. Reconstruir privilegios de pagina del rol GLUNA en la ejecutora 1750.

  Uso:
    sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" -i solo_desarrollo/reparar_menu_gluna_ejecutora.sql
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

DECLARE @Usuario   varchar(30) = 'GLUNA';
DECLARE @Plantilla varchar(30) = 'SIGAMEF';
DECLARE @SecEjec   decimal(6,0) = 1750;
DECLARE @menuCopiados int;
DECLARE @opcionCopiadas int;
DECLARE @privReconstruidos int;

BEGIN TRY
    BEGIN TRANSACTION;

    /* FK_USERS_MENU_USERS_OPCION: primero opciones, luego menu. */

    DELETE FROM dbo.USERS_OPCION
     WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = @Usuario;

    DELETE FROM dbo.USERS_MENU
     WHERE UPPER(LTRIM(RTRIM(CUSER_ID))) = @Usuario;

    INSERT INTO dbo.USERS_MENU
        (CUSER_ID, CMENU_ID, ESTADO, NOMBRE, ORDEN, SEC_EJEC, TIPO, TITULO, TITULO_SEC)
    SELECT
        @Usuario,
        p.CMENU_ID, NULL, NULL, p.ORDEN,
        @SecEjec, NULL, p.TITULO, p.TITULO_SEC
      FROM dbo.USERS_MENU AS p
     WHERE UPPER(LTRIM(RTRIM(p.CUSER_ID))) = @Plantilla;

    SET @menuCopiados = @@ROWCOUNT;

    IF @menuCopiados = 0
        THROW 51030, 'No se copiaron filas de USERS_MENU desde SIGAMEF.', 1;

    INSERT INTO dbo.USERS_OPCION
        (CUSER_ID, CMENU_ID, TITULO, TITULO_SEC, OPCION, SEC_EJEC,
         TIPO, ORDEN, NOMBRE, COMANDO, CONDICION,
         TITULO1, TITULO_SEC1, SALTO_TABLA, SALTO_CAMPO, MANTENIMIENTO, ESTADO, FLAG_WEB)
    SELECT
        @Usuario,
        o.CMENU_ID, o.TITULO, o.TITULO_SEC, o.OPCION, @SecEjec,
        o.TIPO, o.ORDEN, o.NOMBRE, o.COMANDO, o.CONDICION,
        o.TITULO1, o.TITULO_SEC1, o.SALTO_TABLA, o.SALTO_CAMPO, o.MANTENIMIENTO, o.ESTADO, o.FLAG_WEB
      FROM dbo.USERS_OPCION AS o
     WHERE UPPER(LTRIM(RTRIM(o.CUSER_ID))) = @Plantilla;

    SET @opcionCopiadas = @@ROWCOUNT;

    DELETE FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO
     WHERE UPPER(LTRIM(RTRIM(ROL))) = @Usuario
       AND SEC_EJEC IN (0, @SecEjec);

    INSERT INTO dbo.SEG_ROL_PAGINA_PRIVILEGIO (PRIVILEGIO, ROL, PAGINA, SEC_EJEC)
    SELECT DISTINCT
           A.MANTENIMIENTO, @Usuario, B.ORDEN, @SecEjec
      FROM dbo.USERS_OPCION AS A
      JOIN dbo.USERS_OPCION AS B
        ON B.CUSER_ID = @Plantilla
       AND A.CUSER_ID = @Usuario
       AND A.TITULO = B.TITULO
       AND B.CMENU_ID = 20
       AND A.CMENU_ID = 20
       AND A.TITULO_SEC = B.TITULO_SEC
       AND A.OPCION = B.OPCION
     WHERE NOT A.MANTENIMIENTO IS NULL;

    SET @privReconstruidos = @@ROWCOUNT;

    INSERT INTO dbo.SEG_ROL_PAGINA_PRIVILEGIO (PRIVILEGIO, ROL, PAGINA, SEC_EJEC)
    SELECT 2, @Usuario, 1020000, e.SEC_EJEC
      FROM dbo.SIG_EJECUTORA AS e
     WHERE e.SEC_EJEC = @SecEjec
       AND NOT EXISTS (
           SELECT 1
             FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO AS p
            WHERE p.ROL = @Usuario
              AND p.PAGINA = 1020000
              AND p.SEC_EJEC = e.SEC_EJEC);

    COMMIT TRANSACTION;

    PRINT '=== Reparacion completada ===';
    PRINT CONCAT('Menu copiado: ', @menuCopiados);
    PRINT CONCAT('Opciones copiadas: ', @opcionCopiadas);
    PRINT CONCAT('Privilegios reconstruidos en ejecutora ', @SecEjec, ': ', @privReconstruidos);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @err nvarchar(4000) = ERROR_MESSAGE();
    RAISERROR('REPARACION_FALLIDA: %s', 16, 1, @err);
    RETURN;
END CATCH;
GO

PRINT '';
PRINT '=== Verificacion ===';

SELECT cuser_id, sec_ejec, menus = COUNT(*)
  FROM dbo.USERS_MENU
 WHERE UPPER(CUSER_ID) = 'GLUNA'
 GROUP BY cuser_id, sec_ejec;

SELECT cuser_id, sec_ejec, opciones = COUNT(*)
  FROM dbo.USERS_OPCION
 WHERE UPPER(CUSER_ID) = 'GLUNA'
 GROUP BY cuser_id, sec_ejec;

SELECT rol, sec_ejec, paginas = COUNT(*)
  FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO
 WHERE UPPER(ROL) = 'GLUNA'
 GROUP BY rol, sec_ejec;

PRINT '';
PRINT 'Cierre SIGA y vuelva a ingresar con GLUNA en ejecutora 001750.';
GO
