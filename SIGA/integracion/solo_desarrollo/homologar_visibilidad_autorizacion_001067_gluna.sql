/*
===============================================================================
  SIGA - Homologacion: visibilidad del pedido 001067 en Autorizacion (opcion 04)
  Ambito : [SIGA_1750]  (solo desarrollo / homologacion)

  Causa:
    La opcion 04 lista pedidos cuyo empleado_vb coincide con el empleado
    vinculado al usuario en SIG_PERSONAL (cuser_id).

    - GLUNA  -> empleado 42910131 (registro homologacion)
    - 001067 -> empleado_vb 09946882 (BOJORQUEZ, responsable del centro 01.04.02)

    Por eso la grilla queda vacia aun con Tipo=Servicio y Mes/Estado=Todos.

  Que hace:
    1. Asigna centro 01.04.02 a GLUNA en SIG_USUARIO_CCOSTO (ano 2026).
    2. Alinea empleado_vb del pedido 001067 al empleado de GLUNA.

  Revertir en esta copia local:
    Restaurar empleado_vb = '09946882' en el pedido y quitar la fila de
    SIG_USUARIO_CCOSTO si no corresponde al perfil de prueba.

  Uso:
    sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" -i solo_desarrollo/homologar_visibilidad_autorizacion_001067_gluna.sql
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

DECLARE @Usuario      varchar(30) = 'GLUNA';
DECLARE @SecEjec      decimal(6,0) = 1750;
DECLARE @AnoEje       numeric(4,0) = 2026;
DECLARE @CentroCosto  varchar(15) = '01.04.02';
DECLARE @NroPedido    varchar(6) = '001067';
DECLARE @EmpleadoGluna varchar(15);
DECLARE @EmpleadoVbAnterior varchar(15);

SELECT @EmpleadoGluna = p.empleado
  FROM dbo.SIG_PERSONAL AS p
 WHERE p.sec_ejec = @SecEjec
   AND p.cuser_id = @Usuario;

IF @EmpleadoGluna IS NULL
BEGIN
    RAISERROR('HOMOLOGACION_FALLIDA: %s no tiene empleado en SIG_PERSONAL.', 16, 1, @Usuario);
    RETURN;
END;

SELECT @EmpleadoVbAnterior = p.empleado_vb
  FROM dbo.SIG_PEDIDOS AS p
 WHERE p.ANO_EJE = @AnoEje
   AND p.SEC_EJEC = @SecEjec
   AND p.NRO_PEDIDO = @NroPedido
   AND p.TIPO_PEDIDO = '2'
   AND p.TIPO_BIEN = 'S';

IF @EmpleadoVbAnterior IS NULL
BEGIN
    RAISERROR('HOMOLOGACION_FALLIDA: no existe pedido servicio %s.', 16, 1, @NroPedido);
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
          FROM dbo.SIG_USUARIO_CCOSTO
         WHERE ANO_EJE = @AnoEje
           AND SEC_EJEC = @SecEjec
           AND CUSER_ID = @Usuario
           AND CENTRO_COSTO = @CentroCosto)
    BEGIN
        INSERT INTO dbo.SIG_USUARIO_CCOSTO (ANO_EJE, SEC_EJEC, CUSER_ID, CENTRO_COSTO, ESTADO, FECHA_REG)
        VALUES (@AnoEje, @SecEjec, @Usuario, @CentroCosto, 'A', GETDATE());
    END;

    UPDATE dbo.SIG_PEDIDOS
       SET empleado_vb = @EmpleadoGluna
     WHERE ANO_EJE = @AnoEje
       AND SEC_EJEC = @SecEjec
       AND NRO_PEDIDO = @NroPedido
       AND TIPO_PEDIDO = '2'
       AND TIPO_BIEN = 'S'
       AND ISNULL(empleado_vb, '') <> @EmpleadoGluna;

    COMMIT TRANSACTION;

    PRINT '=== Homologacion aplicada ===';
    PRINT 'GLUNA empleado     : ' + @EmpleadoGluna;
    PRINT 'empleado_vb antes  : ' + ISNULL(@EmpleadoVbAnterior, '(null)');
    PRINT 'empleado_vb ahora  : ' + @EmpleadoGluna;
    PRINT 'Centro asignado    : ' + @CentroCosto;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @err nvarchar(4000) = ERROR_MESSAGE();
    RAISERROR('HOMOLOGACION_FALLIDA: %s', 16, 1, @err);
    RETURN;
END CATCH;
GO

PRINT '';
PRINT 'Cierre SIGA y vuelva a entrar con GLUNA.';
PRINT 'Opcion 04: Ano 2026, Tipo Servicio, centro 01.04.02, pedido 001067.';
GO
