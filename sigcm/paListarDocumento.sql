/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paListarDocumento
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 3. sigcm.paListarDocumento                                                */
/* ========================================================================== */

/*
  Documentos de un expediente con su version vigente. Es lo que la pantalla
  necesita para saber si hay que generar, si se puede firmar y con que URL se
  abre el PDF.

  Entrada: { "Actor": {...}, "IdExpediente": "..." }
*/
CREATE   PROCEDURE sigcm.paListarDocumento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF sigcm.fnEsJson(@parametro) <> 1
            RAISERROR('JSON incorrecto.', 16, 1);

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

        DECLARE @IdExpediente uniqueidentifier =
            sigcm.fnTryGuid(sigcm.fnJsonTexto(@parametro, 'IdExpediente'));

        IF @IdExpediente IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta IdExpediente.', 16, 1);

        DECLARE @Documentos nvarchar(max);
        SET @Documentos = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"IdDocumento":' + sigcm.fnJsonValorTexto(CONVERT(varchar(36), d.IdDocumento))
                + N',"CodigoTipoDocumento":' + sigcm.fnJsonValorTexto(d.CodigoTipoDocumento)
                + N',"Numero":' + sigcm.fnJsonValorTexto(d.Numero)
                + N',"TipoDocumento":' + sigcm.fnJsonValorTexto(td.Nombre)
                + N',"Version":' + CONVERT(nvarchar(20), dv.Version)
                + N',"Estado":' + sigcm.fnJsonValorTexto(dv.Estado)
                + N',"GeneradoDocumento":' + sigcm.fnJsonValorTexto(dv.GeneradoDocumento)
                + N',"NombreDocumento":' + sigcm.fnJsonValorTexto(dv.NombreDocumento)
                + N',"FirmadoEn":' + CASE WHEN dv.FirmadoEn IS NULL THEN N'null'
                                          ELSE N'"' + CONVERT(varchar(23), dv.FirmadoEn, 126) + N'"' END
                + N',"PuedeFirmarEsteRol":' + CASE WHEN EXISTS (
                      SELECT 1 FROM sigcm.TipoDocumentoFirma AS f
                       WHERE f.CodigoTipoDocumento = d.CodigoTipoDocumento
                         AND f.CodigoRol = @CodigoRol) THEN N'true' ELSE N'false' END
                + N'}'
              FROM sigcm.Documento AS d
              JOIN sigcm.DocumentoExpediente AS de ON de.IdDocumento = d.IdDocumento
              JOIN sigcm.TipoDocumento AS td ON td.CodigoTipoDocumento = d.CodigoTipoDocumento
              JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumento = d.IdDocumento
                                               AND dv.Version = d.VersionVigente
             WHERE de.IdExpediente = @IdExpediente
               AND d.Anulado = 0 AND d.Activo = 1
             ORDER BY d.CodigoTipoDocumento
               FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SET @resultado = N'{"estado":1,"mensaje":"OK","Documentos":' + @Documentos + N'}';

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N',"Documentos":[]}';
        SELECT @resultado;
    END CATCH
END
GO
