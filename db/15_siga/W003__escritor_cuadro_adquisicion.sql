/*
===============================================================================
  SIGCM - W003 : Escritor de cuadro de adquisicion en SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Drena integracion.Operacion con Operacion = CREAR_CUADRO_ADQUISICION y llama
  a siga.usp_ext_crear_cuadro_adquisicion_desde_pedido.

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

DECLARE @obj nvarchar(512) = @bdSiga + N'.dbo.usp_ext_crear_cuadro_adquisicion_desde_pedido';

SET @sql = N'SELECT @r = CASE WHEN OBJECT_ID(@n) IS NULL THEN 0 ELSE 1 END;';
EXEC sys.sp_executesql @sql,
     N'@r bit OUTPUT, @n nvarchar(512)',
     @r = @existe OUTPUT,
     @n = @obj;

IF OBJECT_ID(N'siga.usp_ext_crear_cuadro_adquisicion_desde_pedido', N'SN') IS NOT NULL
    DROP SYNONYM siga.usp_ext_crear_cuadro_adquisicion_desde_pedido;

IF @existe = 1
BEGIN
    SET @sql = N'CREATE SYNONYM siga.usp_ext_crear_cuadro_adquisicion_desde_pedido FOR '
             + QUOTENAME(@bdSiga) + N'.dbo.usp_ext_crear_cuadro_adquisicion_desde_pedido;';
    EXEC sys.sp_executesql @sql;
    PRINT '  Sinonimo siga.usp_ext_crear_cuadro_adquisicion_desde_pedido enlazado.';
END
ELSE
    PRINT '  [AVISO] usp_ext_crear_cuadro_adquisicion_desde_pedido no existe en SIGA; W003 solo simulara.';

DECLARE @t sysname, @sqlTab nvarchar(max);
DECLARE curTab CURSOR LOCAL FAST_FORWARD FOR
    SELECT v FROM (VALUES
        (N'SIG_DETALLE_BSERV_CUADRO'),
        (N'SIG_DETALLE_ANEXO_CUADRO'),
        (N'SIG_DETALLE_PEDIDOS_ANEXO'),
        (N'SIG_DETALLE_PEDIDOS'),
        (N'SIG_ORDEN_ITEM'),
        (N'SIG_ORDEN_ITEM_ANEXO')
    ) AS x(v);
OPEN curTab;
FETCH NEXT FROM curTab INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.synonyms
                WHERE name = @t AND SCHEMA_NAME(schema_id) = N'siga')
    BEGIN
        SET @sqlTab = N'DROP SYNONYM siga.' + QUOTENAME(@t) + N';';
        EXEC sys.sp_executesql @sqlTab;
    END
    SET @sqlTab = N'CREATE SYNONYM siga.' + QUOTENAME(@t)
                + N' FOR ' + QUOTENAME(@bdSiga) + N'.dbo.' + QUOTENAME(@t) + N';';
    EXEC sys.sp_executesql @sqlTab;
    FETCH NEXT FROM curTab INTO @t;
END
CLOSE curTab;
DEALLOCATE curTab;
PRINT '  Sinonimos de anexo TDR enlazados.';
GO

/*
  Traduce el TDR del Anexo 3 (JSON) a las tablas de rubros de SIGA.
  Si el cuadro/pedido ya tiene anexos, no pisa. Si llega NroOrden, copia
  los rubros del cuadro a SIG_ORDEN_ITEM_ANEXO.
*/
CREATE OR ALTER PROCEDURE integracion.paCopiarTdrHaciaSiga
    @AnoEje     numeric(4,0),
    @SecEjec    numeric(6,0),
    @SecCuadro  numeric(6,0),
    @NroPedido  varchar(6) = NULL,
    @NroOrden   numeric(7,0) = NULL,
    @TdrJson    nvarchar(max) = NULL,
    @Usuario    varchar(30),
    @Equipo     varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TipoBien varchar(1) = 'S';
    DECLARE @TipoPedido char(1) = '2';
    DECLARE @Ahora datetime = GETDATE();
    DECLARE @tdr nvarchar(max) = @TdrJson;

    IF ISJSON(@tdr) = 1 AND JSON_QUERY(@tdr, '$.Tdr') IS NOT NULL
        SET @tdr = JSON_QUERY(@tdr, '$.Tdr');

    IF @NroPedido IS NOT NULL
        SET @NroPedido = RIGHT('000000' + LTRIM(RTRIM(@NroPedido)), 6);

    DECLARE @rubro TABLE (
        SecAnexo numeric(6,0) NOT NULL PRIMARY KEY,
        Rubro    varchar(60)  NOT NULL,
        Texto    varchar(max) NOT NULL
    );

    IF ISJSON(ISNULL(@tdr, N'')) = 1 AND @tdr NOT IN (N'{}', N'[]', N'')
    BEGIN
        DECLARE @actividades varchar(max) =
            (SELECT STRING_AGG(CONVERT(varchar(max), LTRIM(RTRIM(a.Descripcion))), CHAR(13)+CHAR(10))
               FROM OPENJSON(@tdr, '$.Actividades')
                    WITH (Descripcion nvarchar(max) '$.Descripcion') AS a
              WHERE NULLIF(LTRIM(RTRIM(a.Descripcion)), '') IS NOT NULL);

        DECLARE @introActividades varchar(max) =
            NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.IntroActividades'))), '');

        IF @introActividades IS NOT NULL AND @actividades IS NOT NULL
            SET @actividades = @introActividades + CHAR(13)+CHAR(10) + @actividades;
        ELSE IF @introActividades IS NOT NULL
            SET @actividades = @introActividades;

        DECLARE @entregables varchar(max) =
            (SELECT STRING_AGG(CONVERT(varchar(max),
                       CONCAT(LTRIM(RTRIM(e.Nombre)),
                              CASE WHEN e.Dias IS NOT NULL
                                   THEN CONCAT(' (', CONVERT(varchar(10), e.Dias), ' dias)')
                                   ELSE '' END)), CHAR(13)+CHAR(10))
               FROM OPENJSON(@tdr, '$.Entregables')
                    WITH (Nombre nvarchar(max) '$.Nombre', Dias int '$.Dias') AS e
              WHERE NULLIF(LTRIM(RTRIM(e.Nombre)), '') IS NOT NULL);

        INSERT INTO @rubro (SecAnexo, Rubro, Texto)
        SELECT ROW_NUMBER() OVER (ORDER BY Orden), Rubro, Texto
          FROM (
                SELECT 1 AS Orden, 'Finalidad publica' AS Rubro,
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.FinalidadPublica'))), '') AS Texto
                UNION ALL SELECT 2, 'Objetivo',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.Objetivo'))), '')
                UNION ALL SELECT 3, 'Justificacion',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.Justificacion'))), '')
                UNION ALL SELECT 4, 'Proyecto',
                       CASE WHEN JSON_VALUE(@tdr, '$.EsProyecto') IN ('true','1')
                            THEN NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.NombreProyecto'))), '')
                            ELSE NULL END
                UNION ALL SELECT 5, 'Actividades', @actividades
                UNION ALL SELECT 6, 'Perfil del proveedor',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.PerfilProveedor'))), '')
                UNION ALL SELECT 7, 'Capacitacion',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.Capacitacion'))), '')
                UNION ALL SELECT 8, 'Experiencia general',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.ExperienciaGeneral'))), '')
                UNION ALL SELECT 9, 'Experiencia especifica',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.ExperienciaEspecifica'))), '')
                UNION ALL SELECT 10, 'Area usuaria',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.UnidadOrganizacional'))), '')
                UNION ALL SELECT 11, 'Unidad de conformidad',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.UnidadConformidad'))), '')
                UNION ALL SELECT 12, 'Lugar de prestacion',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.LugarPrestacion'))), '')
                UNION ALL SELECT 13, 'Entregables', @entregables
                UNION ALL SELECT 14, 'Otras penalidades',
                       NULLIF(LTRIM(RTRIM(JSON_VALUE(@tdr, '$.OtrasPenalidades'))), '')
          ) AS x
         WHERE NULLIF(LTRIM(RTRIM(x.Texto)), '') IS NOT NULL;
    END

    DECLARE @SecuenciaCuadro int = 1,
            @SecuenciaPedido numeric(4,0) = 1,
            @TipoPpto numeric(2,0) = 1,
            @SecOrden numeric(2,0) = 1,
            @SecItem numeric(4,0) = 1;

    IF @SecCuadro IS NOT NULL AND OBJECT_ID(N'siga.SIG_DETALLE_BSERV_CUADRO', N'SN') IS NOT NULL
        SELECT @SecuenciaCuadro = COALESCE(MIN(d.SECUENCIA), @SecuenciaCuadro)
          FROM siga.SIG_DETALLE_BSERV_CUADRO AS d
         WHERE d.ANO_EJE = @AnoEje AND d.SEC_EJEC = @SecEjec
           AND d.TIPO_BIEN = @TipoBien AND d.SEC_CUADRO = @SecCuadro;

    IF @NroPedido IS NOT NULL AND OBJECT_ID(N'siga.SIG_DETALLE_PEDIDOS', N'SN') IS NOT NULL
        SELECT @SecuenciaPedido = COALESCE(MIN(d.SECUENCIA), @SecuenciaPedido)
          FROM siga.SIG_DETALLE_PEDIDOS AS d
         WHERE d.ANO_EJE = @AnoEje AND d.sec_ejec = @SecEjec
           AND d.TIPO_BIEN = @TipoBien AND d.TIPO_PEDIDO = @TipoPedido
           AND d.NRO_PEDIDO = @NroPedido;

    IF @NroOrden IS NOT NULL AND OBJECT_ID(N'siga.SIG_ORDEN_ITEM', N'SN') IS NOT NULL
        SELECT TOP 1
               @TipoPpto = i.TIPO_PPTO,
               @SecOrden = i.SEC_ORDEN,
               @SecItem  = i.SEC_ITEM
          FROM siga.SIG_ORDEN_ITEM AS i
         WHERE i.ANO_EJE = @AnoEje AND i.SEC_EJEC = @SecEjec
           AND i.TIPO_BIEN = @TipoBien AND i.NRO_ORDEN = @NroOrden
         ORDER BY i.SEC_ITEM;

    IF @SecCuadro IS NOT NULL AND EXISTS (SELECT 1 FROM @rubro)
       AND NOT EXISTS (
            SELECT 1 FROM siga.SIG_DETALLE_ANEXO_CUADRO AS a
             WHERE a.ANO_EJE = @AnoEje AND a.SEC_EJEC = @SecEjec
               AND a.TIPO_BIEN = @TipoBien AND a.SEC_CUADRO = @SecCuadro)
    BEGIN
        INSERT INTO siga.SIG_DETALLE_ANEXO_CUADRO
            (ANO_EJE, SEC_EJEC, TIPO_BIEN, SEC_CUADRO, SECUENCIA, SEC_ANEXO,
             TIPO_REQUER, ANEXO_ITEM, FECHA_REG, CUSER_ID, EQUIPO_REG)
        SELECT @AnoEje, @SecEjec, @TipoBien, @SecCuadro, @SecuenciaCuadro, r.SecAnexo,
               r.Rubro, r.Texto, @Ahora, @Usuario, @Equipo
          FROM @rubro AS r;
    END

    IF @NroPedido IS NOT NULL AND EXISTS (SELECT 1 FROM @rubro)
       AND NOT EXISTS (
            SELECT 1 FROM siga.SIG_DETALLE_PEDIDOS_ANEXO AS a
             WHERE a.ANO_EJE = @AnoEje AND a.sec_ejec = @SecEjec
               AND a.TIPO_BIEN = @TipoBien AND a.TIPO_PEDIDO = @TipoPedido
               AND a.NRO_PEDIDO = @NroPedido)
    BEGIN
        INSERT INTO siga.SIG_DETALLE_PEDIDOS_ANEXO
            (ANO_EJE, sec_ejec, TIPO_BIEN, TIPO_PEDIDO, NRO_PEDIDO, SECUENCIA, SEC_ANEXO,
             TIPO_REQUER, ANEXO_ITEM, FECHA_REG, CUSER_ID, EQUIPO_REG)
        SELECT @AnoEje, @SecEjec, @TipoBien, @TipoPedido, @NroPedido, @SecuenciaPedido, r.SecAnexo,
               r.Rubro, r.Texto, @Ahora, @Usuario, @Equipo
          FROM @rubro AS r;
    END

    IF @NroOrden IS NOT NULL
       AND NOT EXISTS (
            SELECT 1 FROM siga.SIG_ORDEN_ITEM_ANEXO AS a
             WHERE a.ANO_EJE = @AnoEje AND a.SEC_EJEC = @SecEjec
               AND a.TIPO_BIEN = @TipoBien AND a.NRO_ORDEN = @NroOrden)
    BEGIN
        INSERT INTO siga.SIG_ORDEN_ITEM_ANEXO
            (ANO_EJE, SEC_EJEC, NRO_ORDEN, TIPO_BIEN, TIPO_PPTO,
             SEC_ORDEN, SEC_ITEM, SEC_ANEXO, DETALLE)
        SELECT @AnoEje, @SecEjec, @NroOrden, @TipoBien, @TipoPpto,
               @SecOrden, @SecItem, a.SEC_ANEXO,
               CONVERT(varchar(max),
                   CASE WHEN NULLIF(LTRIM(RTRIM(a.TIPO_REQUER)), '') IS NULL
                        THEN CONVERT(varchar(max), a.ANEXO_ITEM)
                        ELSE CONVERT(varchar(max), a.TIPO_REQUER) + ': '
                           + CONVERT(varchar(max), a.ANEXO_ITEM) END)
          FROM siga.SIG_DETALLE_ANEXO_CUADRO AS a
         WHERE a.ANO_EJE = @AnoEje AND a.SEC_EJEC = @SecEjec
           AND a.TIPO_BIEN = @TipoBien AND a.SEC_CUADRO = @SecCuadro;
    END
END
GO

CREATE OR ALTER PROCEDURE integracion.paEscribirCuadroAdquisicion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @haySinonimo bit = CASE
        WHEN OBJECT_ID(N'siga.usp_ext_crear_cuadro_adquisicion_desde_pedido', N'SN') IS NOT NULL
        THEN 1 ELSE 0 END;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51420, 'JSON incorrecto.', 1;

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
            THROW 51421, 'VALIDACION_PAYLOAD: Modo debe ser simulacion o real.', 1;

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
           AND o.Operacion = 'CREAR_CUADRO_ADQUISICION'
           AND o.Estado IN ('PENDIENTE', 'REINTENTO')
           AND o.ProximoIntentoEn <= @Ahora
           AND o.Intentos < o.MaxIntentos
           AND (@IdOperacion IS NULL OR o.IdOperacion = @IdOperacion)
         ORDER BY o.Secuencia, o.FechaCreacionAuditoria;

        DECLARE @detalle TABLE (
            IdOperacion uniqueidentifier NOT NULL,
            Secuencia   int              NOT NULL,
            Resultado   varchar(20)      NOT NULL,
            SecCuadro   bigint               NULL,
            NroCuadro   bigint               NULL,
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

                DECLARE @AnoEje numeric(4,0), @SecEjec numeric(6,0),
                        @NroPedido varchar(6), @SecCuadro numeric(6,0),
                        @NroCuadro numeric(6,0), @EquipoTdr varchar(20);

                SELECT @AnoEje    = j.AnoEje,
                       @SecEjec   = j.SecEjec,
                       @NroPedido = RIGHT('000000' + LTRIM(RTRIM(j.NumeroPedido)), 6)
                  FROM OPENJSON(@req)
                  WITH (AnoEje numeric(4,0), SecEjec numeric(6,0),
                        NumeroPedido varchar(20)) AS j;

                IF @AnoEje IS NULL OR @SecEjec IS NULL OR @NroPedido IS NULL
                    THROW 51422, 'INTEGRACION_PAYLOAD: faltan AnoEje, SecEjec o NumeroPedido.', 1;

                DECLARE @modoReal varchar(15) = @Modo;

                IF @Modo = 'real'
                BEGIN
                    IF @haySinonimo = 0
                        THROW 51423,
                            'INTEGRACION_NO_DISPONIBLE: falta usp_ext_crear_cuadro_adquisicion_desde_pedido en SIGA.',
                            1;

                    EXEC siga.usp_ext_crear_cuadro_adquisicion_desde_pedido
                         @AnoEje    = @AnoEje,
                         @SecEjec   = @SecEjec,
                         @NroPedido = @NroPedido,
                         @Usuario   = @Cuenta,
                         @Equipo    = @Equipo,
                         @SecCuadro = @SecCuadro OUTPUT,
                         @NroCuadro = @NroCuadro OUTPUT;

                    SET @EquipoTdr = LEFT(@Equipo, 20);
                    EXEC integracion.paCopiarTdrHaciaSiga
                         @AnoEje    = @AnoEje,
                         @SecEjec   = @SecEjec,
                         @SecCuadro = @SecCuadro,
                         @NroPedido = @NroPedido,
                         @NroOrden  = NULL,
                         @TdrJson   = @req,
                         @Usuario   = @Cuenta,
                         @Equipo    = @EquipoTdr;
                END
                ELSE
                BEGIN
                    SET @modoReal = 'simulacion';
                    SET @SecCuadro = 0;
                    SET @NroCuadro = 0;
                END

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
                                   SecCuadro = @SecCuadro,
                                   NroCuadro = @NroCuadro,
                                   NumeroPedido = @NroPedido,
                                   EnviadoASiga = CASE WHEN @modoReal = 'real'
                                                       THEN CONVERT(bit, 1) ELSE CONVERT(bit, 0) END
                              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       UsuarioModificacionAuditoria  = @Cuenta,
                       FechaModificacionAuditoria    = @Ahora,
                       EquipoModificacionAuditoria   = @Equipo,
                       ProgramaModificacionAuditoria = @Programa
                 WHERE IdOperacion = @id;

                INSERT INTO @detalle (IdOperacion, Secuencia, Resultado, SecCuadro, NroCuadro, Mensaje)
                VALUES (@id, @sec,
                        CASE WHEN @modoReal = 'real' THEN 'ESCRITO' ELSE 'SIMULADO' END,
                        CONVERT(bigint, @SecCuadro), CONVERT(bigint, @NroCuadro), NULL);
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

                INSERT INTO @detalle (IdOperacion, Secuencia, Resultado, SecCuadro, NroCuadro, Mensaje)
                VALUES (@id, @sec, 'ERROR', NULL, NULL, @err);
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
                    Detalle     = (SELECT IdOperacion, Secuencia, Resultado, SecCuadro, NroCuadro, Mensaje
                                     FROM @detalle ORDER BY Secuencia
                                      FOR JSON PATH),
                    mensaje     = 'Drenaje de cuadro de adquisicion terminado.'
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

PRINT 'W003 instalado: integracion.paEscribirCuadroAdquisicion';
GO
