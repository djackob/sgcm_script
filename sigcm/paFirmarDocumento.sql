/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paFirmarDocumento
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 2. sigcm.paFirmarDocumento                                                */
/* ========================================================================== */

/*
  Marca como FIRMADA la version vigente del documento.

  Entrada:
  { "Actor": {...}, "IdExpediente": "...", "CodigoTipoDocumento": "...",
    "ArchivoHash": "...",        opcional, huella del PDF firmado
    "GeneradoDocumento": "..."   opcional, si el firmador devuelve otro archivo }

  ---------------------------------------------------------------------------
  AQUI ENTRA EL FIRMADOR
  ---------------------------------------------------------------------------
  Hoy la firma es un asiento: quien tiene el rol autorizado deja constancia de
  que firmo, con fecha y actor. Es lo que hace el mockup, y alcanza para
  recorrer y validar el flujo.

  Cuando se integre el firmador institucional, el cambio queda contenido AQUI:
  el firmador devolvera un PDF con la firma incrustada y su huella, y esta
  rutina recibira GeneradoDocumento y ArchivoHash con esos valores en vez de
  conservar los del borrador. Ninguna otra rutina, ningun endpoint y ninguna
  pantalla cambian, porque todas preguntan por el ESTADO de la version, no por
  como se firmo.

  QUIEN PUEDE FIRMAR
  Lo dice sigcm.TipoDocumentoFirma, que es dato sembrado: AREA_JEFE firma el
  Anexo 3; el Anexo 4 lleva dos firmas, ABAST_JEFE y MAX_AUT_ADMIN. No esta
  cableado aqui.
*/
CREATE   PROCEDURE sigcm.paFirmarDocumento
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

        DECLARE @IdExpediente        uniqueidentifier,
                @CodigoTipoDocumento varchar(60),
                @ArchivoHash         varchar(128),
                @GeneradoDocumento   nvarchar(1000);

        SET @IdExpediente        = sigcm.fnTryGuid(sigcm.fnJsonTexto(@parametro, 'IdExpediente'));
        SET @CodigoTipoDocumento = sigcm.fnJsonTexto(@parametro, 'CodigoTipoDocumento');
        SET @ArchivoHash         = sigcm.fnJsonTexto(@parametro, 'ArchivoHash');
        SET @GeneradoDocumento   = sigcm.fnJsonTexto(@parametro, 'GeneradoDocumento');

        IF @IdExpediente IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta IdExpediente.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@CodigoTipoDocumento)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta CodigoTipoDocumento.', 16, 1);

        DECLARE @CodigoModulo varchar(30) =
            (SELECT CodigoModulo FROM sigcm.Expediente
              WHERE IdExpediente = @IdExpediente AND Anulado = 0 AND Activo = 1);

        IF @CodigoModulo IS NULL
            RAISERROR('NO_ENCONTRADO: el expediente no existe o esta anulado.', 16, 1);

        /* ---- El rol debe estar autorizado a firmar ESTE tipo ----------- */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumentoFirma
                        WHERE CodigoTipoDocumento = @CodigoTipoDocumento
                          AND CodigoRol = @CodigoRol)
        BEGIN
            DECLARE @errRol nvarchar(500);
            SET @errRol = 'NO_AUTORIZADO: el rol ' + ISNULL(@CodigoRol, '')
                + ' no figura entre los firmantes de ' + ISNULL(@CodigoTipoDocumento, '')
                + '. Firman: '
                + ISNULL(STUFF((
                    SELECT ',' + CodigoRol
                      FROM sigcm.TipoDocumentoFirma
                     WHERE CodigoTipoDocumento = @CodigoTipoDocumento
                     ORDER BY OrdenFirma
                       FOR XML PATH(''), TYPE
                  ).value('.', 'nvarchar(max)'), 1, 1, ''), '(ninguno configurado)')
                + '.';
            RAISERROR(@errRol, 16, 1);
        END

        /* ---- Version vigente ------------------------------------------ */
        DECLARE @IdDocumento uniqueidentifier, @Version int, @EstadoVersion varchar(15);

        SELECT @IdDocumento = d.IdDocumento, @Version = d.VersionVigente
          FROM sigcm.Documento AS d
          JOIN sigcm.DocumentoExpediente AS de ON de.IdDocumento = d.IdDocumento
         WHERE de.IdExpediente = @IdExpediente
           AND d.CodigoTipoDocumento = @CodigoTipoDocumento
           AND d.Anulado = 0 AND d.Activo = 1;

        IF @IdDocumento IS NULL
        BEGIN
            DECLARE @errDoc nvarchar(500);
            SET @errDoc = 'NO_ENCONTRADO: el expediente no tiene el documento ' + ISNULL(@CodigoTipoDocumento, '')
                + '. Debe generarse antes de firmarlo.';
            RAISERROR(@errDoc, 16, 1);
        END

        SELECT @EstadoVersion = Estado
          FROM sigcm.DocumentoVersion
         WHERE IdDocumento = @IdDocumento AND Version = @Version;

        IF @EstadoVersion = 'FIRMADO'
            RAISERROR('CONFLICTO_DOCUMENTO: la version vigente del documento ya esta firmada.', 16, 1);

        DECLARE @Ahora datetime = GETDATE();

        UPDATE sigcm.DocumentoVersion
           SET Estado = 'FIRMADO',
               FirmadoEn = @Ahora,
               ArchivoHash = ISNULL(@ArchivoHash, ArchivoHash),
               GeneradoDocumento = ISNULL(@GeneradoDocumento, GeneradoDocumento),
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdDocumento = @IdDocumento AND Version = @Version;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = @CodigoModulo,
             @Entidad = 'sigcm.DocumentoVersion', @IdEntidad = @IdDocumento,
             @Accion = 'FIRMAR_DOCUMENTO', @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta, @ActorRol = @CodigoRol,
             @IdActorUnidad = @IdUnidad, @OrigenIp = @Ip, @Equipo = @Equipo,
             @Programa = @Programa;

        SET @resultado = N'{"estado":1'
            + N',"IdDocumento":' + sigcm.fnJsonValorTexto(CONVERT(varchar(36), @IdDocumento))
            + N',"Version":' + CONVERT(nvarchar(20), @Version)
            + N',"EstadoDocumento":"FIRMADO"'
            + N',"Firmante":' + sigcm.fnJsonValorTexto(@NombreCompleto)
            + N',"RolFirmante":' + sigcm.fnJsonValorTexto(@CodigoRol)
            + N',"FirmadoEn":' + sigcm.fnJsonValorTexto(CONVERT(varchar(19), @Ahora, 126))
            + N',"mensaje":' + sigcm.fnJsonValorTexto(N'Se registro la firma del documento.')
            + N'}';

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N'}';
        SELECT @resultado;
    END CATCH
END
GO
