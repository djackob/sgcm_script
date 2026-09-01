/*
===============================================================================
  SIGA - Aprobacion S (servicios) para GLUNA en Autorizacion del Pedido
  Ambito : [SIGA_1750]

  Problema:
    En la opcion 04 (pagina 03020000) el filtro Tipo queda en Bien y no muestra
    pedidos de servicio (ej. 001067). GLUNA tiene MANTENIMIENTO/PRIVILEGIO 3
    (nivel alto copiado de JMARINO), asociado en esta instalacion a bienes/almacen.

  Referencia:
    Usuarios con autorizacion de servicios (GGONZALES, RSAAVEDRA, SZUNIGA)
    tienen PRIVILEGIO 2 en la pagina 03020000.

  Solucion homologacion:
    1. Ajustar GLUNA a MANTENIMIENTO 2 en Autorizacion del Pedido (Aprobacion S).
    2. Mantener tambien PRIVILEGIO 3 en la misma pagina (Aprobacion B/S: bienes + servicios).
    3. Renombrar la opcion de menu para GLUNA (sin "Almacen").

  Uso:
    sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" -i solo_desarrollo/otorgar_aprobacion_servicio_gluna.sql

  Luego: cerrar SIGA por completo y volver a entrar con GLUNA.
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
DECLARE @Referencia varchar(30) = 'GGONZALES';
DECLARE @SecEjec   decimal(6,0) = 1750;
DECLARE @PaginaAuth varchar(8) = '03020000';
DECLARE @OpcionAuth varchar(2) = '04';

BEGIN TRY
    BEGIN TRANSACTION;

    /* Aprobacion S: mismo nivel que GGONZALES en Autorizacion del Pedido */
    UPDATE g
       SET g.MANTENIMIENTO = r.MANTENIMIENTO
      FROM dbo.USERS_OPCION AS g
      JOIN dbo.USERS_OPCION AS r
        ON r.CUSER_ID = @Referencia
       AND g.CUSER_ID = @Usuario
       AND g.CMENU_ID = r.CMENU_ID
       AND g.TITULO = r.TITULO
       AND g.TITULO_SEC = r.TITULO_SEC
       AND g.OPCION = r.OPCION
       AND g.SEC_EJEC = r.SEC_EJEC
      JOIN dbo.USERS_OPCION AS b
        ON b.CUSER_ID = 'SIGAMEF'
       AND b.CMENU_ID = 20
       AND g.CMENU_ID = 20
       AND g.TITULO = b.TITULO
       AND g.TITULO_SEC = b.TITULO_SEC
       AND g.OPCION = b.OPCION
       AND b.ORDEN = @PaginaAuth
       AND b.OPCION = @OpcionAuth;

    IF @@ROWCOUNT = 0
        THROW 52001, 'No se actualizo USERS_OPCION de Autorizacion del Pedido para GLUNA.', 1;

    /* Privilegio 2 = servicios (referencia GGONZALES) */
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
    END

    /* Privilegio 3 = bienes; juntos forman B/S segun manual MEF */
    IF NOT EXISTS (
        SELECT 1
          FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO
         WHERE ROL = @Usuario
           AND PAGINA = @PaginaAuth
           AND SEC_EJEC = @SecEjec
           AND PRIVILEGIO = 3)
    BEGIN
        INSERT INTO dbo.SEG_ROL_PAGINA_PRIVILEGIO (PRIVILEGIO, ROL, PAGINA, SEC_EJEC)
        VALUES (3, @Usuario, @PaginaAuth, @SecEjec);
    END

    /* Etiqueta de menu mas clara solo para GLUNA */
    UPDATE dbo.USERS_OPCION
       SET NOMBRE = 'Autorizaci' + CHAR(243) + 'n del Pedido'
     WHERE CUSER_ID = @Usuario
       AND CMENU_ID = 20
       AND TITULO = '03'
       AND TITULO_SEC = '00'
       AND OPCION = @OpcionAuth
       AND ORDEN = @PaginaAuth;

    COMMIT TRANSACTION;

    PRINT '=== Aprobacion S/B/S aplicada a GLUNA ===';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @err nvarchar(4000) = ERROR_MESSAGE();
    RAISERROR('APROBACION_SERVICIO_FALLIDA: %s', 16, 1, @err);
    RETURN;
END CATCH;
GO

PRINT '';
PRINT '=== Verificacion Autorizacion del Pedido (GLUNA) ===';

SELECT a.opcion,
       a.nombre,
       a.mantenimiento,
       p.privilegio,
       p.pagina
  FROM dbo.USERS_OPCION AS a
  JOIN dbo.USERS_OPCION AS b
    ON b.CUSER_ID = 'SIGAMEF'
   AND b.CMENU_ID = 20
   AND a.CMENU_ID = 20
   AND a.TITULO = b.TITULO
   AND a.TITULO_SEC = b.TITULO_SEC
   AND a.OPCION = b.OPCION
  LEFT JOIN dbo.SEG_ROL_PAGINA_PRIVILEGIO AS p
    ON p.ROL = 'GLUNA'
   AND p.SEC_EJEC = 1750
   AND p.PAGINA = b.ORDEN
 WHERE a.CUSER_ID = 'GLUNA'
   AND a.TITULO = '03'
   AND a.TITULO_SEC = '00'
   AND a.OPCION = '04'
 ORDER BY p.privilegio;

PRINT '';
PRINT 'Cierre SIGA (siga.exe) y vuelva a entrar con GLUNA.';
PRINT 'En opcion 04: Tipo = Servicio, Estado = VB Jefe, centro 01.04.02, pedido 001067.';
GO
