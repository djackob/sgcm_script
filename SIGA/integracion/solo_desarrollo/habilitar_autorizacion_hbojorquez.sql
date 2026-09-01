/*
===============================================================================
  SIGA - Habilitar Autorizacion del Pedido (opcion 04) para responsable de centro
  Ambito : [SIGA_1750]

  Contexto:
    El responsable del centro 01.04.02 es BOJORQUEZ (empleado 09946882).
  En esta instalacion ese empleado esta vinculado a IRIVERA en SIG_PERSONAL;
  el usuario HBOJORQUEZ existe pero no tiene opcion 04 ni enlace de empleado.

  Que hace:
    1. Agrega opcion 04 (pagina 03020000) al menu Pedidos de HBOJORQUEZ.
    2. Otorga PRIVILEGIO 2 (servicios) en SEG_ROL_PAGINA_PRIVILEGIO.
    3. Vincula empleado 09946882 a HBOJORQUEZ en SIG_PERSONAL.

  Nota:
    Si IRIVERA dejaba de ver pedidos como BOJORQUEZ, revertir cuser_id en
    SIG_PERSONAL o usar IRIVERA para autorizar (tiene el mismo empleado hoy).

  Uso:
    sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" -i solo_desarrollo/habilitar_autorizacion_hbojorquez.sql
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

DECLARE @Usuario     varchar(30) = 'HBOJORQUEZ';
DECLARE @Referencia  varchar(30) = 'GGONZALES';
DECLARE @SecEjec     decimal(6,0) = 1750;
DECLARE @PaginaAuth  varchar(8) = '03020000';
DECLARE @OpcionAuth  varchar(2) = '04';
DECLARE @EmpleadoResp varchar(15) = '09946882';

BEGIN TRY
    BEGIN TRANSACTION;

  IF NOT EXISTS (
        SELECT 1
          FROM dbo.USERS_OPCION
         WHERE CUSER_ID = @Usuario
           AND CMENU_ID = '20'
           AND TITULO = '03'
           AND TITULO_SEC = '00'
           AND OPCION = @OpcionAuth
           AND SEC_EJEC = @SecEjec)
    BEGIN
        INSERT INTO dbo.USERS_OPCION (
            CUSER_ID, CMENU_ID, TITULO, TITULO_SEC, OPCION, SEC_EJEC,
            TIPO, ORDEN, NOMBRE, COMANDO, CONDICION,
            TITULO1, TITULO_SEC1, SALTO_TABLA, SALTO_CAMPO,
            MANTENIMIENTO, ESTADO, FLAG_WEB)
        SELECT
            @Usuario, CMENU_ID, TITULO, TITULO_SEC, OPCION, SEC_EJEC,
            TIPO, ORDEN, 'Autorizaci' + CHAR(243) + 'n del Pedido', COMANDO, CONDICION,
            TITULO1, TITULO_SEC1, SALTO_TABLA, SALTO_CAMPO,
            '2', ESTADO, FLAG_WEB
          FROM dbo.USERS_OPCION
         WHERE CUSER_ID = @Referencia
           AND CMENU_ID = '20'
           AND TITULO = '03'
           AND TITULO_SEC = '00'
           AND OPCION = @OpcionAuth
           AND SEC_EJEC = @SecEjec;

        IF @@ROWCOUNT = 0
        BEGIN
            INSERT INTO dbo.USERS_OPCION (
                CUSER_ID, CMENU_ID, TITULO, TITULO_SEC, OPCION, SEC_EJEC,
                ORDEN, NOMBRE, MANTENIMIENTO)
            SELECT
                @Usuario, '20', '03', '00', @OpcionAuth, @SecEjec,
                @PaginaAuth, 'Autorizaci' + CHAR(243) + 'n del Pedido', '2';
        END;
    END
    ELSE
    BEGIN
        UPDATE dbo.USERS_OPCION
           SET MANTENIMIENTO = '2',
               ORDEN = @PaginaAuth,
               NOMBRE = 'Autorizaci' + CHAR(243) + 'n del Pedido'
         WHERE CUSER_ID = @Usuario
           AND CMENU_ID = '20'
           AND TITULO = '03'
           AND TITULO_SEC = '00'
           AND OPCION = @OpcionAuth
           AND SEC_EJEC = @SecEjec;
    END;

    IF NOT EXISTS (
        SELECT 1
          FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO
         WHERE ROL = @Usuario
           AND PAGINA = @PaginaAuth
           AND SEC_EJEC = @SecEjec
           AND PRIVILEGIO = 2)
    BEGIN
        INSERT INTO dbo.SEG_ROL_PAGINA_PRIVILEGIO (PRIVILEGIO, ROL, PAGINA, SEC_EJEC)
        VALUES (2, @Usuario, @PaginaAuth, @SecEjec);
    END;

    UPDATE dbo.SIG_PERSONAL
       SET cuser_id = @Usuario
     WHERE sec_ejec = @SecEjec
       AND empleado = @EmpleadoResp;

    COMMIT TRANSACTION;

    PRINT '=== Autorizacion habilitada para HBOJORQUEZ ===';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @err nvarchar(4000) = ERROR_MESSAGE();
    RAISERROR('HBOJORQUEZ_AUTH_FALLIDA: %s', 16, 1, @err);
    RETURN;
END CATCH;
GO

PRINT '';
PRINT '=== Verificacion ===';
SELECT u.CUSER_ID, u.OPCION, u.ORDEN, u.MANTENIMIENTO, u.NOMBRE
  FROM dbo.USERS_OPCION AS u
 WHERE u.CUSER_ID = 'HBOJORQUEZ'
   AND u.CMENU_ID = '20'
   AND u.TITULO = '03'
   AND u.OPCION = '04';

SELECT p.PRIVILEGIO, p.PAGINA, p.ROL
  FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO AS p
 WHERE p.ROL = 'HBOJORQUEZ'
   AND p.SEC_EJEC = 1750
   AND p.PAGINA = '03020000';

SELECT empleado, nombre_completo, cuser_id
  FROM dbo.SIG_PERSONAL
 WHERE sec_ejec = 1750
   AND empleado = '09946882';

PRINT '';
PRINT 'Cierre SIGA y entre con HBOJORQUEZ (o IRIVERA si conserva el enlace).';
GO
