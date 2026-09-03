/*
===============================================================================
  SIGCM - F013 : Aviso al area usuaria de que su modificacion del CMN se hizo
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: V028 (cmn.NotificacionAnexo4)

  DE DONDE SALE ESTO
  Al firmar el Jefe de Abastecimiento el Anexo 4, W001 aprueba en SIGA la
  solicitud de modificacion -SIG_SOLICITUD_MODIFICACION pasa a ESTADO '3' y el
  item vuelve a MOTIVO_SOLICITUD '0', o sea queda pedible- y el expediente
  regresa al area usuaria: CMN_A4_ENVIADO tiene como responsable a AREA_JEFE y
  el enrutamiento de F004 lo devuelve a la unidad de origen.

  La derivacion, entonces, ya existia. Lo que faltaba era avisar. El area
  usuaria no vive dentro del sistema y su bandeja esta quieta la mayor parte del
  tiempo: sin correo, la aprobacion que habilita su pedido en SIGA se entera
  cuando alguien entra a mirar.

  POR QUE UN SOBRE Y NO UN ENVIO
  Igual que F011 con el locador: SMTP no corre en SQL Server. Esta rutina arma
  el sobre -a quien, con que asunto y con que cuerpo-, el backend lo envia con
  UT_Correo adjuntando el PDF del Anexo 4, y vuelve con el resultado a
  cmn.paMarcarAnexo4Notificado. Si el correo falla, el expediente NO se bloquea:
  ya esta en la bandeja del area usuaria y la aprobacion en SIGA ya ocurrio. La
  constancia queda con CorreoEnviado = 0 y se puede reintentar.

  UNO POR AREA USUARIA
  Un Anexo 4 agrupa los Anexos 3 de varias areas. El sobre se arma por
  SOLICITUD, no por paquete: cada area usuaria recibe el suyo, con su propio
  codigo de expediente. La pantalla llama una vez por cada solicitud del lote
  que acaba de moverse.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ========================================================================== */
/* 1. cmn.paPrepararNotificacionAnexo4                                       */
/* ========================================================================== */

/*
  Entrada : { "Actor": {...}, "IdSolicitud": "..." }
  Salida  : { estado, IdSolicitud, IdExpediente, Destinatario, Copia, Asunto,
              Cuerpo, Anexo4Documento, NombreAnexo4, CodigoAnexo4 }
*/
CREATE OR ALTER PROCEDURE cmn.paPrepararNotificacionAnexo4
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51900, 'JSON incorrecto.', 1;

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

        DECLARE @IdSolicitud uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdSolicitud'));

        IF @IdSolicitud IS NULL
            THROW 51901, 'VALIDACION_PAYLOAD: falta IdSolicitud.', 1;

        DECLARE @Codigo varchar(40), @IdExpediente uniqueidentifier,
                @CodigoEstado varchar(60), @AnoEje smallint,
                @CentroCosto varchar(15), @Sustento nvarchar(max),
                @IdUnidadOrigen uniqueidentifier, @AreaUsuaria nvarchar(250),
                @TipoOperacion varchar(20);

        SELECT @Codigo         = s.Codigo,
               @IdExpediente   = s.IdExpediente,
               @AnoEje         = s.AnoEje,
               @CentroCosto    = s.CentroCosto,
               @Sustento       = s.Sustento,
               @TipoOperacion  = s.TipoOperacion,
               @CodigoEstado   = e.CodigoEstado,
               @IdUnidadOrigen = e.IdUnidadOrigen,
               @AreaUsuaria    = u.Nombre
          FROM cmn.Solicitud AS s
          JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
          JOIN sigcm.Unidad     AS u ON u.IdUnidad     = e.IdUnidadOrigen
         WHERE s.IdSolicitud = @IdSolicitud AND s.Activo = 1;

        IF @Codigo IS NULL
            THROW 51902, 'NO_ENCONTRADO: la solicitud CMN no existe.', 1;

        /* El aviso es "tu modificacion ya se hizo". Antes de CMN_A4_ENVIADO eso
           todavia no es cierto: la aprobacion en SIGA la ejecuta W001 al firmar
           el jefe, que es justo la transicion que lleva a este estado. */
        IF @CodigoEstado NOT IN ('CMN_A4_ENVIADO', 'CMN_FINALIZADO')
            THROW 51903, 'CONFLICTO_ESTADO: el aviso del Anexo 4 se envia cuando el expediente llega al area usuaria, no antes de que el Jefe de Abastecimiento lo firme.', 1;

        DECLARE @IdPaquete uniqueidentifier, @CodigoAnexo4 varchar(40);

        SELECT TOP 1 @IdPaquete = pk.IdPaquete, @CodigoAnexo4 = pk.Codigo
          FROM cmn.PaqueteSolicitud AS ps
          JOIN cmn.Paquete AS pk ON pk.IdPaquete = ps.IdPaquete
         WHERE ps.IdSolicitud = @IdSolicitud AND ps.Activo = 1 AND pk.Anulado = 0;

        /* ------------------------------------------------------------------
           A QUIEN SE AVISA
           Al jefe del area usuaria de ORIGEN, que es quien tiene el expediente
           en su bandeja, con copia al resto de perfiles del area que
           intervienen en el tramite. Se resuelve por rol y unidad, nunca por un
           id fijo: quien ocupa el puesto cambia, el puesto no.

           Los correos vienen del padron del SSO, que es quien los mantiene. Un
           usuario sin correo simplemente no entra en la lista.
           ------------------------------------------------------------------ */
        DECLARE @Destinatario varchar(400), @Copia varchar(400);

        SELECT @Destinatario = STRING_AGG(CONVERT(varchar(400), x.Correo), ';')
          FROM (SELECT DISTINCT us.Correo
                  FROM sigcm.UsuarioRol AS ur
                  JOIN sigcm.Usuario    AS us ON us.IdUsuario = ur.IdUsuario
                 WHERE ur.IdUnidad  = @IdUnidadOrigen
                   AND ur.CodigoRol = 'AREA_JEFE'
                   AND ur.Activo    = 1
                   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()))
                   AND us.Activo = 1
                   AND NULLIF(LTRIM(RTRIM(us.Correo)), '') IS NOT NULL) AS x;

        SELECT @Copia = STRING_AGG(CONVERT(varchar(400), x.Correo), ';')
          FROM (SELECT DISTINCT us.Correo
                  FROM sigcm.UsuarioRol AS ur
                  JOIN sigcm.Usuario    AS us ON us.IdUsuario = ur.IdUsuario
                 WHERE ur.IdUnidad  = @IdUnidadOrigen
                   AND ur.CodigoRol IN ('AREA_COORDINADOR', 'AREA_ESPECIALISTA')
                   AND ur.Activo    = 1
                   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()))
                   AND us.Activo = 1
                   AND NULLIF(LTRIM(RTRIM(us.Correo)), '') IS NOT NULL) AS x;

        IF NULLIF(LTRIM(RTRIM(@Destinatario)), '') IS NULL
            THROW 51904, 'VALIDACION_CORREO: el area usuaria no tiene un jefe con correo registrado en el padron. El expediente ya esta en su bandeja; corrija el correo y reintente el aviso.', 1;

        /* El Anexo 4 firmado, para adjuntarlo. Es el documento del expediente,
           no un archivo que la pantalla tenga a mano. */
        DECLARE @Anexo4Documento nvarchar(200), @NombreAnexo4 nvarchar(200);

        SELECT @Anexo4Documento = a4.GeneradoDocumento,
               @NombreAnexo4    = a4.NombreDocumento
          FROM cmn.fnDocumentoVigente(@IdExpediente, N'CMN_ANEXO_4_APROBACION_MODIFICACION') AS a4;

        DECLARE @Asunto nvarchar(300) = CONCAT(
            N'Modificación del CMN aprobada — ', @Codigo,
            CASE WHEN @CodigoAnexo4 IS NULL THEN N''
                 ELSE CONCAT(N' — Anexo 4 ', @CodigoAnexo4) END);

        DECLARE @Cuerpo nvarchar(max) = CONCAT(
            N'<p>Estimado/a Jefe(a) de <b>', @AreaUsuaria, N'</b>:</p>',
            N'<p>Su solicitud de modificación del Cuadro Multianual de Necesidades ',
            N'<b>', @Codigo, N'</b> fue <b>aprobada</b>. El Anexo 4',
            CASE WHEN @CodigoAnexo4 IS NULL THEN N''
                 ELSE CONCAT(N' <b>', @CodigoAnexo4, N'</b>') END,
            N' está firmado por el Jefe de la Unidad de Abastecimiento y la ',
            N'modificación ya se registró en el SIGA.</p>',
            N'<p><b>Ejercicio:</b> ', CONVERT(varchar(4), @AnoEje), N'<br/>',
            N'<b>Centro de costo:</b> ', @CentroCosto, N'<br/>',
            N'<b>Tipo de operación:</b> ', ISNULL(@TipoOperacion, N'—'), N'</p>',
            /* Lo util del aviso no es que el papel se firmo, sino que ya puede
               pedir: es el paso que en SIGA habilita el item. */
            N'<p>Con esta aprobación los ítems incluidos quedan <b>disponibles ',
            N'para ser pedidos</b> en el SIGA. Puede registrar su pedido ',
            N'seleccionándolos del cuadro y, con ese número de pedido, continuar ',
            N'con su requerimiento en el SIGCM.</p>',
            N'<p>El expediente ya figura en su bandeja de Gestión CMN, donde debe ',
            N'<b>recepcionar el Anexo 4</b> para cerrarlo.</p>',
            N'<p>Se adjunta el Anexo 4 firmado.</p>',
            N'<p>Autoridad Nacional de Infraestructura — Unidad de Abastecimiento</p>');

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdSolicitud     AS IdSolicitud,
                   @IdExpediente    AS IdExpediente,
                   @IdPaquete       AS IdPaquete,
                   @CodigoAnexo4    AS CodigoAnexo4,
                   @Codigo          AS CodigoSolicitud,
                   Destinatario     = @Destinatario,
                   Copia            = @Copia,
                   Asunto           = @Asunto,
                   Cuerpo           = @Cuerpo,
                   Anexo4Documento  = @Anexo4Documento,
                   NombreAnexo4     = @NombreAnexo4,
                   N'Sobre del aviso listo.' AS mensaje
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

/* ========================================================================== */
/* 2. cmn.paMarcarAnexo4Notificado                                           */
/* ========================================================================== */

/*
  Deja la constancia del envio. Se llama SIEMPRE, haya salido el correo o no:
  una notificacion fallida que no queda registrada es indistinguible de una que
  nunca se intento, y es lo que hace falta saber para reintentar.

  Entrada : { "Actor": {...}, "IdSolicitud": "...", "Destinatario": "...",
              "Copia": "...", "ResultadoCorreo": "...", "CorreoEnviado": true,
              "Anexo4Documento": "..." }
*/
CREATE OR ALTER PROCEDURE cmn.paMarcarAnexo4Notificado
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51910, 'JSON incorrecto.', 1;

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

        DECLARE @IdSolicitud uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdSolicitud'));

        IF @IdSolicitud IS NULL
            THROW 51911, 'VALIDACION_PAYLOAD: falta IdSolicitud.', 1;

        DECLARE @Destinatario varchar(400) =
                    NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Destinatario'))), ''),
                @Copia varchar(400) =
                    NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Copia'))), ''),
                @ResultadoCorreo nvarchar(400) = JSON_VALUE(@parametro, '$.ResultadoCorreo'),
                @Anexo4Documento nvarchar(200) = JSON_VALUE(@parametro, '$.Anexo4Documento');

        DECLARE @CorreoEnviado bit = CASE
            WHEN JSON_VALUE(@parametro, '$.CorreoEnviado') IN ('true', '1') THEN 1 ELSE 0 END;

        IF @Destinatario IS NULL
            THROW 51912, 'VALIDACION_PAYLOAD: falta Destinatario.', 1;

        DECLARE @IdPaquete uniqueidentifier, @Ahora datetime = GETDATE();

        SELECT TOP 1 @IdPaquete = ps.IdPaquete
          FROM cmn.PaqueteSolicitud AS ps
          JOIN cmn.Paquete AS pk ON pk.IdPaquete = ps.IdPaquete
         WHERE ps.IdSolicitud = @IdSolicitud AND ps.Activo = 1 AND pk.Anulado = 0;

        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @TranPropia = 1;
        END

        /* Reintento: la fila viva de la solicitud se actualiza, no se duplica.
           El indice unico filtrado de V028 lo garantiza ademas en la base. */
        UPDATE cmn.NotificacionAnexo4
           SET IdPaquete                     = @IdPaquete,
               Destinatario                  = @Destinatario,
               Copia                         = @Copia,
               EnviadaEn                     = CASE WHEN @CorreoEnviado = 1
                                                    THEN @Ahora ELSE EnviadaEn END,
               ResultadoCorreo               = @ResultadoCorreo,
               CorreoEnviado                 = @CorreoEnviado,
               Anexo4Documento               = @Anexo4Documento,
               UsuarioModificacionAuditoria  = @Cuenta,
               FechaModificacionAuditoria    = @Ahora,
               EquipoModificacionAuditoria   = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdSolicitud = @IdSolicitud AND Activo = 1;

        IF @@ROWCOUNT = 0
            INSERT INTO cmn.NotificacionAnexo4
                (IdSolicitud, IdPaquete, Destinatario, Copia, EnviadaEn,
                 ResultadoCorreo, CorreoEnviado, Anexo4Documento,
                 UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                 EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdSolicitud, @IdPaquete, @Destinatario, @Copia,
                 CASE WHEN @CorreoEnviado = 1 THEN @Ahora ELSE NULL END,
                 @ResultadoCorreo, @CorreoEnviado, @Anexo4Documento,
                 @Cuenta, @Ahora, @Equipo, @Programa);

        IF @TranPropia = 1 COMMIT TRANSACTION;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdSolicitud   AS IdSolicitud,
                   @Destinatario  AS Destinatario,
                   @CorreoEnviado AS CorreoEnviado,
                   mensaje = CASE WHEN @CorreoEnviado = 1
                                  THEN N'Aviso enviado al area usuaria.'
                                  ELSE N'El expediente ya esta en la bandeja del area usuaria, pero el correo no salio. Puede reintentar el aviso.' END
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @TranPropia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F013 aplicada: cmn.paPrepararNotificacionAnexo4 / cmn.paMarcarAnexo4Notificado.';
GO
