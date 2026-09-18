/*
===============================================================================
  SIGCM - F018 : Resolucion del contrato menor
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 52200-52299

  Directiva 002-2026-ANIN 7.3.7. Bizagi "5. RESOLUCION" (cinco diagramas).
  Analisis en docs/analisis-modulos-modificacion-resolucion.md.

  La maquina de estados es sigcm.paEjecutarTransicion (S040). Aqui vive lo que
  ella no puede:

    - abrir el procedimiento sobre un contrato VIGENTE por su causal, con dos
      entradas: el AU informa (a-f, unilateral) o el proveedor solicita (mutuo
      acuerdo, hecho sobreviniente);
    - calcular el rango del plazo de apercibimiento (7.3.7.2.b): 10 %-15 % del
      plazo vigente, redondeo hacia arriba, tres dias si el plazo es menor a 30;
    - guardar pronunciamientos, respuesta del proveedor, cartas y medios de
      notificacion;
    - al firmar la carta de resolucion, CERRAR EL CONTRATO en Ejecucion
      (EJE_RESOLVER) en la misma llamada;
    - armar el sobre del correo (7.3.7.3) y marcar el resultado.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE resolucion.paMoverProcedimientoInterno
    @parametro        nvarchar(max),
    @IdProcedimiento  uniqueidentifier,
    @CodigoTransicion varchar(70)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdExpediente uniqueidentifier, @IdContrato uniqueidentifier, @Version int,
            @EstadoDestino varchar(60), @RolDestino varchar(40), @IdUnidadDestino uniqueidentifier;

    SELECT @IdExpediente = p.IdExpediente, @IdContrato = p.IdContrato, @Version = e.Version
      FROM resolucion.Procedimiento AS p JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
     WHERE p.IdProcedimiento = @IdProcedimiento AND p.Activo = 1;
    IF @IdExpediente IS NULL THROW 52201, 'NO_ENCONTRADO: el procedimiento no existe.', 1;

    SELECT @EstadoDestino = CodigoEstadoDestino FROM sigcm.Transicion WHERE CodigoTransicion = @CodigoTransicion AND Activo = 1;
    SELECT @RolDestino = RolResponsable FROM sigcm.Estado WHERE CodigoEstado = @EstadoDestino;
    EXEC ejecucion.paResolverUnidadDestinoInterno @IdContrato, @RolDestino, @IdUnidadDestino OUTPUT;

    SET @parametro = JSON_MODIFY(@parametro, '$.IdExpediente', CONVERT(nvarchar(36), @IdExpediente));
    SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', @CodigoTransicion);
    IF JSON_VALUE(@parametro, '$.Version') IS NULL
        SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);
    IF @IdUnidadDestino IS NOT NULL
        SET @parametro = JSON_MODIFY(@parametro, '$.IdUnidadDestino', CONVERT(nvarchar(36), @IdUnidadDestino));

    EXEC sigcm.paEjecutarTransicion @parametro;
END
GO

CREATE OR ALTER FUNCTION resolucion.fnTransicionesJson (@CodigoEstado varchar(60), @CodigoRol varchar(40))
RETURNS nvarchar(max)
AS
BEGIN
    RETURN COALESCE((
        SELECT t.CodigoTransicion, t.NombreAccion, t.CodigoEstadoDestino, EstadoDestino = d.Nombre,
               t.RequiereComentario, t.RequiereFirma, t.DocumentoRequerido, t.EncolaIntegracion, t.GeneraObservacion
          FROM sigcm.Transicion AS t JOIN sigcm.Estado AS d ON d.CodigoEstado = t.CodigoEstadoDestino
         WHERE t.CodigoModulo = 'RESOLUCION' AND t.CodigoEstadoOrigen = @CodigoEstado AND t.Activo = 1
           AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS tr WHERE tr.CodigoTransicion = t.CodigoTransicion AND tr.CodigoRol = @CodigoRol)
         ORDER BY t.CodigoTransicion FOR JSON PATH), N'[]');
END
GO

/* ========================================================================== */
/* 1. resolucion.paRegistrarProcedimiento                                    */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE resolucion.paRegistrarProcedimiento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52210, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdContrato uniqueidentifier, @Causal varchar(25), @Alcance varchar(10), @Parte nvarchar(1000),
                @Hechos nvarchar(max), @Doc nvarchar(200);
        SELECT @IdContrato = TRY_CONVERT(uniqueidentifier, IdContrato), @Causal = UPPER(NULLIF(LTRIM(RTRIM(Causal)), '')),
               @Alcance = COALESCE(UPPER(NULLIF(LTRIM(RTRIM(Alcance)), '')), 'TOTAL'), @Parte = NULLIF(LTRIM(RTRIM(ParteResuelta)), N''),
               @Hechos = NULLIF(LTRIM(RTRIM(Hechos)), N''), @Doc = NULLIF(LTRIM(RTRIM(Documento)), N'')
          FROM OPENJSON(@parametro) WITH (IdContrato varchar(50), Causal varchar(25), Alcance varchar(10), ParteResuelta nvarchar(1000),
                                          Hechos nvarchar(max), Documento nvarchar(200));

        IF @IdContrato IS NULL THROW 52211, 'VALIDACION_PAYLOAD: falta IdContrato.', 1;
        IF @Causal NOT IN ('INCUMPLIMIENTO','CASO_FORTUITO','HECHO_SOBREVINIENTE','ANTICORRUPCION','DOCUMENTACION_FALSA','PENALIDAD_MAXIMA','MUTUO_ACUERDO','UNILATERAL')
            THROW 52212, 'VALIDACION_CAUSAL: la causal no es una de las del numeral 7.3.7.1.', 1;
        IF @Hechos IS NULL THROW 52213, 'VALIDACION_PAYLOAD: describa los hechos que configuran la causal.', 1;
        IF @Alcance NOT IN ('TOTAL', 'PARCIAL') THROW 52214, 'VALIDACION_ALCANCE: el alcance es TOTAL o PARCIAL.', 1;
        IF @Alcance = 'PARCIAL' AND @Parte IS NULL THROW 52215, 'VALIDACION_ALCANCE: la resolucion parcial debe precisar que parte del contrato queda resuelta (7.3.7.5).', 1;

        DECLARE @Origen varchar(15) = CASE WHEN @CodigoRol = 'PROVEEDOR' THEN 'PROVEEDOR' WHEN @CodigoRol LIKE 'AREA[_]%' THEN 'AREA_USUARIA' END;
        IF @Origen IS NULL THROW 52216, 'NO_AUTORIZADO: el procedimiento lo inicia el area usuaria o el proveedor.', 1;
        IF @Origen = 'PROVEEDOR' AND @Causal NOT IN ('MUTUO_ACUERDO', 'HECHO_SOBREVINIENTE')
            THROW 52217, 'CONFLICTO_CAUSAL: el proveedor solo puede solicitar la resolucion por mutuo acuerdo o por hecho sobreviniente.', 1;

        DECLARE @IdExpContrato uniqueidentifier, @IdUnidadOrigen uniqueidentifier, @EsFinal bit, @AnoEje smallint, @TipoCon varchar(20),
                @CodigoContrato varchar(40), @FechaInicio date, @FechaFin date, @Ruc varchar(11), @Dni varchar(15), @Correo varchar(200),
                @MontoContrato decimal(18,2), @IdRequerimiento uniqueidentifier;
        SELECT @IdExpContrato = c.IdExpediente, @IdUnidadOrigen = e.IdUnidadOrigen, @EsFinal = w.EsFinal, @AnoEje = e.AnoEje,
               @TipoCon = e.CodigoTipoContratacion, @CodigoContrato = e.Codigo, @FechaInicio = c.FechaInicio, @FechaFin = c.FechaFinPrevista,
               @Ruc = c.RucProveedor, @Dni = c.DniProveedor, @Correo = c.CorreoProveedor, @MontoContrato = c.MontoContrato, @IdRequerimiento = c.IdRequerimiento
          FROM ejecucion.Contrato AS c JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE c.IdContrato = @IdContrato AND c.Activo = 1;
        IF @IdExpContrato IS NULL THROW 52218, 'NO_ENCONTRADO: el contrato no existe.', 1;
        IF @EsFinal = 1 THROW 52219, 'CONFLICTO_ESTADO: el contrato ya no esta en ejecucion.', 1;
        IF @Origen = 'AREA_USUARIA' AND @IdUnidad <> @IdUnidadOrigen THROW 52220, 'NO_AUTORIZADO: el contrato no pertenece a su area usuaria.', 1;
        IF @Origen = 'PROVEEDOR'
        BEGIN
            DECLARE @DocActor varchar(20), @CorreoActor varchar(200);
            SELECT @DocActor = NULLIF(DocumentoIdentidad, ''), @CorreoActor = Correo FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;
            IF NOT ((@DocActor IS NOT NULL AND (@Ruc = @DocActor OR @Dni = @DocActor)) OR @Ruc = @Cuenta OR @Dni = @Cuenta
                    OR (@CorreoActor IS NOT NULL AND @Correo = @CorreoActor))
                THROW 52221, 'NO_AUTORIZADO: este contrato no corresponde al proveedor que ingreso.', 1;
        END
        IF EXISTS (SELECT 1 FROM resolucion.Procedimiento AS p JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
                   JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado WHERE p.IdContrato = @IdContrato AND p.Activo = 1 AND w.EsFinal = 0)
            THROW 52222, 'CONFLICTO_ESTADO: ya hay un procedimiento de resolucion en tramite para este contrato.', 1;

        /* 7.3.7.1.f: la causal de penalidad maxima se comprueba contra lo acumulado en Pagos. */
        IF @Causal = 'PENALIDAD_MAXIMA'
        BEGIN
            DECLARE @Penalidad decimal(18,2) = (SELECT ISNULL(SUM(p.MontoPenalidad), 0) FROM pago.ExpedientePago AS p WHERE p.IdRequerimiento = @IdRequerimiento AND p.Activo = 1);
            IF @MontoContrato > 0 AND @Penalidad <= @MontoContrato * 0.10
            BEGIN
                DECLARE @errPen nvarchar(400) = CONCAT('CONFLICTO_CAUSAL: las penalidades acumuladas (S/ ', CONVERT(varchar(20), @Penalidad),
                    ') no superan el 10 % del contrato (S/ ', CONVERT(varchar(20), @MontoContrato * 0.10), ').');
                THROW 52223, @errPen, 1;
            END
        END

        /* 7.3.7.2.b: rango del apercibimiento sobre el plazo vigente. */
        DECLARE @PlazoBase int = DATEDIFF(DAY, @FechaInicio, @FechaFin) + 1;
        IF @PlazoBase < 1 SET @PlazoBase = 1;
        DECLARE @Min int, @Max int;
        IF @PlazoBase < 30 BEGIN SET @Min = 3; SET @Max = 3; END
        ELSE BEGIN SET @Min = CEILING(@PlazoBase * 0.10); SET @Max = CEILING(@PlazoBase * 0.15); END
        DECLARE @Requiere bit = CASE WHEN @Causal = 'INCUMPLIMIENTO' THEN 1 ELSE 0 END;

        DECLARE @EstadoIni varchar(60) = CASE WHEN @Origen = 'PROVEEDOR' THEN 'RES_SOLICITADA' ELSE 'RES_INFORMADA' END;
        DECLARE @RolIni varchar(40);
        SELECT @RolIni = RolResponsable FROM sigcm.Estado WHERE CodigoEstado = @EstadoIni AND Activo = 1;
        IF @RolIni IS NULL THROW 52224, 'CONFLICTO_CONFIGURACION: faltan los estados del modulo. Falta S040.', 1;

        DECLARE @IdUnidadDestino uniqueidentifier;
        EXEC ejecucion.paResolverUnidadDestinoInterno @IdContrato, @RolIni, @IdUnidadDestino OUTPUT;
        IF @IdUnidadDestino IS NULL SET @IdUnidadDestino = @IdUnidadOrigen;

        DECLARE @Codigo varchar(40), @Ahora datetime = GETDATE(), @IdExp uniqueidentifier, @IdProc uniqueidentifier;

        BEGIN TRANSACTION;

        EXEC sigcm.paSiguienteCodigo 'RES', @AnoEje, N'resolucion.SeqProcedimiento', @Codigo OUTPUT;

        INSERT INTO sigcm.Expediente
            (Codigo, CodigoModulo, CodigoTipoContratacion, AnoEje, IdUnidadOrigen, CodigoEstado, IdUnidadActual, Version, IdExpedientePadre,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES (@Codigo, 'RESOLUCION', @TipoCon, @AnoEje, @IdUnidadOrigen, @EstadoIni, @IdUnidadDestino, 1, @IdExpContrato,
                @Cuenta, @Ahora, @Equipo, @Programa);
        SELECT @IdExp = IdExpediente FROM sigcm.Expediente WHERE Codigo = @Codigo;

        INSERT INTO resolucion.Procedimiento
            (IdExpediente, IdContrato, Causal, Origen, Alcance, ParteResuelta, FechaInicio, Hechos,
             InformeAuDocumento, SolicitudDocumento, RequiereApercibimiento, PlazoBaseDias, PlazoApercibimientoMin, PlazoApercibimientoMax,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES (@IdExp, @IdContrato, @Causal, @Origen, @Alcance, @Parte, @Ahora, @Hechos,
                CASE WHEN @Origen = 'AREA_USUARIA' THEN @Doc END, CASE WHEN @Origen = 'PROVEEDOR' THEN @Doc END,
                @Requiere, @PlazoBase, @Min, @Max,
                @Cuenta, @Ahora, @Equipo, @Programa);
        SELECT @IdProc = IdProcedimiento FROM resolucion.Procedimiento WHERE IdExpediente = @IdExp;

        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion, Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES (@IdExp, NULL, @EstadoIni, NULL,
                CONCAT(CASE WHEN @Origen = 'PROVEEDOR' THEN N'Solicitud de resolucion del proveedor' ELSE N'Causal de resolucion informada por el area usuaria' END,
                       N' (', @Causal, N', ', @Alcance, N'): ', LEFT(@Hechos, 400)),
                @IdUsuario, @CodigoRol, @IdUnidad,
                (SELECT @CodigoContrato AS Contrato, @Causal AS Causal, @Alcance AS Alcance, @Requiere AS RequiereApercibimiento,
                        @Min AS PlazoMin, @Max AS PlazoMax FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                @Cuenta, @Equipo, @Programa);

        EXEC sigcm.paRegistrarAuditoria @CorrelacionId, 'RESOLUCION', 'resolucion.Procedimiento', @IdExp,
             'REGISTRAR_PROCEDIMIENTO', 'OK', @IdUsuario, @Cuenta, @CodigoRol, @IdUnidad, @Ip, @Equipo, @Programa, NULL, @parametro;

        COMMIT TRANSACTION;

        SELECT @resultado = (
            SELECT 1 AS estado, @IdProc AS IdProcedimiento, @IdExp AS IdExpediente, @Codigo AS Codigo, @EstadoIni AS CodigoEstado,
                   RequiereApercibimiento = @Requiere, PlazoApercibimientoMin = @Min, PlazoApercibimientoMax = @Max,
                   N'Se registro el procedimiento de resolucion.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 2. resolucion.paListarProcedimiento                                       */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE resolucion.paListarProcedimiento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52230, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @DocIdent varchar(20), @CorreoActor varchar(200);
        SELECT @DocIdent = NULLIF(DocumentoIdentidad, ''), @CorreoActor = Correo FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;

        DECLARE @SoloMiBandeja bit, @Causal varchar(25), @CodigoEstado varchar(60), @Texto varchar(200),
                @Limite int, @Desplazamiento int, @SoloVigentes bit, @IdContrato uniqueidentifier;
        SELECT @SoloMiBandeja = SoloMiBandeja, @Causal = Causal, @CodigoEstado = CodigoEstado, @Texto = Texto,
               @Limite = Limite, @Desplazamiento = Desplazamiento, @SoloVigentes = SoloVigentes, @IdContrato = TRY_CONVERT(uniqueidentifier, IdContrato)
          FROM OPENJSON(@parametro, '$.Filtro')
          WITH (SoloMiBandeja bit, Causal varchar(25), CodigoEstado varchar(60), Texto varchar(200), Limite int, Desplazamiento int, SoloVigentes bit, IdContrato varchar(50));
        SET @SoloMiBandeja = ISNULL(@SoloMiBandeja, 1); SET @SoloVigentes = ISNULL(@SoloVigentes, 0);
        SET @Limite = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50 WHEN @Limite > 200 THEN 200 ELSE @Limite END;
        SET @Desplazamiento = CASE WHEN @Desplazamiento IS NULL OR @Desplazamiento < 0 THEN 0 ELSE @Desplazamiento END;

        CREATE TABLE #Visible (IdProcedimiento uniqueidentifier PRIMARY KEY, MeToca bit NOT NULL);
        INSERT INTO #Visible
        SELECT p.IdProcedimiento, CONVERT(bit, CASE WHEN e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol THEN 1 ELSE 0 END)
          FROM resolucion.Procedimiento AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
          JOIN ejecucion.Contrato AS c ON c.IdContrato = p.IdContrato
         WHERE e.Anulado = 0 AND e.Activo = 1 AND p.Activo = 1
           AND (@Causal IS NULL OR p.Causal = @Causal)
           AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
           AND (@IdContrato IS NULL OR p.IdContrato = @IdContrato)
           AND (@SoloVigentes = 0 OR w.EsFinal = 0)
           AND (@Texto IS NULL OR e.Codigo LIKE '%' + @Texto + '%' OR c.CodigoRequerimiento LIKE '%' + @Texto + '%'
                OR c.NumeroOrdenSiga LIKE '%' + @Texto + '%' OR c.NombreProveedor LIKE '%' + @Texto + '%')
           AND (
                @CodigoRol = 'PROVEEDOR'
                AND ((@DocIdent IS NOT NULL AND (c.DniProveedor = @DocIdent OR c.RucProveedor = @DocIdent))
                     OR c.RucProveedor = @Cuenta OR c.DniProveedor = @Cuenta OR (@CorreoActor IS NOT NULL AND c.CorreoProveedor = @CorreoActor))
             OR (@CodigoRol <> 'PROVEEDOR' AND (
                    @SoloMiBandeja = 0 OR e.IdUnidadActual = @IdUnidad OR e.IdUnidadOrigen = @IdUnidad
                 OR @CodigoRol LIKE 'ABAST[_]%' OR @CodigoRol IN ('OA', 'ADMIN_SISTEMA')
                 OR EXISTS (SELECT 1 FROM sigcm.Historial AS h WHERE h.IdExpediente = e.IdExpediente AND (h.IdActor = @IdUsuario OR h.IdActorUnidad = @IdUnidad))))
           );

        DECLARE @Total int = (SELECT COUNT(*) FROM #Visible);
        DECLARE @Hoy date = CONVERT(date, GETDATE());

        SELECT @resultado = (
            SELECT 1 AS estado, @Total AS total, @Limite AS limite, @Desplazamiento AS desplazamiento,
                   Procedimientos = JSON_QUERY(COALESCE((
                       SELECT p.IdProcedimiento, e.IdExpediente, e.Codigo, e.CodigoEstado, e.Version, Estado = w.Nombre,
                              RolResponsable = w.RolResponsable, EsFinal = w.EsFinal, MeToca = v.MeToca,
                              p.IdContrato, ContratoCodigo = ec.Codigo, c.CodigoRequerimiento, c.NumeroOrdenSiga, c.Denominacion,
                              c.NombreProveedor, c.RucProveedor, c.DniProveedor, UnidadOrigen = uo.Sigla,
                              p.Causal, p.Origen, p.Alcance, p.FechaInicio, p.RequiereApercibimiento, p.FechaLimiteSubsanacion,
                              DiasSubsanacion = CASE WHEN e.CodigoEstado = 'RES_APERCIBIDO' THEN DATEDIFF(DAY, @Hoy, p.FechaLimiteSubsanacion) END,
                              p.ResultadoApercibimiento, p.ResultadoDec, p.FechaResolucion, p.NotificadaEn,
                              Transiciones = JSON_QUERY(resolucion.fnTransicionesJson(e.CodigoEstado, @CodigoRol)),
                              ActualizadoEn = ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria)
                         FROM #Visible AS v
                         JOIN resolucion.Procedimiento AS p ON p.IdProcedimiento = v.IdProcedimiento
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
                         JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                         JOIN ejecucion.Contrato AS c ON c.IdContrato = p.IdContrato
                         JOIN sigcm.Expediente AS ec ON ec.IdExpediente = c.IdExpediente
                         JOIN sigcm.Unidad AS uo ON uo.IdUnidad = e.IdUnidadOrigen
                        ORDER BY v.MeToca DESC, w.EsFinal, p.FechaInicio DESC
                        OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        DROP TABLE #Visible;
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF OBJECT_ID('tempdb..#Visible') IS NOT NULL DROP TABLE #Visible;
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 3. resolucion.paObtenerProcedimiento                                      */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE resolucion.paObtenerProcedimiento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52240, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdProc uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdProcedimiento'));
        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        IF @IdProc IS NULL AND @IdExpediente IS NOT NULL
            SELECT @IdProc = IdProcedimiento FROM resolucion.Procedimiento WHERE IdExpediente = @IdExpediente AND Activo = 1;
        IF @IdProc IS NULL THROW 52241, 'VALIDACION_PAYLOAD: falta IdProcedimiento o IdExpediente.', 1;
        IF NOT EXISTS (SELECT 1 FROM resolucion.Procedimiento WHERE IdProcedimiento = @IdProc AND Activo = 1)
            THROW 52242, 'NO_ENCONTRADO: el procedimiento no existe.', 1;

        DECLARE @Hoy date = CONVERT(date, GETDATE());

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Procedimiento = JSON_QUERY((
                       SELECT p.IdProcedimiento, e.IdExpediente, e.Codigo, e.CodigoEstado, e.Version, Estado = w.Nombre,
                              RolResponsable = w.RolResponsable, EsFinal = w.EsFinal, e.AnoEje,
                              MeToca = CONVERT(bit, CASE WHEN e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol THEN 1 ELSE 0 END),
                              p.IdContrato, ContratoCodigo = ec.Codigo, ContratoEstado = ec.CodigoEstado,
                              c.CodigoRequerimiento, c.NumeroOrdenSiga, c.Denominacion, c.TipoPrestacion, c.MontoContrato,
                              c.FechaInicio AS ContratoInicio, c.FechaFinPrevista AS ContratoFin, c.PlazoDias,
                              PenalidadAcumulada = (SELECT ISNULL(SUM(pg.MontoPenalidad), 0) FROM pago.ExpedientePago AS pg WHERE pg.IdRequerimiento = c.IdRequerimiento AND pg.Activo = 1),
                              c.NombreProveedor, c.RucProveedor, c.DniProveedor, c.CorreoProveedor,
                              UnidadOrigen = uo.Sigla, UnidadOrigenNombre = uo.Nombre,
                              p.Causal, p.Origen, p.Alcance, p.ParteResuelta, p.FechaInicio, p.Hechos, p.InformeAuDocumento, p.SolicitudDocumento,
                              p.PronunciamientoAu, p.InformeAu, p.PronunciamientoEn,
                              p.RequiereApercibimiento, p.PlazoBaseDias, p.PlazoApercibimientoMin, p.PlazoApercibimientoMax, p.PlazoApercibimientoDias,
                              p.NumeroCartaApercibimiento, p.CartaApercibimientoDocumento, p.ApercibimientoNotificadoEn, p.FechaLimiteSubsanacion,
                              DiasSubsanacion = CASE WHEN e.CodigoEstado = 'RES_APERCIBIDO' THEN DATEDIFF(DAY, @Hoy, p.FechaLimiteSubsanacion) END,
                              p.RespuestaProveedor, p.RespuestaDocumento, p.RespondidaEn, p.ResultadoApercibimiento,
                              p.ResultadoDec, p.MotivoDec, p.DecisionEn,
                              DecisionPor = (SELECT CONCAT(u.Nombres, N' ', u.Apellidos) FROM sigcm.Usuario AS u WHERE u.IdUsuario = p.IdActorDecision),
                              p.NumeroCarta, p.CartaDocumento, p.MedioNotificacion, p.NotificadaEn, p.ResultadoNotificacion, p.RegistroPladicop, p.FechaResolucion,
                              Plazos = JSON_QUERY(COALESCE((
                                  SELECT pl.CodigoRegla, Nombre = pr.Nombre, pl.Inicio, pl.Vencimiento, pl.AmpliadoHasta, pl.CumplidoEn, pl.Estado
                                    FROM sigcm.Plazo AS pl JOIN sigcm.PlazoRegla AS pr ON pr.CodigoRegla = pl.CodigoRegla
                                   WHERE pl.IdExpediente = e.IdExpediente AND pl.Activo = 1 ORDER BY pl.Inicio FOR JSON PATH), N'[]')),
                              Transiciones = JSON_QUERY(resolucion.fnTransicionesJson(e.CodigoEstado, @CodigoRol)),
                              PuedePronunciarAu = CONVERT(bit, CASE WHEN @CodigoRol LIKE 'AREA[_]%' AND e.CodigoEstado IN ('RES_SOLICITADA','RES_RESPUESTA_EN_EVALUACION') THEN 1 ELSE 0 END),
                              PuedeDecidirDec = CONVERT(bit, CASE WHEN @CodigoRol IN ('ABAST_ESPECIALISTA','ABAST_COORDINADOR') AND e.CodigoEstado = 'RES_EN_EVALUACION_DEC' THEN 1 ELSE 0 END),
                              PuedeEmitirCarta = CONVERT(bit, CASE WHEN @CodigoRol = 'ABAST_JEFE' AND e.CodigoEstado IN ('RES_POR_FIRMA_APERCIBIMIENTO','RES_POR_RESOLVER') THEN 1 ELSE 0 END),
                              PuedeResponder = CONVERT(bit, CASE WHEN @CodigoRol = 'PROVEEDOR' AND e.CodigoEstado = 'RES_APERCIBIDO' THEN 1 ELSE 0 END),
                              PuedeNotificar = CONVERT(bit, CASE WHEN @CodigoRol LIKE 'ABAST[_]%' AND e.CodigoEstado IN ('RES_RESUELTO','RES_DENEGADA') AND p.NotificadaEn IS NULL THEN 1 ELSE 0 END)
                         FROM resolucion.Procedimiento AS p
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
                         JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                         JOIN ejecucion.Contrato AS c ON c.IdContrato = p.IdContrato
                         JOIN sigcm.Expediente AS ec ON ec.IdExpediente = c.IdExpediente
                         JOIN sigcm.Unidad AS uo ON uo.IdUnidad = e.IdUnidadOrigen
                        WHERE p.IdProcedimiento = @IdProc
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 4. resolucion.paPronunciarAu                                              */
/*    RES_SOLICITADA: favorable remite a la DEC; desfavorable niega.         */
/*    RES_RESPUESTA_EN_EVALUACION: FAVORABLE = subsano; DESFAVORABLE = no.   */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE resolucion.paPronunciarAu
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52250, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdExpediente uniqueidentifier, @Pron varchar(15), @Informe nvarchar(max), @Doc nvarchar(200);
        SELECT @IdExpediente = TRY_CONVERT(uniqueidentifier, IdExpediente), @Pron = UPPER(NULLIF(LTRIM(RTRIM(Pronunciamiento)), '')),
               @Informe = NULLIF(LTRIM(RTRIM(Informe)), N''), @Doc = NULLIF(LTRIM(RTRIM(InformeDocumento)), N'')
          FROM OPENJSON(@parametro) WITH (IdExpediente varchar(50), Pronunciamiento varchar(15), Informe nvarchar(max), InformeDocumento nvarchar(200));
        IF @IdExpediente IS NULL THROW 52251, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @Pron NOT IN ('FAVORABLE', 'DESFAVORABLE') THROW 52252, 'VALIDACION_PRONUNCIAMIENTO: el pronunciamiento es FAVORABLE o DESFAVORABLE.', 1;
        IF @Informe IS NULL THROW 52253, 'VALIDACION_PAYLOAD: el informe del area usuaria es obligatorio.', 1;

        DECLARE @IdProc uniqueidentifier, @Estado varchar(60);
        SELECT @IdProc = p.IdProcedimiento, @Estado = e.CodigoEstado
          FROM resolucion.Procedimiento AS p JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;
        IF @IdProc IS NULL THROW 52254, 'NO_ENCONTRADO: el procedimiento no existe.', 1;

        DECLARE @Transicion varchar(70) =
            CASE WHEN @Estado = 'RES_SOLICITADA' AND @Pron = 'FAVORABLE' THEN 'RES_OPINAR_FAVORABLE'
                 WHEN @Estado = 'RES_SOLICITADA' THEN 'RES_OPINAR_DESFAVORABLE'
                 WHEN @Estado = 'RES_RESPUESTA_EN_EVALUACION' AND @Pron = 'FAVORABLE' THEN 'RES_EVALUAR_SUBSANADO'
                 WHEN @Estado = 'RES_RESPUESTA_EN_EVALUACION' THEN 'RES_EVALUAR_NO_SUBSANADO' END;
        IF @Transicion IS NULL THROW 52255, 'CONFLICTO_ESTADO: el procedimiento no esta en manos del area usuaria.', 1;

        DECLARE @Ahora datetime = GETDATE();
        UPDATE resolucion.Procedimiento
           SET PronunciamientoAu = @Pron, InformeAu = @Informe, InformeAuDocumento = COALESCE(@Doc, InformeAuDocumento), PronunciamientoEn = @Ahora,
               ResultadoApercibimiento = CASE WHEN @Estado = 'RES_RESPUESTA_EN_EVALUACION' THEN CASE WHEN @Pron = 'FAVORABLE' THEN 'SUBSANO' ELSE 'NO_SUBSANO' END ELSE ResultadoApercibimiento END,
               ResultadoDec = CASE WHEN @Transicion = 'RES_OPINAR_DESFAVORABLE' THEN 'DENEGADO'
                                   WHEN @Transicion = 'RES_EVALUAR_SUBSANADO' THEN 'SUBSANADO' ELSE ResultadoDec END,
               DecisionEn = CASE WHEN @Transicion IN ('RES_OPINAR_DESFAVORABLE', 'RES_EVALUAR_SUBSANADO') THEN @Ahora ELSE DecisionEn END,
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdProcedimiento = @IdProc;

        IF @Transicion = 'RES_EVALUAR_SUBSANADO'
            UPDATE sigcm.Plazo SET CumplidoEn = @Ahora, Estado = 'CUMPLIDO'
             WHERE IdExpediente = @IdExpediente AND CodigoRegla = 'RES_SUBSANACION_APERCIBIMIENTO' AND Estado = 'EN_CURSO' AND Activo = 1;

        IF JSON_VALUE(@parametro, '$.Comentario') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Comentario', LEFT(@Informe, 1000));

        EXEC resolucion.paMoverProcedimientoInterno @parametro, @IdProc, @Transicion;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 5. resolucion.paDecidirDec                                                */
/*    APERCIBIR (con dias dentro del rango), RESOLVER directo o DESESTIMAR.  */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE resolucion.paDecidirDec
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52260, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdExpediente uniqueidentifier, @Decision varchar(15), @Motivo nvarchar(max), @Dias int, @Alcance varchar(10), @Parte nvarchar(1000);
        SELECT @IdExpediente = TRY_CONVERT(uniqueidentifier, IdExpediente), @Decision = UPPER(NULLIF(LTRIM(RTRIM(Decision)), '')),
               @Motivo = NULLIF(LTRIM(RTRIM(Motivo)), N''), @Dias = PlazoApercibimientoDias,
               @Alcance = UPPER(NULLIF(LTRIM(RTRIM(Alcance)), '')), @Parte = NULLIF(LTRIM(RTRIM(ParteResuelta)), N'')
          FROM OPENJSON(@parametro) WITH (IdExpediente varchar(50), Decision varchar(15), Motivo nvarchar(max), PlazoApercibimientoDias int,
                                          Alcance varchar(10), ParteResuelta nvarchar(1000));
        IF @IdExpediente IS NULL THROW 52261, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @Decision NOT IN ('APERCIBIR', 'RESOLVER', 'DESESTIMAR') THROW 52262, 'VALIDACION_DECISION: la decision es APERCIBIR, RESOLVER o DESESTIMAR.', 1;
        IF @Motivo IS NULL THROW 52263, 'VALIDACION_PAYLOAD: indique el motivo de la decision.', 1;

        DECLARE @IdProc uniqueidentifier, @Estado varchar(60), @Causal varchar(25), @Min int, @Max int, @Requiere bit;
        SELECT @IdProc = p.IdProcedimiento, @Estado = e.CodigoEstado, @Causal = p.Causal, @Min = p.PlazoApercibimientoMin,
               @Max = p.PlazoApercibimientoMax, @Requiere = p.RequiereApercibimiento
          FROM resolucion.Procedimiento AS p JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;
        IF @IdProc IS NULL THROW 52264, 'NO_ENCONTRADO: el procedimiento no existe.', 1;
        IF @Estado <> 'RES_EN_EVALUACION_DEC' THROW 52265, 'CONFLICTO_ESTADO: el procedimiento no esta en evaluacion de la DEC.', 1;

        IF @Decision = 'APERCIBIR'
        BEGIN
            IF @Causal <> 'INCUMPLIMIENTO' THROW 52266, 'CONFLICTO_CAUSAL: el apercibimiento previo solo aplica al incumplimiento de obligaciones (7.3.7.2); las demas causales se resuelven directamente (7.3.7.3).', 1;
            IF @Dias IS NULL OR @Dias < @Min OR @Dias > @Max
            BEGIN
                DECLARE @errDias nvarchar(300) = CONCAT('VALIDACION_PLAZO: el plazo para cumplir va de ', @Min, ' a ', @Max, ' dias calendario (7.3.7.2.b).');
                THROW 52267, @errDias, 1;
            END
        END
        IF @Alcance IS NOT NULL AND @Alcance NOT IN ('TOTAL', 'PARCIAL') THROW 52268, 'VALIDACION_ALCANCE: el alcance es TOTAL o PARCIAL.', 1;
        IF @Alcance = 'PARCIAL' AND @Parte IS NULL THROW 52269, 'VALIDACION_ALCANCE: la resolucion parcial debe precisar que parte queda resuelta (7.3.7.5).', 1;

        DECLARE @Transicion varchar(70) = CASE @Decision WHEN 'APERCIBIR' THEN 'RES_APERCIBIR' WHEN 'RESOLVER' THEN 'RES_RESOLVER_DIRECTO' ELSE 'RES_DESESTIMAR' END;
        DECLARE @Ahora datetime = GETDATE();

        UPDATE resolucion.Procedimiento
           SET MotivoDec = @Motivo, IdActorDecision = @IdUsuario,
               PlazoApercibimientoDias = CASE WHEN @Decision = 'APERCIBIR' THEN @Dias ELSE PlazoApercibimientoDias END,
               ResultadoDec = CASE WHEN @Decision = 'DESESTIMAR' THEN 'DESESTIMADO' ELSE ResultadoDec END,
               DecisionEn = CASE WHEN @Decision = 'DESESTIMAR' THEN @Ahora ELSE DecisionEn END,
               Alcance = COALESCE(@Alcance, Alcance), ParteResuelta = CASE WHEN @Alcance = 'PARCIAL' THEN @Parte WHEN @Alcance = 'TOTAL' THEN NULL ELSE ParteResuelta END,
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdProcedimiento = @IdProc;

        IF JSON_VALUE(@parametro, '$.Comentario') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Comentario', LEFT(@Motivo, 1000));

        EXEC resolucion.paMoverProcedimientoInterno @parametro, @IdProc, @Transicion;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 6. resolucion.paRegistrarCarta                                            */
/*    Numero, archivo y medio de la carta que el jefe genera antes de firmar.*/
/* ========================================================================== */

CREATE OR ALTER PROCEDURE resolucion.paRegistrarCarta
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52270, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        IF @CodigoRol NOT LIKE 'ABAST[_]%' AND @CodigoRol NOT LIKE 'AREA[_]%' THROW 52271, 'NO_AUTORIZADO.', 1;

        DECLARE @IdExpediente uniqueidentifier, @TipoCarta varchar(15), @Numero varchar(40), @Doc nvarchar(200), @Medio varchar(15), @Pladicop varchar(60);
        SELECT @IdExpediente = TRY_CONVERT(uniqueidentifier, IdExpediente), @TipoCarta = UPPER(NULLIF(LTRIM(RTRIM(TipoCarta)), '')),
               @Numero = NULLIF(LTRIM(RTRIM(NumeroCarta)), ''), @Doc = NULLIF(LTRIM(RTRIM(CartaDocumento)), N''),
               @Medio = UPPER(NULLIF(LTRIM(RTRIM(MedioNotificacion)), '')), @Pladicop = NULLIF(LTRIM(RTRIM(RegistroPladicop)), '')
          FROM OPENJSON(@parametro) WITH (IdExpediente varchar(50), TipoCarta varchar(15), NumeroCarta varchar(40), CartaDocumento nvarchar(200),
                                          MedioNotificacion varchar(15), RegistroPladicop varchar(60));
        IF @IdExpediente IS NULL THROW 52272, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @TipoCarta NOT IN ('APERCIBIMIENTO', 'RESOLUCION', 'RESPUESTA') THROW 52273, 'VALIDACION_TIPO: la carta es de APERCIBIMIENTO, RESOLUCION o RESPUESTA.', 1;
        IF @Medio IS NOT NULL AND @Medio NOT IN ('NOTARIAL', 'PLADICOP', 'CORREO') THROW 52274, 'VALIDACION_MEDIO: el medio es NOTARIAL, PLADICOP o CORREO (7.3.7.2.e).', 1;
        IF NOT EXISTS (SELECT 1 FROM resolucion.Procedimiento WHERE IdExpediente = @IdExpediente AND Activo = 1) THROW 52275, 'NO_ENCONTRADO: el procedimiento no existe.', 1;

        DECLARE @Ahora datetime = GETDATE();
        UPDATE resolucion.Procedimiento
           SET NumeroCartaApercibimiento = CASE WHEN @TipoCarta = 'APERCIBIMIENTO' THEN COALESCE(@Numero, NumeroCartaApercibimiento) ELSE NumeroCartaApercibimiento END,
               CartaApercibimientoDocumento = CASE WHEN @TipoCarta = 'APERCIBIMIENTO' THEN COALESCE(@Doc, CartaApercibimientoDocumento) ELSE CartaApercibimientoDocumento END,
               NumeroCarta = CASE WHEN @TipoCarta <> 'APERCIBIMIENTO' THEN COALESCE(@Numero, NumeroCarta) ELSE NumeroCarta END,
               CartaDocumento = CASE WHEN @TipoCarta <> 'APERCIBIMIENTO' THEN COALESCE(@Doc, CartaDocumento) ELSE CartaDocumento END,
               MedioNotificacion = COALESCE(@Medio, MedioNotificacion), RegistroPladicop = COALESCE(@Pladicop, RegistroPladicop),
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdExpediente = @IdExpediente;

        SELECT @resultado = (SELECT 1 AS estado, N'Se registro la carta.' AS mensaje FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 7. resolucion.paEjecutarAccion                                            */
/*    Remitir, firmar cartas, responder, vencer el plazo. Firmar la carta de */
/*    resolucion cierra el contrato en Ejecucion en la misma llamada.        */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE resolucion.paEjecutarAccion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52280, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @Transicion varchar(70) = JSON_VALUE(@parametro, '$.CodigoTransicion');
        DECLARE @Respuesta nvarchar(max) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Respuesta'))), N'');
        DECLARE @RespuestaDoc nvarchar(200) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.RespuestaDocumento'))), N'');
        IF @IdExpediente IS NULL OR @Transicion IS NULL THROW 52281, 'VALIDACION_PAYLOAD: faltan IdExpediente y CodigoTransicion.', 1;

        DECLARE @IdProc uniqueidentifier, @Estado varchar(60), @Dias int, @Limite date, @IdContrato uniqueidentifier,
                @IdExpContrato uniqueidentifier, @VersionContrato int, @CartaAp nvarchar(200), @Carta nvarchar(200), @Medio varchar(15), @Alcance varchar(10);
        SELECT @IdProc = p.IdProcedimiento, @Estado = e.CodigoEstado, @Dias = p.PlazoApercibimientoDias, @Limite = p.FechaLimiteSubsanacion,
               @IdContrato = p.IdContrato, @IdExpContrato = c.IdExpediente, @VersionContrato = ec.Version,
               @CartaAp = p.CartaApercibimientoDocumento, @Carta = p.CartaDocumento, @Medio = p.MedioNotificacion, @Alcance = p.Alcance
          FROM resolucion.Procedimiento AS p JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
          JOIN ejecucion.Contrato AS c ON c.IdContrato = p.IdContrato JOIN sigcm.Expediente AS ec ON ec.IdExpediente = c.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;
        IF @IdProc IS NULL THROW 52282, 'NO_ENCONTRADO: el procedimiento no existe.', 1;

        DECLARE @Ahora datetime = GETDATE(), @Hoy date = CONVERT(date, GETDATE());

        IF @Transicion = 'RES_FIRMAR_APERCIBIMIENTO'
        BEGIN
            IF @CartaAp IS NULL THROW 52283, 'CONFLICTO_DOCUMENTO: genere la carta de apercibimiento antes de firmarla.', 1;
            IF ISNULL(@Dias, 0) < 1 THROW 52284, 'CONFLICTO_ESTADO: la DEC no fijo el plazo del apercibimiento.', 1;
            SET @Limite = DATEADD(DAY, @Dias, @Hoy);
            UPDATE resolucion.Procedimiento
               SET ApercibimientoNotificadoEn = @Ahora, FechaLimiteSubsanacion = @Limite,
                   UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora
             WHERE IdProcedimiento = @IdProc;
            IF NOT EXISTS (SELECT 1 FROM sigcm.Plazo WHERE IdExpediente = @IdExpediente AND CodigoRegla = 'RES_SUBSANACION_APERCIBIMIENTO' AND Activo = 1)
                INSERT INTO sigcm.Plazo (IdExpediente, CodigoRegla, Inicio, Vencimiento, Estado, UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                VALUES (@IdExpediente, 'RES_SUBSANACION_APERCIBIMIENTO', @Ahora, @Limite, 'EN_CURSO', @Cuenta, @Equipo, @Programa);
        END

        IF @Transicion = 'RES_RESPONDER_APERCIBIMIENTO'
        BEGIN
            IF @Respuesta IS NULL THROW 52285, 'VALIDACION_PAYLOAD: indique como cumplio o que alega frente al apercibimiento.', 1;
            UPDATE resolucion.Procedimiento
               SET RespuestaProveedor = @Respuesta, RespuestaDocumento = COALESCE(@RespuestaDoc, RespuestaDocumento), RespondidaEn = @Ahora,
                   UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora
             WHERE IdProcedimiento = @IdProc;
            IF JSON_VALUE(@parametro, '$.Comentario') IS NULL SET @parametro = JSON_MODIFY(@parametro, '$.Comentario', LEFT(@Respuesta, 1000));
        END

        IF @Transicion = 'RES_VENCER_APERCIBIMIENTO'
        BEGIN
            IF @Limite IS NULL OR @Hoy <= @Limite
            BEGIN
                DECLARE @errV nvarchar(300) = CONCAT('CONFLICTO_PLAZO: el plazo para cumplir vence el ', CONVERT(varchar(10), @Limite, 103), '; todavia no se puede declarar vencido.');
                THROW 52286, @errV, 1;
            END
            UPDATE resolucion.Procedimiento SET ResultadoApercibimiento = 'SIN_RESPUESTA', UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora
             WHERE IdProcedimiento = @IdProc;
            UPDATE sigcm.Plazo SET Estado = 'VENCIDO' WHERE IdExpediente = @IdExpediente AND CodigoRegla = 'RES_SUBSANACION_APERCIBIMIENTO' AND Estado = 'EN_CURSO' AND Activo = 1;
        END

        IF @Transicion = 'RES_FIRMAR_RESOLUCION'
        BEGIN
            IF @Carta IS NULL THROW 52287, 'CONFLICTO_DOCUMENTO: genere la carta de resolucion antes de firmarla.', 1;

            /* Primero el contrato: si no se puede cerrar, no se firma nada.

               Se mueve el expediente del contrato directamente y no con
               sigcm.paEjecutarTransicion. El motor devuelve su resultado como
               result set y capturarlo exige INSERT ... EXEC, que no admite
               anidarse (error 8164) cuando quien llama a esta rutina ya lo
               esta usando -los scripts de prueba, por ejemplo-. La transicion
               EJE_RESOLVER sigue declarada en S040 para que la maquina de
               Ejecucion la documente; aqui se aplica su efecto con las mismas
               escrituras que hace el motor: estado, version, cierre e historial. */
            DECLARE @EstadoContrato varchar(60);
            SELECT @EstadoContrato = CodigoEstado FROM sigcm.Expediente WHERE IdExpediente = @IdExpContrato;
            IF @EstadoContrato <> 'EJE_VIGENTE'
            BEGIN
                DECLARE @errC nvarchar(400) = CONCAT('CONFLICTO_CONTRATO: el contrato esta en ', @EstadoContrato, ' y solo se resuelve un contrato vigente.');
                THROW 52288, @errC, 1;
            END
            IF NOT EXISTS (SELECT 1 FROM sigcm.Transicion WHERE CodigoTransicion = 'EJE_RESOLVER' AND CodigoEstadoOrigen = 'EJE_VIGENTE' AND Activo = 1)
                THROW 52289, 'CONFLICTO_CONFIGURACION: falta la transicion EJE_RESOLVER (S040).', 1;

            DECLARE @CodigoRes varchar(40) = (SELECT Codigo FROM sigcm.Expediente WHERE IdExpediente = @IdExpediente);

            UPDATE sigcm.Expediente
               SET CodigoEstado = 'EJE_RESUELTO', Version = Version + 1, CerradoEn = @Ahora,
                   UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
                   EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
             WHERE IdExpediente = @IdExpContrato AND Version = @VersionContrato;
            IF @@ROWCOUNT = 0
                THROW 52288, 'CONFLICTO_VERSION: el contrato cambio mientras se resolvia. Vuelva a abrirlo.', 1;

            INSERT INTO sigcm.Historial (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion, Comentario,
                                         IdActor, ActorRol, IdActorUnidad, Metadata, UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES (@IdExpContrato, 'EJE_VIGENTE', 'EJE_RESUELTO', 'EJE_RESOLVER',
                    CONCAT(N'Contrato resuelto (', @Alcance, N') por el procedimiento ', @CodigoRes, N'.'),
                    @IdUsuario, @CodigoRol, @IdUnidad,
                    (SELECT @CodigoRes AS Procedimiento, @Alcance AS Alcance FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                    @Cuenta, @Equipo, @Programa);

            UPDATE resolucion.Procedimiento
               SET ResultadoDec = 'RESUELTO', DecisionEn = COALESCE(DecisionEn, @Ahora), IdActorDecision = COALESCE(IdActorDecision, @IdUsuario),
                   FechaResolucion = @Hoy,
                   UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora
             WHERE IdProcedimiento = @IdProc;

            UPDATE ejecucion.Contrato SET FechaFinReal = @Hoy, UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora
             WHERE IdContrato = @IdContrato;
            UPDATE sigcm.Plazo SET CumplidoEn = @Ahora, Estado = 'VENCIDO'
             WHERE IdExpediente = @IdExpContrato AND CodigoRegla = 'EJE_EJECUCION_CONTRATO' AND Estado = 'EN_CURSO' AND Activo = 1;
        END

        EXEC resolucion.paMoverProcedimientoInterno @parametro, @IdProc, @Transicion;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 8. resolucion.paPrepararNotificacion / paMarcarNotificada                 */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE resolucion.paPrepararNotificacion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52290, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        IF @CodigoRol NOT LIKE 'ABAST[_]%' THROW 52291, 'NO_AUTORIZADO: la DEC notifica al proveedor.', 1;

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        IF @IdExpediente IS NULL THROW 52292, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @Codigo varchar(40), @Estado varchar(60), @Causal varchar(25), @Alcance varchar(10), @Parte nvarchar(1000),
                @Correo varchar(200), @Proveedor nvarchar(250), @Orden varchar(40), @Denominacion varchar(500),
                @Motivo nvarchar(max), @Carta nvarchar(200), @CorreoAu varchar(200), @FechaRes date, @Dias int, @Limite date, @CartaAp nvarchar(200);
        SELECT @Codigo = e.Codigo, @Estado = e.CodigoEstado, @Causal = p.Causal, @Alcance = p.Alcance, @Parte = p.ParteResuelta,
               @Correo = c.CorreoProveedor, @Proveedor = c.NombreProveedor, @Orden = c.NumeroOrdenSiga, @Denominacion = c.Denominacion,
               @Motivo = COALESCE(p.MotivoDec, p.InformeAu), @Carta = p.CartaDocumento, @FechaRes = p.FechaResolucion,
               @Dias = p.PlazoApercibimientoDias, @Limite = p.FechaLimiteSubsanacion, @CartaAp = p.CartaApercibimientoDocumento,
               @CorreoAu = (SELECT u.Correo FROM sigcm.Usuario AS u WHERE u.IdUsuario = c.IdSupervisor)
          FROM resolucion.Procedimiento AS p JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
          JOIN ejecucion.Contrato AS c ON c.IdContrato = p.IdContrato
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;
        IF @Codigo IS NULL THROW 52293, 'NO_ENCONTRADO: el procedimiento no existe.', 1;
        IF @Estado NOT IN ('RES_RESUELTO', 'RES_DENEGADA', 'RES_APERCIBIDO') THROW 52294, 'CONFLICTO_ESTADO: no hay carta que notificar en este estado.', 1;
        IF NULLIF(@Correo, '') IS NULL THROW 52295, 'VALIDACION_CORREO: el contrato no tiene correo del proveedor.', 1;

        DECLARE @Asunto nvarchar(300) = CONCAT(
            CASE @Estado WHEN 'RES_RESUELTO' THEN N'Resolucion del contrato menor' WHEN 'RES_APERCIBIDO' THEN N'Apercibimiento de resolucion del contrato menor'
                         ELSE N'Respuesta a la solicitud de resolucion' END, N' - O/S ', ISNULL(@Orden, N''), N' - ', @Codigo);

        DECLARE @Cuerpo nvarchar(max) = CONCAT(
            N'Estimado(a) ', ISNULL(@Proveedor, N'proveedor'), N':<br><br>',
            N'En relacion con la orden ', ISNULL(@Orden, N''), N' (', ISNULL(@Denominacion, N''), N'), la Direccion de Ejecucion de Contrataciones comunica que ',
            CASE @Estado
                 WHEN 'RES_RESUELTO' THEN CONCAT(N'el contrato menor queda <b>resuelto de forma ', LOWER(@Alcance), N'</b> a partir del ', CONVERT(varchar(10), @FechaRes, 103),
                                                 N', por la causal ', @Causal, N'.', CASE WHEN @Alcance = 'PARCIAL' THEN CONCAT(N' Parte resuelta: ', @Parte, N'.') ELSE N'' END,
                                                 N' Se adjunta la carta de resolucion.')
                 WHEN 'RES_APERCIBIDO' THEN CONCAT(N'se le requiere cumplir la prestacion materia de incumplimiento en un plazo de ', @Dias, N' dias calendario, hasta el ',
                                                   CONVERT(varchar(10), @Limite, 103), N', bajo apercibimiento de resolver el contrato (Directiva 002-2026-ANIN, 7.3.7.2). Se adjunta la carta.')
                 ELSE N'la solicitud de resolucion del contrato ha sido <b>denegada</b>.' END,
            N'<br><br>Sustento: ', ISNULL(@Motivo, N''), N'<br><br>Expediente ', @Codigo, N'.<br>Autoridad Nacional de Infraestructura - SIGCM');

        SELECT @resultado = (
            SELECT 1 AS estado, Destinatario = @Correo, Copia = @CorreoAu, Asunto = @Asunto, Cuerpo = @Cuerpo,
                   AdjuntoDocumento = CASE WHEN @Estado = 'RES_APERCIBIDO' THEN @CartaAp ELSE @Carta END,
                   NombreAdjunto = CASE WHEN @Estado = 'RES_APERCIBIDO' AND @CartaAp IS NOT NULL THEN CONCAT('Carta de apercibimiento - ', @Codigo, '.pdf')
                                        WHEN @Carta IS NOT NULL THEN CONCAT('Carta - ', @Codigo, '.pdf') END,
                   Carpeta = 'resolucion'
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE resolucion.paMarcarNotificada
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52296, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @ResultadoCorreo nvarchar(300) = JSON_VALUE(@parametro, '$.ResultadoCorreo');
        DECLARE @Enviado bit = CASE WHEN JSON_VALUE(@parametro, '$.CorreoEnviado') IN ('true', '1') THEN 1 ELSE 0 END;
        DECLARE @Medio varchar(15) = COALESCE(NULLIF(UPPER(JSON_VALUE(@parametro, '$.MedioNotificacion')), ''), 'CORREO');
        IF @IdExpediente IS NULL THROW 52297, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @Ahora datetime = GETDATE(), @Estado varchar(60);
        SELECT @Estado = CodigoEstado FROM sigcm.Expediente WHERE IdExpediente = @IdExpediente;

        UPDATE resolucion.Procedimiento
           SET NotificadaEn = CASE WHEN @Estado <> 'RES_APERCIBIDO' AND (@Enviado = 1 OR @Medio <> 'CORREO') THEN @Ahora ELSE NotificadaEn END,
               ApercibimientoNotificadoEn = CASE WHEN @Estado = 'RES_APERCIBIDO' AND @Enviado = 1 THEN @Ahora ELSE ApercibimientoNotificadoEn END,
               MedioNotificacion = @Medio, ResultadoNotificacion = @ResultadoCorreo,
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdExpediente = @IdExpediente AND Activo = 1;

        INSERT INTO sigcm.Historial (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion, Comentario,
                                     IdActor, ActorRol, IdActorUnidad, UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT e.IdExpediente, e.CodigoEstado, e.CodigoEstado, NULL,
               CONCAT(CASE WHEN @Enviado = 1 THEN N'Carta notificada al proveedor por correo' ELSE N'Intento de notificacion al proveedor' END,
                      CASE WHEN @ResultadoCorreo IS NOT NULL THEN N': ' + @ResultadoCorreo ELSE N'' END),
               @IdUsuario, @CodigoRol, @IdUnidad, @Cuenta, @Equipo, @Programa
          FROM sigcm.Expediente AS e WHERE e.IdExpediente = @IdExpediente;

        SELECT @resultado = (SELECT 1 AS estado,
                                    mensaje = CASE WHEN @Enviado = 1 THEN N'Se notifico la carta al proveedor.' ELSE N'Se registro el intento de notificacion.' END
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F018 aplicada: procedimiento de resolucion, apercibimiento, cartas y cierre del contrato.';
GO
