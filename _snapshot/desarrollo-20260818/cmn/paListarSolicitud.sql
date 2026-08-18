/*
  Base    : DBSIGCM
  Esquema : cmn
  Objeto  : cmn.paListarSolicitud
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 3. cmn.paListarSolicitud                                                  */
/* ========================================================================== */

/*
  Bandeja del modulo. El filtro por defecto es "mi bandeja": lo que esta en la
  unidad del actor Y cuyo estado tiene como responsable el rol del actor. Asi el
  especialista no ve lo que le toca firmar al jefe, ni al reves.

  Entrada:
  { "Actor": {...},
    "Filtro": { "SoloMiBandeja": true, "CodigoEstado": "...", "AnoEje": 2026,
                "CentroCosto": "...", "Texto": "...", "Limite": 50, "Desplazamiento": 0 } }
*/
CREATE   PROCEDURE cmn.paListarSolicitud
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF sigcm.fnEsJson(@parametro) <> 1
            RAISERROR('JSON incorrecto.', 16, 1);

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

        DECLARE @SoloMiBandeja bit, @CodigoEstado varchar(60), @AnoEje smallint,
                @CentroCosto varchar(15), @Texto varchar(200),
                @Limite int, @Desplazamiento int,
                @SoloTxt nvarchar(20);

        SET @SoloTxt        = sigcm.fnJsonTexto(@parametro, 'Filtro.SoloMiBandeja');
        SET @SoloMiBandeja  = CASE
                                WHEN @SoloTxt IS NULL THEN 1
                                WHEN @SoloTxt IN (N'true', N'True', N'TRUE', N'1') THEN 1
                                WHEN @SoloTxt IN (N'false', N'False', N'FALSE', N'0') THEN 0
                                ELSE 1
                              END;
        SET @CodigoEstado   = sigcm.fnJsonTexto(@parametro, 'Filtro.CodigoEstado');
        SET @AnoEje         = CONVERT(smallint, sigcm.fnJsonEntero(@parametro, 'Filtro.AnoEje'));
        SET @CentroCosto    = sigcm.fnJsonTexto(@parametro, 'Filtro.CentroCosto');
        SET @Texto          = sigcm.fnJsonTexto(@parametro, 'Filtro.Texto');
        SET @Limite         = sigcm.fnJsonEntero(@parametro, 'Filtro.Limite');
        SET @Desplazamiento = sigcm.fnJsonEntero(@parametro, 'Filtro.Desplazamiento');

        SET @SoloMiBandeja  = ISNULL(@SoloMiBandeja, 1);
        SET @Limite         = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50
                                   WHEN @Limite > 200 THEN 200 ELSE @Limite END;
        SET @Desplazamiento = CASE WHEN @Desplazamiento IS NULL OR @Desplazamiento < 0
                                   THEN 0 ELSE @Desplazamiento END;

        DECLARE @Total int;

        SELECT @Total = COUNT(*)
          FROM cmn.Solicitud AS s
          JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
          JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE e.Anulado = 0 AND e.Activo = 1 AND s.Activo = 1
           AND (@SoloMiBandeja = 0
                OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol))
           AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
           AND (@AnoEje       IS NULL OR s.AnoEje       = @AnoEje)
           AND (@CentroCosto  IS NULL OR s.CentroCosto  = @CentroCosto)
           AND (@Texto        IS NULL OR s.Codigo LIKE '%' + @Texto + '%'
                                      OR s.Sustento LIKE '%' + @Texto + '%');

        DECLARE @Solicitudes nvarchar(max);
        SET @Solicitudes = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"IdSolicitud":'    + sigcm.fnJsonValorTexto(CONVERT(varchar(36), t.IdSolicitud))
                + N',"Codigo":'         + sigcm.fnJsonValorTexto(t.Codigo)
                + N',"AnoEje":'         + CONVERT(nvarchar(10), t.AnoEje)
                + N',"CentroCosto":'    + sigcm.fnJsonValorTexto(t.CentroCosto)
                + N',"TipoOperacion":'  + sigcm.fnJsonValorTexto(t.TipoOperacion)
                + N',"TipoInclusion":'  + sigcm.fnJsonValorTexto(t.TipoInclusion)
                + N',"FechaSolicitud":' + sigcm.fnJsonValorTexto(CONVERT(varchar(10), t.FechaSolicitud, 23))
                + N',"IdExpediente":'   + sigcm.fnJsonValorTexto(CONVERT(varchar(36), t.IdExpediente))
                + N',"CodigoEstado":'   + sigcm.fnJsonValorTexto(t.CodigoEstado)
                + N',"Version":'        + CONVERT(nvarchar(20), t.Version)
                + N',"Estado":'         + sigcm.fnJsonValorTexto(t.Estado)
                + N',"RolResponsable":' + sigcm.fnJsonValorTexto(t.RolResponsable)
                + N',"Items":'          + CONVERT(nvarchar(20), t.Items)
                + N',"MontoTotal":'     + CONVERT(nvarchar(40), t.MontoTotal)
                + N',"ActualizadoEn":'  + sigcm.fnJsonValorTexto(CONVERT(varchar(23), t.ActualizadoEn, 126))
                + N'}'
            FROM (
                SELECT s.IdSolicitud, s.Codigo, s.AnoEje, s.CentroCosto,
                       s.TipoOperacion, s.TipoInclusion, s.FechaSolicitud,
                       e.IdExpediente, e.CodigoEstado, e.Version,
                       Estado = w.Nombre,
                       RolResponsable = w.RolResponsable,
                       Items = (SELECT COUNT(*) FROM cmn.SolicitudItem AS it
                                 WHERE it.IdSolicitud = s.IdSolicitud AND it.Activo = 1),
                       MontoTotal = (SELECT ISNULL(SUM(p.Monto), 0)
                                       FROM cmn.SolicitudItem AS it
                                       JOIN cmn.SolicitudItemPeriodo AS p
                                         ON p.IdSolicitudItem = it.IdSolicitudItem
                                      WHERE it.IdSolicitud = s.IdSolicitud),
                       ActualizadoEn = ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria),
                       Fila = ROW_NUMBER() OVER (
                           ORDER BY ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria) DESC)
                  FROM cmn.Solicitud AS s
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
                  JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
                 WHERE e.Anulado = 0 AND e.Activo = 1 AND s.Activo = 1
                   AND (@SoloMiBandeja = 0
                        OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol))
                   AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
                   AND (@AnoEje       IS NULL OR s.AnoEje       = @AnoEje)
                   AND (@CentroCosto  IS NULL OR s.CentroCosto  = @CentroCosto)
                   AND (@Texto        IS NULL OR s.Codigo LIKE '%' + @Texto + '%'
                                              OR s.Sustento LIKE '%' + @Texto + '%')
            ) AS t
            WHERE t.Fila > @Desplazamiento AND t.Fila <= @Desplazamiento + @Limite
            ORDER BY t.Fila
            FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SET @resultado = N'{"estado":1'
            + N',"total":'          + CONVERT(nvarchar(20), @Total)
            + N',"limite":'         + CONVERT(nvarchar(20), @Limite)
            + N',"desplazamiento":' + CONVERT(nvarchar(20), @Desplazamiento)
            + N',"Solicitudes":'    + ISNULL(@Solicitudes, N'[]')
            + N',"mensaje":"OK"}';

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N',"Solicitudes":[]}';
        SELECT @resultado;
    END CATCH
END
GO
