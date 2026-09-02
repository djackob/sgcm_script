/*
===============================================================================
  SIGCM - F012 : Entregables, conformidad, liquidacion y pago
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51900-51999

  C# es ControladorPuente. La maquina de estados es sigcm.paEjecutarTransicion
  (S017). Aqui vive lo que esa maquina no puede: abrir el expediente digital
  desde la O/S (Hito 1), validar RHE / rendiciones, dias de atraso, formula
  Anexo 10, checklist Anexo 9 y la captura de numeros SIAF (Hitos 4 y 5).

  SUNAT RHE y rendiciones de Tesoreria: STUB de homologacion. No hay API
  institucional cableada; se acepta el RHE si hay PDF+XML y se bloquea solo
  si el cliente manda ForzarRheInvalido / ForzarRendicionPendiente.

  SIGA: bitacora en pago.HitoSincronizacion. Sin DML ad hoc.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ========================================================================== */
/* 1. pago.paRegistrarHito                                                   */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paRegistrarHito
    @IdExpedientePago uniqueidentifier,
    @NumeroHito       tinyint,
    @NombreHito       varchar(80),
    @Direccion        varchar(20),
    @TablaSiga        varchar(80),
    @Payload          nvarchar(max),
    @Mensaje          nvarchar(500)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO pago.HitoSincronizacion
        (IdExpedientePago, NumeroHito, NombreHito, Direccion, TablaSiga, Payload, Estado, Mensaje)
    VALUES
        (@IdExpedientePago, @NumeroHito, @NombreHito, @Direccion, @TablaSiga,
         CASE WHEN ISJSON(@Payload) = 1 THEN @Payload ELSE NULL END,
         'STUB', @Mensaje);
END
GO

/* ========================================================================== */
/* 2. pago.paAbrirDesdeOrdenServicioInterno                                  */
/*    Sin result set. Idempotente. Un expediente PAGO por entregable.        */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paAbrirDesdeOrdenServicioInterno
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISJSON(@parametro) <> 1
        THROW 51901, 'JSON incorrecto.', 1;

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
        THROW 51902, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

    DECLARE @IdExpReq uniqueidentifier, @CodigoReq varchar(40), @AnoEje smallint,
            @Denominacion varchar(500), @Monto decimal(18,2), @PlazoDias int,
            @IdUnidadOrigen uniqueidentifier, @Datos nvarchar(max),
            @TipoCon varchar(20), @FechaInicio date, @CentroCosto varchar(15);

    SELECT @IdExpReq = r.IdExpediente, @CodigoReq = r.Codigo, @AnoEje = r.AnoEje,
           @Denominacion = r.Denominacion, @Monto = r.Monto, @PlazoDias = r.PlazoDias,
           @Datos = r.DatosAdicionales, @TipoCon = r.CodigoTipoContratacion,
           @FechaInicio = CONVERT(date, r.FechaInicioPrevisto),
           @CentroCosto = r.CentroCosto
      FROM requerimiento.Requerimiento AS r
     WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1;

    IF @IdExpReq IS NULL
        THROW 51903, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

    SELECT @IdUnidadOrigen = e.IdUnidadOrigen
      FROM sigcm.Expediente AS e WHERE e.IdExpediente = @IdExpReq;

    DECLARE @IdOrden uniqueidentifier, @NumeroOrden varchar(40),
            @NotificadoEn datetime, @FechaEmision datetime, @CorreoOs varchar(200);

    SELECT @IdOrden = o.IdOrdenServicio, @NumeroOrden = o.NumeroOrden,
           @NotificadoEn = o.NotificadoEn, @FechaEmision = o.FechaEmision,
           @CorreoOs = o.CorreoLocador
      FROM requerimiento.OrdenServicio AS o
     WHERE o.IdRequerimiento = @IdRequerimiento AND o.Activo = 1;

    IF @IdOrden IS NULL
        RETURN;

    DECLARE @Prov nvarchar(max) = COALESCE(
        JSON_QUERY(@Datos, '$.Proveedores[0]'),
        JSON_QUERY(@Datos, '$.Proveedor'));

    DECLARE @Ruc varchar(11) = NULLIF(JSON_VALUE(@Prov, '$.Ruc'), ''),
            @Dni varchar(15) = NULLIF(JSON_VALUE(@Prov, '$.Dni'), ''),
            @Nombres nvarchar(120) = ISNULL(JSON_VALUE(@Prov, '$.Nombres'), N''),
            @ApPat nvarchar(80) = ISNULL(JSON_VALUE(@Prov, '$.ApellidoPaterno'), N''),
            @ApMat nvarchar(80) = ISNULL(JSON_VALUE(@Prov, '$.ApellidoMaterno'), N''),
            @Email varchar(200) = COALESCE(NULLIF(JSON_VALUE(@Prov, '$.Email'), ''), @CorreoOs),
            @Cci varchar(20) = NULLIF(JSON_VALUE(@Prov, '$.Cci'), ''),
            @CantEnt int = ISNULL(TRY_CONVERT(int, JSON_VALUE(@Prov, '$.CantidadEntregables')), 0),
            @MontoMensual decimal(18,2) = TRY_CONVERT(decimal(18,2), JSON_VALUE(@Prov, '$.MontoMensual'));

    DECLARE @NombreLocador nvarchar(250) =
        NULLIF(LTRIM(RTRIM(CONCAT(@Nombres, N' ', @ApPat, N' ', @ApMat))), N'');

    DECLARE @Pedido varchar(20), @Clasificador varchar(20), @Meta varchar(20);
    SELECT TOP 1 @Pedido = p.NumeroPedido, @Clasificador = p.Clasificador, @Meta = p.SecFunc
      FROM requerimiento.RequerimientoPedido AS p
     WHERE p.IdRequerimiento = @IdRequerimiento AND p.Activo = 1
     ORDER BY p.FechaCreacionAuditoria;

    DECLARE @Payload nvarchar(max);
    SELECT TOP 1 @Payload = dv.Payload
      FROM sigcm.DocumentoExpediente AS de
      JOIN sigcm.Documento AS d ON d.IdDocumento = de.IdDocumento
      JOIN sigcm.DocumentoVersion AS dv
        ON dv.IdDocumento = d.IdDocumento AND dv.Version = d.VersionVigente
     WHERE de.IdExpediente = @IdExpReq
       AND d.CodigoTipoDocumento = 'REQ_TDR_LOCACION'
       AND d.Anulado = 0 AND d.Activo = 1;

    DECLARE @EntJson nvarchar(max) = COALESCE(
        JSON_QUERY(@Payload, '$.Entregables'),
        JSON_QUERY(@Payload, '$.Tdr.Entregables'));

    DECLARE @Ent TABLE (
        Numero smallint NOT NULL PRIMARY KEY,
        Nombre nvarchar(300) NOT NULL,
        Dias int NOT NULL,
        Acum int NOT NULL
    );

    IF @EntJson IS NOT NULL AND ISJSON(@EntJson) = 1
    BEGIN
        INSERT INTO @Ent (Numero, Nombre, Dias, Acum)
        SELECT ROW_NUMBER() OVER (ORDER BY TRY_CONVERT(int, e.[key])),
               LEFT(COALESCE(NULLIF(LTRIM(JSON_VALUE(e.value, '$.Nombre')), N''),
                             CONCAT(N'Entregable ', e.[key])), 300),
               CASE WHEN ISNULL(TRY_CONVERT(int, JSON_VALUE(e.value, '$.Dias')), 0) < 1
                    THEN 1 ELSE TRY_CONVERT(int, JSON_VALUE(e.value, '$.Dias')) END,
               0
          FROM OPENJSON(@EntJson) AS e;
    END

    IF NOT EXISTS (SELECT 1 FROM @Ent)
    BEGIN
        DECLARE @n smallint = CASE WHEN @CantEnt > 0 THEN @CantEnt ELSE 1 END;
        DECLARE @i smallint = 1;
        DECLARE @diasUno int = CASE WHEN @PlazoDias > 0 THEN @PlazoDias / @n ELSE 1 END;
        IF @diasUno < 1 SET @diasUno = 1;
        WHILE @i <= @n
        BEGIN
            INSERT INTO @Ent (Numero, Nombre, Dias, Acum)
            VALUES (@i, CONCAT(N'Entregable ', CONVERT(varchar(4), @i)), @diasUno, 0);
            SET @i = @i + 1;
        END
    END

    UPDATE e SET e.Acum = x.Acum
      FROM @Ent AS e
      JOIN (SELECT Numero, SUM(Dias) OVER (ORDER BY Numero) AS Acum FROM @Ent) AS x
        ON x.Numero = e.Numero;

    DECLARE @EstadoIni varchar(60);
    SELECT @EstadoIni = CodigoEstado
      FROM sigcm.Estado
     WHERE CodigoModulo = 'PAGO' AND EsInicial = 1 AND Activo = 1;
    IF @EstadoIni IS NULL
        THROW 51904, 'CONFLICTO_CONFIGURACION: el modulo PAGO no tiene estado inicial. Falta S017.', 1;

    DECLARE @IdUnidadLocador uniqueidentifier;
    SELECT TOP 1 @IdUnidadLocador = ur.IdUnidad
      FROM sigcm.UsuarioRol AS ur
      JOIN sigcm.Unidad AS n ON n.IdUnidad = ur.IdUnidad
     WHERE ur.CodigoRol = 'PROVEEDOR' AND ur.Activo = 1 AND n.Activo = 1
     ORDER BY n.Codigo;

    IF @IdUnidadLocador IS NULL
        SET @IdUnidadLocador = @IdUnidadOrigen;

    DECLARE @TotalEnt int = (SELECT COUNT(*) FROM @Ent);
    IF @TotalEnt < 1 SET @TotalEnt = 1;
    DECLARE @MontoContrato decimal(18,2) = ISNULL(@Monto, 0);
    IF @MontoContrato <= 0 AND @MontoMensual IS NOT NULL AND @CantEnt > 0
        SET @MontoContrato = ROUND(@MontoMensual * @CantEnt, 2);

    DECLARE @BaseFecha date = CONVERT(date, COALESCE(@NotificadoEn, @FechaEmision, @FechaInicio, GETDATE()));
    DECLARE @Ahora datetime = GETDATE();
    DECLARE @Numero smallint, @Nombre nvarchar(300), @Dias int, @Acum int;
    DECLARE @Codigo varchar(40), @MontoEnt decimal(18,2);
    DECLARE @IdExpPago uniqueidentifier, @IdPago uniqueidentifier;
    DECLARE @PayloadHito nvarchar(max);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT Numero, Nombre, Dias, Acum FROM @Ent ORDER BY Numero;
    OPEN c;
    FETCH NEXT FROM c INTO @Numero, @Nombre, @Dias, @Acum;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pago.ExpedientePago
                        WHERE IdRequerimiento = @IdRequerimiento
                          AND NumeroEntregable = @Numero AND Activo = 1)
        BEGIN
            SET @Codigo = NULL;
            EXEC sigcm.paSiguienteCodigo
                 'PAG', @AnoEje, N'pago.SeqExpedientePago', @Codigo OUTPUT;

            SET @MontoEnt =
                CASE WHEN @MontoMensual IS NOT NULL AND @MontoMensual > 0 THEN ROUND(@MontoMensual, 2)
                     WHEN @TotalEnt > 0 THEN ROUND(@MontoContrato / @TotalEnt, 2)
                     ELSE @MontoContrato END;
            IF @Dias < 1 SET @Dias = 1;

            INSERT INTO sigcm.Expediente
                (Codigo, CodigoModulo, CodigoTipoContratacion, AnoEje, IdUnidadOrigen,
                 CodigoEstado, IdUnidadActual, Version, IdExpedientePadre,
                 UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                 EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@Codigo, 'PAGO', @TipoCon, @AnoEje, @IdUnidadOrigen,
                 @EstadoIni, @IdUnidadLocador, 1, @IdExpReq,
                 @Cuenta, @Ahora, @Equipo, @Programa);

            SELECT @IdExpPago = IdExpediente FROM sigcm.Expediente WHERE Codigo = @Codigo;

            INSERT INTO pago.ExpedientePago
                (IdExpediente, IdRequerimiento, IdOrdenServicio, CodigoRequerimiento,
                 NumeroOrdenSiga, NumeroPedidoSiga, MetaPresupuestal, ClasificadorGasto,
                 NumeroEntregable, NombreEntregable, PlazoDias, MontoEntregable, MontoContrato,
                 PlazoContratoDias, FechaLimiteCronograma,
                 RucLocador, DniLocador, NombreLocador, CorreoLocador, Cci,
                 UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                 EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdExpPago, @IdRequerimiento, @IdOrden, @CodigoReq,
                 @NumeroOrden, @Pedido, @Meta, @Clasificador,
                 @Numero, @Nombre, @Dias, @MontoEnt, @MontoContrato,
                 @PlazoDias, DATEADD(DAY, @Acum, @BaseFecha),
                 @Ruc, @Dni, @NombreLocador, @Email, @Cci,
                 @Cuenta, @Ahora, @Equipo, @Programa);

            SELECT @IdPago = IdExpedientePago FROM pago.ExpedientePago WHERE IdExpediente = @IdExpPago;

            INSERT INTO sigcm.Historial
                (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
                 Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
                 UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdExpPago, NULL, @EstadoIni, NULL,
                 CONCAT(N'Apertura del expediente de pago del entregable ', CONVERT(varchar(4), @Numero)),
                 @IdUsuario, @CodigoRol, @IdUnidad,
                 (SELECT @CodigoReq AS CodigoRequerimiento, @NumeroOrden AS NumeroOrden,
                         @Numero AS NumeroEntregable FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                 @Cuenta, @Equipo, @Programa);

            SELECT @PayloadHito = (
                SELECT @NumeroOrden AS NumeroOrden, @Pedido AS NumeroPedido,
                       @Ruc AS Ruc, @Numero AS NumeroEntregable
                  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC pago.paRegistrarHito @IdPago, 1, 'Activa O/S', 'SIGA_A_SGCM',
                 'sg_orden_servicio / sg_detalle_orden',
                 @PayloadHito,
                 N'Expediente digital abierto desde la O/S del SGCM. Lectura SIGA pendiente de usp_ext homologado.';
        END
        FETCH NEXT FROM c INTO @Numero, @Nombre, @Dias, @Acum;
    END
    CLOSE c;
    DEALLOCATE c;
END
GO

/* ========================================================================== */
/* 3. pago.paAbrirExpedientePago  (API)                                      */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paAbrirExpedientePago
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        EXEC pago.paAbrirDesdeOrdenServicioInterno @parametro;

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        SELECT @resultado = (
            SELECT 1 AS estado,
                   N'Se abrio o confirmo el expediente digital de pago.' AS mensaje,
                   Abiertos = JSON_QUERY(COALESCE((
                       SELECT p.IdExpedientePago, p.IdExpediente, e.Codigo,
                              p.NumeroEntregable, p.NombreEntregable, e.CodigoEstado
                         FROM pago.ExpedientePago AS p
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
                        WHERE p.IdRequerimiento = @IdRequerimiento AND p.Activo = 1
                        ORDER BY p.NumeroEntregable
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 4. Subconsulta de transiciones (misma regla que F005)                     */
/* ========================================================================== */

/* ========================================================================== */
/* 5. pago.paListarPago                                                      */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paListarPago
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;

    DECLARE @resultado nvarchar(max);
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

        DECLARE @DocIdent varchar(20), @CorreoActor varchar(200);
        SELECT @DocIdent = NULLIF(DocumentoIdentidad, ''), @CorreoActor = Correo
          FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;

        DECLARE @SoloMiBandeja bit, @CodigoEstado varchar(60), @AnoEje smallint,
                @Texto varchar(200), @Limite int, @Desplazamiento int;

        SELECT @SoloMiBandeja = ISNULL(SoloMiBandeja, 1),
               @CodigoEstado  = CodigoEstado,
               @AnoEje        = AnoEje,
               @Texto         = Texto,
               @Limite        = Limite,
               @Desplazamiento = Desplazamiento
        FROM OPENJSON(@parametro, '$.Filtro')
        WITH (
            SoloMiBandeja bit, CodigoEstado varchar(60), AnoEje smallint,
            Texto varchar(200), Limite int, Desplazamiento int
        );

        SET @SoloMiBandeja  = ISNULL(@SoloMiBandeja, 1);
        SET @Limite         = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50
                                   WHEN @Limite > 200 THEN 200 ELSE @Limite END;
        SET @Desplazamiento = CASE WHEN @Desplazamiento IS NULL OR @Desplazamiento < 0
                                   THEN 0 ELSE @Desplazamiento END;

        DECLARE @Total int;
        SELECT @Total = COUNT(*)
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE e.Anulado = 0 AND e.Activo = 1 AND p.Activo = 1
           AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
           AND (@AnoEje IS NULL OR e.AnoEje = @AnoEje)
           AND (@Texto IS NULL
                OR e.Codigo LIKE '%' + @Texto + '%'
                OR p.CodigoRequerimiento LIKE '%' + @Texto + '%'
                OR p.NumeroOrdenSiga LIKE '%' + @Texto + '%'
                OR p.NombreLocador LIKE '%' + @Texto + '%')
           AND (
                @CodigoRol = 'PROVEEDOR'
                AND (
                    (@DocIdent IS NOT NULL AND (p.DniLocador = @DocIdent OR p.RucLocador = @DocIdent))
                 OR p.RucLocador = @Cuenta OR p.DniLocador = @Cuenta
                 OR (@CorreoActor IS NOT NULL AND p.CorreoLocador = @CorreoActor)
                )
             OR (@CodigoRol <> 'PROVEEDOR' AND (
                    @SoloMiBandeja = 0
                 OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol)
                ))
           );

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @Total AS total,
                   @Limite AS limite,
                   @Desplazamiento AS desplazamiento,
                   Expedientes = JSON_QUERY(COALESCE((
                       SELECT p.IdExpedientePago, e.IdExpediente, e.Codigo, e.CodigoEstado, e.Version,
                              Estado = w.Nombre, RolResponsable = w.RolResponsable,
                              p.IdRequerimiento, p.CodigoRequerimiento, p.NumeroOrdenSiga,
                              p.NumeroEntregable, p.NombreEntregable, p.PlazoDias,
                              p.MontoEntregable, p.MontoContrato, p.FechaLimiteCronograma,
                              p.FechaPresentacion, p.DiasAtraso, p.MontoPenalidad,
                              p.AlertaResolucion, p.NombreLocador, p.RucLocador, p.DniLocador,
                              p.ExpedienteSiaf, p.NotaPagoSiaf,
                              Transiciones = JSON_QUERY(COALESCE((
                                  SELECT t.CodigoTransicion, t.NombreAccion,
                                         t.CodigoEstadoDestino, EstadoDestino = d.Nombre,
                                         t.RequiereComentario, t.RequiereFirma,
                                         t.DocumentoRequerido, t.EncolaIntegracion, t.GeneraObservacion
                                    FROM sigcm.Transicion AS t
                                    JOIN sigcm.Estado AS d ON d.CodigoEstado = t.CodigoEstadoDestino
                                   WHERE t.CodigoModulo = e.CodigoModulo
                                     AND t.CodigoEstadoOrigen = e.CodigoEstado
                                     AND t.Activo = 1
                                     AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS tr
                                                  WHERE tr.CodigoTransicion = t.CodigoTransicion
                                                    AND tr.CodigoRol = @CodigoRol)
                                   ORDER BY t.CodigoTransicion
                                     FOR JSON PATH), N'[]')),
                              ActualizadoEn = ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria)
                         FROM pago.ExpedientePago AS p
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
                         JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                        WHERE e.Anulado = 0 AND e.Activo = 1 AND p.Activo = 1
                          AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
                          AND (@AnoEje IS NULL OR e.AnoEje = @AnoEje)
                          AND (@Texto IS NULL
                               OR e.Codigo LIKE '%' + @Texto + '%'
                               OR p.CodigoRequerimiento LIKE '%' + @Texto + '%'
                               OR p.NumeroOrdenSiga LIKE '%' + @Texto + '%'
                               OR p.NombreLocador LIKE '%' + @Texto + '%')
                          AND (
                               @CodigoRol = 'PROVEEDOR'
                               AND (
                                   (@DocIdent IS NOT NULL AND (p.DniLocador = @DocIdent OR p.RucLocador = @DocIdent))
                                OR p.RucLocador = @Cuenta OR p.DniLocador = @Cuenta
                                OR (@CorreoActor IS NOT NULL AND p.CorreoLocador = @CorreoActor)
                               )
                            OR (@CodigoRol <> 'PROVEEDOR' AND (
                                   @SoloMiBandeja = 0
                                OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol)
                               ))
                          )
                        ORDER BY e.FechaModificacionAuditoria DESC
                        OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 6. pago.paObtenerPago                                                     */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paObtenerPago
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51920, 'JSON incorrecto.', 1;

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
        DECLARE @IdExpedientePago uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpedientePago'));

        IF @IdExpediente IS NULL AND @IdExpedientePago IS NOT NULL
            SELECT @IdExpediente = IdExpediente FROM pago.ExpedientePago WHERE IdExpedientePago = @IdExpedientePago;

        IF @IdExpediente IS NULL
            THROW 51921, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        IF NOT EXISTS (SELECT 1 FROM pago.ExpedientePago WHERE IdExpediente = @IdExpediente AND Activo = 1)
            THROW 51922, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Expediente = JSON_QUERY((
                       SELECT p.IdExpedientePago, e.IdExpediente, e.Codigo, e.CodigoEstado, e.Version,
                              Estado = w.Nombre, RolResponsable = w.RolResponsable,
                              e.AnoEje, p.IdRequerimiento, p.CodigoRequerimiento, p.NumeroOrdenSiga,
                              p.NumeroPedidoSiga, p.MetaPresupuestal, p.ClasificadorGasto,
                              p.NumeroEntregable, p.NombreEntregable, p.PlazoDias,
                              p.MontoEntregable, p.MontoContrato, p.PlazoContratoDias,
                              p.FechaLimiteCronograma, p.FechaPresentacion, p.FechaRecepcionAu,
                              p.FechaConformidadTecnica, p.FechaLimiteSubsanacion,
                              p.RucLocador, p.DniLocador, p.NombreLocador, p.CorreoLocador,
                              p.Cci, p.Banco, p.RheSerie, p.RheNumero, p.RheValidadoSunat,
                              p.RheOrigenValidacion, p.BloqueoRendicion, p.AplicaRetencion4ta,
                              p.SubsanacionTardia, p.RetrasoJustificado, p.DiasAtraso,
                              p.PenalidadDiaria, p.MontoPenalidad, p.MontoPenalidadAcumulada,
                              p.AlertaResolucion, p.ObservacionAu, p.ObservacionUc,
                              p.DestinoDevolucionUc, p.ExpedienteSiaf, p.FechaDevengado,
                              p.NotaPagoSiaf, p.FechaAbono, p.NumeroOperacion,
                              p.RetencionCuarta, p.MontoNeto, p.ProrrogaDias, p.MotivoProrroga,
                              p.InformeDocumento, p.RhePdfDocumento, p.RheXmlDocumento,
                              p.Suspension4taDocumento, p.NotaPagoDocumento,
                              p.ConstanciaDocumento, p.PapeletaPenalidadDocumento,
                              r.Denominacion,
                              Checklist = JSON_QUERY(COALESCE((
                                  SELECT i.CodigoItem, i.Nombre, i.Orden, i.Obligatorio,
                                         Valor = ISNULL(m.Valor, N''),
                                         Observacion = m.Observacion
                                    FROM pago.ChecklistItem AS i
                                    LEFT JOIN pago.ChecklistMarca AS m
                                      ON m.CodigoItem = i.CodigoItem
                                     AND m.IdExpedientePago = p.IdExpedientePago
                                   WHERE i.Activo = 1
                                   ORDER BY i.Orden
                                     FOR JSON PATH), N'[]')),
                              Hitos = JSON_QUERY(COALESCE((
                                  SELECT h.NumeroHito, h.NombreHito, h.Direccion, h.TablaSiga,
                                         h.Estado, h.Mensaje, h.FechaHito
                                    FROM pago.HitoSincronizacion AS h
                                   WHERE h.IdExpedientePago = p.IdExpedientePago
                                   ORDER BY h.FechaHito
                                     FOR JSON PATH), N'[]')),
                              Transiciones = JSON_QUERY(COALESCE((
                                  SELECT t.CodigoTransicion, t.NombreAccion,
                                         t.CodigoEstadoDestino, EstadoDestino = d.Nombre,
                                         t.RequiereComentario, t.RequiereFirma,
                                         t.DocumentoRequerido, t.EncolaIntegracion, t.GeneraObservacion
                                    FROM sigcm.Transicion AS t
                                    JOIN sigcm.Estado AS d ON d.CodigoEstado = t.CodigoEstadoDestino
                                   WHERE t.CodigoModulo = e.CodigoModulo
                                     AND t.CodigoEstadoOrigen = e.CodigoEstado
                                     AND t.Activo = 1
                                     AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS tr
                                                  WHERE tr.CodigoTransicion = t.CodigoTransicion
                                                    AND tr.CodigoRol = @CodigoRol)
                                   ORDER BY t.CodigoTransicion
                                     FOR JSON PATH), N'[]'))
                         FROM pago.ExpedientePago AS p
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
                         JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                         JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = p.IdRequerimiento
                        WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 7. pago.paListarPortalLocador                                             */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paListarPortalLocador
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51930, 'JSON incorrecto.', 1;

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

        DECLARE @DocIdent varchar(20), @CorreoActor varchar(200);
        SELECT @DocIdent = NULLIF(DocumentoIdentidad, ''), @CorreoActor = Correo
          FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;

        /* Hito 1 diferido: abre expedientes de O/S ya emitidas que coincidan. */
        DECLARE @IdReq uniqueidentifier, @p nvarchar(max);
        DECLARE cReq CURSOR LOCAL FAST_FORWARD FOR
            SELECT r.IdRequerimiento
              FROM requerimiento.Requerimiento AS r
              JOIN requerimiento.OrdenServicio AS o ON o.IdRequerimiento = r.IdRequerimiento AND o.Activo = 1
             WHERE r.Activo = 1
               AND (
                    (@DocIdent IS NOT NULL AND (
                        JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Dni') = @DocIdent
                     OR JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Dni') = @DocIdent
                     OR JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Ruc') = @DocIdent
                     OR JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Ruc') = @DocIdent))
                 OR JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Ruc') = @Cuenta
                 OR JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Ruc') = @Cuenta
                 OR JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Dni') = @Cuenta
                 OR JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Dni') = @Cuenta
                 OR (@CorreoActor IS NOT NULL AND o.CorreoLocador = @CorreoActor)
               );
        OPEN cReq;
        FETCH NEXT FROM cReq INTO @IdReq;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                SET @p = JSON_MODIFY(@parametro, '$.IdRequerimiento', CONVERT(nvarchar(36), @IdReq));
                EXEC pago.paAbrirDesdeOrdenServicioInterno @p;
            END TRY
            BEGIN CATCH
                /* Una O/S fallida no tumba el portal. */
            END CATCH
            FETCH NEXT FROM cReq INTO @IdReq;
        END
        CLOSE cReq;
        DEALLOCATE cReq;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Ordenes = JSON_QUERY(COALESCE((
                       SELECT cab.IdRequerimiento, cab.CodigoRequerimiento, cab.NumeroOrdenSiga,
                              cab.NombreLocador, cab.RucLocador, cab.MontoContrato,
                              r.Denominacion,
                              Entregables = JSON_QUERY((
                                  SELECT p2.IdExpedientePago, e2.IdExpediente, e2.Codigo,
                                         e2.CodigoEstado, e2.Version, Estado = w2.Nombre,
                                         p2.NumeroEntregable, p2.NombreEntregable, p2.PlazoDias,
                                         p2.MontoEntregable, p2.FechaLimiteCronograma,
                                         p2.FechaPresentacion, p2.FechaLimiteSubsanacion,
                                         p2.ObservacionAu, p2.DiasAtraso,
                                         Transiciones = JSON_QUERY(COALESCE((
                                             SELECT t.CodigoTransicion, t.NombreAccion,
                                                    t.CodigoEstadoDestino, EstadoDestino = d.Nombre,
                                                    t.RequiereComentario, t.RequiereFirma,
                                                    t.DocumentoRequerido, t.EncolaIntegracion, t.GeneraObservacion
                                               FROM sigcm.Transicion AS t
                                               JOIN sigcm.Estado AS d ON d.CodigoEstado = t.CodigoEstadoDestino
                                              WHERE t.CodigoModulo = e2.CodigoModulo
                                                AND t.CodigoEstadoOrigen = e2.CodigoEstado
                                                AND t.Activo = 1
                                                AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS tr
                                                             WHERE tr.CodigoTransicion = t.CodigoTransicion
                                                               AND tr.CodigoRol = @CodigoRol)
                                              ORDER BY t.CodigoTransicion
                                                FOR JSON PATH), N'[]'))
                                    FROM pago.ExpedientePago AS p2
                                    JOIN sigcm.Expediente AS e2 ON e2.IdExpediente = p2.IdExpediente
                                    JOIN sigcm.Estado AS w2 ON w2.CodigoEstado = e2.CodigoEstado
                                   WHERE p2.IdRequerimiento = cab.IdRequerimiento AND p2.Activo = 1
                                   ORDER BY p2.NumeroEntregable
                                     FOR JSON PATH))
                         FROM (
                              SELECT p.IdRequerimiento,
                                     MAX(p.CodigoRequerimiento) AS CodigoRequerimiento,
                                     MAX(p.NumeroOrdenSiga) AS NumeroOrdenSiga,
                                     MAX(p.NombreLocador) AS NombreLocador,
                                     MAX(p.RucLocador) AS RucLocador,
                                     MAX(p.MontoContrato) AS MontoContrato
                                FROM pago.ExpedientePago AS p
                               WHERE p.Activo = 1
                                 AND (
                                      (@DocIdent IS NOT NULL AND (p.DniLocador = @DocIdent OR p.RucLocador = @DocIdent))
                                   OR p.RucLocador = @Cuenta OR p.DniLocador = @Cuenta
                                   OR (@CorreoActor IS NOT NULL AND p.CorreoLocador = @CorreoActor)
                                 )
                               GROUP BY p.IdRequerimiento
                         ) AS cab
                         JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = cab.IdRequerimiento
                        ORDER BY cab.CodigoRequerimiento
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F012 (1/2) aplicada: apertura, listados y portal del locador.';
GO

/* ========================================================================== */
/* 8. pago.paPresentarEntregable                                             */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paPresentarEntregable
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51940, 'JSON incorrecto.', 1;

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
            THROW 51941, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @Informe nvarchar(200) = NULLIF(JSON_VALUE(@parametro, '$.InformeDocumento'), '');
        DECLARE @RhePdf nvarchar(200) = NULLIF(JSON_VALUE(@parametro, '$.RhePdfDocumento'), '');
        DECLARE @RheXml nvarchar(200) = NULLIF(JSON_VALUE(@parametro, '$.RheXmlDocumento'), '');
        DECLARE @Susp nvarchar(200) = NULLIF(JSON_VALUE(@parametro, '$.Suspension4taDocumento'), '');
        DECLARE @RheSerie varchar(20) = NULLIF(JSON_VALUE(@parametro, '$.RheSerie'), '');
        DECLARE @RheNumero varchar(20) = NULLIF(JSON_VALUE(@parametro, '$.RheNumero'), '');
        DECLARE @ForzarRhe bit = CASE WHEN JSON_VALUE(@parametro, '$.ForzarRheInvalido') IN ('true','1') THEN 1 ELSE 0 END;
        DECLARE @ForzarRend bit = CASE WHEN JSON_VALUE(@parametro, '$.ForzarRendicionPendiente') IN ('true','1') THEN 1 ELSE 0 END;

        IF @Informe IS NULL OR @RhePdf IS NULL OR @RheXml IS NULL
            THROW 51942, 'VALIDACION_DOCUMENTOS: el informe (PDF) y el RHE (PDF y XML) son obligatorios.', 1;

        IF @ForzarRhe = 1
            THROW 51943, 'VALIDACION_SUNAT: el RHE no esta activo o no corresponde al RUC del locador.', 1;

        IF @ForzarRend = 1
            THROW 51944, 'VALIDACION_RENDICION: el locador tiene rendiciones de cuentas pendientes con la ANIN. No se puede cargar el entregable.', 1;

        DECLARE @IdPago uniqueidentifier, @Estado varchar(60), @Version int,
                @FechaLimiteSub datetime, @Plazo int;

        SELECT @IdPago = p.IdExpedientePago, @Estado = e.CodigoEstado, @Version = e.Version,
               @FechaLimiteSub = p.FechaLimiteSubsanacion, @Plazo = p.PlazoDias
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 51945, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        IF @Estado NOT IN ('PAG_PENDIENTE', 'PAG_OBSERVADO_AU')
            THROW 51946, 'CONFLICTO_ESTADO: el entregable no admite carga en el estado actual.', 1;

        DECLARE @Ahora datetime = GETDATE();
        DECLARE @Tardia bit = 0;
        IF @Estado = 'PAG_OBSERVADO_AU' AND @FechaLimiteSub IS NOT NULL AND @Ahora > @FechaLimiteSub
            SET @Tardia = 1;

        UPDATE pago.ExpedientePago
           SET FechaPresentacion = @Ahora,
               FechaRecepcionAu = DATEADD(DAY, 1, CONVERT(date, @Ahora)),
               InformeDocumento = @Informe,
               RhePdfDocumento = @RhePdf,
               RheXmlDocumento = @RheXml,
               Suspension4taDocumento = @Susp,
               RheSerie = @RheSerie,
               RheNumero = @RheNumero,
               RheValidadoSunat = 1,
               RheOrigenValidacion = N'STUB_HOMOLOGACION',
               BloqueoRendicion = 0,
               AplicaRetencion4ta = CASE WHEN @Susp IS NULL THEN 1 ELSE 0 END,
               SubsanacionTardia = @Tardia,
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdExpedientePago = @IdPago;

        DECLARE @CodigoTr varchar(70) = CASE WHEN @Estado = 'PAG_OBSERVADO_AU' THEN 'PAG_SUBSANAR' ELSE 'PAG_PRESENTAR' END;
        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', @CodigoTr);
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 9. pago.paObservarEntregable                                              */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paObservarEntregable
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51950, 'JSON incorrecto.', 1;

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
        DECLARE @Comentario nvarchar(max) = JSON_VALUE(@parametro, '$.Comentario');
        IF @IdExpediente IS NULL
            THROW 51951, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF NULLIF(LTRIM(@Comentario), N'') IS NULL
            THROW 51952, 'VALIDACION_PAYLOAD: las observaciones tecnicas son obligatorias.', 1;

        DECLARE @IdPago uniqueidentifier, @Plazo int, @Version int;
        SELECT @IdPago = p.IdExpedientePago, @Plazo = p.PlazoDias, @Version = e.Version
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 51953, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        DECLARE @DiasSub int = CEILING(@Plazo * 0.30);
        IF @DiasSub < 1 SET @DiasSub = 1;

        UPDATE pago.ExpedientePago
           SET ObservacionAu = @Comentario,
               FechaLimiteSubsanacion = DATEADD(DAY, @DiasSub, GETDATE()),
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdExpedientePago = @IdPago;

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'PAG_OBSERVAR_AU');
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 10. pago.paAprobarConformidadTecnica                                      */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paAprobarConformidadTecnica
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51960, 'JSON incorrecto.', 1;

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
            THROW 51961, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @Justificado bit = CASE WHEN JSON_VALUE(@parametro, '$.RetrasoJustificado') IN ('true','1') THEN 1 ELSE 0 END;

        DECLARE @IdPago uniqueidentifier, @Version int, @FechaPres datetime, @FechaLim date;
        SELECT @IdPago = p.IdExpedientePago, @Version = e.Version,
               @FechaPres = p.FechaPresentacion, @FechaLim = p.FechaLimiteCronograma
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 51962, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        DECLARE @Dias int = 0;
        IF @Justificado = 0 AND @FechaPres IS NOT NULL AND @FechaLim IS NOT NULL
           AND CONVERT(date, @FechaPres) > @FechaLim
            SET @Dias = DATEDIFF(DAY, @FechaLim, CONVERT(date, @FechaPres));

        UPDATE pago.ExpedientePago
           SET DiasAtraso = @Dias,
               RetrasoJustificado = @Justificado,
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdExpedientePago = @IdPago;

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'PAG_APROBAR_TECNICO');
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 11. pago.paMarcarConformidadFirmada  (tras PAG_FIRMAR_ANEXO11)            */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paMarcarConformidadFirmada
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51970, 'JSON incorrecto.', 1;

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
            THROW 51971, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @IdPago uniqueidentifier, @Version int, @Dias int, @FechaPres datetime;
        SELECT @IdPago = p.IdExpedientePago, @Version = e.Version,
               @Dias = p.DiasAtraso, @FechaPres = p.FechaPresentacion
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 51972, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        UPDATE pago.ExpedientePago
           SET FechaConformidadTecnica = GETDATE(),
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = GETDATE()
         WHERE IdExpedientePago = @IdPago;

        DECLARE @PayloadHito nvarchar(max) = (
            SELECT @Dias AS DiasAtraso, @FechaPres AS FechaRecepcion
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC pago.paRegistrarHito @IdPago, 2, 'Conformidad', 'SGCM_A_SIGA',
             'sg_conformidad_servicio / sg_detalle_conformidad',
             @PayloadHito,
             N'Hito 2 stub: no existe usp_ext de conformidad. El Acta 11 queda en SGCM.';

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'PAG_FIRMAR_ANEXO11');
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 12. pago.paRegistrarChecklist                                             */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paRegistrarChecklist
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51980, 'JSON incorrecto.', 1;

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
            THROW 51981, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @IdPago uniqueidentifier;
        SELECT @IdPago = IdExpedientePago FROM pago.ExpedientePago
         WHERE IdExpediente = @IdExpediente AND Activo = 1;
        IF @IdPago IS NULL
            THROW 51982, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        MERGE pago.ChecklistMarca AS d
        USING (
            SELECT CodigoItem, Valor, Observacion
              FROM OPENJSON(@parametro, '$.Checklist')
              WITH (CodigoItem varchar(40), Valor varchar(12), Observacion nvarchar(400))
             WHERE Valor IN ('SI','NO','NO_APLICA')
        ) AS s ON d.IdExpedientePago = @IdPago AND d.CodigoItem = s.CodigoItem
        WHEN MATCHED THEN
            UPDATE SET d.Valor = s.Valor, d.Observacion = s.Observacion,
                       d.UsuarioModificacionAuditoria = @Cuenta,
                       d.FechaModificacionAuditoria = GETDATE()
        WHEN NOT MATCHED THEN
            INSERT (IdExpedientePago, CodigoItem, Valor, Observacion,
                    UsuarioCreacionAuditoria, FechaCreacionAuditoria)
            VALUES (@IdPago, s.CodigoItem, s.Valor, s.Observacion, @Cuenta, GETDATE());

        SELECT @resultado = (
            SELECT 1 AS estado, N'Se registro el checklist de control de pagos (Anexo 9).' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 13. pago.paLiquidarExpediente                                             */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paLiquidarExpediente
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51990, 'JSON incorrecto.', 1;

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
            THROW 51991, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @ConfirmarAlerta bit = CASE WHEN JSON_VALUE(@parametro, '$.ConfirmarAlertaResolucion') IN ('true','1') THEN 1 ELSE 0 END;

        DECLARE @IdPago uniqueidentifier, @Version int, @IdReq uniqueidentifier,
                @MontoEnt decimal(18,2), @Plazo int, @Dias int, @MontoContrato decimal(18,2);

        SELECT @IdPago = p.IdExpedientePago, @Version = e.Version, @IdReq = p.IdRequerimiento,
               @MontoEnt = p.MontoEntregable, @Plazo = p.PlazoDias, @Dias = p.DiasAtraso,
               @MontoContrato = p.MontoContrato
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 51992, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        IF EXISTS (
            SELECT 1
              FROM pago.ChecklistItem AS i
              LEFT JOIN pago.ChecklistMarca AS m
                ON m.IdExpedientePago = @IdPago AND m.CodigoItem = i.CodigoItem
             WHERE i.Activo = 1 AND i.Obligatorio = 1
               AND ISNULL(m.Valor, N'') NOT IN ('SI', 'NO_APLICA')
        )
            THROW 51993, 'VALIDACION_ANEXO9: el checklist de control de pagos exige SI o No aplica en todos los campos obligatorios.', 1;

        DECLARE @PenDiaria decimal(18,6) = 0, @MontoPen decimal(18,2) = 0;
        IF @Dias > 0 AND @Plazo > 0 AND @MontoEnt > 0
        BEGIN
            SET @PenDiaria = (0.10 * @MontoEnt) / (0.40 * @Plazo);
            SET @MontoPen = ROUND(@PenDiaria * @Dias, 2);
        END

        DECLARE @Acum decimal(18,2) =
            ISNULL((SELECT SUM(MontoPenalidad) FROM pago.ExpedientePago
                     WHERE IdRequerimiento = @IdReq AND Activo = 1
                       AND IdExpedientePago <> @IdPago), 0) + @MontoPen;

        DECLARE @Alerta bit = CASE WHEN @MontoContrato > 0 AND @Acum > ROUND(@MontoContrato * 0.10, 2) THEN 1 ELSE 0 END;

        IF @Alerta = 1 AND @ConfirmarAlerta = 0
            THROW 51994, 'ALERTA_RESOLUCION: la sumatoria de penalidades supera el 10% del monto del contrato menor. Confirme la alerta (ConfirmarAlertaResolucion) o inicie el proceso de resolucion contractual.', 1;

        UPDATE pago.ExpedientePago
           SET PenalidadDiaria = @PenDiaria,
               MontoPenalidad = @MontoPen,
               MontoPenalidadAcumulada = @Acum,
               AlertaResolucion = @Alerta,
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdExpedientePago = @IdPago;

        DECLARE @PayloadHito nvarchar(max) = (
            SELECT @MontoPen AS MontoPenalidad, @Acum AS Acumulado, @Alerta AS AlertaResolucion
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC pago.paRegistrarHito @IdPago, 3, 'Penalidades', 'SGCM_A_SIGA',
             'sg_liquidacion_servicio / descuento en sg_conformidad_servicio',
             @PayloadHito,
             N'Hito 3 stub: el descuento se conserva en SGCM. SIGA no se actualiza sin usp_ext homologado.';

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'PAG_LIQUIDAR');
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 14. pago.paRegistrarDevengado                                             */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paRegistrarDevengado
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51995, 'JSON incorrecto.', 1;

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
        DECLARE @ExpedienteSiaf varchar(40) = NULLIF(JSON_VALUE(@parametro, '$.ExpedienteSiaf'), '');
        IF @IdExpediente IS NULL
            THROW 51996, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @ExpedienteSiaf IS NULL
            THROW 51997, 'VALIDACION_SIAF: indique el N.° de expediente SIAF del devengado.', 1;

        DECLARE @IdPago uniqueidentifier, @Version int;
        SELECT @IdPago = p.IdExpedientePago, @Version = e.Version
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;
        IF @IdPago IS NULL
            THROW 51998, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        UPDATE pago.ExpedientePago
           SET ExpedienteSiaf = @ExpedienteSiaf,
               FechaDevengado = GETDATE(),
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = GETDATE()
         WHERE IdExpedientePago = @IdPago;

        DECLARE @PayloadHito nvarchar(max) = (
            SELECT @ExpedienteSiaf AS ExpedienteSiaf FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC pago.paRegistrarHito @IdPago, 4, 'Devengado', 'SIGA_A_SGCM',
             'sg_interfaz_siaf / sg_fase_devengado',
             @PayloadHito,
             N'Hito 4: N.° SIAF capturado en SGCM. Monitoreo de interfaz pendiente de usp_ext homologado.';

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'PAG_APROBAR_DEVENGADO');
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 15. pago.paRegistrarGiro                                                  */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paRegistrarGiro
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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

        DECLARE @IdExpediente uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @NotaPago varchar(40) = NULLIF(JSON_VALUE(@parametro, '$.NotaPagoSiaf'), '');
        DECLARE @NumOp varchar(40) = NULLIF(JSON_VALUE(@parametro, '$.NumeroOperacion'), '');
        DECLARE @Cci varchar(20) = NULLIF(JSON_VALUE(@parametro, '$.Cci'), '');
        DECLARE @NotaDoc nvarchar(200) = NULLIF(JSON_VALUE(@parametro, '$.NotaPagoDocumento'), '');
        DECLARE @ConstDoc nvarchar(200) = NULLIF(JSON_VALUE(@parametro, '$.ConstanciaDocumento'), '');
        DECLARE @PapDoc nvarchar(200) = NULLIF(JSON_VALUE(@parametro, '$.PapeletaPenalidadDocumento'), '');

        IF @IdExpediente IS NULL
            THROW 51901, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @NotaPago IS NULL
            THROW 51902, 'VALIDACION_GIRO: indique el N.° de Nota de Pago SIAF.', 1;
        IF @NotaDoc IS NULL OR @ConstDoc IS NULL
            THROW 51903, 'VALIDACION_GIRO: adjunte la Nota de Pago SIAF y la constancia de transferencia.', 1;

        DECLARE @IdPago uniqueidentifier, @Version int, @MontoEnt decimal(18,2),
                @Pen decimal(18,2), @Retiene bit, @PenDocNeed decimal(18,2);

        SELECT @IdPago = p.IdExpedientePago, @Version = e.Version,
               @MontoEnt = p.MontoEntregable, @Pen = p.MontoPenalidad,
               @Retiene = p.AplicaRetencion4ta, @PenDocNeed = p.MontoPenalidad,
               @Cci = COALESCE(@Cci, p.Cci)
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 51904, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;
        IF NULLIF(@Cci, '') IS NULL
            THROW 51905, 'VALIDACION_CCI: el locador no tiene CCI. Consigne el de la cotizacion (Anexo 6).', 1;
        IF @PenDocNeed > 0 AND @PapDoc IS NULL
            THROW 51906, 'VALIDACION_GIRO: hay penalidad; adjunte la papeleta de deposito en cuentas de la ANIN.', 1;

        DECLARE @Retencion decimal(18,2) = 0;
        DECLARE @Base decimal(18,2) = ROUND(@MontoEnt - ISNULL(@Pen, 0), 2);
        IF @Retiene = 1
            SET @Retencion = ROUND(@Base * 0.08, 2);
        DECLARE @Neto decimal(18,2) = ROUND(@Base - @Retencion, 2);

        UPDATE pago.ExpedientePago
           SET NotaPagoSiaf = @NotaPago,
               NumeroOperacion = @NumOp,
               FechaAbono = GETDATE(),
               Cci = @Cci,
               NotaPagoDocumento = @NotaDoc,
               ConstanciaDocumento = @ConstDoc,
               PapeletaPenalidadDocumento = @PapDoc,
               RetencionCuarta = @Retencion,
               MontoNeto = @Neto,
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = GETDATE()
         WHERE IdExpedientePago = @IdPago;

        DECLARE @PayloadHito nvarchar(max) = (
            SELECT @NotaPago AS NotaPagoSiaf, @NumOp AS NumeroOperacion, @Cci AS Cci, @Neto AS MontoNeto
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC pago.paRegistrarHito @IdPago, 5, 'Pago cerrado', 'SIGA_A_SGCM',
             'sg_orden_pago / sg_giro_banco',
             @PayloadHito,
             N'Hito 5: giro capturado en SGCM. Lectura del estado Pagado en SIGA pendiente de usp_ext homologado.';

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'PAG_CONFIRMAR_PAGO');
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 16. pago.paRegistrarProrroga                                              */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paRegistrarProrroga
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51907, 'JSON incorrecto.', 1;

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
        DECLARE @Dias smallint = TRY_CONVERT(smallint, JSON_VALUE(@parametro, '$.ProrrogaDias'));
        DECLARE @Motivo nvarchar(500) = JSON_VALUE(@parametro, '$.MotivoProrroga');

        IF @IdExpediente IS NULL
            THROW 51908, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @Dias IS NULL OR @Dias < 1 OR @Dias > 5
            THROW 51909, 'VALIDACION_PLAZO: la prorroga es de 1 a 5 dias habiles y debe justificarse.', 1;
        IF NULLIF(LTRIM(@Motivo), N'') IS NULL
            THROW 51910, 'VALIDACION_PLAZO: indique el motivo de la prorroga.', 1;

        UPDATE p
           SET p.ProrrogaDias = @Dias,
               p.MotivoProrroga = @Motivo,
               p.UsuarioModificacionAuditoria = @Cuenta,
               p.FechaModificacionAuditoria = GETDATE()
          FROM pago.ExpedientePago AS p
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @@ROWCOUNT = 0
            THROW 51911, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado, N'Se registro la prorroga justificada del plazo de pago.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F012 aplicada: presentacion, AU, DEC, UC, UT y hitos SIGA en stub.';
GO

