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
  FINALIZA (CMN_FINALIZADO). Ya no hay recepcion del jefe del area usuaria.

  La derivacion fisica del expediente al AU se omitio; lo que falta es avisar.
  El area usuaria no vive dentro del sistema: sin correo, la aprobacion que
  habilita su pedido en SIGA se entera cuando alguien entra a mirar.

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
           A QUIEN SE AVISA (T7 / observacion CMN 16/09/2026)
           Para: jefe AU + especialista AU del area de origen.
           Copia: especialista Abast + jefe Abast.
           Se resuelve por rol y unidad; correos del padron SSO.
           ------------------------------------------------------------------ */
        DECLARE @Destinatario varchar(800), @Copia varchar(800);
        DECLARE @IdUnidadAbast uniqueidentifier;

        SELECT TOP 1 @IdUnidadAbast = n.IdUnidad
          FROM sigcm.UsuarioRol AS ur
          JOIN sigcm.Unidad AS n ON n.IdUnidad = ur.IdUnidad AND n.Activo = 1
         WHERE ur.CodigoRol = 'ABAST_ESPECIALISTA' AND ur.Activo = 1
         ORDER BY CASE WHEN n.Codigo = 'UO-ABAST' THEN 0 ELSE 1 END,
                  n.Nombre;

        IF @IdUnidadAbast IS NULL
            SELECT TOP 1 @IdUnidadAbast = IdUnidad
              FROM sigcm.Unidad
             WHERE Activo = 1 AND Codigo = 'UO-ABAST';

        SELECT @Destinatario = STRING_AGG(CONVERT(varchar(400), x.Correo), ';')
          FROM (SELECT DISTINCT us.Correo
                  FROM sigcm.UsuarioRol AS ur
                  JOIN sigcm.Usuario    AS us ON us.IdUsuario = ur.IdUsuario
                 WHERE ur.IdUnidad  = @IdUnidadOrigen
                   AND ur.CodigoRol IN ('AREA_JEFE', 'AREA_ESPECIALISTA')
                   AND ur.Activo    = 1
                   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()))
                   AND us.Activo = 1
                   AND NULLIF(LTRIM(RTRIM(us.Correo)), '') IS NOT NULL) AS x;

        SELECT @Copia = STRING_AGG(CONVERT(varchar(400), x.Correo), ';')
          FROM (SELECT DISTINCT us.Correo
                  FROM sigcm.UsuarioRol AS ur
                  JOIN sigcm.Usuario    AS us ON us.IdUsuario = ur.IdUsuario
                 WHERE @IdUnidadAbast IS NOT NULL
                   AND ur.IdUnidad  = @IdUnidadAbast
                   AND ur.CodigoRol IN ('ABAST_ESPECIALISTA', 'ABAST_JEFE')
                   AND ur.Activo    = 1
                   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()))
                   AND us.Activo = 1
                   AND NULLIF(LTRIM(RTRIM(us.Correo)), '') IS NOT NULL
                   AND us.Correo NOT IN (
                        SELECT value FROM STRING_SPLIT(ISNULL(@Destinatario, ''), ';')
                         WHERE NULLIF(LTRIM(RTRIM(value)), '') IS NOT NULL
                   )) AS x;

        IF NULLIF(LTRIM(RTRIM(@Destinatario)), '') IS NULL
            THROW 51904, 'VALIDACION_CORREO: el area usuaria no tiene jefe ni especialista con correo registrado en el padron. El expediente ya esta finalizado; corrija el correo y reintente el aviso.', 1;

        DECLARE @CuerpoSaludo nvarchar(200) = N'Estimados responsables de <b>' + @AreaUsuaria + N'</b>:';

        /* El Anexo 4 firmado, para adjuntarlo. Es el documento del expediente,
           no un archivo que la pantalla tenga a mano. */
        DECLARE @Anexo4Documento nvarchar(200), @NombreAnexo4 nvarchar(200);

        SELECT @Anexo4Documento = a4.GeneradoDocumento,
               @NombreAnexo4    = a4.NombreDocumento
          FROM cmn.fnDocumentoVigente(@IdExpediente, N'CMN_ANEXO_4_APROBACION_MODIFICACION') AS a4;

        DECLARE @o nchar(1) = NCHAR(0x00F3);
        DECLARE @i nchar(1) = NCHAR(0x00ED);
        DECLARE @a nchar(1) = NCHAR(0x00E1);
        DECLARE @e nchar(1) = NCHAR(0x00E9);
        DECLARE @u nchar(1) = NCHAR(0x00FA);
        DECLARE @Asunto nvarchar(300) = CONCAT(
            N'Modificaci', @o, N'n del CMN aprobada - ', @Codigo,
            CASE WHEN @CodigoAnexo4 IS NULL THEN N''
                 ELSE CONCAT(N' - Anexo 4 ', @CodigoAnexo4) END);

        DECLARE @Cuerpo nvarchar(max) = CONCAT(
            N'<p>', @CuerpoSaludo, N'</p>',
            N'<p>Su solicitud de modificaci', @o, N'n del Cuadro Multianual de Necesidades ',
            N'<b>', @Codigo, N'</b> fue <b>aprobada</b>. El Anexo 4',
            CASE WHEN @CodigoAnexo4 IS NULL THEN N''
                 ELSE CONCAT(N' <b>', @CodigoAnexo4, N'</b>') END,
            N' est', @a, N' firmado por el Jefe de la Unidad de Abastecimiento y la ',
            N'modificaci', @o, N'n ya se registr', @o, N' en el SIGA.</p>',
            N'<p><b>Ejercicio:</b> ', CONVERT(varchar(4), @AnoEje), N'<br/>',
            N'<b>Centro de costo:</b> ', @CentroCosto, N'<br/>',
            N'<b>Tipo de operaci', @o, N'n:</b> ', ISNULL(@TipoOperacion, N'-'), N'</p>',
            N'<p>Con esta aprobaci', @o, N'n los ', @i, N'tems incluidos quedan <b>disponibles ',
            N'para ser pedidos</b> en el SIGA. Puede registrar su pedido ',
            N'seleccion', @a, N'ndolos del cuadro y, con ese n', @u, N'mero de pedido, continuar ',
            N'con su requerimiento en el SIGCM.</p>',
            N'<p>El expediente CMN qued', @o, N' <b>finalizado</b> con la firma del Jefe ',
            N'de Abastecimiento; no requiere recepci', @o, N'n adicional.</p>',
            N'<p>Se adjunta el Anexo 4 firmado.</p>',
            N'<p>Autoridad Nacional de Infraestructura - Unidad de Abastecimiento</p>');

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
