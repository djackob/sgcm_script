/*
===============================================================================
  SIGCM - F027 : Dashboard de atencion de expedientes de Abastecimiento
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 52620-52629

  Lo consultan el jefe y el coordinador de Abastecimiento. Devuelve el
  detalle con el que el front arma los cuadros de atencion:
    Expedientes  requerimientos que ya ingresaron a Abastecimiento y aun no
                 se notifican: especialista, tipo, estado de atencion, area
                 usuaria, dias sin movimiento y proveedores
    Ordenes      ordenes con contrato en ejecucion (ordenes vigentes)
    Estados      agrupacion de los estados en columnas de atencion

  Especialista: responsable actual si tiene el rol ABAST_ESPECIALISTA; si no,
  el ultimo especialista que actuo sobre el expediente.

  Entrada: { "CodigoTipoContratacion": null }
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE sigcm.paDashboardAtencion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52620, 'JSON incorrecto.', 1;

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

        IF @CodigoRol NOT IN ('ABAST_JEFE', 'ABAST_COORDINADOR')
            THROW 52621, 'NO_AUTORIZADO: el dashboard de atencion es para el jefe y el coordinador de Abastecimiento.', 1;

        DECLARE @Tipo varchar(30) =
            NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.CodigoTipoContratacion'))), '');

        DECLARE @Hoy date = CONVERT(date, GETDATE()), @Ahora datetime = GETDATE();

        DECLARE @Grupo TABLE (
            CodigoEstado varchar(60) PRIMARY KEY,
            Grupo        nvarchar(60) NOT NULL,
            Orden        int NOT NULL
        );

        INSERT INTO @Grupo (CodigoEstado, Grupo, Orden) VALUES
            ('REQ_EN_ABAST_JEFE',      N'POR ASIGNAR',            10),
            ('REQ_EN_ABAST_COORD',     N'POR ASIGNAR',            10),
            ('REQ_EN_EVAL_DEC',        N'REV DE EXP',             20),
            ('REQ_EN_EVAL_DAI',        N'REV DE EXP',             20),
            ('REQ_OBS_AU_JEFE',        N'UP',                     30),
            ('REQ_OBS_AU_COORD',       N'UP',                     30),
            ('REQ_OBSERVADO',          N'UP',                     30),
            ('REQ_NO_OBJECION',        N'UP',                     30),
            ('REQ_CONFORME',           N'INVITACIÓN',             40),
            ('REQ_INDAGACION_MERCADO', N'INVITACIÓN',             40),
            ('REQ_FILTROS',            N'VALIDACIÓN (SERV/ADQ)',  50),
            ('REQ_FILTROS_COORD',      N'VALIDACIÓN (SERV/ADQ)',  50),
            ('REQ_FILTROS_JEFE',       N'VALIDACIÓN (SERV/ADQ)',  50),
            ('REQ_CCP_SOLICITADO',     N'CCP/EN ATENCIÓN',        60),
            ('REQ_CCP_CARGADA',        N'CCP/EN ATENCIÓN',        60),
            ('REQ_CUADRO_GENERADO',    N'EMISIÓN DE ORDEN',       70),
            ('REQ_OS_EMITIDA',         N'EMISIÓN DE ORDEN',       70);

        CREATE TABLE #Esp (IdUsuario uniqueidentifier PRIMARY KEY);

        INSERT INTO #Esp (IdUsuario)
        SELECT DISTINCT ur.IdUsuario
          FROM sigcm.UsuarioRol AS ur
         WHERE ur.CodigoRol = 'ABAST_ESPECIALISTA'
           AND ur.Activo = 1;

        CREATE TABLE #Exp (
            IdExpediente   uniqueidentifier PRIMARY KEY,
            Codigo         varchar(40) NOT NULL,
            Denominacion   nvarchar(600) NULL,
            CodigoTipoContratacion varchar(30) NULL,
            CodigoEstado   varchar(60) NOT NULL,
            IdUnidad       uniqueidentifier NULL,
            IdEspecialista uniqueidentifier NULL,
            UltimoMov      datetime NULL,
            Monto          decimal(18, 2) NULL,
            Proveedores    nvarchar(1000) NULL
        );

        INSERT INTO #Exp
        SELECT e.IdExpediente, e.Codigo, r.Denominacion, r.CodigoTipoContratacion, e.CodigoEstado,
               e.IdUnidadOrigen,
               COALESCE(CASE WHEN EXISTS (SELECT 1 FROM #Esp AS x WHERE x.IdUsuario = e.IdResponsableActual)
                             THEN e.IdResponsableActual END,
                        ult.IdActor),
               mov.OcurridoEn, r.Monto,
               CASE WHEN ISJSON(r.DatosAdicionales) = 1 THEN
                   (SELECT STRING_AGG(CONVERT(nvarchar(1000), p.Nombre), N', ')
                      FROM (SELECT Nombre = COALESCE(NULLIF(LTRIM(RTRIM(j.RazonSocial)), N''),
                                                     NULLIF(LTRIM(RTRIM(CONCAT(j.Nombres, N' ', j.ApellidoPaterno, N' ', j.ApellidoMaterno))), N''))
                              FROM OPENJSON(r.DatosAdicionales, '$.Proveedores')
                                   WITH (RazonSocial nvarchar(250), Nombres nvarchar(120),
                                         ApellidoPaterno nvarchar(120), ApellidoMaterno nvarchar(120)) AS j) AS p
                     WHERE p.Nombre IS NOT NULL) END
          FROM sigcm.Expediente AS e
          JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente AND r.Activo = 1
          JOIN @Grupo AS g ON g.CodigoEstado = e.CodigoEstado
          OUTER APPLY (
              SELECT TOP (1) h.IdActor
                FROM sigcm.Historial AS h
               WHERE h.IdExpediente = e.IdExpediente
                 AND h.ActorRol = 'ABAST_ESPECIALISTA'
               ORDER BY h.OcurridoEn DESC, h.IdHistorial DESC) AS ult
          OUTER APPLY (
              SELECT TOP (1) h.OcurridoEn
                FROM sigcm.Historial AS h
               WHERE h.IdExpediente = e.IdExpediente
               ORDER BY h.OcurridoEn DESC, h.IdHistorial DESC) AS mov
         WHERE e.Activo = 1
           AND e.Anulado = 0
           AND e.CerradoEn IS NULL
           AND e.CodigoModulo = 'REQUERIMIENTO'
           AND (@Tipo IS NULL OR r.CodigoTipoContratacion = @Tipo)
           AND (g.Grupo <> N'UP'
                OR EXISTS (SELECT 1 FROM sigcm.Historial AS h
                            WHERE h.IdExpediente = e.IdExpediente
                              AND h.CodigoEstadoDestino IN ('REQ_EN_ABAST_JEFE', 'REQ_EN_EVAL_DEC')));

        CREATE TABLE #Ord (
            IdOrdenServicio uniqueidentifier PRIMARY KEY,
            IdContrato      uniqueidentifier NOT NULL,
            NumeroOrden     varchar(60) NULL,
            TipoOrden       char(2) NULL,
            CodigoTipoContratacion varchar(30) NULL,
            CodigoRequerimiento varchar(40) NULL,
            Denominacion    nvarchar(600) NULL,
            IdUnidad        uniqueidentifier NULL,
            Monto           decimal(18, 2) NULL,
            Entregables     int NULL,
            Proveedor       nvarchar(250) NULL,
            Ruc             varchar(20) NULL,
            FechaInicio     date NULL,
            FechaFin        date NULL,
            Estado          varchar(150) NULL
        );

        INSERT INTO #Ord
        SELECT os.IdOrdenServicio, ct.IdContrato,
               COALESCE(NULLIF(os.NumeroOrden, ''), ct.NumeroOrdenSiga, pg.NumeroOrdenSiga),
               COALESCE(pg.TipoOrden, CASE WHEN r.CodigoTipoContratacion = 'BIEN' THEN 'OC' ELSE 'OS' END),
               r.CodigoTipoContratacion, r.Codigo, COALESCE(ct.Denominacion, r.Denominacion), er.IdUnidadOrigen,
               COALESCE(ct.MontoContrato, pg.MontoContrato, r.Monto),
               COALESCE(NULLIF(pg.Entregables, 0), NULLIF(en.Entregas, 0), dp.CantidadEntregables),
               COALESCE(ct.NombreProveedor, pg.NombreLocador),
               COALESCE(ct.RucProveedor, ct.DniProveedor, pg.RucLocador, pg.DniLocador),
               ct.FechaInicio, COALESCE(ct.FechaFinReal, ct.FechaFinPrevista), w.Nombre
          FROM ejecucion.Contrato AS ct
          JOIN sigcm.Expediente AS ec ON ec.IdExpediente = ct.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = ec.CodigoEstado
          JOIN requerimiento.OrdenServicio AS os ON os.IdOrdenServicio = ct.IdOrdenServicio AND os.Activo = 1
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = os.IdRequerimiento
          JOIN sigcm.Expediente AS er ON er.IdExpediente = r.IdExpediente
          OUTER APPLY (SELECT NumeroOrdenSiga = MAX(NULLIF(p.NumeroOrdenSiga, '')), TipoOrden = MAX(p.TipoOrden),
                              NombreLocador = MAX(p.NombreLocador), RucLocador = MAX(p.RucLocador),
                              DniLocador = MAX(p.DniLocador), MontoContrato = MAX(p.MontoContrato),
                              Entregables = COUNT(*)
                         FROM pago.ExpedientePago AS p
                         JOIN sigcm.Expediente AS ep ON ep.IdExpediente = p.IdExpediente
                        WHERE p.IdOrdenServicio = os.IdOrdenServicio AND p.Activo = 1 AND ep.Anulado = 0) AS pg
          OUTER APPLY (SELECT Entregas = COUNT(DISTINCT x.NumeroEntregable)
                         FROM ejecucion.Entrega AS x
                        WHERE x.IdContrato = ct.IdContrato AND x.Activo = 1) AS en
          OUTER APPLY (SELECT CantidadEntregables = MAX(j.CantidadEntregables)
                         FROM OPENJSON(CASE WHEN ISJSON(r.DatosAdicionales) = 1 THEN r.DatosAdicionales END, '$.Proveedores')
                              WITH (CantidadEntregables int) AS j) AS dp
         WHERE ct.Activo = 1
           AND ec.Activo = 1
           AND ec.Anulado = 0
           AND ec.CerradoEn IS NULL
           AND w.EsFinal = 0
           AND (@Tipo IS NULL OR r.CodigoTipoContratacion = @Tipo)
           AND ct.IdContrato = (SELECT TOP (1) c2.IdContrato FROM ejecucion.Contrato AS c2
                                 WHERE c2.IdOrdenServicio = os.IdOrdenServicio AND c2.Activo = 1
                                 ORDER BY c2.FechaCreacionAuditoria DESC);

        SELECT @resultado = (
            SELECT 1 AS estado,
                   CONVERT(char(10), @Hoy, 23) AS FechaReporte,
                   @Tipo AS CodigoTipoContratacion,
                   Estados = JSON_QUERY(COALESCE((
                       SELECT g.Grupo, Orden = MIN(g.Orden)
                         FROM @Grupo AS g
                        GROUP BY g.Grupo
                        ORDER BY MIN(g.Orden)
                          FOR JSON PATH), '[]')),
                   Tipos = JSON_QUERY(COALESCE((
                       SELECT t.CodigoTipoContratacion, t.Nombre
                         FROM sigcm.TipoContratacion AS t
                        WHERE t.Activo = 1
                        ORDER BY t.Nombre
                          FOR JSON PATH), '[]')),
                   Expedientes = JSON_QUERY(COALESCE((
                       SELECT x.IdExpediente, x.Codigo, x.Denominacion, x.CodigoTipoContratacion,
                              TipoGrupo = CASE x.CodigoTipoContratacion
                                              WHEN 'BIEN' THEN N'BIENES'
                                              WHEN 'LOCACION' THEN N'LOCADOR'
                                              WHEN 'CEAM' THEN N'CEAM'
                                              ELSE N'SERVICIOS' END,
                              x.IdEspecialista,
                              Especialista = COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(u.Nombres, N' ', u.Apellidos))), N''), N'SIN ASIGNAR'),
                              g.Grupo, GrupoOrden = g.Orden, x.CodigoEstado, Estado = s.Nombre,
                              AreaSigla = COALESCE(NULLIF(n.Sigla, ''), n.Codigo, N'SIN ÁREA'), Area = n.Nombre,
                              UltimoMovimiento = CONVERT(char(10), x.UltimoMov, 23),
                              DiasInactivo = DATEDIFF(DAY, x.UltimoMov, @Ahora),
                              x.Monto, x.Proveedores
                         FROM #Exp AS x
                         JOIN @Grupo AS g ON g.CodigoEstado = x.CodigoEstado
                         JOIN sigcm.Estado AS s ON s.CodigoEstado = x.CodigoEstado
                         LEFT JOIN sigcm.Usuario AS u ON u.IdUsuario = x.IdEspecialista
                         LEFT JOIN sigcm.Unidad AS n ON n.IdUnidad = x.IdUnidad
                        ORDER BY g.Orden, x.Codigo
                          FOR JSON PATH, INCLUDE_NULL_VALUES), '[]')),
                   Ordenes = JSON_QUERY(COALESCE((
                       SELECT o.IdOrdenServicio, o.NumeroOrden, o.TipoOrden, o.CodigoTipoContratacion,
                              TipoGrupo = CASE o.CodigoTipoContratacion
                                              WHEN 'BIEN' THEN N'BIENES'
                                              WHEN 'LOCACION' THEN N'LOCADOR'
                                              WHEN 'CEAM' THEN N'CEAM'
                                              ELSE N'SERVICIOS' END,
                              o.CodigoRequerimiento, o.Denominacion,
                              AreaSigla = COALESCE(NULLIF(n.Sigla, ''), n.Codigo, N'SIN ÁREA'), Area = n.Nombre,
                              o.Monto, Entregables = ISNULL(o.Entregables, 0), o.Proveedor, o.Ruc,
                              FechaInicio = CONVERT(char(10), o.FechaInicio, 23),
                              FechaFin = CONVERT(char(10), o.FechaFin, 23),
                              DiasRestantes = DATEDIFF(DAY, @Hoy, o.FechaFin), o.Estado
                         FROM #Ord AS o
                         LEFT JOIN sigcm.Unidad AS n ON n.IdUnidad = o.IdUnidad
                        ORDER BY o.FechaFin, o.NumeroOrden
                          FOR JSON PATH, INCLUDE_NULL_VALUES), '[]')),
                   N'OK' AS mensaje
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

PRINT 'F027 aplicada: sigcm.paDashboardAtencion.';
GO
