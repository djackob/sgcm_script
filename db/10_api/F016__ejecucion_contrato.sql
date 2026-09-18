/*
===============================================================================
  SIGCM - F016 : Ejecucion contractual - contrato, entregas de bienes e incidencias
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 52000-52099

  Directiva 002-2026-ANIN 7.3. Bizagi "3. EJECUCION". Analisis en
  docs/analisis-modulo-ejecucion.md.

  C# es ControladorPuente. La maquina de estados es sigcm.paEjecutarTransicion
  (S038). Aqui vive lo que esa maquina no puede:

    - abrir el contrato desde la orden notificada (7.3.1) y su plazo;
    - crear cada entrega de bienes con su propio expediente, en la ruta que
      manda el lugar de entrega (7.3.6.3 a / b);
    - guardar lo que cada accion trae consigo: la guia, el verificador
      designado, el resultado de la verificacion, el acta, la Pecosa;
    - resolver a QUE UNIDAD queda la entrega tras cada accion. El motor la
      deduce por rol y su regla 3 exige una unidad unica CON centro de costo
      SIGA; Abastecimiento no siempre lo tiene cargado y la entrega se quedaria
      en el area usuaria con un estado de Almacen. Por eso aqui se manda
      IdUnidadDestino explicito, siempre;
    - registrar y atender incidencias (7.3.3), que no mueven el expediente;
    - culminar el contrato cuando todos los entregables tienen conformidad.

  La rama de SERVICIOS (presentar entregable -> Anexo 11) es el modulo PAGO.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ========================================================================== */
/* 0. Utilitarios internos (sin result set)                                  */
/* ========================================================================== */

/* A que unidad va un expediente cuyo estado destino declara @RolDestino.
   - Roles del area usuaria: la unidad de origen del contrato.
   - Roles de Abastecimiento: la unidad que ejerce ABAST_ESPECIALISTA; si hay
     varias, la que tiene centro de costo SIGA; si sigue habiendo varias, la de
     codigo UO-ABAST.
   - PROVEEDOR: la unidad donde el proveedor del contrato tiene su rol; si no
     se le encuentra, la unidad de origen (misma salida que Pagos).
   - Sin rol (estado final): se conserva la actual, y se devuelve NULL. */
CREATE OR ALTER PROCEDURE ejecucion.paResolverUnidadDestinoInterno
    @IdContrato  uniqueidentifier,
    @RolDestino  varchar(40),
    @IdUnidad    uniqueidentifier OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @IdUnidad = NULL;

    IF @RolDestino IS NULL RETURN;

    DECLARE @IdUnidadOrigen uniqueidentifier, @Ruc varchar(11), @Dni varchar(15), @Correo varchar(200);
    SELECT @IdUnidadOrigen = e.IdUnidadOrigen, @Ruc = c.RucProveedor,
           @Dni = c.DniProveedor, @Correo = c.CorreoProveedor
      FROM ejecucion.Contrato AS c
      JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
     WHERE c.IdContrato = @IdContrato;

    IF @RolDestino LIKE 'AREA[_]%'
    BEGIN
        SET @IdUnidad = @IdUnidadOrigen;
        RETURN;
    END

    IF @RolDestino LIKE 'ABAST[_]%'
    BEGIN
        SELECT TOP 1 @IdUnidad = ur.IdUnidad
          FROM sigcm.UsuarioRol AS ur
          JOIN sigcm.Unidad AS n ON n.IdUnidad = ur.IdUnidad
         WHERE ur.CodigoRol = 'ABAST_ESPECIALISTA' AND ur.Activo = 1 AND n.Activo = 1
           AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()))
         ORDER BY CASE WHEN NULLIF(LTRIM(RTRIM(n.CentroCostoSiga)), '') IS NOT NULL THEN 0 ELSE 1 END,
                  CASE WHEN n.Codigo = 'UO-ABAST' THEN 0 ELSE 1 END,
                  n.Codigo;
        RETURN;
    END

    IF @RolDestino = 'PROVEEDOR'
    BEGIN
        SELECT TOP 1 @IdUnidad = ur.IdUnidad
          FROM sigcm.UsuarioRol AS ur
          JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
          JOIN sigcm.Unidad AS n ON n.IdUnidad = ur.IdUnidad
         WHERE ur.CodigoRol = 'PROVEEDOR' AND ur.Activo = 1 AND u.Activo = 1 AND n.Activo = 1
           AND (   (@Ruc IS NOT NULL AND (u.DocumentoIdentidad = @Ruc OR u.Cuenta = @Ruc))
                OR (@Dni IS NOT NULL AND (u.DocumentoIdentidad = @Dni OR u.Cuenta = @Dni))
                OR (@Correo IS NOT NULL AND u.Correo = @Correo))
         ORDER BY CASE WHEN ur.IdUnidad = @IdUnidadOrigen THEN 0 ELSE 1 END, n.Codigo;

        IF @IdUnidad IS NULL SET @IdUnidad = @IdUnidadOrigen;
        RETURN;
    END

    /* OA, ADMIN u otro: la unidad unica con ese rol, si existe. */
    IF (SELECT COUNT(DISTINCT ur.IdUnidad) FROM sigcm.UsuarioRol AS ur
         WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1) = 1
        SELECT @IdUnidad = MIN(ur.IdUnidad) FROM sigcm.UsuarioRol AS ur
         WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1;
END
GO

/* Ejecuta una transicion sobre el expediente de una entrega, con la unidad de
   destino ya resuelta. Devuelve el result set del motor, que es la respuesta
   que ve el cliente. Las rutinas publicas graban primero lo suyo y terminan
   aqui. */
CREATE OR ALTER PROCEDURE ejecucion.paMoverEntregaInterno
    @parametro        nvarchar(max),
    @IdEntrega        uniqueidentifier,
    @CodigoTransicion varchar(70)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdExpediente uniqueidentifier, @IdContrato uniqueidentifier, @Version int,
            @EstadoActual varchar(60), @EstadoDestino varchar(60), @RolDestino varchar(40),
            @IdUnidadDestino uniqueidentifier;

    SELECT @IdExpediente = en.IdExpediente, @IdContrato = en.IdContrato,
           @Version = e.Version, @EstadoActual = e.CodigoEstado
      FROM ejecucion.Entrega AS en
      JOIN sigcm.Expediente AS e ON e.IdExpediente = en.IdExpediente
     WHERE en.IdEntrega = @IdEntrega AND en.Activo = 1;

    IF @IdExpediente IS NULL
        THROW 52001, 'NO_ENCONTRADO: la entrega no existe.', 1;

    SELECT @EstadoDestino = t.CodigoEstadoDestino
      FROM sigcm.Transicion AS t
     WHERE t.CodigoTransicion = @CodigoTransicion AND t.Activo = 1;

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

/* ========================================================================== */
/* 1. ejecucion.paAbrirDesdeOrdenServicioInterno                             */
/*    Sin result set. Idempotente. Lo llama requerimiento.paMarcarOrden-      */
/*    Notificada en el mismo punto donde abre los expedientes de pago.        */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paAbrirDesdeOrdenServicioInterno
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISJSON(@parametro) <> 1
        THROW 52010, 'JSON incorrecto.', 1;

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
        THROW 52011, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

    /* Ya abierto: nada que hacer. */
    IF EXISTS (SELECT 1 FROM ejecucion.Contrato WHERE IdRequerimiento = @IdRequerimiento AND Activo = 1)
        RETURN;

    DECLARE @IdExpReq uniqueidentifier, @CodigoReq varchar(40), @AnoEje smallint,
            @Denominacion varchar(500), @Monto decimal(18,2), @PlazoDias int,
            @IdUnidadOrigen uniqueidentifier, @Datos nvarchar(max),
            @TipoCon varchar(20), @IdResponsable uniqueidentifier;

    SELECT @IdExpReq = r.IdExpediente, @CodigoReq = r.Codigo, @AnoEje = r.AnoEje,
           @Denominacion = r.Denominacion, @Monto = r.Monto, @PlazoDias = r.PlazoDias,
           @Datos = r.DatosAdicionales, @TipoCon = r.CodigoTipoContratacion,
           @IdResponsable = r.IdResponsable
      FROM requerimiento.Requerimiento AS r
     WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1;

    IF @IdExpReq IS NULL
        THROW 52012, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

    SELECT @IdUnidadOrigen = e.IdUnidadOrigen FROM sigcm.Expediente AS e WHERE e.IdExpediente = @IdExpReq;

    DECLARE @IdOrden uniqueidentifier, @NumeroOrden varchar(40),
            @NotificadoEn datetime, @FechaEmision datetime, @CorreoOs varchar(200);

    SELECT @IdOrden = o.IdOrdenServicio, @NumeroOrden = o.NumeroOrden,
           @NotificadoEn = o.NotificadoEn, @FechaEmision = o.FechaEmision,
           @CorreoOs = o.CorreoLocador
      FROM requerimiento.OrdenServicio AS o
     WHERE o.IdRequerimiento = @IdRequerimiento AND o.Activo = 1;

    /* Sin orden no hay contrato que ejecutar (7.3.1). */
    IF @IdOrden IS NULL
        RETURN;

    DECLARE @Prov nvarchar(max) = COALESCE(
        JSON_QUERY(@Datos, '$.Proveedores[0]'),
        JSON_QUERY(@Datos, '$.Proveedor'));

    DECLARE @Ruc varchar(11) = NULLIF(JSON_VALUE(@Prov, '$.Ruc'), ''),
            @Dni varchar(15) = NULLIF(JSON_VALUE(@Prov, '$.Dni'), ''),
            @Email varchar(200) = COALESCE(NULLIF(JSON_VALUE(@Prov, '$.Email'), ''), @CorreoOs);

    /* Mismo respaldo que F011 y F012: la razon social manda cuando el
       proveedor se identifico por RUC. */
    DECLARE @NombreProveedor nvarchar(250) = COALESCE(
        NULLIF(LTRIM(RTRIM(JSON_VALUE(@Prov, '$.RazonSocial'))), N''),
        NULLIF(LTRIM(RTRIM(CONCAT(ISNULL(JSON_VALUE(@Prov, '$.Nombres'), N''), N' ',
                                  ISNULL(JSON_VALUE(@Prov, '$.ApellidoPaterno'), N''), N' ',
                                  ISNULL(JSON_VALUE(@Prov, '$.ApellidoMaterno'), N'')))), N''));

    /* 7.3.1: la ejecucion se inicia el dia calendario siguiente a la
       notificacion. Si la orden todavia no tiene NotificadoEn -la rutina que
       nos llama lo acaba de escribir en la misma transaccion, pero por si
       llega de otro lado- se toma la emision. */
    DECLARE @FechaNotif datetime = COALESCE(@NotificadoEn, @FechaEmision, GETDATE());
    DECLARE @FechaInicio date = DATEADD(DAY, 1, CONVERT(date, @FechaNotif));
    IF ISNULL(@PlazoDias, 0) < 1 SET @PlazoDias = 1;
    DECLARE @FechaFin date = DATEADD(DAY, @PlazoDias - 1, @FechaInicio);

    DECLARE @EstadoIni varchar(60);
    SELECT @EstadoIni = CodigoEstado FROM sigcm.Estado
     WHERE CodigoModulo = 'EJECUCION' AND EsInicial = 1 AND Activo = 1;
    IF @EstadoIni IS NULL
        THROW 52013, 'CONFLICTO_CONFIGURACION: el modulo EJECUCION no tiene estado inicial. Falta S038.', 1;

    DECLARE @Codigo varchar(40), @Ahora datetime = GETDATE(), @IdExpEje uniqueidentifier;
    EXEC sigcm.paSiguienteCodigo 'EJE', @AnoEje, N'ejecucion.SeqContrato', @Codigo OUTPUT;

    INSERT INTO sigcm.Expediente
        (Codigo, CodigoModulo, CodigoTipoContratacion, AnoEje, IdUnidadOrigen,
         CodigoEstado, IdUnidadActual, IdResponsableActual, Version, IdExpedientePadre,
         UsuarioCreacionAuditoria, FechaCreacionAuditoria,
         EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES
        (@Codigo, 'EJECUCION', @TipoCon, @AnoEje, @IdUnidadOrigen,
         @EstadoIni, @IdUnidadOrigen, @IdResponsable, 1, @IdExpReq,
         @Cuenta, @Ahora, @Equipo, @Programa);

    SELECT @IdExpEje = IdExpediente FROM sigcm.Expediente WHERE Codigo = @Codigo;

    INSERT INTO ejecucion.Contrato
        (IdExpediente, IdRequerimiento, IdOrdenServicio, CodigoRequerimiento, NumeroOrdenSiga,
         Denominacion, TipoPrestacion, FechaNotificacion, FechaInicio, PlazoDias, FechaFinPrevista,
         IdSupervisor, MontoContrato, RucProveedor, DniProveedor, NombreProveedor, CorreoProveedor,
         UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES
        (@IdExpEje, @IdRequerimiento, @IdOrden, @CodigoReq, @NumeroOrden,
         @Denominacion, ISNULL(@TipoCon, 'SERVICIO'), @FechaNotif, @FechaInicio, @PlazoDias, @FechaFin,
         @IdResponsable, ISNULL(@Monto, 0), @Ruc, @Dni, @NombreProveedor, @Email,
         @Cuenta, @Ahora, @Equipo, @Programa);

    INSERT INTO sigcm.Historial
        (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
         Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
         UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES
        (@IdExpEje, NULL, @EstadoIni, NULL,
         CONCAT(N'Inicio de la ejecucion contractual el ', CONVERT(varchar(10), @FechaInicio, 103),
                N', dia siguiente a la notificacion de la orden ', ISNULL(@NumeroOrden, N'')),
         @IdUsuario, @CodigoRol, @IdUnidad,
         (SELECT @CodigoReq AS CodigoRequerimiento, @NumeroOrden AS NumeroOrden,
                 CONVERT(varchar(10), @FechaInicio, 23) AS FechaInicio,
                 CONVERT(varchar(10), @FechaFin, 23) AS FechaFinPrevista
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
         @Cuenta, @Equipo, @Programa);

    /* El plazo del contrato: la regla lleva Dias = 1 porque el numero real es
       de cada contrato; el vencimiento se fija aqui. */
    INSERT INTO sigcm.Plazo
        (IdExpediente, CodigoRegla, Inicio, Vencimiento, Estado,
         UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES
        (@IdExpEje, 'EJE_EJECUCION_CONTRATO', @FechaInicio, @FechaFin, 'EN_CURSO',
         @Cuenta, @Equipo, @Programa);

    EXEC sigcm.paRegistrarAuditoria @CorrelacionId, 'EJECUCION', 'ejecucion.Contrato', @IdExpEje,
         'ABRIR_CONTRATO', 'OK', @IdUsuario, @Cuenta, @CodigoRol, @IdUnidad, @Ip, @Equipo, @Programa;
END
GO

/* ========================================================================== */
/* 2. ejecucion.paAbrirContrato  (API, idempotente)                          */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paAbrirContrato
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        EXEC ejecucion.paAbrirDesdeOrdenServicioInterno @parametro;

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        SELECT @resultado = (
            SELECT 1 AS estado,
                   N'Se abrio o confirmo el contrato en ejecucion.' AS mensaje,
                   Contrato = JSON_QUERY((
                       SELECT c.IdContrato, c.IdExpediente, e.Codigo, e.CodigoEstado,
                              c.TipoPrestacion, c.FechaInicio, c.FechaFinPrevista
                         FROM ejecucion.Contrato AS c
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
                        WHERE c.IdRequerimiento = @IdRequerimiento AND c.Activo = 1
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
/* 3. ejecucion.paListarContrato                                             */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paListarContrato
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52020, 'JSON incorrecto.', 1;

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
                @Texto varchar(200), @Limite int, @Desplazamiento int, @SoloVigentes bit;

        SELECT @SoloMiBandeja = SoloMiBandeja, @CodigoEstado = CodigoEstado, @AnoEje = AnoEje,
               @Texto = Texto, @Limite = Limite, @Desplazamiento = Desplazamiento,
               @SoloVigentes = SoloVigentes
          FROM OPENJSON(@parametro, '$.Filtro')
          WITH (SoloMiBandeja bit, CodigoEstado varchar(60), AnoEje smallint,
                Texto varchar(200), Limite int, Desplazamiento int, SoloVigentes bit);

        SET @SoloMiBandeja  = ISNULL(@SoloMiBandeja, 1);
        SET @SoloVigentes   = ISNULL(@SoloVigentes, 0);
        SET @Limite         = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50
                                   WHEN @Limite > 200 THEN 200 ELSE @Limite END;
        SET @Desplazamiento = CASE WHEN @Desplazamiento IS NULL OR @Desplazamiento < 0 THEN 0 ELSE @Desplazamiento END;

        /* La visibilidad se resuelve una vez en una tabla temporal y las dos
           consultas -conteo y pagina- leen de ahi, para que no puedan discrepar. */
        CREATE TABLE #Visible (IdContrato uniqueidentifier PRIMARY KEY, MeToca bit NOT NULL);

        INSERT INTO #Visible (IdContrato, MeToca)
        SELECT c.IdContrato,
               CONVERT(bit, CASE
                   /* Le toca al actor si el contrato esta en su unidad con su rol,
                      o si alguna entrega del contrato lo esta. */
                   WHEN e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol THEN 1
                   WHEN EXISTS (SELECT 1 FROM ejecucion.Entrega AS en
                                JOIN sigcm.Expediente AS ee ON ee.IdExpediente = en.IdExpediente
                                JOIN sigcm.Estado AS we ON we.CodigoEstado = ee.CodigoEstado
                               WHERE en.IdContrato = c.IdContrato AND en.Activo = 1
                                 AND ee.IdUnidadActual = @IdUnidad AND we.RolResponsable = @CodigoRol) THEN 1
                   ELSE 0 END)
          FROM ejecucion.Contrato AS c
          JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE e.Anulado = 0 AND e.Activo = 1 AND c.Activo = 1
           AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
           AND (@AnoEje IS NULL OR e.AnoEje = @AnoEje)
           AND (@SoloVigentes = 0 OR w.EsFinal = 0)
           AND (@Texto IS NULL
                OR e.Codigo LIKE '%' + @Texto + '%'
                OR c.CodigoRequerimiento LIKE '%' + @Texto + '%'
                OR c.NumeroOrdenSiga LIKE '%' + @Texto + '%'
                OR c.NombreProveedor LIKE '%' + @Texto + '%'
                OR c.Denominacion LIKE '%' + @Texto + '%')
           AND (
                @CodigoRol = 'PROVEEDOR'
                AND (   (@DocIdent IS NOT NULL AND (c.DniProveedor = @DocIdent OR c.RucProveedor = @DocIdent))
                     OR c.RucProveedor = @Cuenta OR c.DniProveedor = @Cuenta
                     OR (@CorreoActor IS NOT NULL AND c.CorreoProveedor = @CorreoActor))
             OR (@CodigoRol <> 'PROVEEDOR' AND (
                    @SoloMiBandeja = 0
                 OR e.IdUnidadActual = @IdUnidad
                 OR e.IdUnidadOrigen = @IdUnidad
                 /* Abastecimiento ve todos los contratos: es la DEC quien
                    autoriza el ingreso y registra la guia, y el contrato en si
                    nunca pasa por su unidad. */
                 OR @CodigoRol LIKE 'ABAST[_]%'
                 OR @CodigoRol IN ('OA', 'ADMIN_SISTEMA')
                 OR EXISTS (SELECT 1 FROM ejecucion.Entrega AS en
                            JOIN sigcm.Expediente AS ee ON ee.IdExpediente = en.IdExpediente
                           WHERE en.IdContrato = c.IdContrato AND en.Activo = 1
                             AND ee.IdUnidadActual = @IdUnidad)
                 OR EXISTS (SELECT 1 FROM sigcm.Historial AS h
                             WHERE h.IdExpediente = e.IdExpediente
                               AND (h.IdActor = @IdUsuario OR h.IdActorUnidad = @IdUnidad))
                ))
           );

        DECLARE @Total int = (SELECT COUNT(*) FROM #Visible);
        DECLARE @Hoy date = CONVERT(date, GETDATE());

        SELECT @resultado = (
            SELECT 1 AS estado, @Total AS total, @Limite AS limite, @Desplazamiento AS desplazamiento,
                   Contratos = JSON_QUERY(COALESCE((
                       SELECT c.IdContrato, e.IdExpediente, e.Codigo, e.CodigoEstado, e.Version,
                              Estado = w.Nombre, RolResponsable = w.RolResponsable,
                              MeToca = v.MeToca,
                              c.IdRequerimiento, c.CodigoRequerimiento, c.NumeroOrdenSiga,
                              c.Denominacion, c.TipoPrestacion,
                              TipoPrestacionNombre = tc.Nombre,
                              c.FechaInicio, c.FechaFinPrevista, c.FechaFinReal, c.PlazoDias,
                              /* Negativo = vencido. Es el dato que la bandeja pinta en rojo. */
                              DiasRestantes = CASE WHEN w.EsFinal = 1 THEN NULL
                                                   ELSE DATEDIFF(DAY, @Hoy, c.FechaFinPrevista) END,
                              c.LugarEntrega, c.MontoContrato,
                              c.NombreProveedor, c.RucProveedor, c.DniProveedor,
                              UnidadOrigen = uo.Sigla,
                              TotalEntregables = (SELECT COUNT(*) FROM pago.ExpedientePago AS p
                                                   WHERE p.IdRequerimiento = c.IdRequerimiento AND p.Activo = 1),
                              EntregablesConformes = (SELECT COUNT(*) FROM pago.ExpedientePago AS p
                                                        JOIN sigcm.Expediente AS ep ON ep.IdExpediente = p.IdExpediente
                                                        JOIN sigcm.Estado AS wp ON wp.CodigoEstado = ep.CodigoEstado
                                                       WHERE p.IdRequerimiento = c.IdRequerimiento AND p.Activo = 1
                                                         AND wp.Orden >= 40),
                              TotalEntregas = (SELECT COUNT(*) FROM ejecucion.Entrega AS en
                                                WHERE en.IdContrato = c.IdContrato AND en.Activo = 1),
                              EntregasPendientes = (SELECT COUNT(*) FROM ejecucion.Entrega AS en
                                                     JOIN sigcm.Expediente AS ee ON ee.IdExpediente = en.IdExpediente
                                                     JOIN sigcm.Estado AS we ON we.CodigoEstado = ee.CodigoEstado
                                                    WHERE en.IdContrato = c.IdContrato AND en.Activo = 1 AND we.EsFinal = 0),
                              IncidenciasAbiertas = (SELECT COUNT(*) FROM ejecucion.Incidencia AS i
                                                      WHERE i.IdContrato = c.IdContrato AND i.Activo = 1 AND i.Estado = 'COMUNICADA'),
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
                         FROM #Visible AS v
                         JOIN ejecucion.Contrato AS c ON c.IdContrato = v.IdContrato
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
                         JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                         JOIN sigcm.Unidad AS uo ON uo.IdUnidad = e.IdUnidadOrigen
                         LEFT JOIN sigcm.TipoContratacion AS tc ON tc.CodigoTipoContratacion = c.TipoPrestacion
                        ORDER BY v.MeToca DESC, w.EsFinal, c.FechaFinPrevista
                        OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        DROP TABLE #Visible;
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF OBJECT_ID('tempdb..#Visible') IS NOT NULL DROP TABLE #Visible;
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 4. ejecucion.paObtenerContrato                                            */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paObtenerContrato
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52030, 'JSON incorrecto.', 1;

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
        DECLARE @IdContrato uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdContrato'));

        IF @IdContrato IS NULL AND @IdExpediente IS NOT NULL
            SELECT @IdContrato = IdContrato FROM ejecucion.Contrato WHERE IdExpediente = @IdExpediente AND Activo = 1;
        IF @IdContrato IS NULL
            THROW 52031, 'VALIDACION_PAYLOAD: falta IdContrato o IdExpediente.', 1;
        IF NOT EXISTS (SELECT 1 FROM ejecucion.Contrato WHERE IdContrato = @IdContrato AND Activo = 1)
            THROW 52032, 'NO_ENCONTRADO: el contrato no existe.', 1;

        DECLARE @Hoy date = CONVERT(date, GETDATE());

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Contrato = JSON_QUERY((
                       SELECT c.IdContrato, e.IdExpediente, e.Codigo, e.CodigoEstado, e.Version,
                              Estado = w.Nombre, RolResponsable = w.RolResponsable, EsFinal = w.EsFinal,
                              e.AnoEje, c.IdRequerimiento, c.CodigoRequerimiento, c.NumeroOrdenSiga,
                              c.Denominacion, c.TipoPrestacion, TipoPrestacionNombre = tc.Nombre,
                              c.FechaNotificacion, c.FechaInicio, c.PlazoDias, c.FechaFinPrevista, c.FechaFinReal,
                              DiasRestantes = CASE WHEN w.EsFinal = 1 THEN NULL
                                                   ELSE DATEDIFF(DAY, @Hoy, c.FechaFinPrevista) END,
                              c.LugarEntrega, c.DireccionEntrega,
                              c.IdSupervisor,
                              Supervisor = (SELECT CONCAT(u.Nombres, N' ', u.Apellidos) FROM sigcm.Usuario AS u WHERE u.IdUsuario = c.IdSupervisor),
                              c.MontoContrato, c.RucProveedor, c.DniProveedor, c.NombreProveedor, c.CorreoProveedor,
                              UnidadOrigen = uo.Sigla, UnidadOrigenNombre = uo.Nombre,
                              /* Entregas fisicas: cada una con sus acciones para ESTE actor. */
                              Entregas = JSON_QUERY(COALESCE((
                                  SELECT en.IdEntrega, ee.IdExpediente, ee.Codigo, ee.CodigoEstado, ee.Version,
                                         Estado = we.Nombre, RolResponsable = we.RolResponsable, EsFinal = we.EsFinal,
                                         MeToca = CONVERT(bit, CASE WHEN ee.IdUnidadActual = @IdUnidad
                                                                     AND we.RolResponsable = @CodigoRol THEN 1 ELSE 0 END),
                                         en.NumeroEntrega, en.NumeroEntregable, en.IdExpedientePago,
                                         en.Lugar, en.Detalle, en.FechaAnuncio, en.FechaPrevista, en.FechaIngreso,
                                         en.FechaVerificacion, en.FechaRecepcion, en.FechaRetiro,
                                         en.NumeroGuiaRemision, en.GuiaDocumento, en.GuiaSuscritaDocumento,
                                         en.ActaIncumplimientoDocumento, en.NumeroPecosa, en.PecosaDocumento,
                                         en.IdVerificador,
                                         Verificador = (SELECT CONCAT(u.Nombres, N' ', u.Apellidos) FROM sigcm.Usuario AS u WHERE u.IdUsuario = en.IdVerificador),
                                         en.ResultadoVerificacion, en.DetalleVerificacion,
                                         Transiciones = JSON_QUERY(COALESCE((
                                             SELECT t.CodigoTransicion, t.NombreAccion,
                                                    t.CodigoEstadoDestino, EstadoDestino = d.Nombre,
                                                    t.RequiereComentario, t.RequiereFirma,
                                                    t.DocumentoRequerido, t.EncolaIntegracion, t.GeneraObservacion
                                               FROM sigcm.Transicion AS t
                                               JOIN sigcm.Estado AS d ON d.CodigoEstado = t.CodigoEstadoDestino
                                              WHERE t.CodigoModulo = 'EJECUCION'
                                                AND t.CodigoEstadoOrigen = ee.CodigoEstado
                                                AND t.Activo = 1
                                                AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS tr
                                                             WHERE tr.CodigoTransicion = t.CodigoTransicion
                                                               AND tr.CodigoRol = @CodigoRol)
                                              ORDER BY t.CodigoTransicion
                                                FOR JSON PATH), N'[]'))
                                    FROM ejecucion.Entrega AS en
                                    JOIN sigcm.Expediente AS ee ON ee.IdExpediente = en.IdExpediente
                                    JOIN sigcm.Estado AS we ON we.CodigoEstado = ee.CodigoEstado
                                   WHERE en.IdContrato = c.IdContrato AND en.Activo = 1
                                   ORDER BY en.NumeroEntrega
                                     FOR JSON PATH), N'[]')),
                              /* Entregables del cronograma, con su estado de pago. Solo lectura:
                                 se trabajan en Entregables y pagos. */
                              Entregables = JSON_QUERY(COALESCE((
                                  SELECT p.IdExpedientePago, ep.IdExpediente, ep.Codigo, ep.CodigoEstado,
                                         Estado = wp.Nombre, EsFinal = wp.EsFinal,
                                         ConConformidad = CONVERT(bit, CASE WHEN wp.Orden >= 40 THEN 1 ELSE 0 END),
                                         p.NumeroEntregable, p.NombreEntregable, p.MontoEntregable,
                                         p.FechaLimiteCronograma, p.FechaPresentacion, p.FechaConformidadTecnica,
                                         p.DiasAtraso, p.MontoPenalidad
                                    FROM pago.ExpedientePago AS p
                                    JOIN sigcm.Expediente AS ep ON ep.IdExpediente = p.IdExpediente
                                    JOIN sigcm.Estado AS wp ON wp.CodigoEstado = ep.CodigoEstado
                                   WHERE p.IdRequerimiento = c.IdRequerimiento AND p.Activo = 1
                                   ORDER BY p.NumeroEntregable
                                     FOR JSON PATH), N'[]')),
                              Incidencias = JSON_QUERY(COALESCE((
                                  SELECT i.IdIncidencia, i.Tipo, i.Detalle, i.DocumentoSgd, i.InformeDocumento,
                                         i.Estado, i.Respuesta, i.RegistradaEn, i.AtendidaEn,
                                         RegistradaPor = (SELECT CONCAT(u.Nombres, N' ', u.Apellidos) FROM sigcm.Usuario AS u WHERE u.IdUsuario = i.IdActorRegistro),
                                         AtendidaPor   = (SELECT CONCAT(u.Nombres, N' ', u.Apellidos) FROM sigcm.Usuario AS u WHERE u.IdUsuario = i.IdActorAtencion)
                                    FROM ejecucion.Incidencia AS i
                                   WHERE i.IdContrato = c.IdContrato AND i.Activo = 1
                                   ORDER BY i.RegistradaEn DESC
                                     FOR JSON PATH), N'[]')),
                              Plazos = JSON_QUERY(COALESCE((
                                  SELECT pl.CodigoRegla, Nombre = pr.Nombre, pl.Inicio, pl.Vencimiento,
                                         pl.AmpliadoHasta, pl.CumplidoEn, pl.Estado
                                    FROM sigcm.Plazo AS pl
                                    JOIN sigcm.PlazoRegla AS pr ON pr.CodigoRegla = pl.CodigoRegla
                                   WHERE pl.IdExpediente = e.IdExpediente AND pl.Activo = 1
                                   ORDER BY pl.Inicio
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
                                     FOR JSON PATH), N'[]')),
                              /* Lo que ESTE actor puede hacer fuera de la maquina de estados.
                                 Se decide aqui y no en la pantalla (ESTANDARES 4.5). */
                              PuedeAnunciarEntrega = CONVERT(bit, CASE
                                  WHEN @CodigoRol = 'PROVEEDOR' AND c.TipoPrestacion = 'BIEN'
                                   AND w.EsFinal = 0 AND c.LugarEntrega IS NOT NULL THEN 1 ELSE 0 END),
                              PuedeEditarContrato = CONVERT(bit, CASE
                                  WHEN w.EsFinal = 0 AND (@CodigoRol LIKE 'AREA[_]%' OR @CodigoRol LIKE 'ABAST[_]%') THEN 1 ELSE 0 END),
                              PuedeRegistrarIncidencia = CONVERT(bit, CASE
                                  WHEN w.EsFinal = 0 AND @CodigoRol LIKE 'AREA[_]%' THEN 1 ELSE 0 END),
                              PuedeAtenderIncidencia = CONVERT(bit, CASE
                                  WHEN @CodigoRol LIKE 'ABAST[_]%' THEN 1 ELSE 0 END)
                         FROM ejecucion.Contrato AS c
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
                         JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                         JOIN sigcm.Unidad AS uo ON uo.IdUnidad = e.IdUnidadOrigen
                         LEFT JOIN sigcm.TipoContratacion AS tc ON tc.CodigoTipoContratacion = c.TipoPrestacion
                        WHERE c.IdContrato = @IdContrato
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
/* 5. ejecucion.paActualizarContrato                                         */
/*    Lugar y direccion de entrega (7.3.6.3) y supervisor del AU (7.3.2).    */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paActualizarContrato
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52040, 'JSON incorrecto.', 1;

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

        IF NOT (@CodigoRol LIKE 'AREA[_]%' OR @CodigoRol LIKE 'ABAST[_]%')
            THROW 52041, 'NO_AUTORIZADO: solo el Area usuaria o Abastecimiento fijan el lugar de entrega y el supervisor.', 1;

        DECLARE @IdContrato uniqueidentifier, @LugarEntrega varchar(25), @Direccion nvarchar(300),
                @IdSupervisor uniqueidentifier;
        SELECT @IdContrato = TRY_CONVERT(uniqueidentifier, IdContrato),
               @LugarEntrega = NULLIF(LTRIM(RTRIM(LugarEntrega)), ''),
               @Direccion = NULLIF(LTRIM(RTRIM(DireccionEntrega)), N''),
               @IdSupervisor = TRY_CONVERT(uniqueidentifier, IdSupervisor)
          FROM OPENJSON(@parametro)
          WITH (IdContrato varchar(50), LugarEntrega varchar(25), DireccionEntrega nvarchar(300), IdSupervisor varchar(50));

        IF @IdContrato IS NULL
            THROW 52042, 'VALIDACION_PAYLOAD: falta IdContrato.', 1;
        IF @LugarEntrega IS NOT NULL AND @LugarEntrega NOT IN ('SEDE_CENTRAL','SEDE_DESCONCENTRADA')
            THROW 52043, 'VALIDACION_LUGAR: el lugar de entrega es SEDE_CENTRAL o SEDE_DESCONCENTRADA.', 1;
        IF @LugarEntrega = 'SEDE_DESCONCENTRADA' AND @Direccion IS NULL
            THROW 52044, 'VALIDACION_LUGAR: la entrega fuera de la Sede Central exige la direccion.', 1;

        DECLARE @IdExpediente uniqueidentifier, @IdUnidadOrigen uniqueidentifier, @EsFinal bit;
        SELECT @IdExpediente = c.IdExpediente, @IdUnidadOrigen = e.IdUnidadOrigen, @EsFinal = w.EsFinal
          FROM ejecucion.Contrato AS c
          JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE c.IdContrato = @IdContrato AND c.Activo = 1;

        IF @IdExpediente IS NULL
            THROW 52045, 'NO_ENCONTRADO: el contrato no existe.', 1;
        IF @EsFinal = 1
            THROW 52046, 'CONFLICTO_ESTADO: el contrato ya esta cerrado.', 1;

        /* El supervisor tiene que ser alguien del area usuaria del contrato. */
        IF @IdSupervisor IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM sigcm.UsuarioRol AS ur
             WHERE ur.IdUsuario = @IdSupervisor AND ur.IdUnidad = @IdUnidadOrigen
               AND ur.CodigoRol LIKE 'AREA[_]%' AND ur.Activo = 1)
            THROW 52047, 'VALIDACION_SUPERVISOR: la persona elegida no pertenece al area usuaria del contrato.', 1;

        DECLARE @Ahora datetime = GETDATE();
        UPDATE ejecucion.Contrato
           SET LugarEntrega = COALESCE(@LugarEntrega, LugarEntrega),
               DireccionEntrega = CASE WHEN @LugarEntrega IS NULL THEN DireccionEntrega ELSE @Direccion END,
               IdSupervisor = COALESCE(@IdSupervisor, IdSupervisor),
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdContrato = @IdContrato;

        EXEC sigcm.paRegistrarAuditoria @CorrelacionId, 'EJECUCION', 'ejecucion.Contrato', @IdExpediente,
             'ACTUALIZAR_CONTRATO', 'OK', @IdUsuario, @Cuenta, @CodigoRol, @IdUnidad, @Ip, @Equipo, @Programa,
             NULL, @parametro;

        SELECT @resultado = (
            SELECT 1 AS estado, @IdContrato AS IdContrato,
                   N'Se actualizo el contrato.' AS mensaje
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

/* ========================================================================== */
/* 6. ejecucion.paAnunciarEntrega  (PROVEEDOR)                               */
/*    Crea la entrega y su expediente en la ruta que manda el lugar.         */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paAnunciarEntrega
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52050, 'JSON incorrecto.', 1;

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

        IF @CodigoRol <> 'PROVEEDOR'
            THROW 52051, 'NO_AUTORIZADO: la entrega la anuncia el proveedor.', 1;

        DECLARE @IdContrato uniqueidentifier, @NumeroEntregable smallint, @Detalle nvarchar(1000),
                @FechaPrevista date, @Guia varchar(40), @GuiaDoc nvarchar(200);
        SELECT @IdContrato = TRY_CONVERT(uniqueidentifier, IdContrato),
               @NumeroEntregable = NumeroEntregable,
               @Detalle = NULLIF(LTRIM(RTRIM(Detalle)), N''),
               @FechaPrevista = TRY_CONVERT(date, FechaPrevista),
               @Guia = NULLIF(LTRIM(RTRIM(NumeroGuiaRemision)), ''),
               @GuiaDoc = NULLIF(LTRIM(RTRIM(GuiaDocumento)), N'')
          FROM OPENJSON(@parametro)
          WITH (IdContrato varchar(50), NumeroEntregable smallint, Detalle nvarchar(1000),
                FechaPrevista varchar(30), NumeroGuiaRemision varchar(40), GuiaDocumento nvarchar(200));

        IF @IdContrato IS NULL
            THROW 52052, 'VALIDACION_PAYLOAD: falta IdContrato.', 1;
        IF @Detalle IS NULL
            THROW 52053, 'VALIDACION_PAYLOAD: indique los bienes que entrega.', 1;
        IF @Guia IS NULL
            THROW 52054, 'VALIDACION_PAYLOAD: indique el numero de la guia de remision.', 1;
        IF @FechaPrevista IS NULL SET @FechaPrevista = CONVERT(date, GETDATE());

        DECLARE @IdExpContrato uniqueidentifier, @IdUnidadOrigen uniqueidentifier, @Tipo varchar(20),
                @Lugar varchar(25), @EsFinal bit, @AnoEje smallint, @TipoCon varchar(20),
                @IdRequerimiento uniqueidentifier, @CodigoContrato varchar(40), @Ruc varchar(11), @Dni varchar(15);

        SELECT @IdExpContrato = c.IdExpediente, @IdUnidadOrigen = e.IdUnidadOrigen, @Tipo = c.TipoPrestacion,
               @Lugar = c.LugarEntrega, @EsFinal = w.EsFinal, @AnoEje = e.AnoEje, @TipoCon = e.CodigoTipoContratacion,
               @IdRequerimiento = c.IdRequerimiento, @CodigoContrato = e.Codigo,
               @Ruc = c.RucProveedor, @Dni = c.DniProveedor
          FROM ejecucion.Contrato AS c
          JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE c.IdContrato = @IdContrato AND c.Activo = 1;

        IF @IdExpContrato IS NULL
            THROW 52055, 'NO_ENCONTRADO: el contrato no existe.', 1;
        IF @EsFinal = 1
            THROW 52056, 'CONFLICTO_ESTADO: el contrato ya esta cerrado.', 1;
        IF @Tipo <> 'BIEN'
            THROW 52057, 'CONFLICTO_TIPO: la entrega fisica solo aplica a bienes; los servicios presentan su entregable en Entregables y pagos.', 1;
        IF @Lugar IS NULL
            THROW 52058, 'CONFLICTO_LUGAR: el area usuaria todavia no fijo el lugar de entrega del contrato.', 1;

        /* El proveedor que anuncia tiene que ser el del contrato. */
        DECLARE @DocActor varchar(20), @CorreoActor varchar(200);
        SELECT @DocActor = NULLIF(DocumentoIdentidad, ''), @CorreoActor = Correo FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;
        IF NOT EXISTS (SELECT 1 FROM ejecucion.Contrato AS c WHERE c.IdContrato = @IdContrato
                          AND (   (@DocActor IS NOT NULL AND (c.RucProveedor = @DocActor OR c.DniProveedor = @DocActor))
                               OR c.RucProveedor = @Cuenta OR c.DniProveedor = @Cuenta
                               OR (@CorreoActor IS NOT NULL AND c.CorreoProveedor = @CorreoActor)))
            THROW 52059, 'NO_AUTORIZADO: este contrato no corresponde al proveedor que ingreso.', 1;

        DECLARE @IdExpPago uniqueidentifier = NULL;
        IF @NumeroEntregable IS NOT NULL
        BEGIN
            SELECT @IdExpPago = p.IdExpedientePago
              FROM pago.ExpedientePago AS p
             WHERE p.IdRequerimiento = @IdRequerimiento AND p.NumeroEntregable = @NumeroEntregable AND p.Activo = 1;
            IF @IdExpPago IS NULL
                THROW 52060, 'NO_ENCONTRADO: el entregable indicado no esta en el cronograma del contrato.', 1;
        END

        DECLARE @EstadoIni varchar(60) = CASE WHEN @Lugar = 'SEDE_CENTRAL'
                                              THEN 'EJE_ENT_POR_AUTORIZAR_ALMACEN'
                                              ELSE 'EJE_ENT_POR_AUTORIZAR_SEDE' END;
        DECLARE @RolIni varchar(40);
        SELECT @RolIni = RolResponsable FROM sigcm.Estado WHERE CodigoEstado = @EstadoIni AND Activo = 1;
        IF @RolIni IS NULL
            THROW 52061, 'CONFLICTO_CONFIGURACION: faltan los estados de entrega. Falta S038.', 1;

        DECLARE @IdUnidadDestino uniqueidentifier;
        EXEC ejecucion.paResolverUnidadDestinoInterno @IdContrato, @RolIni, @IdUnidadDestino OUTPUT;
        IF @IdUnidadDestino IS NULL SET @IdUnidadDestino = @IdUnidadOrigen;

        DECLARE @Numero smallint = ISNULL((SELECT MAX(NumeroEntrega) FROM ejecucion.Entrega WHERE IdContrato = @IdContrato), 0) + 1;
        DECLARE @Codigo varchar(40), @Ahora datetime = GETDATE(), @IdExpEnt uniqueidentifier, @IdEntrega uniqueidentifier;

        BEGIN TRANSACTION;

        EXEC sigcm.paSiguienteCodigo 'ENT', @AnoEje, N'ejecucion.SeqEntrega', @Codigo OUTPUT;

        INSERT INTO sigcm.Expediente
            (Codigo, CodigoModulo, CodigoTipoContratacion, AnoEje, IdUnidadOrigen,
             CodigoEstado, IdUnidadActual, Version, IdExpedientePadre,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@Codigo, 'EJECUCION', @TipoCon, @AnoEje, @IdUnidadOrigen,
             @EstadoIni, @IdUnidadDestino, 1, @IdExpContrato,
             @Cuenta, @Ahora, @Equipo, @Programa);

        SELECT @IdExpEnt = IdExpediente FROM sigcm.Expediente WHERE Codigo = @Codigo;

        INSERT INTO ejecucion.Entrega
            (IdExpediente, IdContrato, NumeroEntrega, NumeroEntregable, IdExpedientePago,
             Lugar, Detalle, FechaAnuncio, FechaPrevista, NumeroGuiaRemision, GuiaDocumento,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExpEnt, @IdContrato, @Numero, @NumeroEntregable, @IdExpPago,
             @Lugar, @Detalle, @Ahora, @FechaPrevista, @Guia, @GuiaDoc,
             @Cuenta, @Ahora, @Equipo, @Programa);

        SELECT @IdEntrega = IdEntrega FROM ejecucion.Entrega WHERE IdExpediente = @IdExpEnt;

        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
             Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExpEnt, NULL, @EstadoIni, NULL,
             CONCAT(N'Entrega ', @Numero, N' anunciada con guia de remision ', @Guia,
                    CASE WHEN @Lugar = 'SEDE_CENTRAL' THEN N' para Almacen (Sede Central).' ELSE N' para sede desconcentrada.' END),
             @IdUsuario, @CodigoRol, @IdUnidad,
             (SELECT @CodigoContrato AS Contrato, @Numero AS NumeroEntrega, @NumeroEntregable AS NumeroEntregable,
                     @Guia AS NumeroGuiaRemision, @Lugar AS Lugar FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
             @Cuenta, @Equipo, @Programa);

        EXEC sigcm.paRegistrarAuditoria @CorrelacionId, 'EJECUCION', 'ejecucion.Entrega', @IdExpEnt,
             'ANUNCIAR_ENTREGA', 'OK', @IdUsuario, @Cuenta, @CodigoRol, @IdUnidad, @Ip, @Equipo, @Programa,
             NULL, @parametro;

        COMMIT TRANSACTION;

        SELECT @resultado = (
            SELECT 1 AS estado, @IdEntrega AS IdEntrega, @IdExpEnt AS IdExpediente, @Codigo AS Codigo,
                   @EstadoIni AS CodigoEstado,
                   N'Se registro la entrega. Queda pendiente de autorizacion de ingreso.' AS mensaje
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

/* ========================================================================== */
/* 7. ejecucion.paAutorizarIngreso                                           */
/*    Almacen (Sede Central) o el AU (sede desconcentrada), segun la ruta.   */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paAutorizarIngreso
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52062, 'JSON incorrecto.', 1;

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
        IF @IdExpediente IS NULL
            THROW 52063, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @IdEntrega uniqueidentifier, @Estado varchar(60);
        SELECT @IdEntrega = en.IdEntrega, @Estado = e.CodigoEstado
          FROM ejecucion.Entrega AS en
          JOIN sigcm.Expediente AS e ON e.IdExpediente = en.IdExpediente
         WHERE en.IdExpediente = @IdExpediente AND en.Activo = 1;
        IF @IdEntrega IS NULL
            THROW 52064, 'NO_ENCONTRADO: la entrega no existe.', 1;

        DECLARE @Transicion varchar(70) =
            CASE @Estado WHEN 'EJE_ENT_POR_AUTORIZAR_ALMACEN' THEN 'EJE_ENT_AUTORIZAR_INGRESO_ALMACEN'
                         WHEN 'EJE_ENT_POR_AUTORIZAR_SEDE'    THEN 'EJE_ENT_AUTORIZAR_INGRESO_SEDE' END;
        IF @Transicion IS NULL
            THROW 52065, 'CONFLICTO_ESTADO: la entrega no esta pendiente de autorizacion de ingreso.', 1;

        UPDATE ejecucion.Entrega
           SET FechaIngreso = GETDATE(),
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdEntrega = @IdEntrega;

        EXEC ejecucion.paMoverEntregaInterno @parametro, @IdEntrega, @Transicion;
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
/* 8. ejecucion.paDesignarVerificador  (AREA_JEFE, ruta Almacen)             */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paDesignarVerificador
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52066, 'JSON incorrecto.', 1;

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
        DECLARE @IdVerificador uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdVerificador'));
        IF @IdExpediente IS NULL
            THROW 52067, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @IdVerificador IS NULL
            THROW 52068, 'VALIDACION_PAYLOAD: elija al responsable de verificacion.', 1;

        DECLARE @IdEntrega uniqueidentifier, @Estado varchar(60), @IdUnidadOrigen uniqueidentifier;
        SELECT @IdEntrega = en.IdEntrega, @Estado = e.CodigoEstado, @IdUnidadOrigen = e.IdUnidadOrigen
          FROM ejecucion.Entrega AS en
          JOIN sigcm.Expediente AS e ON e.IdExpediente = en.IdExpediente
         WHERE en.IdExpediente = @IdExpediente AND en.Activo = 1;
        IF @IdEntrega IS NULL
            THROW 52069, 'NO_ENCONTRADO: la entrega no existe.', 1;
        IF @Estado <> 'EJE_ENT_POR_DESIGNAR_VERIFICADOR'
            THROW 52070, 'CONFLICTO_ESTADO: la entrega no esta pendiente de designar responsable.', 1;

        /* Quien acompana a Almacen es alguien del area usuaria del contrato:
           es a quien le toca el visto bueno en la guia (7.3.6.3.a). */
        IF NOT EXISTS (SELECT 1 FROM sigcm.UsuarioRol AS ur
                        WHERE ur.IdUsuario = @IdVerificador AND ur.IdUnidad = @IdUnidadOrigen
                          AND ur.CodigoRol LIKE 'AREA[_]%' AND ur.Activo = 1)
            THROW 52071, 'VALIDACION_VERIFICADOR: la persona elegida no pertenece al area usuaria del contrato.', 1;

        UPDATE ejecucion.Entrega
           SET IdVerificador = @IdVerificador,
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdEntrega = @IdEntrega;

        EXEC ejecucion.paMoverEntregaInterno @parametro, @IdEntrega, 'EJE_ENT_DESIGNAR_VERIFICADOR';
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
/* 9. ejecucion.paVerificarEntrega                                           */
/*    Resultado CONFORME (recepciona con guia suscrita) u OBSERVADO (acta de */
/*    incumplimiento y retiro, 7.3.6.3.c). La ruta sale del estado actual.   */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paVerificarEntrega
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52072, 'JSON incorrecto.', 1;

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

        DECLARE @IdExpediente uniqueidentifier, @Resultado varchar(12), @Detalle nvarchar(max),
                @GuiaSuscrita nvarchar(200), @Acta nvarchar(200);
        SELECT @IdExpediente = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @Resultado = UPPER(NULLIF(LTRIM(RTRIM(Resultado)), '')),
               @Detalle = NULLIF(LTRIM(RTRIM(Detalle)), N''),
               @GuiaSuscrita = NULLIF(LTRIM(RTRIM(GuiaSuscritaDocumento)), N''),
               @Acta = NULLIF(LTRIM(RTRIM(ActaIncumplimientoDocumento)), N'')
          FROM OPENJSON(@parametro)
          WITH (IdExpediente varchar(50), Resultado varchar(12), Detalle nvarchar(max),
                GuiaSuscritaDocumento nvarchar(200), ActaIncumplimientoDocumento nvarchar(200));

        IF @IdExpediente IS NULL
            THROW 52073, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @Resultado NOT IN ('CONFORME', 'OBSERVADO')
            THROW 52074, 'VALIDACION_RESULTADO: el resultado de la verificacion es CONFORME u OBSERVADO.', 1;

        DECLARE @IdEntrega uniqueidentifier, @Estado varchar(60), @IdContrato uniqueidentifier;
        SELECT @IdEntrega = en.IdEntrega, @Estado = e.CodigoEstado, @IdContrato = en.IdContrato
          FROM ejecucion.Entrega AS en
          JOIN sigcm.Expediente AS e ON e.IdExpediente = en.IdExpediente
         WHERE en.IdExpediente = @IdExpediente AND en.Activo = 1;
        IF @IdEntrega IS NULL
            THROW 52075, 'NO_ENCONTRADO: la entrega no existe.', 1;

        DECLARE @Transicion varchar(70) =
            CASE WHEN @Estado = 'EJE_ENT_EN_VERIFICACION_ALMACEN' AND @Resultado = 'CONFORME'  THEN 'EJE_ENT_RECEPCIONAR_ALMACEN'
                 WHEN @Estado = 'EJE_ENT_EN_VERIFICACION_ALMACEN' AND @Resultado = 'OBSERVADO' THEN 'EJE_ENT_OBSERVAR_ALMACEN'
                 WHEN @Estado = 'EJE_ENT_EN_VERIFICACION_SEDE'    AND @Resultado = 'CONFORME'  THEN 'EJE_ENT_RECEPCIONAR_SEDE'
                 WHEN @Estado = 'EJE_ENT_EN_VERIFICACION_SEDE'    AND @Resultado = 'OBSERVADO' THEN 'EJE_ENT_OBSERVAR_SEDE' END;
        IF @Transicion IS NULL
            THROW 52076, 'CONFLICTO_ESTADO: la entrega no esta en verificacion.', 1;

        IF @Resultado = 'OBSERVADO' AND @Detalle IS NULL
            THROW 52077, 'VALIDACION_PAYLOAD: la observacion exige detallar el incumplimiento de las EETT.', 1;
        IF @Resultado = 'OBSERVADO' AND @Acta IS NULL
            THROW 52078, 'VALIDACION_DOCUMENTO: adjunte el acta de incumplimiento suscrita por el proveedor, el area usuaria y Almacen.', 1;
        IF @Resultado = 'CONFORME' AND @GuiaSuscrita IS NULL
            THROW 52079, 'VALIDACION_DOCUMENTO: adjunte la guia de remision suscrita.', 1;

        DECLARE @Ahora datetime = GETDATE();
        UPDATE ejecucion.Entrega
           SET ResultadoVerificacion = @Resultado,
               DetalleVerificacion = @Detalle,
               FechaVerificacion = @Ahora,
               FechaRecepcion = CASE WHEN @Resultado = 'CONFORME' THEN @Ahora ELSE FechaRecepcion END,
               GuiaSuscritaDocumento = COALESCE(@GuiaSuscrita, GuiaSuscritaDocumento),
               ActaIncumplimientoDocumento = COALESCE(@Acta, ActaIncumplimientoDocumento),
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdEntrega = @IdEntrega;

        /* 7.3.6.1: desde el dia siguiente a recibido el bien corren 7 dias
           calendario para la conformidad. */
        IF @Resultado = 'CONFORME'
        BEGIN
            DECLARE @Regla varchar(60) = CASE WHEN @Estado = 'EJE_ENT_EN_VERIFICACION_ALMACEN'
                                              THEN 'EJE_CONFORMIDAD_BIEN' ELSE 'EJE_CONFORMIDAD_BIEN_SEDE' END;
            IF NOT EXISTS (SELECT 1 FROM sigcm.Plazo WHERE IdExpediente = @IdExpediente AND CodigoRegla = @Regla AND Activo = 1)
                INSERT INTO sigcm.Plazo
                    (IdExpediente, CodigoRegla, Inicio, Vencimiento, Estado,
                     UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                VALUES
                    (@IdExpediente, @Regla, @Ahora, DATEADD(DAY, 7, CONVERT(date, @Ahora)), 'EN_CURSO',
                     @Cuenta, @Equipo, @Programa);
        END

        /* El motor exige comentario en la observacion; el detalle es ese comentario. */
        IF @Resultado = 'OBSERVADO' AND JSON_VALUE(@parametro, '$.Comentario') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Comentario', @Detalle);

        EXEC ejecucion.paMoverEntregaInterno @parametro, @IdEntrega, @Transicion;
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
/* 10. ejecucion.paEntregarBienAu  (Almacen entrega al AU con Pecosa)        */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paEntregarBienAu
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52080, 'JSON incorrecto.', 1;

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

        DECLARE @IdExpediente uniqueidentifier, @Pecosa varchar(40), @PecosaDoc nvarchar(200);
        SELECT @IdExpediente = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @Pecosa = NULLIF(LTRIM(RTRIM(NumeroPecosa)), ''),
               @PecosaDoc = NULLIF(LTRIM(RTRIM(PecosaDocumento)), N'')
          FROM OPENJSON(@parametro)
          WITH (IdExpediente varchar(50), NumeroPecosa varchar(40), PecosaDocumento nvarchar(200));

        IF @IdExpediente IS NULL
            THROW 52081, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @Pecosa IS NULL
            THROW 52082, 'VALIDACION_PAYLOAD: indique el numero de la Pecosa.', 1;

        DECLARE @IdEntrega uniqueidentifier, @Estado varchar(60);
        SELECT @IdEntrega = en.IdEntrega, @Estado = e.CodigoEstado
          FROM ejecucion.Entrega AS en
          JOIN sigcm.Expediente AS e ON e.IdExpediente = en.IdExpediente
         WHERE en.IdExpediente = @IdExpediente AND en.Activo = 1;
        IF @IdEntrega IS NULL
            THROW 52083, 'NO_ENCONTRADO: la entrega no existe.', 1;
        IF @Estado <> 'EJE_ENT_RECEPCIONADA_ALMACEN'
            THROW 52084, 'CONFLICTO_ESTADO: la entrega no esta recepcionada en Almacen.', 1;

        UPDATE ejecucion.Entrega
           SET NumeroPecosa = @Pecosa, PecosaDocumento = COALESCE(@PecosaDoc, PecosaDocumento),
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdEntrega = @IdEntrega;

        EXEC ejecucion.paMoverEntregaInterno @parametro, @IdEntrega, 'EJE_ENT_ENTREGAR_AU';
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
/* 11. ejecucion.paEjecutarAccionEntrega                                     */
/*     Las transiciones que no traen datos propios: registrar la guia en     */
/*     Almacen (ruta sede) y confirmar el retiro. Pasan por aqui y no por    */
/*     sigcm.paEjecutarTransicion directo solo para resolver la unidad.      */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paEjecutarAccionEntrega
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52085, 'JSON incorrecto.', 1;

        DECLARE @IdExpediente uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @Transicion varchar(70) = JSON_VALUE(@parametro, '$.CodigoTransicion');
        IF @IdExpediente IS NULL OR @Transicion IS NULL
            THROW 52086, 'VALIDACION_PAYLOAD: faltan IdExpediente y CodigoTransicion.', 1;

        DECLARE @IdEntrega uniqueidentifier;
        SELECT @IdEntrega = IdEntrega FROM ejecucion.Entrega WHERE IdExpediente = @IdExpediente AND Activo = 1;
        IF @IdEntrega IS NULL
            THROW 52087, 'NO_ENCONTRADO: la entrega no existe.', 1;

        IF @Transicion = 'EJE_ENT_RETIRAR'
            UPDATE ejecucion.Entrega SET FechaRetiro = GETDATE() WHERE IdEntrega = @IdEntrega;

        EXEC ejecucion.paMoverEntregaInterno @parametro, @IdEntrega, @Transicion;
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
/* 12. ejecucion.paRegistrarIncidencia  (AU, 7.3.3)                          */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paRegistrarIncidencia
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52088, 'JSON incorrecto.', 1;

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

        IF @CodigoRol NOT LIKE 'AREA[_]%'
            THROW 52089, 'NO_AUTORIZADO: la incidencia la comunica el area usuaria (7.3.3).', 1;

        DECLARE @IdContrato uniqueidentifier, @Tipo varchar(20), @Detalle nvarchar(max),
                @Sgd varchar(60), @Informe nvarchar(200);
        SELECT @IdContrato = TRY_CONVERT(uniqueidentifier, IdContrato),
               @Tipo = UPPER(NULLIF(LTRIM(RTRIM(Tipo)), '')),
               @Detalle = NULLIF(LTRIM(RTRIM(Detalle)), N''),
               @Sgd = NULLIF(LTRIM(RTRIM(DocumentoSgd)), ''),
               @Informe = NULLIF(LTRIM(RTRIM(InformeDocumento)), N'')
          FROM OPENJSON(@parametro)
          WITH (IdContrato varchar(50), Tipo varchar(20), Detalle nvarchar(max),
                DocumentoSgd varchar(60), InformeDocumento nvarchar(200));

        IF @IdContrato IS NULL
            THROW 52090, 'VALIDACION_PAYLOAD: falta IdContrato.', 1;
        IF @Tipo NOT IN ('INCIDENCIA', 'INCUMPLIMIENTO', 'RIESGO')
            THROW 52091, 'VALIDACION_TIPO: el tipo es INCIDENCIA, INCUMPLIMIENTO o RIESGO.', 1;
        IF @Detalle IS NULL
            THROW 52092, 'VALIDACION_PAYLOAD: detalle las circunstancias detectadas.', 1;

        DECLARE @IdExpediente uniqueidentifier, @EsFinal bit;
        SELECT @IdExpediente = c.IdExpediente, @EsFinal = w.EsFinal
          FROM ejecucion.Contrato AS c
          JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE c.IdContrato = @IdContrato AND c.Activo = 1;
        IF @IdExpediente IS NULL
            THROW 52093, 'NO_ENCONTRADO: el contrato no existe.', 1;
        IF @EsFinal = 1
            THROW 52094, 'CONFLICTO_ESTADO: el contrato ya esta cerrado.', 1;

        DECLARE @Ahora datetime = GETDATE(), @IdIncidencia uniqueidentifier = NEWID();
        INSERT INTO ejecucion.Incidencia
            (IdIncidencia, IdContrato, Tipo, Detalle, DocumentoSgd, InformeDocumento, Estado,
             IdActorRegistro, RegistradaEn,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdIncidencia, @IdContrato, @Tipo, @Detalle, @Sgd, @Informe, 'COMUNICADA',
             @IdUsuario, @Ahora,
             @Cuenta, @Ahora, @Equipo, @Programa);

        /* Queda en la trazabilidad del contrato sin mover su estado. */
        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
             Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT e.IdExpediente, e.CodigoEstado, e.CodigoEstado, NULL,
               CONCAT(N'Incidencia comunicada a la DEC (', @Tipo, N'): ', LEFT(@Detalle, 400)),
               @IdUsuario, @CodigoRol, @IdUnidad,
               (SELECT @IdIncidencia AS IdIncidencia, @Tipo AS Tipo, @Sgd AS DocumentoSgd FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @Cuenta, @Equipo, @Programa
          FROM sigcm.Expediente AS e WHERE e.IdExpediente = @IdExpediente;

        EXEC sigcm.paRegistrarAuditoria @CorrelacionId, 'EJECUCION', 'ejecucion.Incidencia', @IdIncidencia,
             'REGISTRAR_INCIDENCIA', 'OK', @IdUsuario, @Cuenta, @CodigoRol, @IdUnidad, @Ip, @Equipo, @Programa,
             NULL, @parametro;

        SELECT @resultado = (
            SELECT 1 AS estado, @IdIncidencia AS IdIncidencia,
                   N'Se registro la incidencia.' AS mensaje
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

/* ========================================================================== */
/* 13. ejecucion.paAtenderIncidencia  (DEC)                                  */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paAtenderIncidencia
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52095, 'JSON incorrecto.', 1;

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

        IF @CodigoRol NOT LIKE 'ABAST[_]%'
            THROW 52096, 'NO_AUTORIZADO: la incidencia la atiende la DEC.', 1;

        DECLARE @IdIncidencia uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdIncidencia'));
        DECLARE @Respuesta nvarchar(max) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Respuesta'))), N'');
        IF @IdIncidencia IS NULL
            THROW 52097, 'VALIDACION_PAYLOAD: falta IdIncidencia.', 1;
        IF @Respuesta IS NULL
            THROW 52098, 'VALIDACION_PAYLOAD: indique la atencion dada a la incidencia.', 1;

        DECLARE @IdContrato uniqueidentifier, @Estado varchar(15);
        SELECT @IdContrato = IdContrato, @Estado = Estado FROM ejecucion.Incidencia WHERE IdIncidencia = @IdIncidencia AND Activo = 1;
        IF @IdContrato IS NULL
            THROW 52099, 'NO_ENCONTRADO: la incidencia no existe.', 1;
        IF @Estado = 'ATENDIDA'
            THROW 52000, 'CONFLICTO_ESTADO: la incidencia ya fue atendida.', 1;

        DECLARE @Ahora datetime = GETDATE();
        UPDATE ejecucion.Incidencia
           SET Estado = 'ATENDIDA', Respuesta = @Respuesta, IdActorAtencion = @IdUsuario, AtendidaEn = @Ahora,
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdIncidencia = @IdIncidencia;

        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
             Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT e.IdExpediente, e.CodigoEstado, e.CodigoEstado, NULL,
               CONCAT(N'Incidencia atendida por la DEC: ', LEFT(@Respuesta, 400)),
               @IdUsuario, @CodigoRol, @IdUnidad,
               (SELECT @IdIncidencia AS IdIncidencia FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @Cuenta, @Equipo, @Programa
          FROM ejecucion.Contrato AS c
          JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
         WHERE c.IdContrato = @IdContrato;

        EXEC sigcm.paRegistrarAuditoria @CorrelacionId, 'EJECUCION', 'ejecucion.Incidencia', @IdIncidencia,
             'ATENDER_INCIDENCIA', 'OK', @IdUsuario, @Cuenta, @CodigoRol, @IdUnidad, @Ip, @Equipo, @Programa,
             NULL, @parametro;

        SELECT @resultado = (
            SELECT 1 AS estado, @IdIncidencia AS IdIncidencia, N'Se registro la atencion de la incidencia.' AS mensaje
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

/* ========================================================================== */
/* 14. ejecucion.paCulminarContrato  (AREA_JEFE)                             */
/*     Solo cuando todos los entregables del cronograma tienen conformidad   */
/*     y ninguna entrega fisica sigue abierta.                               */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paCulminarContrato
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52002, 'JSON incorrecto.', 1;

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
        IF @IdExpediente IS NULL
            THROW 52003, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @IdContrato uniqueidentifier, @IdRequerimiento uniqueidentifier, @Version int;
        SELECT @IdContrato = c.IdContrato, @IdRequerimiento = c.IdRequerimiento, @Version = e.Version
          FROM ejecucion.Contrato AS c
          JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
         WHERE c.IdExpediente = @IdExpediente AND c.Activo = 1;
        IF @IdContrato IS NULL
            THROW 52004, 'NO_ENCONTRADO: el contrato no existe.', 1;

        DECLARE @SinConformidad int, @EntregasAbiertas int, @Total int;
        SELECT @Total = COUNT(*),
               @SinConformidad = SUM(CASE WHEN wp.Orden < 40 THEN 1 ELSE 0 END)
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS ep ON ep.IdExpediente = p.IdExpediente
          JOIN sigcm.Estado AS wp ON wp.CodigoEstado = ep.CodigoEstado
         WHERE p.IdRequerimiento = @IdRequerimiento AND p.Activo = 1;

        SELECT @EntregasAbiertas = COUNT(*)
          FROM ejecucion.Entrega AS en
          JOIN sigcm.Expediente AS ee ON ee.IdExpediente = en.IdExpediente
          JOIN sigcm.Estado AS we ON we.CodigoEstado = ee.CodigoEstado
         WHERE en.IdContrato = @IdContrato AND en.Activo = 1 AND we.EsFinal = 0;

        IF ISNULL(@Total, 0) = 0
            THROW 52005, 'CONFLICTO_ESTADO: el contrato no tiene entregables en el cronograma.', 1;
        IF ISNULL(@SinConformidad, 0) > 0
        BEGIN
            DECLARE @err nvarchar(400) = CONCAT('CONFLICTO_ESTADO: ', @SinConformidad, ' de ', @Total,
                ' entregable(s) todavia no tienen conformidad aprobada. Se culmina desde Entregables y pagos.');
            THROW 52006, @err, 1;
        END
        IF @EntregasAbiertas > 0
            THROW 52007, 'CONFLICTO_ESTADO: hay entregas de bienes sin cerrar.', 1;

        DECLARE @Ahora datetime = GETDATE();
        UPDATE ejecucion.Contrato
           SET FechaFinReal = CONVERT(date, @Ahora),
               UsuarioModificacionAuditoria = @Cuenta, FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo, ProgramaModificacionAuditoria = @Programa
         WHERE IdContrato = @IdContrato;

        UPDATE sigcm.Plazo
           SET CumplidoEn = @Ahora,
               Estado = CASE WHEN CONVERT(date, @Ahora) <= COALESCE(AmpliadoHasta, Vencimiento) THEN 'CUMPLIDO' ELSE 'VENCIDO' END
         WHERE IdExpediente = @IdExpediente AND CodigoRegla = 'EJE_EJECUCION_CONTRATO' AND Estado = 'EN_CURSO' AND Activo = 1;

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'EJE_CULMINAR');
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
/* 15. ejecucion.paListarVerificadorDisponible                               */
/*     Personas del area usuaria del contrato, para el combo del jefe.       */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE ejecucion.paListarVerificadorDisponible
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52008, 'JSON incorrecto.', 1;

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

        DECLARE @IdContrato uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdContrato'));
        DECLARE @IdUnidadOrigen uniqueidentifier;
        SELECT @IdUnidadOrigen = e.IdUnidadOrigen
          FROM ejecucion.Contrato AS c JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
         WHERE c.IdContrato = @IdContrato AND c.Activo = 1;
        IF @IdUnidadOrigen IS NULL
            THROW 52009, 'NO_ENCONTRADO: el contrato no existe.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Personas = JSON_QUERY(COALESCE((
                       SELECT u.IdUsuario, Nombre = CONCAT(u.Nombres, N' ', u.Apellidos), u.Cuenta,
                              Rol = MIN(ur.CodigoRol)
                         FROM sigcm.UsuarioRol AS ur
                         JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
                        WHERE ur.IdUnidad = @IdUnidadOrigen AND ur.CodigoRol LIKE 'AREA[_]%'
                          AND ur.Activo = 1 AND u.Activo = 1
                        GROUP BY u.IdUsuario, u.Nombres, u.Apellidos, u.Cuenta
                        ORDER BY Nombre
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

PRINT 'F016 aplicada: contrato en ejecucion, entregas de bienes, incidencias y culminacion.';
GO
