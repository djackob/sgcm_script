/*
===============================================================================
  SIGCM - F021 : Estado de la CCP en el SIAF web
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: V031 (siga.vwCertificacionSiaf)
  Bloque de errores: 52110-52119

  Entrada: { "NumeroCcp":"05619", "AnoEje":2026, "SecEjec":1750 }
  AnoEje y SecEjec son opcionales. Sin año se toma el más reciente.
  NumeroCcp es el CERTIFICADO N.° del SIAF web, no el certificado SIGA.

  Salida: Estado = "A" y NombreEstado = "Aprobado" cuando la grilla del
  SIAF web muestra la letra A.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE requerimiento.paConsultarEstadoCcp
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52110, 'JSON incorrecto.', 1;

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

        DECLARE @NumeroCcp varchar(20), @AnoEje smallint, @SecEjec int;

        SELECT @NumeroCcp = NULLIF(LTRIM(RTRIM(NumeroCcp)), ''),
               @AnoEje    = AnoEje,
               @SecEjec   = SecEjec
          FROM OPENJSON(@parametro)
          WITH (
              NumeroCcp varchar(20),
              AnoEje    smallint,
              SecEjec   int
          );

        DECLARE @Numero numeric(10, 0) = TRY_CONVERT(numeric(10, 0), @NumeroCcp);
        IF @Numero IS NULL OR @Numero <= 0
            THROW 52111, 'VALIDACION_CCP: indique el numero de certificacion (CCP) del SIAF.', 1;

        DECLARE @Ano smallint, @Sec int, @CertificaSiga bigint, @Fecha date,
                @Codigo varchar(1), @Anulado char(1), @Letra char(1), @Nombre varchar(40);

        SELECT TOP (1)
               @Ano = v.AnoEje,
               @Sec = v.SecEjec,
               @CertificaSiga = v.NumeroCertificaSiga,
               @Fecha = v.Fecha,
               @Codigo = v.CodigoInterfase,
               @Anulado = v.AnuladoSiga,
               @Letra = v.Estado,
               @Nombre = v.NombreEstado
          FROM siga.vwCertificacionSiaf AS v
         WHERE v.NumeroCcp = @Numero
           AND (@AnoEje IS NULL OR v.AnoEje = @AnoEje)
           AND (@SecEjec IS NULL OR v.SecEjec = @SecEjec)
         ORDER BY v.AnoEje DESC, v.NumeroCertificaSiga DESC;

        IF @Ano IS NULL
        BEGIN
            SELECT (
                SELECT 0 AS estado,
                       N'No hay una CCP ' + @NumeroCcp + N' con respuesta del SIAF en SIGA.' AS mensaje
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            RETURN;
        END

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @Numero AS NumeroCcp,
                   @Ano AS AnoEje,
                   @Sec AS SecEjec,
                   @CertificaSiga AS NumeroCertificaSiga,
                   CONVERT(char(10), @Fecha, 23) AS Fecha,
                   @Letra AS Estado,
                   @Nombre AS NombreEstado,
                   @Codigo AS CodigoInterfase,
                   @Anulado AS AnuladoSiga,
                   N'La CCP ' + CONVERT(varchar(20), @Numero)
                       + N' está en estado ' + ISNULL(@Letra, N'-')
                       + N' (' + @Nombre + N').' AS mensaje
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

PRINT 'F021 aplicada: requerimiento.paConsultarEstadoCcp.';
GO
