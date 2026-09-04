/*
===============================================================================
  SIGCM - W004 : Escritor de la recepcion conforme en SIGA (hito 2 de pagos)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Drena integracion.Operacion con Operacion = REGISTRAR_RECEPCION_OS y llama a
  siga.usp_ext_registrar_recepcion_orden, que marca FLAG_RECEPCION = 'S' y
  FECHA_RECEPCION en SIG_ORDEN_ADQUISICION.

  Es el unico punto donde el modulo de pagos escribe en SIGA. Los otros cuatro
  hitos no tienen destino: ver SIGA/integracion/FLUJO_PAGOS.md seccion 3.

  A diferencia de W001-W003, la operacion cuelga del EXPEDIENTE DE PAGO -uno por
  entregable- y no del requerimiento. Varios entregables de la misma orden
  encolan su propia operacion; el procedimiento de SIGA es idempotente, asi que
  el primero marca la recepcion y los demas la encuentran hecha. Eso es correcto:
  la recepcion es de la orden, no del entregable, y el hito de cada expediente
  tiene que quedar anotado igual.

  Contrato de entrada/salida: identico al de W001 (Modo, Limite, Actor).
===============================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @bdSiga sysname;
DECLARE @sql nvarchar(max);
DECLARE @existe bit = 0;

SELECT TOP 1 @bdSiga = PARSENAME(base_object_name, 3)
  FROM sys.synonyms
 WHERE SCHEMA_NAME(schema_id) = N'siga'
   AND name = N'usp_ext_incluir_item_cmn';

IF @bdSiga IS NULL
    SET @bdSiga = N'SIGA_1750';

DECLARE @obj nvarchar(512) = @bdSiga + N'.dbo.usp_ext_registrar_recepcion_orden';

SET @sql = N'SELECT @r = CASE WHEN OBJECT_ID(@n) IS NULL THEN 0 ELSE 1 END;';
EXEC sys.sp_executesql @sql,
     N'@r bit OUTPUT, @n nvarchar(512)',
     @r = @existe OUTPUT,
     @n = @obj;

IF OBJECT_ID(N'siga.usp_ext_registrar_recepcion_orden', N'SN') IS NOT NULL
    DROP SYNONYM siga.usp_ext_registrar_recepcion_orden;

IF @existe = 1
BEGIN
    SET @sql = N'CREATE SYNONYM siga.usp_ext_registrar_recepcion_orden FOR '
             + QUOTENAME(@bdSiga) + N'.dbo.usp_ext_registrar_recepcion_orden;';
    EXEC sys.sp_executesql @sql;
    PRINT '  Sinonimo siga.usp_ext_registrar_recepcion_orden enlazado.';
END
ELSE
    PRINT '  [AVISO] usp_ext_registrar_recepcion_orden no existe en SIGA; W004 solo simulara.';
GO

CREATE OR ALTER PROCEDURE integracion.paEscribirRecepcionOrden
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @haySinonimo bit = CASE
        WHEN OBJECT_ID(N'siga.usp_ext_registrar_recepcion_orden', N'SN') IS NOT NULL
        THEN 1 ELSE 0 END;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51410, 'JSON incorrecto.', 1;

        DECLARE @Cuenta varchar(30) = COALESCE(
                NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Actor.Usuario'))), ''),
                'SIGCM-WORKER'),
            @Equipo varchar(50) = COALESCE(
                NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Actor.Equipo'))), ''),
                HOST_NAME()),
            @Programa varchar(50) = COALESCE(
                NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Actor.Programa'))), ''),
                'SIGCM-WORKER'),
            @Modo varchar(15) = COALESCE(
                NULLIF(LOWER(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Modo')))), ''),
                'simulacion'),
            @Limite int = COALESCE(TRY_CONVERT(int, JSON_VALUE(@parametro, '$.Limite')), 50),
            @IdOperacion uniqueidentifier =
                TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdOperacion')),
            @Ahora datetime = GETDATE();

        IF @Modo NOT IN ('simulacion', 'real')
            THROW 51411, 'VALIDACION_PAYLOAD: Modo debe ser simulacion o real.', 1;

        DECLARE @lote TABLE (
            IdOperacion     uniqueidentifier NOT NULL PRIMARY KEY,
            Secuencia       int              NOT NULL,
            IdExpediente    uniqueidentifier NOT NULL,
            IdempotenciaKey varchar(200)     NOT NULL,
            RequestJson     nvarchar(max)    NOT NULL
        );

        INSERT INTO @lote (IdOperacion, Secuencia, IdExpediente, IdempotenciaKey, RequestJson)
        SELECT TOP (@Limite)
               o.IdOperacion, o.Secuencia, o.IdExpediente, o.IdempotenciaKey, o.RequestJson
          FROM integracion.Operacion AS o
         WHERE o.Activo = 1
           AND o.Operacion = 'REGISTRAR_RECEPCION_OS'
           AND o.Estado IN ('PENDIENTE', 'REINTENTO')
           AND o.ProximoIntentoEn <= @Ahora
           AND o.Intentos < o.MaxIntentos
           AND (@IdOperacion IS NULL OR o.IdOperacion = @IdOperacion)
         ORDER BY o.Secuencia, o.FechaCreacionAuditoria;

        DECLARE @detalle TABLE (
            IdOperacion uniqueidentifier NOT NULL,
            Secuencia   int              NOT NULL,
            Resultado   varchar(20)      NOT NULL,
            NroOrden    bigint               NULL,
            Mensaje     nvarchar(400)        NULL
        );

        DECLARE @id uniqueidentifier, @sec int, @idExp uniqueidentifier,
                @clave varchar(200), @req nvarchar(max);

        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT IdOperacion, Secuencia, IdExpediente, IdempotenciaKey, RequestJson
              FROM @lote ORDER BY Secuencia;

        OPEN cur;
        FETCH NEXT FROM cur INTO @id, @sec, @idExp, @clave, @req;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                UPDATE integracion.Operacion
                   SET Estado = 'EN_PROCESO',
                       BloqueadoEn = GETDATE(),
                       BloqueadoPor = @Cuenta,
                       BloqueoToken = NEWID()
                 WHERE IdOperacion = @id;

                DECLARE @AnoEje numeric(4,0), @SecEjec numeric(6,0),
                        @NroOrden numeric(7,0), @FechaRecepcion datetime;

                SELECT @AnoEje         = j.AnoEje,
                       @SecEjec        = j.SecEjec,
                       @NroOrden       = j.NroOrden,
                       @FechaRecepcion = COALESCE(TRY_CONVERT(datetime, j.FechaRecepcion), @Ahora)
                  FROM OPENJSON(@req)
                  WITH (AnoEje numeric(4,0), SecEjec numeric(6,0),
                        NroOrden numeric(7,0), FechaRecepcion varchar(30)) AS j;

                IF @NroOrden IS NULL
                    THROW 51412,
                        'INTEGRACION_PAYLOAD: la orden no tiene numero de SIGA. Un expediente sembrado no se puede recibir en SIGA.',
                        1;

                DECLARE @modoReal varchar(15) = @Modo;
                DECLARE @Aplicados int = 0;
                DECLARE @EquipoSiga varchar(20) = LEFT(@Equipo, 20);

                IF @Modo = 'real'
                BEGIN
                    IF @haySinonimo = 0
                        THROW 51413,
                            'INTEGRACION_NO_DISPONIBLE: falta usp_ext_registrar_recepcion_orden en SIGA.',
                            1;

                    EXEC siga.usp_ext_registrar_recepcion_orden
                         @AnoEje         = @AnoEje,
                         @SecEjec        = @SecEjec,
                         @NroOrden       = @NroOrden,
                         @Usuario        = @Cuenta,
                         @FechaRecepcion = @FechaRecepcion,
                         @Equipo         = @EquipoSiga,
                         @Aplicados      = @Aplicados OUTPUT;
                END
                ELSE
                    SET @modoReal = 'simulacion';

                /* El hito deja de ser un stub: dice lo que paso en SIGA. Que
                   Aplicados sea 0 en modo real no es un fallo, es que la orden
                   ya estaba recibida -otro entregable llego primero-. */
                DECLARE @MsgHito nvarchar(400) = CASE
                    WHEN @modoReal = 'simulacion'
                        THEN N'Simulacion: no se escribio en SIGA.'
                    WHEN @Aplicados > 0
                        THEN N'Recepcion conforme registrada en SIGA (FLAG_RECEPCION = S).'
                    ELSE N'La orden ya figuraba recibida en SIGA.' END;

                DECLARE @IdPagoHito uniqueidentifier =
                    (SELECT IdExpedientePago FROM pago.ExpedientePago
                      WHERE IdExpediente = @idExp AND Activo = 1);

                DECLARE @EstadoHito varchar(20) =
                    CASE WHEN @modoReal = 'real' THEN 'REGISTRADO' ELSE 'SIMULADO' END;

                IF @IdPagoHito IS NOT NULL
                    EXEC pago.paAnotarHito @IdPagoHito, 2, 'Conformidad', 'SGCM_A_SIGA',
                         'SIG_ORDEN_ADQUISICION', @req, @EstadoHito, @MsgHito;

                UPDATE integracion.Operacion
                   SET Estado = 'COMPLETADO',
                       ModoEjecucion = @modoReal,
                       CompletadoEn = @Ahora,
                       Intentos = Intentos + 1,
                       BloqueoToken = NULL,
                       BloqueadoEn = NULL,
                       BloqueadoPor = NULL,
                       ResponseJson =
                           (SELECT Modo = @modoReal, NroOrden = @NroOrden,
                                   Aplicados = @Aplicados, Mensaje = @MsgHito
                              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       ErrorCodigo = NULL,
                       ErrorMensaje = NULL,
                       UsuarioModificacionAuditoria  = @Cuenta,
                       FechaModificacionAuditoria    = @Ahora,
                       EquipoModificacionAuditoria   = @Equipo,
                       ProgramaModificacionAuditoria = @Programa
                 WHERE IdOperacion = @id;

                INSERT INTO @detalle (IdOperacion, Secuencia, Resultado, NroOrden, Mensaje)
                VALUES (@id, @sec,
                        CASE WHEN @modoReal = 'real' THEN 'ESCRITO' ELSE 'SIMULADO' END,
                        CONVERT(bigint, @NroOrden), @MsgHito);
            END TRY
            BEGIN CATCH
                DECLARE @err nvarchar(400) = LEFT(ERROR_MESSAGE(), 400);
                DECLARE @nro int = ERROR_NUMBER();

                UPDATE integracion.Operacion
                   SET Estado = CASE WHEN Intentos + 1 >= MaxIntentos
                                     THEN 'ERROR' ELSE 'REINTENTO' END,
                       Intentos         = Intentos + 1,
                       ProximoIntentoEn = DATEADD(minute, 5 * (Intentos + 1), GETDATE()),
                       ErrorCodigo      = CONVERT(varchar(80), @nro),
                       ErrorMensaje     = @err,
                       BloqueoToken     = NULL,
                       BloqueadoEn      = NULL,
                       BloqueadoPor     = NULL,
                       UsuarioModificacionAuditoria  = @Cuenta,
                       FechaModificacionAuditoria    = @Ahora,
                       EquipoModificacionAuditoria   = @Equipo,
                       ProgramaModificacionAuditoria = @Programa
                 WHERE IdOperacion = @id;

                DECLARE @IdPagoErr uniqueidentifier =
                    (SELECT IdExpedientePago FROM pago.ExpedientePago
                      WHERE IdExpediente = @idExp AND Activo = 1);

                IF @IdPagoErr IS NOT NULL
                    EXEC pago.paAnotarHito @IdPagoErr, 2, 'Conformidad', 'SGCM_A_SIGA',
                         'SIG_ORDEN_ADQUISICION', @req, 'ERROR', @err;

                INSERT INTO @detalle (IdOperacion, Secuencia, Resultado, NroOrden, Mensaje)
                VALUES (@id, @sec, 'ERROR', NULL, @err);
            END CATCH

            FETCH NEXT FROM cur INTO @id, @sec, @idExp, @clave, @req;
        END

        CLOSE cur;
        DEALLOCATE cur;

        SET @resultado =
            (SELECT estado    = 1,
                    Modo      = @Modo,
                    Tomadas   = (SELECT COUNT(*) FROM @lote),
                    Escritas  = (SELECT COUNT(*) FROM @detalle WHERE Resultado = 'ESCRITO'),
                    Simuladas = (SELECT COUNT(*) FROM @detalle WHERE Resultado = 'SIMULADO'),
                    ConError  = (SELECT COUNT(*) FROM @detalle WHERE Resultado = 'ERROR'),
                    Detalle   = (SELECT IdOperacion, Secuencia, Resultado, NroOrden, Mensaje
                                   FROM @detalle ORDER BY Secuencia
                                    FOR JSON PATH),
                    mensaje   = 'Drenaje de recepcion de orden terminado.'
               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado AS respuesta;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'cur') >= 0
        BEGIN
            CLOSE cur;
            DEALLOCATE cur;
        END

        SET @resultado =
            (SELECT estado  = 0,
                    codigo  = ERROR_NUMBER(),
                    mensaje = ERROR_MESSAGE()
               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado AS respuesta;
    END CATCH
END
GO

PRINT 'W004 aplicada: integracion.paEscribirRecepcionOrden (hito 2).';
GO
