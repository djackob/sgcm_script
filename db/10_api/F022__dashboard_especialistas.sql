/*
===============================================================================
  SIGCM - F022 : Dashboard de seguimiento de especialistas de Abastecimiento
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 52120-52129

  Lo consultan el jefe y el coordinador de Abastecimiento. Mide, por
  especialista y en el periodo elegido, lo que dice sigcm.Historial:

    Acciones      transiciones que ejecuto con rol ABAST_ESPECIALISTA
    Atendidos     expedientes distintos sobre los que actuo
    Despachados   atendidos que ya salieron de su bandeja
    Pendientes    expedientes hoy en un estado a cargo del especialista
                  (responsable actual o, si no hay, el ultimo especialista
                  que actuo sobre el expediente)
    Devoluciones  veces que coordinador o jefe le devolvieron / observaron
                  un expediente que el habia trabajado
    HorasPromedio tiempo entre la llegada del expediente y su accion
    Efectividad   (Despachados - Devoluciones) / (Despachados + Pendientes)

  Entrada: { "FechaDesde":"2026-01-01", "FechaHasta":"2026-09-27",
             "CodigoModulo":null }
  Sin fechas: desde el 1 de enero del anio en curso hasta hoy.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE sigcm.paDashboardEspecialistas
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52120, 'JSON incorrecto.', 1;

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
            THROW 52121, 'NO_AUTORIZADO: el dashboard de especialistas es para el jefe y el coordinador de Abastecimiento.', 1;

        DECLARE @FechaDesde date, @FechaHasta date, @CodigoModulo varchar(30);

        SELECT @FechaDesde   = FechaDesde,
               @FechaHasta   = FechaHasta,
               @CodigoModulo = NULLIF(LTRIM(RTRIM(CodigoModulo)), '')
          FROM OPENJSON(@parametro)
          WITH (
              FechaDesde   date,
              FechaHasta   date,
              CodigoModulo varchar(30)
          );

        SET @FechaHasta = ISNULL(@FechaHasta, CONVERT(date, GETDATE()));
        SET @FechaDesde = ISNULL(@FechaDesde, DATEFROMPARTS(YEAR(@FechaHasta), 1, 1));

        IF @FechaDesde > @FechaHasta
            THROW 52122, 'VALIDACION_FECHAS: la fecha inicial no puede ser mayor que la final.', 1;

        DECLARE @Desde datetime = CONVERT(datetime, @FechaDesde),
                @Hasta datetime = DATEADD(DAY, 1, CONVERT(datetime, @FechaHasta)),
                @Ahora datetime = GETDATE();

        /* Especialistas vigentes y los que actuaron como tales en el periodo. */
        CREATE TABLE #Esp (IdUsuario uniqueidentifier PRIMARY KEY);

        INSERT INTO #Esp (IdUsuario)
        SELECT DISTINCT ur.IdUsuario
          FROM sigcm.UsuarioRol AS ur
          JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario AND u.Activo = 1
         WHERE ur.CodigoRol = 'ABAST_ESPECIALISTA'
           AND ur.Activo = 1
           AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @FechaDesde);

        INSERT INTO #Esp (IdUsuario)
        SELECT DISTINCT h.IdActor
          FROM sigcm.Historial AS h
         WHERE h.ActorRol = 'ABAST_ESPECIALISTA'
           AND h.OcurridoEn >= @Desde AND h.OcurridoEn < @Hasta
           AND NOT EXISTS (SELECT 1 FROM #Esp AS e WHERE e.IdUsuario = h.IdActor);

        /* Historial de los expedientes del alcance, con el evento anterior. */
        CREATE TABLE #Hist (
            IdHistorial   bigint PRIMARY KEY,
            IdExpediente  uniqueidentifier NOT NULL,
            IdActor       uniqueidentifier NOT NULL,
            ActorRol      varchar(40) NOT NULL,
            CodigoTransicion varchar(70) NULL,
            CodigoEstadoOrigen varchar(60) NULL,
            CodigoEstadoDestino varchar(60) NOT NULL,
            OcurridoEn    datetime NOT NULL,
            Previo        datetime NULL
        );

        INSERT INTO #Hist
        SELECT h.IdHistorial, h.IdExpediente, h.IdActor, h.ActorRol, h.CodigoTransicion,
               h.CodigoEstadoOrigen, h.CodigoEstadoDestino, h.OcurridoEn,
               LAG(h.OcurridoEn) OVER (PARTITION BY h.IdExpediente ORDER BY h.OcurridoEn, h.IdHistorial)
          FROM sigcm.Historial AS h
          JOIN sigcm.Expediente AS e ON e.IdExpediente = h.IdExpediente
         WHERE e.Activo = 1
           AND (@CodigoModulo IS NULL OR e.CodigoModulo = @CodigoModulo)
           AND h.OcurridoEn < @Hasta;

        /* Acciones del especialista en el periodo. */
        CREATE TABLE #Acc (
            IdUsuario    uniqueidentifier NOT NULL,
            IdExpediente uniqueidentifier NOT NULL,
            Minutos      int NULL
        );

        INSERT INTO #Acc
        SELECT h.IdActor, h.IdExpediente,
               CASE WHEN h.Previo IS NULL THEN NULL
                    ELSE DATEDIFF(MINUTE, h.Previo, h.OcurridoEn) END
          FROM #Hist AS h
         WHERE h.ActorRol = 'ABAST_ESPECIALISTA'
           AND h.OcurridoEn >= @Desde;

        /* Pendientes hoy: el estado actual es responsabilidad del especialista. */
        CREATE TABLE #Pend (
            IdExpediente uniqueidentifier PRIMARY KEY,
            IdUsuario    uniqueidentifier NULL,
            Codigo       varchar(40) NOT NULL,
            CodigoModulo varchar(30) NOT NULL,
            Estado       varchar(150) NOT NULL,
            DesdeEl      datetime NULL
        );

        INSERT INTO #Pend
        SELECT e.IdExpediente,
               COALESCE(
                   CASE WHEN EXISTS (SELECT 1 FROM #Esp AS x WHERE x.IdUsuario = e.IdResponsableActual)
                        THEN e.IdResponsableActual END,
                   ult.IdActor),
               e.Codigo, e.CodigoModulo, s.Nombre,
               ISNULL(lle.OcurridoEn, e.FechaCreacionAuditoria)
          FROM sigcm.Expediente AS e
          JOIN sigcm.Estado AS s ON s.CodigoEstado = e.CodigoEstado
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
               ORDER BY h.OcurridoEn DESC, h.IdHistorial DESC) AS lle
         WHERE e.Activo = 1
           AND e.Anulado = 0
           AND e.CerradoEn IS NULL
           AND s.RolResponsable = 'ABAST_ESPECIALISTA'
           AND s.EsFinal = 0
           AND (@CodigoModulo IS NULL OR e.CodigoModulo = @CodigoModulo);

        /* Devoluciones: coordinador o jefe regresan el expediente al especialista
           por observacion; se atribuye al ultimo especialista que lo trabajo. */
        CREATE TABLE #Dev (IdUsuario uniqueidentifier NOT NULL);

        INSERT INTO #Dev
        SELECT prev.IdActor
          FROM #Hist AS h
          JOIN sigcm.Estado AS d ON d.CodigoEstado = h.CodigoEstadoDestino
          LEFT JOIN sigcm.Transicion AS t ON t.CodigoTransicion = h.CodigoTransicion
          CROSS APPLY (
              SELECT TOP (1) p.IdActor
                FROM #Hist AS p
               WHERE p.IdExpediente = h.IdExpediente
                 AND p.ActorRol = 'ABAST_ESPECIALISTA'
                 AND (p.OcurridoEn < h.OcurridoEn
                      OR (p.OcurridoEn = h.OcurridoEn AND p.IdHistorial < h.IdHistorial))
               ORDER BY p.OcurridoEn DESC, p.IdHistorial DESC) AS prev
         WHERE h.OcurridoEn >= @Desde
           AND h.ActorRol IN ('ABAST_COORDINADOR', 'ABAST_JEFE', 'ABAST_SECRETARIA')
           AND d.RolResponsable = 'ABAST_ESPECIALISTA'
           AND (ISNULL(t.GeneraObservacion, 0) = 1
                OR h.CodigoTransicion LIKE '%DEVOLVER%'
                OR h.CodigoTransicion LIKE '%OBSERV%');

        CREATE TABLE #Res (
            IdUsuario     uniqueidentifier PRIMARY KEY,
            Nombre        varchar(250) NOT NULL,
            Cuenta        varchar(120) NOT NULL,
            Acciones      int NOT NULL,
            Atendidos     int NOT NULL,
            Despachados   int NOT NULL,
            Pendientes    int NOT NULL,
            Devoluciones  int NOT NULL,
            HorasPromedio decimal(10, 1) NULL,
            DiasMaxEspera int NULL,
            Efectividad   decimal(5, 1) NULL
        );

        INSERT INTO #Res (IdUsuario, Nombre, Cuenta, Acciones, Atendidos, Despachados,
                          Pendientes, Devoluciones, HorasPromedio, DiasMaxEspera)
        SELECT e.IdUsuario,
               LTRIM(RTRIM(CONCAT(u.Nombres, N' ', u.Apellidos))),
               u.Cuenta,
               ISNULL((SELECT COUNT(*) FROM #Acc AS a WHERE a.IdUsuario = e.IdUsuario), 0),
               ISNULL((SELECT COUNT(DISTINCT a.IdExpediente) FROM #Acc AS a WHERE a.IdUsuario = e.IdUsuario), 0),
               ISNULL((SELECT COUNT(DISTINCT a.IdExpediente)
                         FROM #Acc AS a
                        WHERE a.IdUsuario = e.IdUsuario
                          AND NOT EXISTS (SELECT 1 FROM #Pend AS p
                                           WHERE p.IdExpediente = a.IdExpediente
                                             AND p.IdUsuario = e.IdUsuario)), 0),
               ISNULL((SELECT COUNT(*) FROM #Pend AS p WHERE p.IdUsuario = e.IdUsuario), 0),
               ISNULL((SELECT COUNT(*) FROM #Dev AS d WHERE d.IdUsuario = e.IdUsuario), 0),
               (SELECT CONVERT(decimal(10, 1), AVG(CONVERT(decimal(18, 2), a.Minutos)) / 60.0)
                  FROM #Acc AS a WHERE a.IdUsuario = e.IdUsuario AND a.Minutos IS NOT NULL),
               (SELECT MAX(DATEDIFF(DAY, p.DesdeEl, @Ahora)) FROM #Pend AS p WHERE p.IdUsuario = e.IdUsuario)
          FROM #Esp AS e
          JOIN sigcm.Usuario AS u ON u.IdUsuario = e.IdUsuario;

        UPDATE #Res
           SET Efectividad = CASE WHEN Despachados + Pendientes = 0 THEN NULL
                                  ELSE CONVERT(decimal(5, 1),
                                       100.0 * (Despachados - CASE WHEN Devoluciones > Despachados
                                                                   THEN Despachados ELSE Devoluciones END)
                                       / (Despachados + Pendientes)) END;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   CONVERT(char(10), @FechaDesde, 23) AS FechaDesde,
                   CONVERT(char(10), @FechaHasta, 23) AS FechaHasta,
                   @CodigoModulo AS CodigoModulo,
                   Totales = JSON_QUERY((
                       SELECT COUNT(*) AS Especialistas,
                              ISNULL(SUM(r.Acciones), 0) AS Acciones,
                              ISNULL(SUM(r.Atendidos), 0) AS Atendidos,
                              ISNULL(SUM(r.Despachados), 0) AS Despachados,
                              (SELECT COUNT(*) FROM #Pend) AS Pendientes,
                              (SELECT COUNT(*) FROM #Pend WHERE IdUsuario IS NULL) AS SinAsignar,
                              ISNULL(SUM(r.Devoluciones), 0) AS Devoluciones,
                              (SELECT CONVERT(decimal(10, 1), AVG(CONVERT(decimal(18, 2), a.Minutos)) / 60.0)
                                 FROM #Acc AS a WHERE a.Minutos IS NOT NULL) AS HorasPromedio,
                              CASE WHEN SUM(r.Despachados) + (SELECT COUNT(*) FROM #Pend) = 0 THEN NULL
                                   ELSE CONVERT(decimal(5, 1),
                                        100.0 * (SUM(r.Despachados)
                                                 - CASE WHEN SUM(r.Devoluciones) > SUM(r.Despachados)
                                                        THEN SUM(r.Despachados) ELSE SUM(r.Devoluciones) END)
                                        / (SUM(r.Despachados) + (SELECT COUNT(*) FROM #Pend))) END AS Efectividad
                         FROM #Res AS r
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                   Especialistas = JSON_QUERY(COALESCE((
                       SELECT r.IdUsuario, r.Nombre, r.Cuenta, r.Acciones, r.Atendidos,
                              r.Despachados, r.Pendientes, r.Devoluciones,
                              r.HorasPromedio, r.DiasMaxEspera, r.Efectividad
                         FROM #Res AS r
                        ORDER BY ISNULL(r.Efectividad, -1) DESC, r.Despachados DESC, r.Nombre
                          FOR JSON PATH), '[]')),
                   Pendientes = JSON_QUERY(COALESCE((
                       SELECT p.IdExpediente, p.IdUsuario, p.Codigo, p.CodigoModulo,
                              Modulo = m.Nombre, p.Estado,
                              CONVERT(char(10), p.DesdeEl, 23) AS DesdeEl,
                              DATEDIFF(DAY, p.DesdeEl, @Ahora) AS DiasEspera
                         FROM #Pend AS p
                         JOIN sigcm.Modulo AS m ON m.CodigoModulo = p.CodigoModulo
                        ORDER BY DATEDIFF(DAY, p.DesdeEl, @Ahora) DESC, p.Codigo
                          FOR JSON PATH), '[]')),
                   Modulos = JSON_QUERY(COALESCE((
                       SELECT m.CodigoModulo, m.Nombre
                         FROM sigcm.Modulo AS m
                        WHERE m.Activo = 1
                          AND EXISTS (SELECT 1 FROM sigcm.Estado AS s
                                       WHERE s.CodigoModulo = m.CodigoModulo
                                         AND s.RolResponsable = 'ABAST_ESPECIALISTA'
                                         AND s.Activo = 1)
                        ORDER BY m.Orden
                          FOR JSON PATH), '[]')),
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

PRINT 'F022 aplicada: sigcm.paDashboardEspecialistas.';
GO
