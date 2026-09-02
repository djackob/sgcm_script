/*
===============================================================================
  SIGCM - F010 : Notificacion OS incluye el proveedor para el alta SGCM-E
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El puente, despues del correo de la O/S, llama a
  login.fn_insertar_tm_login_usuario_externo_contrataciones. Esta rutina le
  entrega el primer proveedor del Anexo 5 (DatosAdicionales) sin interpretarlo.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE requerimiento.paPrepararNotificacionOrden
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51850, 'JSON incorrecto.', 1;

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
            THROW 51851, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        DECLARE @Codigo varchar(40), @Denominacion varchar(500), @Plazo int,
                @NumeroOrden varchar(40), @CorreoLocador varchar(200), @CorreoAu varchar(200),
                @IdExpediente uniqueidentifier, @Version int, @Estado varchar(60),
                @Datos nvarchar(max), @Proveedor nvarchar(max);

        SELECT @Codigo = r.Codigo, @Denominacion = r.Denominacion, @Plazo = r.PlazoDias,
               @IdExpediente = r.IdExpediente,
               @NumeroOrden = o.NumeroOrden,
               @CorreoLocador = o.CorreoLocador,
               @CorreoAu = o.CorreoAreaUsuaria,
               @Version = e.Version,
               @Estado = e.CodigoEstado,
               @Datos = r.DatosAdicionales
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
          JOIN requerimiento.OrdenServicio AS o ON o.IdRequerimiento = r.IdRequerimiento AND o.Activo = 1
         WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1;

        IF @Codigo IS NULL
            THROW 51852, 'NO_ENCONTRADO: no hay una orden de servicio registrada para este requerimiento.', 1;

        IF @Estado <> 'REQ_OS_EMITIDA'
            THROW 51853, 'CONFLICTO_ESTADO: la orden solo se notifica cuando ya fue emitida.', 1;

        IF NULLIF(LTRIM(RTRIM(@CorreoLocador)), '') IS NULL
            THROW 51854, 'VALIDACION_CORREO: el locador no tiene correo en el Anexo 5 / Anexo 6. Completelo antes de notificar.', 1;

        SET @Proveedor = COALESCE(
            JSON_QUERY(@Datos, '$.Proveedores[0]'),
            JSON_QUERY(@Datos, '$.Proveedor'));

        DECLARE @Asunto nvarchar(300) = CONCAT(N'Orden de servicio ', ISNULL(@NumeroOrden, @Codigo), N' — ', @Denominacion);
        DECLARE @Cuerpo nvarchar(max) = CONCAT(
            N'<p>Se comunica la emisión de la orden de servicio <b>', ISNULL(@NumeroOrden, @Codigo),
            N'</b> correspondiente al requerimiento <b>', @Codigo, N'</b>.</p>',
            N'<p><b>Denominación:</b> ', @Denominacion, N'</p>',
            N'<p>A partir de esta notificación inicia el plazo de ejecución (',
            CONVERT(varchar(10), ISNULL(@Plazo, 0)), N' día(s) calendario).</p>',
            N'<p>Autoridad Nacional de Infraestructura — SIGCM</p>');

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente AS IdExpediente,
                   @Version AS Version,
                   @NumeroOrden AS NumeroOrden,
                   Destinatario = @CorreoLocador,
                   Copia = @CorreoAu,
                   Asunto = @Asunto,
                   Cuerpo = @Cuerpo,
                   JSON_QUERY(@Proveedor) AS Proveedor,
                   N'Sobre de notificación listo.' AS mensaje
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

PRINT 'F010 aplicada: paPrepararNotificacionOrden entrega el proveedor para el alta SGCM-E.';
GO
