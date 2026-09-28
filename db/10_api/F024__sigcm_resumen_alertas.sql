/*
  F024 - Campana de alertas transversal (todos los modulos).

  sigcm.paResumenAlertas
    Pendientes : expedientes cuya accion le toca a este actor. En PAGO manda
                 pago.fnMeToca (asignacion, secretaria, ruta de vistos buenos);
                 en el resto, la misma regla de sus bandejas: unidad actual y
                 rol responsable del estado.
    PorVencer  : plazos que vencen en los proximos 7 dias (sigcm.Plazo y, en
                 PAGO, entregables por presentar).
    Vencidos   : plazos vencidos sin cumplir.
  Modulos trae el desglose por modulo; BuscarCodigo es el codigo con el que la
  bandeja del modulo encuentra la fila (una entrega se busca por su contrato).
  Abastecimiento ve los plazos de toda la entidad; el resto, los de su unidad.

  Depende de F023 (pago.paResumenAlertas).
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE sigcm.paResumenAlertas
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52401, 'JSON incorrecto.', 1;

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

        DECLARE @Hoy date = CONVERT(date, GETDATE());
        DECLARE @Limite7 date = DATEADD(DAY, 7, @Hoy);
        DECLARE @TodaEntidad bit = CASE WHEN @CodigoRol LIKE 'ABAST[_]%' THEN 1 ELSE 0 END;

        DECLARE @Items TABLE (
            IdExpediente uniqueidentifier, CodigoModulo varchar(30), Codigo varchar(40),
            BuscarCodigo varchar(40), Estado varchar(150), Descripcion nvarchar(400),
            FechaLimite date, Tipo varchar(20), Prioridad int);
        DECLARE @Conteo TABLE (CodigoModulo varchar(30) PRIMARY KEY, Pendientes int, PorVencer int, Vencidos int);

        /* PAGO: su propio resumen ya resuelve asignacion, vistos buenos y proveedor. */
        DECLARE @Pago TABLE (Json nvarchar(max));
        INSERT INTO @Pago EXEC pago.paResumenAlertas @parametro;
        DECLARE @JsonPago nvarchar(max) = (SELECT TOP 1 Json FROM @Pago);

        IF ISJSON(@JsonPago) = 1 AND JSON_VALUE(@JsonPago, '$.estado') = '1'
        BEGIN
            INSERT INTO @Conteo
            SELECT 'PAGO', JSON_VALUE(@JsonPago, '$.Pendientes'),
                   JSON_VALUE(@JsonPago, '$.PorVencer'), JSON_VALUE(@JsonPago, '$.Vencidos');

            INSERT INTO @Items
            SELECT i.IdExpediente, 'PAGO', i.Codigo, i.Codigo, i.Estado,
                   CONCAT(i.NombreEntregable, CASE WHEN i.NombreLocador IS NOT NULL THEN N' · ' + i.NombreLocador END),
                   i.FechaLimite, i.Tipo,
                   CASE i.Tipo WHEN 'VENCIDO' THEN 1 WHEN 'POR_VENCER' THEN 2 ELSE 3 END
              FROM OPENJSON(@JsonPago, '$.Items')
              WITH (IdExpediente uniqueidentifier, Codigo varchar(40), Estado varchar(150),
                    NombreEntregable nvarchar(300), NombreLocador nvarchar(250),
                    FechaLimite date, Tipo varchar(20)) AS i;
        END

        /* Resto de modulos. */
        DECLARE @Base TABLE (
            IdExpediente uniqueidentifier PRIMARY KEY, CodigoModulo varchar(30), Codigo varchar(40),
            BuscarCodigo varchar(40), Estado varchar(150), MeToca bit, Visible bit);

        INSERT INTO @Base
        SELECT e.IdExpediente, e.CodigoModulo, e.Codigo,
               CASE WHEN e.CodigoModulo = 'EJECUCION' AND p.CodigoModulo = 'EJECUCION' THEN p.Codigo ELSE e.Codigo END,
               w.Nombre,
               CONVERT(bit, CASE WHEN e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol
                                  AND (e.IdResponsableActual IS NULL OR e.IdResponsableActual = @IdUsuario)
                                 THEN 1 ELSE 0 END),
               CONVERT(bit, CASE WHEN @TodaEntidad = 1 OR e.IdUnidadActual = @IdUnidad OR e.IdUnidadOrigen = @IdUnidad
                                 THEN 1 ELSE 0 END)
          FROM sigcm.Expediente AS e
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
          LEFT JOIN sigcm.Expediente AS p ON p.IdExpediente = e.IdExpedientePadre
         WHERE e.Anulado = 0 AND e.Activo = 1 AND w.EsFinal = 0
           AND e.CodigoModulo NOT IN ('PAGO')
           AND @CodigoRol <> 'PROVEEDOR'
           AND (@TodaEntidad = 1 OR e.IdUnidadActual = @IdUnidad OR e.IdUnidadOrigen = @IdUnidad);

        /* Un plazo por expediente: el mas urgente. */
        ;WITH Pl AS (
            SELECT b.IdExpediente, pr.Nombre,
                   Vence = COALESCE(pl.AmpliadoHasta, pl.Vencimiento),
                   Orden = ROW_NUMBER() OVER (PARTITION BY b.IdExpediente
                                              ORDER BY COALESCE(pl.AmpliadoHasta, pl.Vencimiento))
              FROM @Base AS b
              JOIN sigcm.Plazo AS pl ON pl.IdExpediente = b.IdExpediente
              JOIN sigcm.PlazoRegla AS pr ON pr.CodigoRegla = pl.CodigoRegla
             WHERE b.Visible = 1 AND pl.Activo = 1 AND pl.CumplidoEn IS NULL
               AND pl.Estado IN ('EN_CURSO', 'VENCIDO')
               AND COALESCE(pl.AmpliadoHasta, pl.Vencimiento) <= @Limite7
        )
        INSERT INTO @Items
        SELECT b.IdExpediente, b.CodigoModulo, b.Codigo, b.BuscarCodigo, b.Estado, Pl.Nombre, Pl.Vence,
               CASE WHEN Pl.Vence < @Hoy THEN 'VENCIDO' ELSE 'POR_VENCER' END,
               CASE WHEN Pl.Vence < @Hoy THEN 1 ELSE 2 END
          FROM Pl JOIN @Base AS b ON b.IdExpediente = Pl.IdExpediente
         WHERE Pl.Orden = 1;

        INSERT INTO @Items
        SELECT b.IdExpediente, b.CodigoModulo, b.Codigo, b.BuscarCodigo, b.Estado, NULL, NULL, 'PENDIENTE', 3
          FROM @Base AS b
         WHERE b.MeToca = 1
           AND NOT EXISTS (SELECT 1 FROM @Items AS i WHERE i.IdExpediente = b.IdExpediente);

        INSERT INTO @Conteo
        SELECT m.CodigoModulo,
               (SELECT COUNT(*) FROM @Base AS b WHERE b.CodigoModulo = m.CodigoModulo AND b.MeToca = 1),
               (SELECT COUNT(*) FROM @Items AS i WHERE i.CodigoModulo = m.CodigoModulo AND i.Tipo = 'POR_VENCER'),
               (SELECT COUNT(*) FROM @Items AS i WHERE i.CodigoModulo = m.CodigoModulo AND i.Tipo = 'VENCIDO')
          FROM (SELECT DISTINCT CodigoModulo FROM @Base) AS m;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Pendientes = (SELECT ISNULL(SUM(Pendientes), 0) FROM @Conteo),
                   PorVencer  = (SELECT ISNULL(SUM(PorVencer), 0) FROM @Conteo),
                   Vencidos   = (SELECT ISNULL(SUM(Vencidos), 0) FROM @Conteo),
                   Modulos = JSON_QUERY(COALESCE((
                       SELECT c.CodigoModulo, Modulo = m.Nombre, c.Pendientes, c.PorVencer, c.Vencidos
                         FROM @Conteo AS c
                         JOIN sigcm.Modulo AS m ON m.CodigoModulo = c.CodigoModulo
                        WHERE c.Pendientes + c.PorVencer + c.Vencidos > 0
                        ORDER BY m.Orden
                          FOR JSON PATH), N'[]')),
                   Items = JSON_QUERY(COALESCE((
                       SELECT TOP 40 i.IdExpediente, i.CodigoModulo, Modulo = m.Nombre, i.Codigo, i.BuscarCodigo,
                              i.Estado, i.Descripcion, i.FechaLimite, i.Tipo,
                              DiasParaVencer = DATEDIFF(DAY, @Hoy, i.FechaLimite)
                         FROM @Items AS i
                         JOIN sigcm.Modulo AS m ON m.CodigoModulo = i.CodigoModulo
                        ORDER BY i.Prioridad, i.FechaLimite, m.Orden, i.Codigo
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
