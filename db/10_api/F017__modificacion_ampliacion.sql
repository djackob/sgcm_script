/*
===============================================================================
  SIGCM - F017 : Modificacion del contrato y ampliacion de plazo
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 52100-52199

  Directiva 002-2026-ANIN 7.3.4 y 7.3.5. Bizagi "4. MODIFICACION-AMPLIACION".
  Analisis en docs/analisis-modulos-modificacion-resolucion.md.

  La maquina de estados es sigcm.paEjecutarTransicion (S039). Aqui vive lo que
  ella no puede:

    - abrir la solicitud sobre un contrato VIGENTE de Ejecucion y elegir su
      arranque: MOD_PRESENTADA (pide el proveedor), MOD_EN_SUSTENTO_AU (inicia
      el AU) o AMP_PRESENTADA (ampliacion, siempre del proveedor);
    - calcular si la ampliacion entro en los 10 dias habiles (7.3.5.1) y sus
      tres plazos (2 + 3 + 7 habiles);
    - guardar la opinion del AU y la decision de la DEC, y con la ampliacion
      aprobada mover la fecha de fin del contrato y su plazo;
    - impedir denegar una ampliacion cuando ya vencieron los 7 dias habiles:
      se entiende aceptada (7.3.5.4);
    - armar el sobre del correo con que se notifica al proveedor y marcar el
      resultado. SMTP no corre en SQL: lo envia el controlador.

  La unidad de destino se resuelve con ejecucion.paResolverUnidadDestinoInterno
  (F016), por la misma razon que alli.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ========================================================================== */
/* 0. Interno: mover una solicitud con la unidad de destino resuelta         */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ampliacion.paMoverSolicitudInterno
    @parametro        nvarchar(max),
    @IdSolicitud      uniqueidentifier,
    @CodigoTransicion varchar(70)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdExpediente uniqueidentifier, @IdContrato uniqueidentifier, @Version int,
            @EstadoDestino varchar(60), @RolDestino varchar(40), @IdUnidadDestino uniqueidentifier;

    SELECT @IdExpediente = s.IdExpediente, @IdContrato = s.IdContrato, @Version = e.Version
      FROM ampliacion.Solicitud AS s JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
     WHERE s.IdSolicitud = @IdSolicitud AND s.Activo = 1;
    IF @IdExpediente IS NULL
        THROW 52101, 'NO_ENCONTRADO: la solicitud no existe.', 1;

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

/* Subconsulta de transiciones disponibles para ESTE actor, igual que F016. */
CREATE OR ALTER FUNCTION ampliacion.fnTransicionesJson (@CodigoEstado varchar(60), @CodigoRol varchar(40))
RETURNS nvarchar(max)
AS
BEGIN
    RETURN COALESCE((
        SELECT t.CodigoTransicion, t.NombreAccion, t.CodigoEstadoDestino, EstadoDestino = d.Nombre,
               t.RequiereComentario, t.RequiereFirma, t.DocumentoRequerido, t.EncolaIntegracion, t.GeneraObservacion
          FROM sigcm.Transicion AS t
          JOIN sigcm.Estado AS d ON d.CodigoEstado = t.CodigoEstadoDestino
         WHERE t.CodigoModulo = 'MODIFICACION' AND t.CodigoEstadoOrigen = @CodigoEstado AND t.Activo = 1
           AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS tr WHERE tr.CodigoTransicion = t.CodigoTransicion AND tr.CodigoRol = @CodigoRol)
         ORDER BY t.CodigoTransicion
           FOR JSON PATH), N'[]');
END
GO

/* ========================================================================== */
/* 1. ampliacion.paRegistrarSolicitud                                        */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ampliacion.paRegistrarSolicitud
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52110, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdContrato uniqueidentifier, @Tipo varchar(20), @Asunto nvarchar(300), @Sustento nvarchar(max),
                @Doc nvarchar(200), @FechaHecho date, @Dias int, @Detalle nvarchar(max);
        SELECT @IdContrato = TRY_CONVERT(uniqueidentifier, IdContrato),
               @Tipo = UPPER(NULLIF(LTRIM(RTRIM(Tipo)), '')),
               @Asunto = NULLIF(LTRIM(RTRIM(Asunto)), N''),
               @Sustento = NULLIF(LTRIM(RTRIM(Sustento)), N''),
               @Doc = NULLIF(LTRIM(RTRIM(SolicitudDocumento)), N''),
               @FechaHecho = TRY_CONVERT(date, FechaFinHechoGenerador),
               @Dias = DiasSolicitados,
               @Detalle = NULLIF(LTRIM(RTRIM(DetalleModificacion)), N'')
          FROM OPENJSON(@parametro)
          WITH (IdContrato varchar(50), Tipo varchar(20), Asunto nvarchar(300), Sustento nvarchar(max),
                SolicitudDocumento nvarchar(200), FechaFinHechoGenerador varchar(30), DiasSolicitados int,
                DetalleModificacion nvarchar(max));

        IF @IdContrato IS NULL THROW 52111, 'VALIDACION_PAYLOAD: falta IdContrato.', 1;
        IF @Tipo NOT IN ('MODIFICACION', 'AMPLIACION_PLAZO') THROW 52112, 'VALIDACION_TIPO: el tipo es MODIFICACION o AMPLIACION_PLAZO.', 1;
        IF @Asunto IS NULL OR @Sustento IS NULL THROW 52113, 'VALIDACION_PAYLOAD: indique el asunto y el sustento de la solicitud.', 1;

        DECLARE @Origen varchar(15) = CASE WHEN @CodigoRol = 'PROVEEDOR' THEN 'PROVEEDOR'
                                           WHEN @CodigoRol LIKE 'AREA[_]%' THEN 'AREA_USUARIA' END;
        IF @Origen IS NULL THROW 52114, 'NO_AUTORIZADO: la solicitud la presenta el proveedor o el area usuaria.', 1;
        IF @Tipo = 'AMPLIACION_PLAZO' AND @Origen <> 'PROVEEDOR'
            THROW 52115, 'CONFLICTO_TIPO: la ampliacion de plazo la solicita el contratista (7.3.5.1).', 1;
        IF @Tipo = 'AMPLIACION_PLAZO' AND (@FechaHecho IS NULL OR ISNULL(@Dias, 0) < 1)
            THROW 52116, 'VALIDACION_PAYLOAD: la ampliacion exige la fecha de fin del hecho generador y los dias solicitados.', 1;
        IF @Tipo = 'MODIFICACION' AND @Detalle IS NULL
            THROW 52117, 'VALIDACION_PAYLOAD: indique que se modifica del contrato.', 1;

        DECLARE @IdExpContrato uniqueidentifier, @IdUnidadOrigen uniqueidentifier, @EsFinal bit, @AnoEje smallint,
                @TipoCon varchar(20), @CodigoContrato varchar(40), @FechaFin date, @Ruc varchar(11), @Dni varchar(15), @Correo varchar(200);
        SELECT @IdExpContrato = c.IdExpediente, @IdUnidadOrigen = e.IdUnidadOrigen, @EsFinal = w.EsFinal, @AnoEje = e.AnoEje,
               @TipoCon = e.CodigoTipoContratacion, @CodigoContrato = e.Codigo, @FechaFin = c.FechaFinPrevista,
               @Ruc = c.RucProveedor, @Dni = c.DniProveedor, @Correo = c.CorreoProveedor
          FROM ejecucion.Contrato AS c JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE c.IdContrato = @IdContrato AND c.Activo = 1;
        IF @IdExpContrato IS NULL THROW 52118, 'NO_ENCONTRADO: el contrato no existe.', 1;
        IF @EsFinal = 1 THROW 52119, 'CONFLICTO_ESTADO: el contrato ya no esta en ejecucion.', 1;

        IF @Origen = 'AREA_USUARIA' AND @IdUnidad <> @IdUnidadOrigen
            THROW 52120, 'NO_AUTORIZADO: el contrato no pertenece a su area usuaria.', 1;
        IF @Origen = 'PROVEEDOR'
        BEGIN
            DECLARE @DocActor varchar(20), @CorreoActor varchar(200);
            SELECT @DocActor = NULLIF(DocumentoIdentidad, ''), @CorreoActor = Correo FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;
            IF NOT ((@DocActor IS NOT NULL AND (@Ruc = @DocActor OR @Dni = @DocActor)) OR @Ruc = @Cuenta OR @Dni = @Cuenta
                    OR (@CorreoActor IS NOT NULL AND @Correo = @CorreoActor))
                THROW 52121, 'NO_AUTORIZADO: este contrato no corresponde al proveedor que ingreso.', 1;
        END

        /* Una solicitud abierta a la vez por tipo: dos ampliaciones en paralelo
           moverian la misma fecha de fin. */
        IF EXISTS (SELECT 1 FROM ampliacion.Solicitud AS s JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
                   JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                   WHERE s.IdContrato = @IdContrato AND s.Tipo = @Tipo AND s.Activo = 1 AND w.EsFinal = 0)
            THROW 52122, 'CONFLICTO_ESTADO: ya hay una solicitud del mismo tipo en tramite para este contrato.', 1;

        DECLARE @EstadoIni varchar(60) = CASE WHEN @Tipo = 'AMPLIACION_PLAZO' THEN 'AMP_PRESENTADA'
                                              WHEN @Origen = 'PROVEEDOR' THEN 'MOD_PRESENTADA'
                                              ELSE 'MOD_EN_SUSTENTO_AU' END;
        DECLARE @RolIni varchar(40);
        SELECT @RolIni = RolResponsable FROM sigcm.Estado WHERE CodigoEstado = @EstadoIni AND Activo = 1;
        IF @RolIni IS NULL THROW 52123, 'CONFLICTO_CONFIGURACION: faltan los estados del modulo. Falta S039.', 1;

        DECLARE @IdUnidadDestino uniqueidentifier;
        EXEC ejecucion.paResolverUnidadDestinoInterno @IdContrato, @RolIni, @IdUnidadDestino OUTPUT;
        IF @IdUnidadDestino IS NULL SET @IdUnidadDestino = @IdUnidadOrigen;

        /* 7.3.5.1: diez dias habiles desde finalizado el hecho generador. */
        DECLARE @Hoy date = CONVERT(date, GETDATE()), @Limite date = NULL, @EnPlazo bit = NULL;
        IF @Tipo = 'AMPLIACION_PLAZO'
        BEGIN
            SET @Limite = sigcm.fnSumarDiasHabiles(@FechaHecho, 10);
            SET @EnPlazo = CASE WHEN @Hoy <= @Limite THEN 1 ELSE 0 END;
        END

        DECLARE @Codigo varchar(40), @Ahora datetime = GETDATE(), @IdExp uniqueidentifier, @IdSolicitud uniqueidentifier;

        BEGIN TRANSACTION;

        EXEC sigcm.paSiguienteCodigo 'MOD', @AnoEje, N'ampliacion.SeqSolicitud', @Codigo OUTPUT;

        INSERT INTO sigcm.Expediente
            (Codigo, CodigoModulo, CodigoTipoContratacion, AnoEje, IdUnidadOrigen, CodigoEstado, IdUnidadActual, Version, IdExpedientePadre,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@Codigo, 'MODIFICACION', @TipoCon, @AnoEje, @IdUnidadOrigen, @EstadoIni, @IdUnidadDestino, 1, @IdExpContrato,
             @Cuenta, @Ahora, @Equipo, @Programa);
        SELECT @IdExp = IdExpediente FROM sigcm.Expediente WHERE Codigo = @Codigo;

        INSERT INTO ampliacion.Solicitud
            (IdExpediente, IdContrato, Tipo, Origen, FechaPresentacion, Asunto, Sustento, SolicitudDocumento,
             FechaFinHechoGenerador, FechaLimitePresentacion, PresentadaEnPlazo, DiasSolicitados, FechaFinAnterior, DetalleModificacion,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExp, @IdContrato, @Tipo, @Origen, @Ahora, @Asunto, @Sustento, @Doc,
             @FechaHecho, @Limite, @EnPlazo, @Dias, CASE WHEN @Tipo = 'AMPLIACION_PLAZO' THEN @FechaFin END, @Detalle,
             @Cuenta, @Ahora, @Equipo, @Programa);
        SELECT @IdSolicitud = IdSolicitud FROM ampliacion.Solicitud WHERE IdExpediente = @IdExp;

        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion, Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExp, NULL, @EstadoIni, NULL,
             CONCAT(CASE WHEN @Tipo = 'AMPLIACION_PLAZO' THEN N'Solicitud de ampliacion de plazo por ' + CONVERT(nvarchar(10), @Dias) + N' dias'
                         ELSE N'Solicitud de modificacion del contrato' END,
                    N' (', CASE @Origen WHEN 'PROVEEDOR' THEN N'proveedor' ELSE N'area usuaria' END, N'): ', @Asunto,
                    CASE WHEN @EnPlazo = 0 THEN N'. Presentada fuera de los diez dias habiles del hecho generador.' ELSE N'' END),
             @IdUsuario, @CodigoRol, @IdUnidad,
             (SELECT @CodigoContrato AS Contrato, @Tipo AS Tipo, @Dias AS DiasSolicitados, @EnPlazo AS PresentadaEnPlazo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
             @Cuenta, @Equipo, @Programa);

        IF @Tipo = 'AMPLIACION_PLAZO'
        BEGIN
            INSERT INTO sigcm.Plazo (IdExpediente, CodigoRegla, Inicio, Vencimiento, Estado, UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES (@IdExp, 'AMP_REMISION_DEC', @Ahora, sigcm.fnSumarDiasHabiles(@Hoy, 2), 'EN_CURSO', @Cuenta, @Equipo, @Programa),
                   (@IdExp, 'AMP_DECISION_DEC', @Ahora, sigcm.fnSumarDiasHabiles(@Hoy, 7), 'EN_CURSO', @Cuenta, @Equipo, @Programa);
        END

        EXEC sigcm.paRegistrarAuditoria @CorrelacionId, 'MODIFICACION', 'ampliacion.Solicitud', @IdExp,
             'REGISTRAR_SOLICITUD', 'OK', @IdUsuario, @Cuenta, @CodigoRol, @IdUnidad, @Ip, @Equipo, @Programa, NULL, @parametro;

        COMMIT TRANSACTION;

        SELECT @resultado = (
            SELECT 1 AS estado, @IdSolicitud AS IdSolicitud, @IdExp AS IdExpediente, @Codigo AS Codigo, @EstadoIni AS CodigoEstado,
                   PresentadaEnPlazo = @EnPlazo,
                   mensaje = CASE WHEN @EnPlazo = 0 THEN N'Se registro la solicitud. Fue presentada fuera de los diez dias habiles del hecho generador.'
                                  ELSE N'Se registro la solicitud.' END
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
/* 2. ampliacion.paListarSolicitud                                           */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ampliacion.paListarSolicitud
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52130, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @DocIdent varchar(20), @CorreoActor varchar(200);
        SELECT @DocIdent = NULLIF(DocumentoIdentidad, ''), @CorreoActor = Correo FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;

        DECLARE @SoloMiBandeja bit, @Tipo varchar(20), @CodigoEstado varchar(60), @Texto varchar(200),
                @Limite int, @Desplazamiento int, @SoloVigentes bit, @IdContrato uniqueidentifier;
        SELECT @SoloMiBandeja = SoloMiBandeja, @Tipo = Tipo, @CodigoEstado = CodigoEstado, @Texto = Texto,
               @Limite = Limite, @Desplazamiento = Desplazamiento, @SoloVigentes = SoloVigentes,
               @IdContrato = TRY_CONVERT(uniqueidentifier, IdContrato)
          FROM OPENJSON(@parametro, '$.Filtro')
          WITH (SoloMiBandeja bit, Tipo varchar(20), CodigoEstado varchar(60), Texto varchar(200), Limite int,
                Desplazamiento int, SoloVigentes bit, IdContrato varchar(50));
        SET @SoloMiBandeja = ISNULL(@SoloMiBandeja, 1); SET @SoloVigentes = ISNULL(@SoloVigentes, 0);
        SET @Limite = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50 WHEN @Limite > 200 THEN 200 ELSE @Limite END;
        SET @Desplazamiento = CASE WHEN @Desplazamiento IS NULL OR @Desplazamiento < 0 THEN 0 ELSE @Desplazamiento END;

        CREATE TABLE #Visible (IdSolicitud uniqueidentifier PRIMARY KEY, MeToca bit NOT NULL);
        INSERT INTO #Visible
        SELECT s.IdSolicitud, CONVERT(bit, CASE WHEN e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol THEN 1 ELSE 0 END)
          FROM ampliacion.Solicitud AS s
          JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
          JOIN ejecucion.Contrato AS c ON c.IdContrato = s.IdContrato
         WHERE e.Anulado = 0 AND e.Activo = 1 AND s.Activo = 1
           AND (@Tipo IS NULL OR s.Tipo = @Tipo)
           AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
           AND (@IdContrato IS NULL OR s.IdContrato = @IdContrato)
           AND (@SoloVigentes = 0 OR w.EsFinal = 0)
           AND (@Texto IS NULL OR e.Codigo LIKE '%' + @Texto + '%' OR c.CodigoRequerimiento LIKE '%' + @Texto + '%'
                OR c.NumeroOrdenSiga LIKE '%' + @Texto + '%' OR c.NombreProveedor LIKE '%' + @Texto + '%' OR s.Asunto LIKE '%' + @Texto + '%')
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
                   Solicitudes = JSON_QUERY(COALESCE((
                       SELECT s.IdSolicitud, e.IdExpediente, e.Codigo, e.CodigoEstado, e.Version, Estado = w.Nombre,
                              RolResponsable = w.RolResponsable, EsFinal = w.EsFinal, MeToca = v.MeToca,
                              s.IdContrato, ContratoCodigo = ec.Codigo, c.CodigoRequerimiento, c.NumeroOrdenSiga, c.Denominacion,
                              c.NombreProveedor, c.RucProveedor, c.DniProveedor, UnidadOrigen = uo.Sigla,
                              s.Tipo, s.Origen, s.FechaPresentacion, s.Asunto, s.DiasSolicitados, s.DiasOtorgados, s.PresentadaEnPlazo,
                              s.ResultadoAu, s.ResultadoDec, s.AceptacionTacita, s.NotificadaEn,
                              /* El plazo que corre ahora, si hay: la bandeja pinta lo que vence. */
                              PlazoVigente = (SELECT TOP 1 pr.Nombre FROM sigcm.Plazo AS pl JOIN sigcm.PlazoRegla AS pr ON pr.CodigoRegla = pl.CodigoRegla
                                               WHERE pl.IdExpediente = e.IdExpediente AND pl.Estado = 'EN_CURSO' AND pl.Activo = 1 ORDER BY pl.Vencimiento),
                              DiasPlazo = (SELECT TOP 1 DATEDIFF(DAY, @Hoy, COALESCE(pl.AmpliadoHasta, pl.Vencimiento)) FROM sigcm.Plazo AS pl
                                            WHERE pl.IdExpediente = e.IdExpediente AND pl.Estado = 'EN_CURSO' AND pl.Activo = 1 ORDER BY pl.Vencimiento),
                              Transiciones = JSON_QUERY(ampliacion.fnTransicionesJson(e.CodigoEstado, @CodigoRol)),
                              ActualizadoEn = ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria)
                         FROM #Visible AS v
                         JOIN ampliacion.Solicitud AS s ON s.IdSolicitud = v.IdSolicitud
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
                         JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                         JOIN ejecucion.Contrato AS c ON c.IdContrato = s.IdContrato
                         JOIN sigcm.Expediente AS ec ON ec.IdExpediente = c.IdExpediente
                         JOIN sigcm.Unidad AS uo ON uo.IdUnidad = e.IdUnidadOrigen
                        ORDER BY v.MeToca DESC, w.EsFinal, s.FechaPresentacion DESC
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
/* 3. ampliacion.paObtenerSolicitud                                          */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ampliacion.paObtenerSolicitud
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52140, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdSolicitud uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdSolicitud'));
        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        IF @IdSolicitud IS NULL AND @IdExpediente IS NOT NULL
            SELECT @IdSolicitud = IdSolicitud FROM ampliacion.Solicitud WHERE IdExpediente = @IdExpediente AND Activo = 1;
        IF @IdSolicitud IS NULL THROW 52141, 'VALIDACION_PAYLOAD: falta IdSolicitud o IdExpediente.', 1;
        IF NOT EXISTS (SELECT 1 FROM ampliacion.Solicitud WHERE IdSolicitud = @IdSolicitud AND Activo = 1)
            THROW 52142, 'NO_ENCONTRADO: la solicitud no existe.', 1;

        DECLARE @Hoy date = CONVERT(date, GETDATE());

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Solicitud = JSON_QUERY((
                       SELECT s.IdSolicitud, e.IdExpediente, e.Codigo, e.CodigoEstado, e.Version, Estado = w.Nombre,
                              RolResponsable = w.RolResponsable, EsFinal = w.EsFinal, e.AnoEje,
                              MeToca = CONVERT(bit, CASE WHEN e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol THEN 1 ELSE 0 END),
                              s.IdContrato, ContratoCodigo = ec.Codigo, ContratoEstado = ec.CodigoEstado,
                              c.CodigoRequerimiento, c.NumeroOrdenSiga, c.Denominacion, c.TipoPrestacion, c.MontoContrato,
                              c.FechaInicio, c.PlazoDias, c.FechaFinPrevista,
                              c.NombreProveedor, c.RucProveedor, c.DniProveedor, c.CorreoProveedor,
                              UnidadOrigen = uo.Sigla, UnidadOrigenNombre = uo.Nombre,
                              s.Tipo, s.Origen, s.FechaPresentacion, s.Asunto, s.Sustento, s.SolicitudDocumento,
                              s.FechaFinHechoGenerador, s.FechaLimitePresentacion, s.PresentadaEnPlazo, s.DiasSolicitados,
                              s.DiasOtorgados, s.FechaFinAnterior, s.NuevaFechaFin, s.DetalleModificacion,
                              s.ResultadoAu, s.InformeAu, s.InformeAuDocumento, s.OpinionAuEn,
                              OpinionAuPor = (SELECT CONCAT(u.Nombres, N' ', u.Apellidos) FROM sigcm.Usuario AS u WHERE u.IdUsuario = s.IdActorOpinionAu),
                              s.ResultadoDec, s.MotivoDec, s.InformeDecDocumento, s.DecisionEn, s.AceptacionTacita,
                              DecisionPor = (SELECT CONCAT(u.Nombres, N' ', u.Apellidos) FROM sigcm.Usuario AS u WHERE u.IdUsuario = s.IdActorDecision),
                              s.NumeroActa, s.ActaDocumento, s.RegistroPladicop, s.SuscritaProveedorEn,
                              s.NumeroCarta, s.CartaDocumento, s.NotificadaEn, s.MedioNotificacion, s.ResultadoNotificacion,
                              /* 7.3.5.4: vencido este plazo sin decision, la ampliacion se entiende aceptada. */
                              VenceDecision = (SELECT TOP 1 COALESCE(pl.AmpliadoHasta, pl.Vencimiento) FROM sigcm.Plazo AS pl
                                                WHERE pl.IdExpediente = e.IdExpediente AND pl.CodigoRegla = 'AMP_DECISION_DEC' AND pl.Activo = 1),
                              DecisionVencida = CONVERT(bit, CASE WHEN s.Tipo = 'AMPLIACION_PLAZO' AND w.EsFinal = 0 AND EXISTS (
                                                    SELECT 1 FROM sigcm.Plazo AS pl WHERE pl.IdExpediente = e.IdExpediente
                                                       AND pl.CodigoRegla = 'AMP_DECISION_DEC' AND pl.Estado = 'EN_CURSO' AND pl.Activo = 1
                                                       AND COALESCE(pl.AmpliadoHasta, pl.Vencimiento) < @Hoy) THEN 1 ELSE 0 END),
                              Plazos = JSON_QUERY(COALESCE((
                                  SELECT pl.CodigoRegla, Nombre = pr.Nombre, pl.Inicio, pl.Vencimiento, pl.AmpliadoHasta, pl.CumplidoEn, pl.Estado
                                    FROM sigcm.Plazo AS pl JOIN sigcm.PlazoRegla AS pr ON pr.CodigoRegla = pl.CodigoRegla
                                   WHERE pl.IdExpediente = e.IdExpediente AND pl.Activo = 1 ORDER BY pl.Inicio FOR JSON PATH), N'[]')),
                              Transiciones = JSON_QUERY(ampliacion.fnTransicionesJson(e.CodigoEstado, @CodigoRol)),
                              /* Que puede hacer este actor ademas de las transiciones. */
                              PuedeOpinarAu = CONVERT(bit, CASE WHEN @CodigoRol LIKE 'AREA[_]%' AND e.CodigoEstado IN ('MOD_PRESENTADA','MOD_EN_SUSTENTO_AU','AMP_EN_OPINION_AU') THEN 1 ELSE 0 END),
                              PuedeDecidirDec = CONVERT(bit, CASE WHEN @CodigoRol IN ('ABAST_ESPECIALISTA','ABAST_COORDINADOR') AND e.CodigoEstado IN ('MOD_EN_EVALUACION_DEC','AMP_PRESENTADA','AMP_EN_DECISION_DEC') THEN 1 ELSE 0 END),
                              PuedeEmitirActa = CONVERT(bit, CASE WHEN @CodigoRol = 'ABAST_JEFE' AND e.CodigoEstado = 'MOD_POR_FIRMA_ACTA' THEN 1 ELSE 0 END),
                              PuedeNotificar = CONVERT(bit, CASE WHEN @CodigoRol LIKE 'ABAST[_]%' AND w.EsFinal = 1 AND s.NotificadaEn IS NULL THEN 1 ELSE 0 END)
                         FROM ampliacion.Solicitud AS s
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
                         JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                         JOIN ejecucion.Contrato AS c ON c.IdContrato = s.IdContrato
                         JOIN sigcm.Expediente AS ec ON ec.IdExpediente = c.IdExpediente
                         JOIN sigcm.Unidad AS uo ON uo.IdUnidad = e.IdUnidadOrigen
                        WHERE s.IdSolicitud = @IdSolicitud
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
/* 4. ampliacion.paOpinarAu                                                  */
/*    MOD_PRESENTADA: acepta (y pasa a sustentar) o rechaza con informe.     */
/*    MOD_EN_SUSTENTO_AU: eleva el sustento al jefe.                         */
/*    AMP_EN_OPINION_AU: emite la opinion tecnica (7.3.5.2).                 */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ampliacion.paOpinarAu
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52150, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdExpediente uniqueidentifier, @Resultado varchar(15), @Informe nvarchar(max), @Doc nvarchar(200), @Detalle nvarchar(max);
        SELECT @IdExpediente = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @Resultado = UPPER(NULLIF(LTRIM(RTRIM(Resultado)), '')),
               @Informe = NULLIF(LTRIM(RTRIM(Informe)), N''),
               @Doc = NULLIF(LTRIM(RTRIM(InformeDocumento)), N''),
               @Detalle = NULLIF(LTRIM(RTRIM(DetalleModificacion)), N'')
          FROM OPENJSON(@parametro) WITH (IdExpediente varchar(50), Resultado varchar(15), Informe nvarchar(max),
                                          InformeDocumento nvarchar(200), DetalleModificacion nvarchar(max));
        IF @IdExpediente IS NULL THROW 52151, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @Resultado NOT IN ('PROCEDE', 'NO_PROCEDE') THROW 52152, 'VALIDACION_RESULTADO: la opinion es PROCEDE o NO_PROCEDE.', 1;
        IF @Informe IS NULL THROW 52153, 'VALIDACION_PAYLOAD: el informe del area usuaria es obligatorio.', 1;

        DECLARE @IdSolicitud uniqueidentifier, @Estado varchar(60), @Tipo varchar(20);
        SELECT @IdSolicitud = s.IdSolicitud, @Estado = e.CodigoEstado, @Tipo = s.Tipo
          FROM ampliacion.Solicitud AS s JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
         WHERE s.IdExpediente = @IdExpediente AND s.Activo = 1;
        IF @IdSolicitud IS NULL THROW 52154, 'NO_ENCONTRADO: la solicitud no existe.', 1;

        DECLARE @Transicion varchar(70) =
            CASE WHEN @Estado = 'MOD_PRESENTADA' AND @Resultado = 'PROCEDE' THEN 'MOD_ACEPTAR_AU'
                 WHEN @Estado = 'MOD_PRESENTADA' THEN 'MOD_RECHAZAR_AU'
                 WHEN @Estado = 'MOD_EN_SUSTENTO_AU' AND @Resultado = 'PROCEDE' THEN 'MOD_ELEVAR_SUSTENTO'
                 WHEN @Estado = 'AMP_EN_OPINION_AU' THEN 'AMP_OPINAR_AU' END;
        IF @Transicion IS NULL
            THROW 52155, 'CONFLICTO_ESTADO: la solicitud no esta en manos del area usuaria, o el sustento propio no se puede declarar improcedente.', 1;

        DECLARE @Ahora datetime = GETDATE();
        UPDATE ampliacion.Solicitud
           SET ResultadoAu = @Resultado, InformeAu = @Informe, InformeAuDocumento = COALESCE(@Doc, InformeAuDocumento),
               DetalleModificacion = COALESCE(@Detalle, DetalleModificacion),
               OpinionAuEn = @Ahora, IdActorOpinionAu = @IdUsuario,
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdSolicitud = @IdSolicitud;

        IF @Estado = 'AMP_EN_OPINION_AU'
            UPDATE sigcm.Plazo SET CumplidoEn = @Ahora,
                   Estado = CASE WHEN CONVERT(date, @Ahora) <= COALESCE(AmpliadoHasta, Vencimiento) THEN 'CUMPLIDO' ELSE 'VENCIDO' END
             WHERE IdExpediente = @IdExpediente AND CodigoRegla = 'AMP_OPINION_AU' AND Estado = 'EN_CURSO' AND Activo = 1;

        IF JSON_VALUE(@parametro, '$.Comentario') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Comentario', LEFT(@Informe, 1000));

        EXEC ampliacion.paMoverSolicitudInterno @parametro, @IdSolicitud, @Transicion;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 5. ampliacion.paDecidirDec                                                */
/*    MOD_EN_EVALUACION_DEC: procedente (acta) o denegada.                   */
/*    AMP_PRESENTADA: denegar directo (7.3.5.3).                             */
/*    AMP_EN_DECISION_DEC: aprobar (mueve el fin del contrato) o denegar.    */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ampliacion.paDecidirDec
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52160, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdExpediente uniqueidentifier, @Resultado varchar(15), @Motivo nvarchar(max), @DiasOtorgados int,
                @InformeDoc nvarchar(200), @CartaDoc nvarchar(200), @NumeroCarta varchar(40);
        SELECT @IdExpediente = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @Resultado = UPPER(NULLIF(LTRIM(RTRIM(Resultado)), '')),
               @Motivo = NULLIF(LTRIM(RTRIM(Motivo)), N''),
               @DiasOtorgados = DiasOtorgados,
               @InformeDoc = NULLIF(LTRIM(RTRIM(InformeDecDocumento)), N''),
               @CartaDoc = NULLIF(LTRIM(RTRIM(CartaDocumento)), N''),
               @NumeroCarta = NULLIF(LTRIM(RTRIM(NumeroCarta)), '')
          FROM OPENJSON(@parametro) WITH (IdExpediente varchar(50), Resultado varchar(15), Motivo nvarchar(max), DiasOtorgados int,
                                          InformeDecDocumento nvarchar(200), CartaDocumento nvarchar(200), NumeroCarta varchar(40));
        IF @IdExpediente IS NULL THROW 52161, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @Resultado NOT IN ('APROBADA', 'DENEGADA') THROW 52162, 'VALIDACION_RESULTADO: la decision es APROBADA o DENEGADA.', 1;
        IF @Motivo IS NULL THROW 52163, 'VALIDACION_PAYLOAD: indique el motivo de la decision.', 1;

        DECLARE @IdSolicitud uniqueidentifier, @Estado varchar(60), @Tipo varchar(20), @IdContrato uniqueidentifier,
                @DiasSolicitados int, @FechaFin date, @IdExpContrato uniqueidentifier, @EnPlazo bit;
        SELECT @IdSolicitud = s.IdSolicitud, @Estado = e.CodigoEstado, @Tipo = s.Tipo, @IdContrato = s.IdContrato,
               @DiasSolicitados = s.DiasSolicitados, @FechaFin = c.FechaFinPrevista, @IdExpContrato = c.IdExpediente, @EnPlazo = s.PresentadaEnPlazo
          FROM ampliacion.Solicitud AS s JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
          JOIN ejecucion.Contrato AS c ON c.IdContrato = s.IdContrato
         WHERE s.IdExpediente = @IdExpediente AND s.Activo = 1;
        IF @IdSolicitud IS NULL THROW 52164, 'NO_ENCONTRADO: la solicitud no existe.', 1;

        DECLARE @Transicion varchar(70) =
            CASE WHEN @Estado = 'MOD_EN_EVALUACION_DEC' AND @Resultado = 'APROBADA' THEN 'MOD_APROBAR_DEC'
                 WHEN @Estado = 'MOD_EN_EVALUACION_DEC' THEN 'MOD_DENEGAR_DEC'
                 WHEN @Estado = 'AMP_PRESENTADA' AND @Resultado = 'DENEGADA' THEN 'AMP_DENEGAR_DIRECTO'
                 WHEN @Estado = 'AMP_EN_DECISION_DEC' AND @Resultado = 'APROBADA' THEN 'AMP_APROBAR'
                 WHEN @Estado = 'AMP_EN_DECISION_DEC' THEN 'AMP_DENEGAR' END;
        IF @Transicion IS NULL
            THROW 52165, 'CONFLICTO_ESTADO: la solicitud no esta en manos de la DEC para esa decision (la ampliacion presentada en plazo exige la opinion del AU antes de aprobarse).', 1;

        DECLARE @Hoy date = CONVERT(date, GETDATE()), @Ahora datetime = GETDATE();

        /* 7.3.5.4: sin pronunciamiento en 7 dias habiles se entiende aceptada.
           Denegar despues del vencimiento contradiria la Directiva. */
        DECLARE @Tacita bit = 0;
        IF @Tipo = 'AMPLIACION_PLAZO' AND EXISTS (
            SELECT 1 FROM sigcm.Plazo WHERE IdExpediente = @IdExpediente AND CodigoRegla = 'AMP_DECISION_DEC'
               AND Estado = 'EN_CURSO' AND Activo = 1 AND COALESCE(AmpliadoHasta, Vencimiento) < @Hoy)
        BEGIN
            IF @Resultado = 'DENEGADA'
                THROW 52166, 'CONFLICTO_PLAZO: vencieron los siete dias habiles sin pronunciamiento; la ampliacion se entiende aceptada (7.3.5.4) y solo puede registrarse como aprobada.', 1;
            SET @Tacita = 1;
        END

        DECLARE @NuevaFin date = NULL;
        IF @Transicion = 'AMP_APROBAR'
        BEGIN
            SET @DiasOtorgados = COALESCE(NULLIF(@DiasOtorgados, 0), @DiasSolicitados);
            IF @DiasOtorgados < 1 OR @DiasOtorgados > @DiasSolicitados
                THROW 52167, 'VALIDACION_DIAS: los dias otorgados van de 1 hasta los dias solicitados.', 1;
            SET @NuevaFin = DATEADD(DAY, @DiasOtorgados, @FechaFin);
        END

        BEGIN TRANSACTION;

        UPDATE ampliacion.Solicitud
           SET ResultadoDec = @Resultado, MotivoDec = @Motivo, DecisionEn = @Ahora, IdActorDecision = @IdUsuario,
               AceptacionTacita = @Tacita,
               DiasOtorgados = CASE WHEN @Transicion = 'AMP_APROBAR' THEN @DiasOtorgados ELSE DiasOtorgados END,
               FechaFinAnterior = CASE WHEN @Transicion = 'AMP_APROBAR' THEN @FechaFin ELSE FechaFinAnterior END,
               NuevaFechaFin = CASE WHEN @Transicion = 'AMP_APROBAR' THEN @NuevaFin ELSE NuevaFechaFin END,
               InformeDecDocumento = COALESCE(@InformeDoc, InformeDecDocumento),
               CartaDocumento = COALESCE(@CartaDoc, CartaDocumento),
               NumeroCarta = COALESCE(@NumeroCarta, NumeroCarta),
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdSolicitud = @IdSolicitud;

        IF @Transicion = 'AMP_APROBAR'
        BEGIN
            UPDATE ejecucion.Contrato
               SET FechaFinPrevista = @NuevaFin, PlazoDias = PlazoDias + @DiasOtorgados,
                   UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
                   EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
             WHERE IdContrato = @IdContrato;

            UPDATE sigcm.Plazo
               SET AmpliadoHasta = @NuevaFin,
                   MotivoAmpliacion = CONCAT(N'Ampliacion de plazo aprobada: ', @DiasOtorgados, N' dias (', @Motivo, N')'),
                   UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora
             WHERE IdExpediente = @IdExpContrato AND CodigoRegla = 'EJE_EJECUCION_CONTRATO' AND Estado = 'EN_CURSO' AND Activo = 1;

            INSERT INTO sigcm.Historial (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion, Comentario,
                                         IdActor, ActorRol, IdActorUnidad, UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            SELECT e.IdExpediente, e.CodigoEstado, e.CodigoEstado, NULL,
                   CONCAT(N'Plazo ampliado en ', @DiasOtorgados, N' dias: el fin previsto pasa del ',
                          CONVERT(varchar(10), @FechaFin, 103), N' al ', CONVERT(varchar(10), @NuevaFin, 103), N'.'),
                   @IdUsuario, @CodigoRol, @IdUnidad, @Cuenta, @Equipo, @Programa
              FROM sigcm.Expediente AS e WHERE e.IdExpediente = @IdExpContrato;
        END

        IF @Tipo = 'AMPLIACION_PLAZO'
            UPDATE sigcm.Plazo SET CumplidoEn = @Ahora,
                   Estado = CASE WHEN @Hoy <= COALESCE(AmpliadoHasta, Vencimiento) THEN 'CUMPLIDO' ELSE 'VENCIDO' END
             WHERE IdExpediente = @IdExpediente AND CodigoRegla IN ('AMP_REMISION_DEC', 'AMP_DECISION_DEC') AND Estado = 'EN_CURSO' AND Activo = 1;

        COMMIT TRANSACTION;

        IF JSON_VALUE(@parametro, '$.Comentario') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Comentario', LEFT(@Motivo, 1000));

        EXEC ampliacion.paMoverSolicitudInterno @parametro, @IdSolicitud, @Transicion;
        RETURN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 6. ampliacion.paRegistrarActa                                             */
/*    El jefe de Abastecimiento genera el acta antes de firmarla.            */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ampliacion.paRegistrarActa
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52170, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        IF @CodigoRol NOT LIKE 'ABAST[_]%' THROW 52171, 'NO_AUTORIZADO: el acta la emite Abastecimiento.', 1;

        DECLARE @IdExpediente uniqueidentifier, @Numero varchar(40), @Doc nvarchar(200), @Pladicop varchar(60);
        SELECT @IdExpediente = TRY_CONVERT(uniqueidentifier, IdExpediente), @Numero = NULLIF(LTRIM(RTRIM(NumeroActa)), ''),
               @Doc = NULLIF(LTRIM(RTRIM(ActaDocumento)), N''), @Pladicop = NULLIF(LTRIM(RTRIM(RegistroPladicop)), '')
          FROM OPENJSON(@parametro) WITH (IdExpediente varchar(50), NumeroActa varchar(40), ActaDocumento nvarchar(200), RegistroPladicop varchar(60));
        IF @IdExpediente IS NULL THROW 52172, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @Estado varchar(60), @Tipo varchar(20);
        SELECT @Estado = e.CodigoEstado, @Tipo = s.Tipo FROM ampliacion.Solicitud AS s JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
         WHERE s.IdExpediente = @IdExpediente AND s.Activo = 1;
        IF @Estado IS NULL THROW 52173, 'NO_ENCONTRADO: la solicitud no existe.', 1;
        IF @Tipo <> 'MODIFICACION' THROW 52174, 'CONFLICTO_TIPO: la ampliacion de plazo no lleva acta.', 1;
        IF @Estado NOT IN ('MOD_POR_FIRMA_ACTA', 'MOD_POR_SUSCRIPCION', 'MOD_APROBADA')
            THROW 52175, 'CONFLICTO_ESTADO: el acta se emite cuando la DEC ya declaro procedente la modificacion.', 1;

        /* El acta se numera una vez; despues solo se completa el registro Pladicop. */
        UPDATE ampliacion.Solicitud
           SET NumeroActa = COALESCE(NumeroActa, @Numero), ActaDocumento = COALESCE(@Doc, ActaDocumento),
               RegistroPladicop = COALESCE(@Pladicop, RegistroPladicop),
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdExpediente = @IdExpediente;

        SELECT @resultado = (SELECT 1 AS estado, N'Se registro el acta de modificacion.' AS mensaje FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 7. ampliacion.paEjecutarAccion                                            */
/*    Transiciones sin datos propios: remitir, firmar el acta, suscribirla.  */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ampliacion.paEjecutarAccion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52180, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @Transicion varchar(70) = JSON_VALUE(@parametro, '$.CodigoTransicion');
        IF @IdExpediente IS NULL OR @Transicion IS NULL THROW 52181, 'VALIDACION_PAYLOAD: faltan IdExpediente y CodigoTransicion.', 1;

        DECLARE @IdSolicitud uniqueidentifier, @Ahora datetime = GETDATE(), @Hoy date = CONVERT(date, GETDATE());
        SELECT @IdSolicitud = IdSolicitud FROM ampliacion.Solicitud WHERE IdExpediente = @IdExpediente AND Activo = 1;
        IF @IdSolicitud IS NULL THROW 52182, 'NO_ENCONTRADO: la solicitud no existe.', 1;

        IF @Transicion = 'MOD_FIRMAR_ACTA' AND NOT EXISTS (SELECT 1 FROM ampliacion.Solicitud WHERE IdSolicitud = @IdSolicitud AND ActaDocumento IS NOT NULL)
            THROW 52183, 'CONFLICTO_DOCUMENTO: genere el acta de modificacion antes de firmarla.', 1;

        IF @Transicion = 'MOD_SUSCRIBIR_ACTA'
            UPDATE ampliacion.Solicitud SET SuscritaProveedorEn = @Ahora,
                   UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora
             WHERE IdSolicitud = @IdSolicitud;

        IF @Transicion = 'AMP_REMITIR_AU'
        BEGIN
            UPDATE sigcm.Plazo SET CumplidoEn = @Ahora,
                   Estado = CASE WHEN @Hoy <= COALESCE(AmpliadoHasta, Vencimiento) THEN 'CUMPLIDO' ELSE 'VENCIDO' END
             WHERE IdExpediente = @IdExpediente AND CodigoRegla = 'AMP_REMISION_DEC' AND Estado = 'EN_CURSO' AND Activo = 1;
            IF NOT EXISTS (SELECT 1 FROM sigcm.Plazo WHERE IdExpediente = @IdExpediente AND CodigoRegla = 'AMP_OPINION_AU' AND Activo = 1)
                INSERT INTO sigcm.Plazo (IdExpediente, CodigoRegla, Inicio, Vencimiento, Estado, UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                VALUES (@IdExpediente, 'AMP_OPINION_AU', @Ahora, sigcm.fnSumarDiasHabiles(@Hoy, 3), 'EN_CURSO', @Cuenta, @Equipo, @Programa);
        END

        EXEC ampliacion.paMoverSolicitudInterno @parametro, @IdSolicitud, @Transicion;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 8. ampliacion.paPrepararNotificacion / paMarcarNotificada                 */
/*    El sobre del correo al proveedor (7.3.5.4). SMTP lo hace el puente.    */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ampliacion.paPrepararNotificacion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52190, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120), @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier, @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50), @CorrelacionId uniqueidentifier;
        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        IF @CodigoRol NOT LIKE 'ABAST[_]%' THROW 52191, 'NO_AUTORIZADO: la DEC notifica al proveedor.', 1;

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        IF @IdExpediente IS NULL THROW 52192, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @Codigo varchar(40), @Estado varchar(60), @EsFinal bit, @Tipo varchar(20), @Decision varchar(15),
                @Correo varchar(200), @Proveedor nvarchar(250), @Orden varchar(40), @Denominacion varchar(500),
                @Dias int, @NuevaFin date, @Motivo nvarchar(max), @Carta nvarchar(200), @Acta nvarchar(200),
                @CorreoAu varchar(200), @Tacita bit;
        SELECT @Codigo = e.Codigo, @Estado = e.CodigoEstado, @EsFinal = w.EsFinal, @Tipo = s.Tipo, @Decision = s.ResultadoDec,
               @Correo = c.CorreoProveedor, @Proveedor = c.NombreProveedor, @Orden = c.NumeroOrdenSiga, @Denominacion = c.Denominacion,
               @Dias = s.DiasOtorgados, @NuevaFin = s.NuevaFechaFin, @Motivo = s.MotivoDec, @Carta = s.CartaDocumento, @Acta = s.ActaDocumento,
               @Tacita = s.AceptacionTacita,
               @CorreoAu = (SELECT u.Correo FROM sigcm.Usuario AS u WHERE u.IdUsuario = c.IdSupervisor)
          FROM ampliacion.Solicitud AS s JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
          JOIN ejecucion.Contrato AS c ON c.IdContrato = s.IdContrato
         WHERE s.IdExpediente = @IdExpediente AND s.Activo = 1;
        IF @Codigo IS NULL THROW 52193, 'NO_ENCONTRADO: la solicitud no existe.', 1;
        IF @EsFinal = 0 THROW 52194, 'CONFLICTO_ESTADO: la solicitud todavia no tiene decision que notificar.', 1;
        IF NULLIF(@Correo, '') IS NULL THROW 52195, 'VALIDACION_CORREO: el contrato no tiene correo del proveedor.', 1;

        DECLARE @Asunto nvarchar(300) = CONCAT(
            CASE WHEN @Tipo = 'AMPLIACION_PLAZO' THEN N'Ampliacion de plazo ' ELSE N'Modificacion del contrato ' END,
            CASE WHEN @Decision = 'APROBADA' THEN N'aprobada' ELSE N'denegada' END,
            N' - O/S ', ISNULL(@Orden, N''), N' - ', @Codigo);

        DECLARE @Cuerpo nvarchar(max) = CONCAT(
            N'Estimado(a) ', ISNULL(@Proveedor, N'proveedor'), N':<br><br>',
            N'En relacion con la orden ', ISNULL(@Orden, N''), N' (', ISNULL(@Denominacion, N''), N'), la Direccion de Ejecucion de Contrataciones comunica que ',
            CASE WHEN @Tipo = 'AMPLIACION_PLAZO' AND @Decision = 'APROBADA'
                 THEN CONCAT(N'la solicitud de ampliacion de plazo ha sido <b>aprobada</b> por ', @Dias, N' dias calendario. El nuevo plazo de ejecucion vence el ',
                             CONVERT(varchar(10), @NuevaFin, 103), N'.', CASE WHEN @Tacita = 1 THEN N' (Directiva 002-2026-ANIN, 7.3.5.4.)' ELSE N'' END)
                 WHEN @Tipo = 'AMPLIACION_PLAZO' THEN N'la solicitud de ampliacion de plazo ha sido <b>denegada</b>.'
                 WHEN @Decision = 'APROBADA' THEN N'la modificacion del contrato ha sido <b>aprobada</b>. Se adjunta el acta de modificacion suscrita.'
                 ELSE N'la solicitud de modificacion del contrato ha sido <b>denegada</b>.' END,
            N'<br><br>Sustento: ', ISNULL(@Motivo, N''),
            N'<br><br>Expediente ', @Codigo, N'.<br>Autoridad Nacional de Infraestructura - SIGCM');

        SELECT @resultado = (
            SELECT 1 AS estado, Destinatario = @Correo, Copia = @CorreoAu, Asunto = @Asunto, Cuerpo = @Cuerpo,
                   AdjuntoDocumento = COALESCE(CASE WHEN @Decision = 'APROBADA' AND @Tipo = 'MODIFICACION' THEN @Acta END, @Carta),
                   NombreAdjunto = CASE WHEN @Decision = 'APROBADA' AND @Tipo = 'MODIFICACION' AND @Acta IS NOT NULL THEN CONCAT('Acta de modificacion - ', @Codigo, '.pdf')
                                        WHEN @Carta IS NOT NULL THEN CONCAT('Carta - ', @Codigo, '.pdf') END,
                   Carpeta = 'modificacion'
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ampliacion.paMarcarNotificada
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1 THROW 52196, 'JSON incorrecto.', 1;

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
        IF @IdExpediente IS NULL THROW 52197, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @Ahora datetime = GETDATE();
        /* Un correo que no salio no es una notificacion: se anota el resultado
           y se deja NotificadaEn en nulo para poder reintentar. */
        UPDATE ampliacion.Solicitud
           SET NotificadaEn = CASE WHEN @Enviado = 1 OR @Medio <> 'CORREO' THEN @Ahora ELSE NotificadaEn END,
               MedioNotificacion = @Medio, ResultadoNotificacion = @ResultadoCorreo,
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdExpediente = @IdExpediente AND Activo = 1;

        INSERT INTO sigcm.Historial (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion, Comentario,
                                     IdActor, ActorRol, IdActorUnidad, UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT e.IdExpediente, e.CodigoEstado, e.CodigoEstado, NULL,
               CONCAT(CASE WHEN @Enviado = 1 THEN N'Decision notificada al proveedor por correo' ELSE N'Intento de notificacion al proveedor' END,
                      CASE WHEN @ResultadoCorreo IS NOT NULL THEN N': ' + @ResultadoCorreo ELSE N'' END),
               @IdUsuario, @CodigoRol, @IdUnidad, @Cuenta, @Equipo, @Programa
          FROM sigcm.Expediente AS e WHERE e.IdExpediente = @IdExpediente;

        SELECT @resultado = (SELECT 1 AS estado,
                                    mensaje = CASE WHEN @Enviado = 1 THEN N'Se notifico la decision al proveedor.' ELSE N'Se registro el intento de notificacion.' END
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F017 aplicada: solicitudes de modificacion y ampliacion de plazo.';
GO
