/*
===============================================================================
  SIGCM - W002 : Escritor de Orden de Servicio en SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Drena integracion.Operacion con Operacion = CREAR_ORDEN_SERVICIO y llama a
  siga.usp_ext_crear_orden_servicio_desde_cuadro. Al completar, actualiza
  requerimiento.OrdenServicio con el NRO_ORDEN devuelto por SIGA.

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

DECLARE @obj nvarchar(512) = @bdSiga + N'.dbo.usp_ext_crear_orden_servicio_desde_cuadro';

SET @sql = N'SELECT @r = CASE WHEN OBJECT_ID(@n) IS NULL THEN 0 ELSE 1 END;';
EXEC sys.sp_executesql @sql,
     N'@r bit OUTPUT, @n nvarchar(512)',
     @r = @existe OUTPUT,
     @n = @obj;

IF OBJECT_ID(N'siga.usp_ext_crear_orden_servicio_desde_cuadro', N'SN') IS NOT NULL
BEGIN
    DROP SYNONYM siga.usp_ext_crear_orden_servicio_desde_cuadro;
END

IF @existe = 1
BEGIN
    SET @sql = N'CREATE SYNONYM siga.usp_ext_crear_orden_servicio_desde_cuadro FOR '
             + QUOTENAME(@bdSiga) + N'.dbo.usp_ext_crear_orden_servicio_desde_cuadro;';
    EXEC sys.sp_executesql @sql;
    PRINT '  Sinonimo siga.usp_ext_crear_orden_servicio_desde_cuadro enlazado.';
END
ELSE
BEGIN
    PRINT '  [AVISO] usp_ext_crear_orden_servicio_desde_cuadro no existe en SIGA; W002 solo simulara.';
END
GO

CREATE OR ALTER PROCEDURE integracion.paEscribirOrdenServicio
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @haySinonimo bit = CASE
        WHEN OBJECT_ID(N'siga.usp_ext_crear_orden_servicio_desde_cuadro', N'SN') IS NOT NULL
        THEN 1 ELSE 0 END;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51400, 'JSON incorrecto.', 1;

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
            THROW 51401, 'VALIDACION_PAYLOAD: Modo debe ser simulacion o real.', 1;

        DECLARE @lote TABLE (
            IdOperacion     uniqueidentifier NOT NULL PRIMARY KEY,
            Secuencia       int              NOT NULL,
            IdRequerimiento uniqueidentifier NOT NULL,
            IdempotenciaKey varchar(200)     NOT NULL,
            RequestJson     nvarchar(max)    NOT NULL
        );

        INSERT INTO @lote (IdOperacion, Secuencia, IdRequerimiento, IdempotenciaKey, RequestJson)
        SELECT TOP (@Limite)
               o.IdOperacion, o.Secuencia, o.IdRequerimiento, o.IdempotenciaKey, o.RequestJson
          FROM integracion.Operacion AS o
         WHERE o.Activo = 1
           AND o.Operacion = 'CREAR_ORDEN_SERVICIO'
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

        DECLARE @id uniqueidentifier, @sec int, @idReq uniqueidentifier,
                @clave varchar(200), @req nvarchar(max);

        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT IdOperacion, Secuencia, IdRequerimiento, IdempotenciaKey, RequestJson
              FROM @lote ORDER BY Secuencia;

        OPEN cur;
        FETCH NEXT FROM cur INTO @id, @sec, @idReq, @clave, @req;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                UPDATE integracion.Operacion
                   SET Estado = 'EN_PROCESO',
                       BloqueadoEn = GETDATE(),
                       BloqueadoPor = @Cuenta,
                       BloqueoToken = NEWID()
                 WHERE IdOperacion = @id;

                UPDATE requerimiento.OrdenServicio
                   SET EstadoIntegracion = 'EN_PROCESO',
                       IdOperacionIntegracion = @id,
                       ErrorIntegracion = NULL,
                       UsuarioModificacionAuditoria = @Cuenta,
                       FechaModificacionAuditoria = @Ahora,
                       EquipoModificacionAuditoria = @Equipo,
                       ProgramaModificacionAuditoria = @Programa
                 WHERE IdRequerimiento = @idReq AND Activo = 1;

                DECLARE @AnoEje numeric(4,0), @SecEjec numeric(6,0),
                        @SecCuadro numeric(6,0), @Proveedor numeric(5,0),
                        @FechaOrden datetime, @Concepto varchar(350),
                        @PlazoEntrega numeric(4,0), @DocumentoReferencia varchar(100);

                SELECT @AnoEje              = j.AnoEje,
                       @SecEjec             = j.SecEjec,
                       @SecCuadro           = j.SecCuadro,
                       @Proveedor           = j.Proveedor,
                       @FechaOrden          = COALESCE(TRY_CONVERT(datetime, j.FechaOrden), @Ahora),
                       @Concepto            = j.Concepto,
                       @PlazoEntrega        = j.PlazoEntrega,
                       @DocumentoReferencia = j.DocumentoReferencia
                  FROM OPENJSON(@req)
                  WITH (AnoEje numeric(4,0), SecEjec numeric(6,0),
                        SecCuadro numeric(6,0), Proveedor numeric(5,0),
                        FechaOrden varchar(30), Concepto varchar(350),
                        PlazoEntrega numeric(4,0), DocumentoReferencia varchar(100)) AS j;

                IF @SecCuadro IS NULL OR @Proveedor IS NULL
                    THROW 51402, 'INTEGRACION_PAYLOAD: faltan SecCuadro o Proveedor en el request.', 1;

                DECLARE @modoReal varchar(15) = @Modo;
                DECLARE @NroOrden numeric(7,0);
                DECLARE @EquipoTdr varchar(20);

                IF @Modo = 'real'
                BEGIN
                    IF @haySinonimo = 0
                        THROW 51403,
                            'INTEGRACION_NO_DISPONIBLE: falta usp_ext_crear_orden_servicio_desde_cuadro en SIGA.',
                            1;

                    EXEC siga.usp_ext_crear_orden_servicio_desde_cuadro
                         @AnoEje              = @AnoEje,
                         @SecEjec             = @SecEjec,
                         @SecCuadro           = @SecCuadro,
                         @Proveedor           = @Proveedor,
                         @FechaOrden          = @FechaOrden,
                         @Usuario             = @Cuenta,
                         @Equipo              = @Equipo,
                         @DocumentoReferencia = @DocumentoReferencia,
                         @Concepto            = @Concepto,
                         @PlazoEntrega        = @PlazoEntrega,
                         @NroOrden            = @NroOrden OUTPUT;

                    SET @EquipoTdr = LEFT(@Equipo, 20);
                    EXEC integracion.paCopiarTdrHaciaSiga
                         @AnoEje    = @AnoEje,
                         @SecEjec   = @SecEjec,
                         @SecCuadro = @SecCuadro,
                         @NroPedido = NULL,
                         @NroOrden  = @NroOrden,
                         @TdrJson   = NULL,
                         @Usuario   = @Cuenta,
                         @Equipo    = @EquipoTdr;
                END
                ELSE
                BEGIN
                    SET @modoReal = 'simulacion';
                    SET @NroOrden = 9999999;
                END

                UPDATE requerimiento.OrdenServicio
                   SET NumeroOrden = CONVERT(varchar(40), @NroOrden),
                       SecCuadroSiga = @SecCuadro,
                       ProveedorSiga = @Proveedor,
                       FechaEmision = COALESCE(FechaEmision, @Ahora),
                       EstadoIntegracion = CASE WHEN @modoReal = 'real'
                                                THEN 'COMPLETADO' ELSE 'SIMULADO' END,
                       ErrorIntegracion = NULL,
                       UsuarioModificacionAuditoria = @Cuenta,
                       FechaModificacionAuditoria = @Ahora,
                       EquipoModificacionAuditoria = @Equipo,
                       ProgramaModificacionAuditoria = @Programa
                 WHERE IdRequerimiento = @idReq AND Activo = 1;

                UPDATE integracion.Operacion
                   SET Estado = 'COMPLETADO',
                       ModoEjecucion = @modoReal,
                       CompletadoEn = @Ahora,
                       Intentos = Intentos + 1,
                       BloqueoToken = NULL,
                       BloqueadoEn = NULL,
                       BloqueadoPor = NULL,
                       ResponseJson =
                           (SELECT Modo = @modoReal,
                                   NroOrden = @NroOrden,
                                   SecCuadro = @SecCuadro,
                                   Proveedor = @Proveedor,
                                   EnviadoASiga = CASE WHEN @modoReal = 'real'
                                                       THEN CONVERT(bit, 1) ELSE CONVERT(bit, 0) END
                              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       UsuarioModificacionAuditoria  = @Cuenta,
                       FechaModificacionAuditoria    = @Ahora,
                       EquipoModificacionAuditoria   = @Equipo,
                       ProgramaModificacionAuditoria = @Programa
                 WHERE IdOperacion = @id;

                INSERT INTO @detalle (IdOperacion, Secuencia, Resultado, NroOrden, Mensaje)
                VALUES (@id, @sec,
                        CASE WHEN @modoReal = 'real' THEN 'ESCRITO' ELSE 'SIMULADO' END,
                        CONVERT(bigint, @NroOrden), NULL);
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

                UPDATE requerimiento.OrdenServicio
                   SET EstadoIntegracion = 'ERROR',
                       ErrorIntegracion = @err,
                       UsuarioModificacionAuditoria = @Cuenta,
                       FechaModificacionAuditoria = @Ahora,
                       EquipoModificacionAuditoria = @Equipo,
                       ProgramaModificacionAuditoria = @Programa
                 WHERE IdRequerimiento = @idReq AND Activo = 1;

                INSERT INTO @detalle (IdOperacion, Secuencia, Resultado, NroOrden, Mensaje)
                VALUES (@id, @sec, 'ERROR', NULL, @err);
            END CATCH

            FETCH NEXT FROM cur INTO @id, @sec, @idReq, @clave, @req;
        END

        CLOSE cur;
        DEALLOCATE cur;

        SET @resultado =
            (SELECT estado      = 1,
                    Modo        = @Modo,
                    Tomadas     = (SELECT COUNT(*) FROM @lote),
                    Escritas    = (SELECT COUNT(*) FROM @detalle WHERE Resultado = 'ESCRITO'),
                    Simuladas   = (SELECT COUNT(*) FROM @detalle WHERE Resultado = 'SIMULADO'),
                    ConError    = (SELECT COUNT(*) FROM @detalle WHERE Resultado = 'ERROR'),
                    Detalle     = (SELECT IdOperacion, Secuencia, Resultado, NroOrden, Mensaje
                                     FROM @detalle ORDER BY Secuencia
                                      FOR JSON PATH),
                    mensaje     = 'Drenaje de orden de servicio terminado.'
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

PRINT 'W002 instalado: integracion.paEscribirOrdenServicio';
GO
