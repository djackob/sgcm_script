/*
===============================================================================
  SIGA - Ajuste perfil logistica HBOJORQUEZ (homologacion)
  Ambito : [SIGA_1750]

  Alinea flag_ccosto=S como usuarios de logistica (GGONZALES, IRIVERA) para
  que la opcion 04 liste pedidos de servicio por centro.

  Uso:
    sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" -i solo_desarrollo/ajustar_perfil_hbojorquez_logistica.sql
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

DECLARE @Usuario varchar(30) = 'HBOJORQUEZ';
DECLARE @SecEjec decimal(6,0) = 1750;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE dbo.SIG_USUARIO_EJECUTORA
       SET flag_ccosto = 'S',
           estado = 'A'
     WHERE CUSER_ID = @Usuario
       AND sec_ejec = @SecEjec;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.SIG_USUARIO_EJECUTORA (CUSER_ID, sec_ejec, flag_ccosto, estado, fecha_reg)
        VALUES (@Usuario, @SecEjec, 'S', 'A', GETDATE());
    END;

    UPDATE dbo.USERS_OPCION
       SET ORDEN = '03010200'
     WHERE CUSER_ID = @Usuario
       AND CMENU_ID = '20'
       AND TITULO = '03'
       AND OPCION = '03'
       AND SEC_EJEC = @SecEjec
       AND (ORDEN IS NULL OR ORDEN = '');

    COMMIT TRANSACTION;

    PRINT '=== Perfil HBOJORQUEZ ajustado ===';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

SELECT CUSER_ID, sec_ejec, flag_ccosto, estado FROM dbo.SIG_USUARIO_EJECUTORA WHERE CUSER_ID = 'HBOJORQUEZ';
GO
