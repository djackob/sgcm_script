/*
===============================================================================
  SIGA - Habilitar Tipo = Servicio en Autorizacion del Pedido para IRIVERA
  Ambito : [SIGA_1750]

  Problema:
    En la opcion 04 (pagina 03020000) el combo Tipo queda fijo en "Bien" y no
    permite elegir "Servicio". IRIVERA tiene nivel 3 en esa pantalla.

  Referencia:
    Los usuarios que autorizan servicios (GGONZALES, RSAAVEDRA, SZUNIGA) tienen
    nivel 2, tanto en USERS_OPCION.MANTENIMIENTO como en
    SEG_ROL_PAGINA_PRIVILEGIO.PRIVILEGIO.

  Que hace:
    Baja IRIVERA de nivel 3 a nivel 2 en la pagina 03020000 unicamente.
    No toca el resto de su menu ni sus otras paginas.

  Revertir:
    UPDATE dbo.USERS_OPCION SET MANTENIMIENTO='3'
     WHERE CUSER_ID='IRIVERA' AND CMENU_ID='20' AND TITULO='03'
       AND TITULO_SEC='00' AND OPCION='04' AND SEC_EJEC=1750;
    UPDATE dbo.SEG_ROL_PAGINA_PRIVILEGIO SET PRIVILEGIO=3
     WHERE ROL='IRIVERA' AND PAGINA='03020000' AND SEC_EJEC=1750;

  Uso:
    sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" -i solo_desarrollo/habilitar_tipo_servicio_irivera_autorizacion.sql
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

DECLARE @Usuario    varchar(30) = 'IRIVERA';
DECLARE @SecEjec    decimal(6,0) = 1750;
DECLARE @PaginaAuth varchar(8) = '03020000';
DECLARE @OpcionAuth varchar(2) = '04';
DECLARE @NivelServicio varchar(1) = '2';

DECLARE @MantAntes varchar(1);
DECLARE @PrivAntes numeric(38, 0);

SELECT @MantAntes = MANTENIMIENTO
  FROM dbo.USERS_OPCION
 WHERE CUSER_ID = @Usuario
   AND CMENU_ID = '20'
   AND TITULO = '03'
   AND TITULO_SEC = '00'
   AND OPCION = @OpcionAuth
   AND SEC_EJEC = @SecEjec;

SELECT @PrivAntes = PRIVILEGIO
  FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO
 WHERE ROL = @Usuario
   AND PAGINA = @PaginaAuth
   AND SEC_EJEC = @SecEjec;

IF @MantAntes IS NULL
BEGIN
    RAISERROR('TIPO_SERVICIO_FALLIDO: %s no tiene la opcion 04 en USERS_OPCION.', 16, 1, @Usuario);
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE dbo.USERS_OPCION
       SET MANTENIMIENTO = @NivelServicio
     WHERE CUSER_ID = @Usuario
       AND CMENU_ID = '20'
       AND TITULO = '03'
       AND TITULO_SEC = '00'
       AND OPCION = @OpcionAuth
       AND SEC_EJEC = @SecEjec;

    UPDATE dbo.SEG_ROL_PAGINA_PRIVILEGIO
       SET PRIVILEGIO = CONVERT(numeric(38, 0), @NivelServicio)
     WHERE ROL = @Usuario
       AND PAGINA = @PaginaAuth
       AND SEC_EJEC = @SecEjec;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.SEG_ROL_PAGINA_PRIVILEGIO (PRIVILEGIO, ROL, PAGINA, SEC_EJEC)
        VALUES (CONVERT(numeric(38, 0), @NivelServicio), @Usuario, @PaginaAuth, @SecEjec);
    END;

    COMMIT TRANSACTION;

    PRINT '=== Tipo Servicio habilitado para IRIVERA en opcion 04 ===';
    PRINT 'MANTENIMIENTO antes : ' + @MantAntes;
    PRINT 'PRIVILEGIO antes    : ' + ISNULL(CONVERT(varchar(10), @PrivAntes), '(sin fila)');
    PRINT 'Nivel aplicado      : ' + @NivelServicio;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @err nvarchar(4000) = ERROR_MESSAGE();
    RAISERROR('TIPO_SERVICIO_FALLIDO: %s', 16, 1, @err);
    RETURN;
END CATCH;
GO

PRINT '';
PRINT '=== Verificacion ===';

SELECT o.CUSER_ID, o.OPCION, o.MANTENIMIENTO, p.PRIVILEGIO, p.PAGINA
  FROM dbo.USERS_OPCION AS o
  LEFT JOIN dbo.SEG_ROL_PAGINA_PRIVILEGIO AS p
    ON p.ROL = o.CUSER_ID
   AND p.SEC_EJEC = o.SEC_EJEC
   AND p.PAGINA = '03020000'
 WHERE o.CUSER_ID IN ('IRIVERA', 'GGONZALES', 'GLUNA')
   AND o.CMENU_ID = '20'
   AND o.TITULO = '03'
   AND o.OPCION = '04'
   AND o.SEC_EJEC = 1750
 ORDER BY o.CUSER_ID;

PRINT '';
PRINT 'Cierre SIGA por completo y entre de nuevo con IRIVERA.';
PRINT 'Opcion 04: Ano 2026, Tipo Servicio, Mes 01 Enero, centro 01.04.02.';
GO
