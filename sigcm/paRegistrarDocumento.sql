/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paRegistrarDocumento
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 1. sigcm.paRegistrarDocumento                                             */
/* ========================================================================== */

/*
  Registra el documento generado por el frontend y lo vincula al expediente.

  Entrada:
  {
    "Actor": { ... },
    "IdExpediente": "...",
    "CodigoTipoDocumento": "CMN_ANEXO_3_SOLICITUD_MODIFICACION",
    "GeneradoDocumento": "http://.../files/cmn/2026....pdf",
    "NombreDocumento": "Anexo 3 - CMN-2026-000002.pdf",
    "ArchivoHash": "...",            opcional
    "Payload": { ... },              opcional, los datos con que se armo
    "MotivoVersion": "..."           opcional
  }

  COMPORTAMIENTO SEGUN LO QUE YA EXISTA
  - No hay documento          -> se crea con la version 1 en BORRADOR.
  - La version vigente esta en BORRADOR -> se REEMPLAZA. Regenerar un borrador
    no es una version nueva: es el mismo borrador otra vez, y numerarlo llenaria
    el historial de ruido.
  - La version vigente esta FIRMADA -> se crea una version NUEVA en BORRADOR y
    la anterior queda ANULADA. Es la invalidacion de firma de CMN-18.
*/
CREATE   PROCEDURE sigcm.paRegistrarDocumento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF sigcm.fnEsJson(@parametro) <> 1
            RAISERROR('JSON incorrecto.', 16, 1);

        /* ---- Actor ---------------------------------------------------- */
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

        /* ---- Payload -------------------------------------------------- */
        DECLARE @IdExpediente        uniqueidentifier,
                @CodigoTipoDocumento varchar(60),
                @GeneradoDocumento   nvarchar(1000),
                @NombreDocumento     nvarchar(1000),
                @ArchivoHash         varchar(128),
                @Payload             nvarchar(max),
                @MotivoVersion       nvarchar(max);

        SET @IdExpediente        = sigcm.fnTryGuid(sigcm.fnJsonTexto(@parametro, 'IdExpediente'));
        SET @CodigoTipoDocumento = sigcm.fnJsonTexto(@parametro, 'CodigoTipoDocumento');
        SET @GeneradoDocumento   = sigcm.fnJsonTexto(@parametro, 'GeneradoDocumento');
        SET @NombreDocumento     = sigcm.fnJsonTexto(@parametro, 'NombreDocumento');
        SET @ArchivoHash         = sigcm.fnJsonTexto(@parametro, 'ArchivoHash');
        SET @Payload             = sigcm.fnJsonTexto(@parametro, 'Payload');
        SET @MotivoVersion       = sigcm.fnJsonTexto(@parametro, 'MotivoVersion');

        IF @IdExpediente IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta IdExpediente o no es un identificador valido.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@CodigoTipoDocumento)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta CodigoTipoDocumento.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@GeneradoDocumento)), '') IS NULL
            RAISERROR('VALIDACION_ARCHIVO: falta GeneradoDocumento. El PDF debe subirse al file server antes de registrarlo.', 16, 1);

        IF sigcm.fnEsJson(ISNULL(@Payload, N'{}')) <> 1 SET @Payload = N'{}';
        SET @Payload = ISNULL(@Payload, N'{}');

        /* ---- Expediente y tipo ---------------------------------------- */
        DECLARE @CodigoModulo varchar(30), @CodigoExpediente varchar(40), @AnoEje smallint;

        SELECT @CodigoModulo = CodigoModulo, @CodigoExpediente = Codigo, @AnoEje = AnoEje
          FROM sigcm.Expediente
         WHERE IdExpediente = @IdExpediente AND Anulado = 0 AND Activo = 1;

        IF @CodigoModulo IS NULL
            RAISERROR('NO_ENCONTRADO: el expediente no existe o esta anulado.', 16, 1);

        /* El tipo de documento debe pertenecer al modulo del expediente: sin
           esto se podria colgar un Anexo 4 de CMN a un requerimiento. */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento
                        WHERE CodigoTipoDocumento = @CodigoTipoDocumento
                          AND CodigoModulo = @CodigoModulo AND Activo = 1)
        BEGIN
            DECLARE @errTipo nvarchar(400);
            SET @errTipo = 'VALIDACION_TIPO_DOCUMENTO: ' + ISNULL(@CodigoTipoDocumento, '')
                + ' no es un documento del modulo ' + ISNULL(@CodigoModulo, '') + '.';
            RAISERROR(@errTipo, 16, 1);
        END

        /* ---- Documento existente -------------------------------------- */
        DECLARE @IdDocumento uniqueidentifier, @VersionVigente int, @EstadoVigente varchar(15);

        SELECT @IdDocumento   = d.IdDocumento,
               @VersionVigente = d.VersionVigente
          FROM sigcm.Documento AS d
          JOIN sigcm.DocumentoExpediente AS de ON de.IdDocumento = d.IdDocumento
         WHERE de.IdExpediente = @IdExpediente
           AND d.CodigoTipoDocumento = @CodigoTipoDocumento
           AND d.Anulado = 0 AND d.Activo = 1;

        IF @IdDocumento IS NOT NULL
            SELECT @EstadoVigente = Estado
              FROM sigcm.DocumentoVersion
             WHERE IdDocumento = @IdDocumento AND Version = @VersionVigente;

        DECLARE @Ahora datetime = GETDATE();
        DECLARE @VersionNueva int;
        DECLARE @FirmaInvalidada bit = 0;

        BEGIN TRANSACTION;

        IF @IdDocumento IS NULL
        BEGIN
            /* Numeracion visible del documento: el codigo del expediente basta
               para identificarlo y evita una secuencia por tipo. */
            DECLARE @Numero varchar(80);
            SET @Numero = ISNULL(@CodigoExpediente, '') + '-'
                + ISNULL((SELECT NumeracionVisible FROM sigcm.TipoDocumento
                           WHERE CodigoTipoDocumento = @CodigoTipoDocumento), '');

            INSERT INTO sigcm.Documento
                (CodigoTipoDocumento, Numero, Consolidado, VersionVigente,
                 UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                 EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@CodigoTipoDocumento, @Numero, 0, 1,
                 @Cuenta, @Ahora, @Equipo, @Programa);

            SELECT @IdDocumento = IdDocumento FROM sigcm.Documento WHERE Numero = @Numero;

            INSERT INTO sigcm.DocumentoExpediente (IdDocumento, IdExpediente)
            VALUES (@IdDocumento, @IdExpediente);

            SET @VersionNueva = 1;
        END
        ELSE IF @EstadoVigente = 'BORRADOR'
        BEGIN
            /* Se reemplaza el borrador en su sitio. */
            SET @VersionNueva = @VersionVigente;

            UPDATE sigcm.DocumentoVersion
               SET Payload = @Payload,
                   GeneradoDocumento = @GeneradoDocumento,
                   NombreDocumento = @NombreDocumento,
                   ArchivoHash = @ArchivoHash,
                   MotivoVersion = @MotivoVersion,
                   UsuarioModificacionAuditoria = @Cuenta,
                   FechaModificacionAuditoria = @Ahora,
                   EquipoModificacionAuditoria = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdDocumento = @IdDocumento AND Version = @VersionVigente;
        END
        ELSE
        BEGIN
            /* Estaba FIRMADO: nace una version nueva y la firma anterior cae. */
            SET @VersionNueva = @VersionVigente + 1;
            SET @FirmaInvalidada = 1;

            UPDATE sigcm.DocumentoVersion
               SET Estado = 'ANULADA',
                   UsuarioModificacionAuditoria = @Cuenta,
                   FechaModificacionAuditoria = @Ahora,
                   EquipoModificacionAuditoria = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdDocumento = @IdDocumento AND Version = @VersionVigente;

            UPDATE sigcm.Documento
               SET VersionVigente = @VersionNueva,
                   UsuarioModificacionAuditoria = @Cuenta,
                   FechaModificacionAuditoria = @Ahora,
                   EquipoModificacionAuditoria = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdDocumento = @IdDocumento;
        END

        /* La version 1 y las nuevas se insertan; el borrador reemplazado no. */
        IF NOT EXISTS (SELECT 1 FROM sigcm.DocumentoVersion
                        WHERE IdDocumento = @IdDocumento AND Version = @VersionNueva)
            INSERT INTO sigcm.DocumentoVersion
                (IdDocumento, Version, Estado, Payload, GeneradoDocumento,
                 NombreDocumento, ArchivoHash, MotivoVersion,
                 UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                 EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdDocumento, @VersionNueva, 'BORRADOR', @Payload, @GeneradoDocumento,
                 @NombreDocumento, @ArchivoHash, @MotivoVersion,
                 @Cuenta, @Ahora, @Equipo, @Programa);

        COMMIT TRANSACTION;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = @CodigoModulo,
             @Entidad = 'sigcm.Documento', @IdEntidad = @IdDocumento,
             @Accion = 'REGISTRAR_DOCUMENTO', @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta, @ActorRol = @CodigoRol,
             @IdActorUnidad = @IdUnidad, @OrigenIp = @Ip, @Equipo = @Equipo,
             @Programa = @Programa;

        SET @resultado = N'{"estado":1'
            + N',"IdDocumento":' + sigcm.fnJsonValorTexto(CONVERT(varchar(36), @IdDocumento))
            + N',"Version":' + CONVERT(nvarchar(20), @VersionNueva)
            + N',"EstadoDocumento":"BORRADOR"'
            + N',"FirmaInvalidada":' + CASE WHEN @FirmaInvalidada = 1 THEN N'true' ELSE N'false' END
            + N',"mensaje":' + sigcm.fnJsonValorTexto(
                CASE WHEN @FirmaInvalidada = 1
                     THEN N'Se registro el documento. La firma anterior quedo invalidada y debe firmarse nuevamente.'
                     ELSE N'Se registro el documento satisfactoriamente.' END)
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
