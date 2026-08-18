/*
===============================================================================
  SIGCM - F003 : Documentos, firmas e invalidacion por version
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51600-51699

  QUE RESUELVE
  ------------
  Es la pieza que faltaba para que el flujo pase de "Por firmar Anexo 3". El
  motor de transiciones (F004) exige, para las acciones marcadas con
  DocumentoRequerido, que el documento exista en su version vigente y FIRMADO.
  Sin estas rutinas no habia forma de crear ese documento ni de firmarlo, y el
  unico que existia en la base se habia insertado a mano.

  Sirve a los dos modulos: el Anexo 3 y el Anexo 4 de CMN, y las EETT, TDR y
  anexos de Requerimiento. El tipo de documento es un dato de
  sigcm.TipoDocumento, no una rama de codigo.

  ---------------------------------------------------------------------------
  DONDE SE GENERA EL PDF
  ---------------------------------------------------------------------------
  En el frontend. Aqui NO se arma el archivo: se recibe ya subido al file
  server y se registra su URL. La base guarda tres cosas distintas:

      Payload            los datos con los que se armo, en JSON. Es lo que
                         permite reimprimir o comparar versiones.
      GeneradoDocumento  la URL del PDF en el file server.
      ArchivoHash        la huella del archivo, para detectar que el PDF que
                         hoy responde esa URL sigue siendo el que se firmo.

  ---------------------------------------------------------------------------
  LA REGLA QUE JUSTIFICA EL VERSIONADO
  ---------------------------------------------------------------------------
  CMN-18 y REQ-29 del analisis: si se actualiza un documento ya firmado, la
  firma anterior se invalida y hay que firmar de nuevo. Por eso el documento
  tiene versiones y no un solo registro que se sobrescribe: la version firmada
  se conserva, y la correccion nace como version nueva en BORRADOR. Sin esto,
  un expediente podria enviarse con una firma que ya no corresponde al contenido.

  Estados de una version:  BORRADOR -> FIRMADO -> ANULADA
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
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
CREATE OR ALTER PROCEDURE sigcm.paRegistrarDocumento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51600, 'JSON incorrecto.', 1;

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

        SELECT @IdExpediente        = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @CodigoTipoDocumento = CodigoTipoDocumento,
               @GeneradoDocumento   = GeneradoDocumento,
               @NombreDocumento     = NombreDocumento,
               @ArchivoHash         = ArchivoHash,
               @Payload             = Payload,
               @MotivoVersion       = MotivoVersion
        FROM OPENJSON(@parametro)
        WITH (
            IdExpediente        varchar(50),
            CodigoTipoDocumento varchar(60),
            GeneradoDocumento   nvarchar(1000),
            NombreDocumento     nvarchar(1000),
            ArchivoHash         varchar(128),
            Payload             nvarchar(max) AS JSON,
            MotivoVersion       nvarchar(max)
        );

        IF @IdExpediente IS NULL
            THROW 51601, 'VALIDACION_PAYLOAD: falta IdExpediente o no es un identificador valido.', 1;
        IF NULLIF(LTRIM(RTRIM(@CodigoTipoDocumento)), '') IS NULL
            THROW 51602, 'VALIDACION_PAYLOAD: falta CodigoTipoDocumento.', 1;
        IF NULLIF(LTRIM(RTRIM(@GeneradoDocumento)), '') IS NULL
            THROW 51603, 'VALIDACION_ARCHIVO: falta GeneradoDocumento. El PDF debe subirse al file server antes de registrarlo.', 1;

        IF ISJSON(ISNULL(@Payload, N'{}')) <> 1 SET @Payload = N'{}';
        SET @Payload = ISNULL(@Payload, N'{}');

        /* ---- Expediente y tipo ---------------------------------------- */
        DECLARE @CodigoModulo varchar(30), @CodigoExpediente varchar(40), @AnoEje smallint;

        SELECT @CodigoModulo = CodigoModulo, @CodigoExpediente = Codigo, @AnoEje = AnoEje
          FROM sigcm.Expediente
         WHERE IdExpediente = @IdExpediente AND Anulado = 0 AND Activo = 1;

        IF @CodigoModulo IS NULL
            THROW 51604, 'NO_ENCONTRADO: el expediente no existe o esta anulado.', 1;

        /* El tipo de documento debe pertenecer al modulo del expediente: sin
           esto se podria colgar un Anexo 4 de CMN a un requerimiento. */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento
                        WHERE CodigoTipoDocumento = @CodigoTipoDocumento
                          AND CodigoModulo = @CodigoModulo AND Activo = 1)
        BEGIN
            DECLARE @errTipo nvarchar(400) = CONCAT(
                'VALIDACION_TIPO_DOCUMENTO: ', @CodigoTipoDocumento,
                ' no es un documento del modulo ', @CodigoModulo, '.');
            THROW 51605, @errTipo, 1;
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
            DECLARE @Numero varchar(80) = CONCAT(@CodigoExpediente, '-',
                (SELECT NumeracionVisible FROM sigcm.TipoDocumento
                  WHERE CodigoTipoDocumento = @CodigoTipoDocumento));

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

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdDocumento     AS IdDocumento,
                   @VersionNueva    AS Version,
                   'BORRADOR'       AS EstadoDocumento,
                   @FirmaInvalidada AS FirmaInvalidada,
                   CASE WHEN @FirmaInvalidada = 1
                        THEN N'Se registro el documento. La firma anterior quedo invalidada y debe firmarse nuevamente.'
                        ELSE N'Se registro el documento satisfactoriamente.' END AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
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
CREATE OR ALTER PROCEDURE sigcm.paFirmarDocumento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51610, 'JSON incorrecto.', 1;

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

        SELECT @IdExpediente        = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @CodigoTipoDocumento = CodigoTipoDocumento,
               @ArchivoHash         = ArchivoHash,
               @GeneradoDocumento   = GeneradoDocumento
        FROM OPENJSON(@parametro)
        WITH (
            IdExpediente        varchar(50),
            CodigoTipoDocumento varchar(60),
            ArchivoHash         varchar(128),
            GeneradoDocumento   nvarchar(1000)
        );

        IF @IdExpediente IS NULL
            THROW 51611, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF NULLIF(LTRIM(RTRIM(@CodigoTipoDocumento)), '') IS NULL
            THROW 51612, 'VALIDACION_PAYLOAD: falta CodigoTipoDocumento.', 1;

        DECLARE @CodigoModulo varchar(30) =
            (SELECT CodigoModulo FROM sigcm.Expediente
              WHERE IdExpediente = @IdExpediente AND Anulado = 0 AND Activo = 1);

        IF @CodigoModulo IS NULL
            THROW 51613, 'NO_ENCONTRADO: el expediente no existe o esta anulado.', 1;

        /* ---- El rol debe estar autorizado a firmar ESTE tipo ----------- */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumentoFirma
                        WHERE CodigoTipoDocumento = @CodigoTipoDocumento
                          AND CodigoRol = @CodigoRol)
        BEGIN
            DECLARE @errRol nvarchar(500) = CONCAT(
                'NO_AUTORIZADO: el rol ', @CodigoRol, ' no figura entre los firmantes de ',
                @CodigoTipoDocumento, '. Firman: ',
                ISNULL((SELECT STRING_AGG(CodigoRol, ', ') WITHIN GROUP (ORDER BY OrdenFirma)
                          FROM sigcm.TipoDocumentoFirma
                         WHERE CodigoTipoDocumento = @CodigoTipoDocumento), '(ninguno configurado)'), '.');
            THROW 51614, @errRol, 1;
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
            DECLARE @errDoc nvarchar(500) = CONCAT(
                'NO_ENCONTRADO: el expediente no tiene el documento ', @CodigoTipoDocumento,
                '. Debe generarse antes de firmarlo.');
            THROW 51615, @errDoc, 1;
        END

        SELECT @EstadoVersion = Estado
          FROM sigcm.DocumentoVersion
         WHERE IdDocumento = @IdDocumento AND Version = @Version;

        IF @EstadoVersion = 'FIRMADO'
            THROW 51616, 'CONFLICTO_DOCUMENTO: la version vigente del documento ya esta firmada.', 1;

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

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdDocumento AS IdDocumento,
                   @Version     AS Version,
                   'FIRMADO'    AS EstadoDocumento,
                   @NombreCompleto AS Firmante,
                   @CodigoRol   AS RolFirmante,
                   CONVERT(varchar(19), @Ahora, 126) AS FirmadoEn,
                   N'Se registro la firma del documento.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
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
CREATE OR ALTER PROCEDURE sigcm.paListarDocumento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51620, 'JSON incorrecto.', 1;

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
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));

        IF @IdExpediente IS NULL
            THROW 51621, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   'OK' AS mensaje,
                   Documentos = JSON_QUERY(COALESCE((
                       SELECT d.IdDocumento, d.CodigoTipoDocumento, d.Numero,
                              TipoDocumento = td.Nombre,
                              dv.Version, dv.Estado,
                              dv.GeneradoDocumento, dv.NombreDocumento,
                              dv.FirmadoEn,
                              /* Para que la pantalla sepa si ofrecer el boton de
                                 firmar a QUIEN esta mirando. */
                              PuedeFirmarEsteRol = CONVERT(bit, CASE WHEN EXISTS (
                                  SELECT 1 FROM sigcm.TipoDocumentoFirma AS f
                                   WHERE f.CodigoTipoDocumento = d.CodigoTipoDocumento
                                     AND f.CodigoRol = @CodigoRol) THEN 1 ELSE 0 END)
                         FROM sigcm.Documento AS d
                         JOIN sigcm.DocumentoExpediente AS de ON de.IdDocumento = d.IdDocumento
                         JOIN sigcm.TipoDocumento AS td ON td.CodigoTipoDocumento = d.CodigoTipoDocumento
                         JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumento = d.IdDocumento
                                                          AND dv.Version = d.VersionVigente
                        WHERE de.IdExpediente = @IdExpediente
                          AND d.Anulado = 0 AND d.Activo = 1
                        ORDER BY d.CodigoTipoDocumento
                          FOR JSON PATH), '[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo,
                   JSON_QUERY('[]') AS Documentos
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

PRINT 'F003 aplicada: documentos, firmas e invalidacion por version.';
GO
