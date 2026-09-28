/*
  F025 - Constancia de prestacion (despues del ultimo giro) y su notificacion.

  pago.paEmitirConstancia
    { IdExpediente, Emitir }  IdExpediente es cualquier pago de la orden.
    Corresponde = 1 cuando todos los entregables activos de la orden estan en
    PAG_PAGO_EFECTUADO. Con Emitir = true y sin constancia previa, la crea
    (TESORERIA o Abastecimiento). Devuelve los datos para generar el PDF.
  pago.paRegistrarConstanciaDocumento
    { IdExpediente, GeneradoDocumento, NombreDocumento }
  pago.paPrepararNotificacionConstancia / pago.paMarcarConstanciaNotificada
    Sobre y marca del puente NotificarPorCorreo: la constancia va adjunta al
    correo del proveedor.

  Depende de V039.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Constancia activa de la orden a la que pertenece un expediente de pago. */
CREATE OR ALTER FUNCTION pago.fnConstanciaDeExpediente (@IdExpediente uniqueidentifier)
RETURNS uniqueidentifier
AS
BEGIN
    RETURN (
        SELECT c.IdConstancia
          FROM pago.ExpedientePago AS p
          JOIN pago.ConstanciaPrestacion AS c ON c.IdRequerimiento = p.IdRequerimiento AND c.Activo = 1
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1);
END
GO

CREATE OR ALTER PROCEDURE pago.paEmitirConstancia
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52501, 'JSON incorrecto.', 1;

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

        IF @CodigoRol = 'PROVEEDOR'
            THROW 52502, 'NO_AUTORIZADO: la constancia se remite al proveedor por correo.', 1;

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @Emitir bit = CASE WHEN JSON_VALUE(@parametro, '$.Emitir') IN ('true', '1') THEN 1 ELSE 0 END;
        IF @IdExpediente IS NULL
            THROW 52503, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @IdReq uniqueidentifier = (
            SELECT p.IdRequerimiento FROM pago.ExpedientePago AS p
             WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1);
        IF @IdReq IS NULL
            THROW 52504, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        DECLARE @Pagos TABLE (IdExpediente uniqueidentifier PRIMARY KEY, CodigoEstado varchar(60), FechaAbono datetime);
        INSERT INTO @Pagos
        SELECT p.IdExpediente, e.CodigoEstado, p.FechaAbono
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdRequerimiento = @IdReq AND p.Activo = 1 AND e.Anulado = 0 AND e.Activo = 1;

        DECLARE @Pendientes int = (SELECT COUNT(*) FROM @Pagos WHERE CodigoEstado <> 'PAG_PAGO_EFECTUADO');
        DECLARE @Corresponde bit = CASE WHEN @Pendientes = 0 AND EXISTS (SELECT 1 FROM @Pagos) THEN 1 ELSE 0 END;

        DECLARE @IdConstancia uniqueidentifier = (
            SELECT IdConstancia FROM pago.ConstanciaPrestacion WHERE IdRequerimiento = @IdReq AND Activo = 1);
        DECLARE @Nueva bit = 0;

        IF @Emitir = 1 AND @IdConstancia IS NULL
        BEGIN
            IF @Corresponde = 0
                THROW 52505, 'CONFLICTO_ESTADO: la constancia se emite cuando todos los entregables de la orden estan pagados.', 1;
            IF @CodigoRol <> 'TESORERIA' AND @CodigoRol NOT LIKE 'ABAST[_]%'
                THROW 52506, 'NO_AUTORIZADO: emiten la constancia Tesoreria o Abastecimiento.', 1;

            DECLARE @IdUltimo uniqueidentifier = (
                SELECT TOP 1 IdExpediente FROM @Pagos ORDER BY FechaAbono DESC);
            DECLARE @Ano smallint = YEAR(GETDATE());

            BEGIN TRAN;
                DECLARE @Correlativo int = ISNULL((
                    SELECT MAX(Correlativo) FROM pago.ConstanciaPrestacion WITH (UPDLOCK, HOLDLOCK)
                     WHERE AnoEje = @Ano), 0) + 1;
                SET @IdConstancia = NEWID();

                INSERT INTO pago.ConstanciaPrestacion
                    (IdConstancia, IdRequerimiento, IdExpediente, AnoEje, Correlativo, Numero,
                     MontoContrato, MontoPagado, MontoPenalidad, CorreoDestino,
                     IdUsuarioEmisor, NombreEmisor, CargoEmisor,
                     UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                SELECT @IdConstancia, @IdReq, @IdUltimo, @Ano, @Correlativo,
                       CONCAT('CP-', @Ano, '-', RIGHT(CONCAT('000000', @Correlativo), 6)),
                       MAX(p.MontoContrato), SUM(p.MontoEntregable), SUM(p.MontoPenalidad),
                       MAX(p.CorreoLocador),
                       @IdUsuario, @NombreCompleto, @Cargo,
                       @Cuenta, @Equipo, @Programa
                  FROM pago.ExpedientePago AS p
                  JOIN @Pagos AS x ON x.IdExpediente = p.IdExpediente;

                INSERT INTO sigcm.Historial (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion, Comentario,
                                             IdActor, ActorRol, IdActorUnidad, UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                SELECT e.IdExpediente, e.CodigoEstado, e.CodigoEstado, NULL,
                       CONCAT(N'Constancia de prestacion emitida: ', c.Numero),
                       @IdUsuario, @CodigoRol, @IdUnidad, @Cuenta, @Equipo, @Programa
                  FROM pago.ConstanciaPrestacion AS c
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
                 WHERE c.IdConstancia = @IdConstancia;
            COMMIT;
            SET @Nueva = 1;
        END

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Corresponde = @Corresponde,
                   Pendientes = @Pendientes,
                   Nueva = @Nueva,
                   PuedeEmitir = CONVERT(bit, CASE WHEN @CodigoRol = 'TESORERIA' OR @CodigoRol LIKE 'ABAST[_]%' THEN 1 ELSE 0 END),
                   Constancia = JSON_QUERY((
                       SELECT c.IdConstancia, c.IdExpediente, c.Numero, c.FechaEmision,
                              c.MontoContrato, c.MontoPagado, c.MontoPenalidad,
                              MontoNeto = (SELECT SUM(p.MontoNeto) FROM pago.ExpedientePago AS p
                                            JOIN @Pagos AS x ON x.IdExpediente = p.IdExpediente),
                              c.GeneradoDocumento, c.NombreDocumento, c.CorreoDestino,
                              c.NotificadaEn, c.ResultadoNotificacion,
                              c.NombreEmisor, c.CargoEmisor,
                              r.Codigo AS CodigoRequerimiento, r.Denominacion, r.CodigoTipoContratacion,
                              r.PlazoDias,
                              UnidadOrigen = u.Nombre, UnidadSigla = u.Sigla,
                              NumeroOrdenSiga = COALESCE(p1.NumeroOrdenSiga, os.NumeroOrden),
                              p1.TipoOrden, p1.NumeroContrato,
                              p1.NombreLocador, p1.RucLocador, p1.DniLocador, p1.CorreoLocador,
                              FechaOrden = os.FechaEmision,
                              FechaNotificacionOrden = os.NotificadoEn,
                              Entregables = JSON_QUERY(COALESCE((
                                  SELECT p.NumeroEntregable, p.NombreEntregable, p.MontoEntregable,
                                         p.FechaLimiteCronograma, p.FechaPresentacion, p.FechaConformidadTecnica,
                                         p.DiasAtraso, p.MontoPenalidad, p.MontoNeto,
                                         p.NotaPagoSiaf, p.FechaAbono, e.Codigo
                                    FROM pago.ExpedientePago AS p
                                    JOIN @Pagos AS x ON x.IdExpediente = p.IdExpediente
                                    JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
                                   ORDER BY p.NumeroEntregable
                                     FOR JSON PATH), N'[]'))
                         FROM pago.ConstanciaPrestacion AS c
                         JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = c.IdRequerimiento
                         JOIN sigcm.Expediente AS er ON er.IdExpediente = r.IdExpediente
                         LEFT JOIN sigcm.Unidad AS u ON u.IdUnidad = er.IdUnidadOrigen
                         CROSS APPLY (SELECT TOP 1 p.* FROM pago.ExpedientePago AS p
                                       WHERE p.IdRequerimiento = c.IdRequerimiento AND p.Activo = 1
                                       ORDER BY p.NumeroEntregable DESC) AS p1
                         LEFT JOIN requerimiento.OrdenServicio AS os ON os.IdOrdenServicio = p1.IdOrdenServicio
                        WHERE c.IdConstancia = @IdConstancia
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE pago.paRegistrarConstanciaDocumento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52511, 'JSON incorrecto.', 1;

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

        IF @CodigoRol <> 'TESORERIA' AND @CodigoRol NOT LIKE 'ABAST[_]%'
            THROW 52512, 'NO_AUTORIZADO: registran la constancia Tesoreria o Abastecimiento.', 1;

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @Doc nvarchar(200) = NULLIF(JSON_VALUE(@parametro, '$.GeneradoDocumento'), '');
        DECLARE @Nombre nvarchar(250) = NULLIF(JSON_VALUE(@parametro, '$.NombreDocumento'), '');
        DECLARE @IdConstancia uniqueidentifier = pago.fnConstanciaDeExpediente(@IdExpediente);
        IF @IdConstancia IS NULL
            THROW 52513, 'NO_ENCONTRADO: la orden no tiene constancia emitida.', 1;
        IF @Doc IS NULL
            THROW 52514, 'VALIDACION_ARCHIVO: falta GeneradoDocumento.', 1;

        UPDATE pago.ConstanciaPrestacion
           SET GeneradoDocumento = @Doc, NombreDocumento = @Nombre,
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdConstancia = @IdConstancia;

        SELECT (SELECT 1 AS estado, IdConstancia = @IdConstancia,
                       IdExpediente = (SELECT IdExpediente FROM pago.ConstanciaPrestacion WHERE IdConstancia = @IdConstancia),
                       mensaje = N'Constancia registrada.'
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE pago.paPrepararNotificacionConstancia
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52521, 'JSON incorrecto.', 1;

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

        IF @CodigoRol <> 'TESORERIA' AND @CodigoRol NOT LIKE 'ABAST[_]%'
            THROW 52522, 'NO_AUTORIZADO: notifican la constancia Tesoreria o Abastecimiento.', 1;

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @IdConstancia uniqueidentifier = pago.fnConstanciaDeExpediente(@IdExpediente);
        IF @IdConstancia IS NULL
            THROW 52523, 'NO_ENCONTRADO: la orden no tiene constancia emitida.', 1;

        DECLARE @Numero varchar(30), @Doc nvarchar(200), @NombreDoc nvarchar(250), @Correo varchar(200),
                @Proveedor nvarchar(250), @Orden varchar(40), @TipoOrden char(2), @Denominacion varchar(500);
        SELECT @Numero = c.Numero, @Doc = c.GeneradoDocumento, @NombreDoc = c.NombreDocumento,
               @Correo = COALESCE(NULLIF(c.CorreoDestino, ''), p1.CorreoLocador),
               @Proveedor = p1.NombreLocador, @Orden = COALESCE(p1.NumeroOrdenSiga, os.NumeroOrden),
               @TipoOrden = p1.TipoOrden, @Denominacion = r.Denominacion
          FROM pago.ConstanciaPrestacion AS c
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = c.IdRequerimiento
          CROSS APPLY (SELECT TOP 1 p.* FROM pago.ExpedientePago AS p
                        WHERE p.IdRequerimiento = c.IdRequerimiento AND p.Activo = 1
                        ORDER BY p.NumeroEntregable DESC) AS p1
          LEFT JOIN requerimiento.OrdenServicio AS os ON os.IdOrdenServicio = p1.IdOrdenServicio
         WHERE c.IdConstancia = @IdConstancia;

        IF @Doc IS NULL
            THROW 52524, 'VALIDACION_ARCHIVO: genere el PDF de la constancia antes de notificarla.', 1;
        IF NULLIF(@Correo, '') IS NULL
            THROW 52525, 'VALIDACION_CORREO: el proveedor no tiene correo registrado.', 1;

        DECLARE @EtiquetaOrden nvarchar(10) = CASE WHEN @TipoOrden = 'OC' THEN N'O/C' ELSE N'O/S' END;

        SELECT (
            SELECT 1 AS estado,
                   Destinatario = @Correo,
                   Copia = CAST(NULL AS varchar(200)),
                   Asunto = CONCAT(N'Constancia de prestacion ', @Numero, N' - ', @EtiquetaOrden, N' ', ISNULL(@Orden, N'')),
                   Cuerpo = CONCAT(
                       N'Estimado(a) ', ISNULL(@Proveedor, N'proveedor'), N':<br><br>',
                       N'Habiendose efectuado el pago del ultimo entregable de la ', @EtiquetaOrden, N' ', ISNULL(@Orden, N''),
                       N' (', ISNULL(@Denominacion, N''), N'), la Autoridad Nacional de Infraestructura le remite la ',
                       N'<b>Constancia de prestacion ', @Numero, N'</b>, que se adjunta al presente correo.',
                       N'<br><br>Atentamente,<br>Autoridad Nacional de Infraestructura - SIGCM'),
                   AdjuntoDocumento = @Doc,
                   NombreAdjunto = COALESCE(@NombreDoc, CONCAT('Constancia de prestacion ', @Numero, '.pdf')),
                   Carpeta = 'pago'
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE pago.paMarcarConstanciaNotificada
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52531, 'JSON incorrecto.', 1;

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

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @IdConstancia uniqueidentifier = pago.fnConstanciaDeExpediente(@IdExpediente);
        DECLARE @Resultado nvarchar(300) = LEFT(JSON_VALUE(@parametro, '$.ResultadoCorreo'), 300);
        DECLARE @Enviado bit = CASE WHEN JSON_VALUE(@parametro, '$.CorreoEnviado') IN ('true', '1') THEN 1 ELSE 0 END;
        DECLARE @Destino varchar(200) = LEFT(JSON_VALUE(@parametro, '$.Destinatario'), 200);
        IF @IdConstancia IS NULL
            THROW 52532, 'NO_ENCONTRADO: la orden no tiene constancia emitida.', 1;

        UPDATE pago.ConstanciaPrestacion
           SET NotificadaEn = CASE WHEN @Enviado = 1 THEN GETDATE() ELSE NotificadaEn END,
               ResultadoNotificacion = @Resultado,
               CorreoDestino = COALESCE(@Destino, CorreoDestino),
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdConstancia = @IdConstancia;

        INSERT INTO sigcm.Historial (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion, Comentario,
                                     IdActor, ActorRol, IdActorUnidad, UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT e.IdExpediente, e.CodigoEstado, e.CodigoEstado, NULL,
               CONCAT(CASE WHEN @Enviado = 1 THEN N'Constancia de prestacion notificada al proveedor'
                           ELSE N'Intento de notificacion de la constancia de prestacion' END,
                      N' (', c.Numero, N')', CASE WHEN @Resultado IS NOT NULL THEN N': ' + @Resultado ELSE N'' END),
               @IdUsuario, @CodigoRol, @IdUnidad, @Cuenta, @Equipo, @Programa
          FROM pago.ConstanciaPrestacion AS c
          JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
         WHERE c.IdConstancia = @IdConstancia;

        SELECT (SELECT 1 AS estado,
                       mensaje = CASE WHEN @Enviado = 1 THEN N'Constancia de prestacion notificada al proveedor.'
                                      ELSE N'Se registro el intento de notificacion.' END
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F025 aplicada: constancia de prestacion y su notificacion.';
GO
