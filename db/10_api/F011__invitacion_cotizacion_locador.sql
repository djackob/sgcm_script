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
        /* La razon social manda cuando el locador se identifico por RUC: en ese
           caso los tres campos de persona natural vienen vacios y el CONCAT
           producia una cadena de espacios, de modo que el correo salia dirigido
           a "Estimado/a locador". Solo se lee el campo; ninguna regla cambia. */
        SET @NombreLocador = COALESCE(
            NULLIF(LTRIM(RTRIM(JSON_VALUE(@Datos, '$.Proveedores[0].RazonSocial'))), ''),
            NULLIF(LTRIM(RTRIM(CONCAT(
                JSON_VALUE(@Datos, '$.Proveedores[0].Nombres'), N' ',
                JSON_VALUE(@Datos, '$.Proveedores[0].ApellidoPaterno'), N' ',
                JSON_VALUE(@Datos, '$.Proveedores[0].ApellidoMaterno')))), ''));
        IF @NombreLocador IS NULL
            SET @NombreLocador = COALESCE(
                NULLIF(LTRIM(RTRIM(JSON_VALUE(@Datos, '$.Proveedor.RazonSocial'))), ''),
                NULLIF(LTRIM(RTRIM(CONCAT(
                    JSON_VALUE(@Datos, '$.Proveedor.Nombres'), N' ',
                    JSON_VALUE(@Datos, '$.Proveedor.ApellidoPaterno'), N' ',
                    JSON_VALUE(@Datos, '$.Proveedor.ApellidoMaterno')))), ''));

        IF @Correo IS NULL
            THROW 51875, 'VALIDACION_CORREO: el locador no tiene correo en el Anexo 5. Completelo antes de invitar.', 1;

        DECLARE @PlazoHasta date = sigcm.fnSumarDiasHabiles(CONVERT(date, GETDATE()), 3);

        /* Especialista que dispara la invitacion: va en copia y en el cuerpo. */
        DECLARE @CorreoEspecialista varchar(200), @NombreEspecialista varchar(250),
                @CargoEspecialista varchar(180);
        SELECT @CorreoEspecialista = NULLIF(LTRIM(RTRIM(u.Correo)), ''),
               @NombreEspecialista = COALESCE(
                   NULLIF(LTRIM(RTRIM(@NombreCompleto)), ''),
                   NULLIF(LTRIM(RTRIM(CONCAT(u.Nombres, N' ', u.Apellidos))), '')),
               @CargoEspecialista = COALESCE(
                   NULLIF(LTRIM(RTRIM(@Cargo)), ''),
                   NULLIF(LTRIM(RTRIM(u.Cargo)), ''),
                   N'Especialista de contratos menores')
          FROM sigcm.Usuario AS u
         WHERE u.IdUsuario = @IdUsuario;

        IF @CorreoEspecialista IS NULL
            SET @CorreoEspecialista = NULLIF(LTRIM(RTRIM(
                JSON_VALUE(@parametro, '$.Actor.Correo'))), '');

        /* Textos con NCHAR: evita mojibake si sqlcmd aplica el .sql sin UTF-8. */
        DECLARE @o nchar(1) = NCHAR(0x00F3); /* o aguda */
        DECLARE @i nchar(1) = NCHAR(0x00ED); /* i aguda */
        DECLARE @a nchar(1) = NCHAR(0x00E1); /* a aguda */
        DECLARE @e nchar(1) = NCHAR(0x00E9); /* e aguda */
        DECLARE @u nchar(1) = NCHAR(0x00FA); /* u aguda */
        DECLARE @UMay nchar(1) = NCHAR(0x00DA); /* U aguda */
        DECLARE @OMay nchar(1) = NCHAR(0x00D3); /* O aguda */
        /* 1900-01-01 fue lunes: el resto de 7 es independiente de DATEFIRST. */
        DECLARE @Dia nvarchar(20) = CASE (DATEDIFF(day, '19000101', @PlazoHasta) % 7)
            WHEN 0 THEN N'Lunes'
            WHEN 1 THEN N'Martes'
            WHEN 2 THEN CONCAT(N'Mi', @e, N'rcoles')
            WHEN 3 THEN N'Jueves'
            WHEN 4 THEN N'Viernes'
            WHEN 5 THEN CONCAT(N'S', @a, N'bado')
            WHEN 6 THEN N'Domingo'
        END;
        DECLARE @FechaPlazo nvarchar(60) = CONCAT(
            @Dia, N' ', CONVERT(varchar(10), @PlazoHasta, 105));
        DECLARE @DenominacionHtml nvarchar(max) = REPLACE(REPLACE(REPLACE(
            ISNULL(@Denominacion, N''), N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;');
        DECLARE @Observacion nvarchar(max) = NULLIF(LTRIM(RTRIM(
            JSON_VALUE(@parametro, '$.Observacion'))), N'');
        DECLARE @BloqueObs nvarchar(max) = N'';
        IF @Observacion IS NOT NULL
        BEGIN
            SET @Observacion = LEFT(@Observacion, 2000);
            SET @Observacion = REPLACE(REPLACE(REPLACE(@Observacion, N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;');
            SET @Observacion = REPLACE(REPLACE(@Observacion, CHAR(13) + CHAR(10), N'<br/>'), CHAR(10), N'<br/>');
            SET @BloqueObs = CONCAT(
                N'<p><b>Observaci', @o, N'n:</b><br/>', @Observacion, N'</p>');
        END
        DECLARE @Asunto nvarchar(300) = CONCAT(
            N'Solicitud de cotizaci', @o, N'n - ', ISNULL(@Codigo, N''), N' - ', @Denominacion);
        DECLARE @Cuerpo nvarchar(max) = CONCAT(
            N'<p>Estimado/a proveedor/a</p>',
            N'<p>Es grato dirigirle la presente a efectos de comunicarle que la Autoridad Nacional de Infraestructura le invita a formular su propuesta T',
            @e, N'cnica-Econ', @o, N'mica con el fin de contar con una cotizaci', @o,
            N'n formal para la siguiente contrataci', @o, N'n:</p>',
            N'<p><b>SERVICIO/ADQUISICI', @OMay, N'N:</b><br/>', @DenominacionHtml, N'</p>',
            @BloqueObs,
            N'<p><b>NOTAS IMPORTANTES:</b></p>',
            N'<ul>',
            N'<li>Encontrarse con Registro Nacional de Proveedores vigente.</li>',
            N'<li>No estar impedido de contratar con el estado.</li>',
            N'<li>De requerir visita t', @e, N'cnica, solicitarla.</li>',
            N'<li>De tener consultas y/u observaciones, comunicadas por este medio a efectos de solicitar al ',
            @a, N'rea correspondiente la absoluci', @o, N'n de las mismas.</li>',
            N'<li>De no estar en condiciones de cotizar, favor de indicar que no es posible atender nuestra solicitud.</li>',
            N'<li>Para poder cotizar deber', @a, N' contar con la actividad econ', @o,
            N'mica del rubro cotizado (RUC).</li>',
            N'<li>Adjuntar en formato PDF, los FORMATOS DE DECLARACI', @OMay,
            N'N JURADA, debidamente llenados y firmados (anexos adjuntos).</li>',
            N'<li>Para que la cotizaci', @o, N'n sea catalogada como v', @a,
            N'lida se deber', @a, N' indicar en la misma lo siguiente:</li>',
            N'</ul>',
            N'<p><b>EN CASO DE SERVICIOS:</b></p>',
            N'<ul>',
            N'<li>Adjuntar la documentaci', @o, N'n sustentatoria del cumplimiento de lo solicitado en los requisitos DEL PROVEEDOR seg',
            @u, N'n los TDR (Constancias, Certificados, u otros, de ser el caso).</li>',
            N'<li>Indicar el plazo de ejecuci', @o, N'n.</li>',
            N'<li>Adjuntar la documentaci', @o, N'n sustentatoria del cumplimiento de lo solicitado en los REQUISITOS Y RECURSOS DEL/DE LA PROVEEDOR/A seg',
            @u, N'n los TDR.</li>',
            N'</ul>',
            N'<p style="color:#c00000;font-weight:bold;">ADJUNTAR ', @UMay, N'NICAMENTE LA DOCUMENTACI', @OMay,
            N'N QUE ACREDITE LOS REQUISITOS ESTABLECIDOS EN EL REQUERIMIENTO.</p>',
            N'<p style="color:#c00000;"><b>Fecha m', @a, N'xima de entrega de propuesta:</b> el d', @i,
            N'a <b>', @FechaPlazo, N'</b></p>',
            N'<p>Asimismo, compartimos con ustedes material informativo sobre la Pol', @i,
            N'tica de Integridad y Antisoborno y un instructivo para la presentaci', @o,
            N'n de denuncias por presuntos actos de corrupci', @o,
            N'n, para su conocimiento y el fortalecimiento de la cultura de integridad en la ANIN.</p>',
            N'<p>Se agradece responder el presente correo a <b>',
            ISNULL(@CorreoEspecialista, N'[correo del especialista]'), N'</b></p>',
            N'<p>Se agradece de antemano la atenci', @o, N'n que se sirva dar al presente.</p>',
            N'<p>Atentamente,<br/><b>', ISNULL(@NombreEspecialista, N'Especialista de contratos menores'), N'</b><br/>',
            ISNULL(@CargoEspecialista, N'Especialista de contratos menores'), N'</p>');

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente AS IdExpediente,
                   @IdRequerimiento AS IdRequerimiento,
                   @Version AS Version,
                   @Estado AS CodigoEstado,
                   Destinatario = @Correo,
                   Copia = @CorreoEspecialista,
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
