/*
===============================================================================
  SIGCM - F011 : Invitacion de cotizacion al locador (indagacion de mercado)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51870-51889

  paPrepararInvitacionLocador arma destinatario, asunto, cuerpo y plazo.
  El puente .NET adjunta A3/A6/A7/integridad y llama a UT_Correo.
  paMarcarInvitacionEnviada guarda el resultado y abre el plazo de 3 dias habiles.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE requerimiento.paPrepararInvitacionLocador
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51870, 'JSON incorrecto.', 1;

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

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        IF @IdRequerimiento IS NULL
            THROW 51871, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        DECLARE @Codigo varchar(40), @Denominacion varchar(500),
                @IdExpediente uniqueidentifier, @Version int, @Estado varchar(60),
                @Tipo varchar(20), @Datos nvarchar(max), @Correo varchar(200),
                @NombreLocador nvarchar(250);

        SELECT @Codigo = r.Codigo, @Denominacion = r.Denominacion,
               @IdExpediente = r.IdExpediente, @Version = e.Version,
               @Estado = e.CodigoEstado, @Tipo = r.CodigoTipoContratacion,
               @Datos = r.DatosAdicionales
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
         WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1;

        IF @Codigo IS NULL
            THROW 51872, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        IF @Tipo <> 'LOCACION'
            THROW 51873, 'CONFLICTO_TIPO: la invitacion uno a uno solo aplica a locacion de servicios.', 1;

        IF @Estado NOT IN ('REQ_CONFORME', 'REQ_INDAGACION_MERCADO')
            THROW 51874, 'CONFLICTO_ESTADO: la invitacion se envia al iniciar la indagacion de mercado.', 1;

        SET @Correo = NULLIF(LTRIM(RTRIM(COALESCE(
                JSON_VALUE(@Datos, '$.Proveedores[0].Email'),
                JSON_VALUE(@Datos, '$.Proveedor.Email')))), '');
        SET @NombreLocador = NULLIF(LTRIM(RTRIM(CONCAT(
                JSON_VALUE(@Datos, '$.Proveedores[0].Nombres'), N' ',
                JSON_VALUE(@Datos, '$.Proveedores[0].ApellidoPaterno'), N' ',
                JSON_VALUE(@Datos, '$.Proveedores[0].ApellidoMaterno')))), '');
        IF @NombreLocador IS NULL
            SET @NombreLocador = NULLIF(LTRIM(RTRIM(CONCAT(
                    JSON_VALUE(@Datos, '$.Proveedor.Nombres'), N' ',
                    JSON_VALUE(@Datos, '$.Proveedor.ApellidoPaterno'), N' ',
                    JSON_VALUE(@Datos, '$.Proveedor.ApellidoMaterno')))), '');

        IF @Correo IS NULL
            THROW 51875, 'VALIDACION_CORREO: el locador no tiene correo en el Anexo 5. Completelo antes de invitar.', 1;

        DECLARE @PlazoHasta date = sigcm.fnSumarDiasHabiles(CONVERT(date, GETDATE()), 3);
        DECLARE @Asunto nvarchar(300) = CONCAT(
            N'Solicitud de cotización — ', ISNULL(@Codigo, N''), N' — ', @Denominacion);
        DECLARE @Cuerpo nvarchar(max) = CONCAT(
            N'<p>Estimado/a <b>', ISNULL(@NombreLocador, N'locador'), N'</b>:</p>',
            N'<p>La Autoridad Nacional de Infraestructura le invita a presentar su cotización ',
            N'para el requerimiento <b>', @Codigo, N'</b> (locación de servicios, invitación directa).</p>',
            N'<p><b>Denominación:</b> ', @Denominacion, N'</p>',
            N'<p>Adjunto encontrará el paquete digital:</p>',
            N'<ol>',
            N'<li>Anexo 3 — Términos de Referencia (TDR) aprobados</li>',
            N'<li>Anexo 6 — Formato de cotización y declaración jurada del proveedor (CCI y monto a dos decimales)</li>',
            N'<li>Anexo 7 — Declaración jurada de prohibiciones e incompatibilidades</li>',
            N'<li>Instructivo para denunciar presuntos actos de corrupción y Política de Integridad y Antisoborno de la ANIN</li>',
            N'</ol>',
            N'<p>El plazo máximo de respuesta es de <b>tres (3) días hábiles</b>, hasta el <b>',
            CONVERT(varchar(10), @PlazoHasta, 103),
            N'</b>. Debe devolver los Anexos 6 y 7 firmados.</p>',
            N'<p>Autoridad Nacional de Infraestructura — Unidad de Abastecimiento (DEC)</p>');

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente AS IdExpediente,
                   @IdRequerimiento AS IdRequerimiento,
                   @Version AS Version,
                   @Estado AS CodigoEstado,
                   Destinatario = @Correo,
                   Copia = CONVERT(varchar(200), NULL),
                   Asunto = @Asunto,
                   Cuerpo = @Cuerpo,
                   PlazoHasta = CONVERT(varchar(10), @PlazoHasta, 23),
                   Locador = @NombreLocador,
                   N'Sobre de invitacion listo.' AS mensaje
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

CREATE OR ALTER PROCEDURE requerimiento.paMarcarInvitacionEnviada
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51880, 'JSON incorrecto.', 1;

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

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));
        DECLARE @ResultadoCorreo nvarchar(400) = JSON_VALUE(@parametro, '$.ResultadoCorreo');
        DECLARE @CorreoEnviado bit = CASE
            WHEN JSON_VALUE(@parametro, '$.CorreoEnviado') IN ('true','1') THEN 1 ELSE 0 END;
        DECLARE @Destinatario varchar(200) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Destinatario'))), '');
        DECLARE @Anexo3 nvarchar(200) = JSON_VALUE(@parametro, '$.Anexo3Documento');
        DECLARE @Anexo6 nvarchar(200) = JSON_VALUE(@parametro, '$.Anexo6Documento');
        DECLARE @Anexo7 nvarchar(200) = JSON_VALUE(@parametro, '$.Anexo7Documento');
        DECLARE @Integridad nvarchar(200) = JSON_VALUE(@parametro, '$.IntegridadDocumento');

        IF @IdRequerimiento IS NULL
            THROW 51881, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        DECLARE @IdExpediente uniqueidentifier, @Ahora datetime = GETDATE();
        DECLARE @PlazoHasta date = sigcm.fnSumarDiasHabiles(CONVERT(date, @Ahora), 3);

        SELECT @IdExpediente = r.IdExpediente,
               @Destinatario = COALESCE(@Destinatario, NULLIF(LTRIM(RTRIM(COALESCE(
                   JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Email'),
                   JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Email')))), ''))
          FROM requerimiento.Requerimiento AS r
         WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1;

        IF @IdExpediente IS NULL
            THROW 51882, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        MERGE requerimiento.InvitacionCotizacion AS d
        USING (SELECT @IdRequerimiento AS IdRequerimiento) AS s
        ON d.IdRequerimiento = s.IdRequerimiento AND d.Activo = 1
        WHEN MATCHED THEN
            UPDATE SET d.Destinatario = COALESCE(@Destinatario, d.Destinatario),
                       d.EnviadaEn = @Ahora,
                       d.PlazoHasta = @PlazoHasta,
                       d.ResultadoCorreo = @ResultadoCorreo,
                       d.CorreoEnviado = @CorreoEnviado,
                       d.Anexo3Documento = COALESCE(@Anexo3, d.Anexo3Documento),
                       d.Anexo6Documento = COALESCE(@Anexo6, d.Anexo6Documento),
                       d.Anexo7Documento = COALESCE(@Anexo7, d.Anexo7Documento),
                       d.IntegridadDocumento = COALESCE(@Integridad, d.IntegridadDocumento),
                       d.UsuarioModificacionAuditoria = @Cuenta,
                       d.FechaModificacionAuditoria = @Ahora,
                       d.EquipoModificacionAuditoria = @Equipo,
                       d.ProgramaModificacionAuditoria = @Programa
        WHEN NOT MATCHED THEN
            INSERT (IdRequerimiento, Destinatario, EnviadaEn, PlazoHasta, ResultadoCorreo,
                    CorreoEnviado, Anexo3Documento, Anexo6Documento, Anexo7Documento,
                    IntegridadDocumento,
                    UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES (@IdRequerimiento, ISNULL(@Destinatario, ''), @Ahora, @PlazoHasta, @ResultadoCorreo,
                    @CorreoEnviado, @Anexo3, @Anexo6, @Anexo7, @Integridad,
                    @Cuenta, @Equipo, @Programa);

        IF NOT EXISTS (
            SELECT 1 FROM sigcm.Plazo
             WHERE IdExpediente = @IdExpediente
               AND CodigoRegla = 'REQ_RESPUESTA_LOCADOR'
               AND Estado = 'EN_CURSO' AND Activo = 1)
        BEGIN
            INSERT INTO sigcm.Plazo
                (IdExpediente, CodigoRegla, Inicio, Vencimiento, Estado,
                 UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdExpediente, 'REQ_RESPUESTA_LOCADOR', @Ahora, @PlazoHasta, 'EN_CURSO',
                 @Cuenta, @Equipo, @Programa);
        END

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente AS IdExpediente,
                   @IdRequerimiento AS IdRequerimiento,
                   @CorreoEnviado AS CorreoEnviado,
                   PlazoHasta = CONVERT(varchar(10), @PlazoHasta, 23),
                   ISNULL(@ResultadoCorreo,
                          N'Se registro la invitacion de cotizacion al locador.') AS mensaje
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

PRINT 'F011 aplicada: invitacion de cotizacion al locador.';
GO
