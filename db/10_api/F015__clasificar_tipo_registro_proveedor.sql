/*
===============================================================================
  SIGCM - F015 : Clasificar Tipo de Registro del proveedor (NUEVO / EXISTENTE)
  Motor  : SQL Server 2022
  Ambito : [DBSIGCM]
  Lectura : SIGA_1750.dbo.SIG_CONTRATISTAS (via sinonimo siga.SIG_CONTRATISTAS)

  El combo Tipo Registro del formulario de requerimiento no se elige a mano:
  al buscar DNI o RUC se pregunta a SIGA si ese documento ya tiene fila. Si hay
  algun registro -> EXISTENTE; si no hay ninguno -> NUEVO.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE requerimiento.paClasificarTipoRegistroProveedor
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51890, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120),
                @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier,
                @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50),
                @CorrelacionId uniqueidentifier;

        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @Ruc varchar(11) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Ruc'))), '');
        DECLARE @Dni varchar(20) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Dni'))), '');

        IF @Ruc IS NOT NULL
            SET @Ruc = LEFT(REPLACE(@Ruc, ' ', ''), 11);
        IF @Dni IS NOT NULL
            SET @Dni = LEFT(REPLACE(@Dni, ' ', ''), 20);

        IF @Ruc IS NULL AND @Dni IS NULL
            THROW 51891, 'VALIDACION_PAYLOAD: indique RUC o DNI.', 1;

        DECLARE @Existe bit = 0;
        DECLARE @Origen varchar(40) = NULL;
        DECLARE @HayContratistas bit = CASE
            WHEN OBJECT_ID(N'siga.SIG_CONTRATISTAS', N'U') IS NOT NULL THEN 1
            WHEN OBJECT_ID(N'siga.SIG_CONTRATISTAS', N'SN') IS NOT NULL THEN 1
            ELSE 0 END;

        IF @HayContratistas = 1
        BEGIN
            IF @Ruc IS NOT NULL AND EXISTS (
                SELECT 1
                  FROM siga.SIG_CONTRATISTAS AS c WITH (NOLOCK)
                 WHERE REPLACE(LTRIM(RTRIM(ISNULL(c.NRO_RUC, ''))), ' ', '')
                       COLLATE DATABASE_DEFAULT = @Ruc)
            BEGIN
                SET @Existe = 1;
                SET @Origen = 'SIG_CONTRATISTAS.NRO_RUC';
            END
            ELSE IF @Dni IS NOT NULL AND EXISTS (
                SELECT 1
                  FROM siga.SIG_CONTRATISTAS AS c WITH (NOLOCK)
                 WHERE REPLACE(LTRIM(RTRIM(ISNULL(c.NUM_DOC, ''))), ' ', '')
                       COLLATE DATABASE_DEFAULT = @Dni
                    OR REPLACE(LTRIM(RTRIM(ISNULL(c.DOC_IDENTIDAD, ''))), ' ', '')
                       COLLATE DATABASE_DEFAULT = @Dni)
            BEGIN
                SET @Existe = 1;
                SET @Origen = 'SIG_CONTRATISTAS.DOC';
            END
        END

        SELECT @resultado = (
            SELECT 1 AS estado,
                   TipoRegistro = CASE WHEN @Existe = 1 THEN 'EXISTENTE' ELSE 'NUEVO' END,
                   ExisteHistorial = @Existe,
                   Origen = @Origen,
                   N'Seleccion automatica de Tipo de Registro.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F015 aplicada: clasificacion TipoRegistro NUEVO/EXISTENTE contra SIGA.';
GO
