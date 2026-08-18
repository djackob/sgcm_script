/*
  Base    : DBSIGCM
  Esquema : requerimiento
  Objeto  : requerimiento.paListarRequerimiento
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 3. requerimiento.paListarRequerimiento                                    */
/* ========================================================================== */

/*
  Bandeja del modulo, con el mismo criterio que la de CMN: por defecto muestra
  lo que esta en la unidad del actor Y cuyo estado tiene como responsable su rol.

  Entrada:
  { "Actor": {...},
    "Filtro": { "SoloMiBandeja":true, "CodigoEstado":null, "AnoEje":2026,
                "CentroCosto":null, "CodigoTipoContratacion":null,
                "Texto":null, "Limite":50, "Desplazamiento":0 } }
*/
CREATE   PROCEDURE requerimiento.paListarRequerimiento
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
                @CentroCosto varchar(15), @CodigoTipoContratacion varchar(20),
                @Texto varchar(200), @Limite int, @Desplazamiento int;

        DECLARE @BandejaTxt nvarchar(20);
        SET @BandejaTxt                = LOWER(sigcm.fnJsonTexto(@parametro, 'Filtro.SoloMiBandeja'));
        SET @SoloMiBandeja             = CASE WHEN @BandejaTxt IS NULL OR @BandejaTxt = N'' THEN 1
                                              WHEN @BandejaTxt IN (N'true', N'1') THEN 1
                                              ELSE 0 END;
        SET @CodigoEstado              = sigcm.fnJsonTexto(@parametro, 'Filtro.CodigoEstado');
        SET @AnoEje                    = CONVERT(smallint, sigcm.fnJsonEntero(@parametro, 'Filtro.AnoEje'));
        SET @CentroCosto               = sigcm.fnJsonTexto(@parametro, 'Filtro.CentroCosto');
        SET @CodigoTipoContratacion    = sigcm.fnJsonTexto(@parametro, 'Filtro.CodigoTipoContratacion');
        SET @Texto                     = sigcm.fnJsonTexto(@parametro, 'Filtro.Texto');
        SET @Limite                    = sigcm.fnJsonEntero(@parametro, 'Filtro.Limite');
        SET @Desplazamiento            = sigcm.fnJsonEntero(@parametro, 'Filtro.Desplazamiento');

        SET @SoloMiBandeja  = ISNULL(@SoloMiBandeja, 1);
        SET @Limite         = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50
                                   WHEN @Limite > 200 THEN 200 ELSE @Limite END;
        SET @Desplazamiento = CASE WHEN @Desplazamiento IS NULL OR @Desplazamiento < 0
                                   THEN 0 ELSE @Desplazamiento END;

        DECLARE @Total int;
        DECLARE @Lista nvarchar(max);

        SELECT @Total = COUNT(*)
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
          JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE e.Anulado = 0 AND e.Activo = 1 AND r.Activo = 1
           AND (@SoloMiBandeja = 0
                OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol))
           AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
           AND (@AnoEje       IS NULL OR r.AnoEje       = @AnoEje)
           AND (@CentroCosto  IS NULL OR r.CentroCosto  = @CentroCosto)
           AND (@CodigoTipoContratacion IS NULL OR r.CodigoTipoContratacion = @CodigoTipoContratacion)
           AND (@Texto        IS NULL OR r.Codigo LIKE '%' + @Texto + '%'
                                      OR r.Denominacion LIKE '%' + @Texto + '%');

        SET @Lista = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"IdRequerimiento":' + sigcm.fnJsonValorTexto(CONVERT(nvarchar(36), t.IdRequerimiento))
                + N',"Codigo":' + sigcm.fnJsonValorTexto(t.Codigo)
                + N',"AnoEje":' + CASE WHEN t.AnoEje IS NULL THEN N'null' ELSE CONVERT(nvarchar(10), t.AnoEje) END
                + N',"CentroCosto":' + sigcm.fnJsonValorTexto(t.CentroCosto)
                + N',"Denominacion":' + sigcm.fnJsonValorTexto(t.Denominacion)
                + N',"CodigoTipoContratacion":' + sigcm.fnJsonValorTexto(t.CodigoTipoContratacion)
                + N',"TipoContratacion":' + sigcm.fnJsonValorTexto(t.TipoContratacion)
                + N',"CodigoDec":' + sigcm.fnJsonValorTexto(t.CodigoDec)
                + N',"CondicionCmn":' + sigcm.fnJsonValorTexto(t.CondicionCmn)
                + N',"Monto":' + CASE WHEN t.Monto IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.Monto) END
                + N',"PlazoDias":' + CASE WHEN t.PlazoDias IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.PlazoDias) END
                + N',"FechaInicioPrevisto":' + CASE WHEN t.FechaInicioPrevisto IS NULL THEN N'null'
                                                    ELSE sigcm.fnJsonValorTexto(CONVERT(varchar(10), t.FechaInicioPrevisto, 23)) END
                + N',"IdExpediente":' + sigcm.fnJsonValorTexto(CONVERT(nvarchar(36), t.IdExpediente))
                + N',"CodigoEstado":' + sigcm.fnJsonValorTexto(t.CodigoEstado)
                + N',"Version":' + CASE WHEN t.Version IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.Version) END
                + N',"Estado":' + sigcm.fnJsonValorTexto(t.Estado)
                + N',"RolResponsable":' + sigcm.fnJsonValorTexto(t.RolResponsable)
                + N',"Items":' + CONVERT(nvarchar(20), t.Items)
                + N',"Pedidos":' + CONVERT(nvarchar(20), t.Pedidos)
                + N',"ActualizadoEn":' + CASE WHEN t.ActualizadoEn IS NULL THEN N'null'
                                              ELSE sigcm.fnJsonValorTexto(CONVERT(varchar(23), t.ActualizadoEn, 126)) END
                + N'}'
            FROM (
                SELECT x.IdRequerimiento, x.Codigo, x.AnoEje, x.CentroCosto, x.Denominacion,
                       x.CodigoTipoContratacion, x.TipoContratacion, x.CodigoDec, x.CondicionCmn,
                       x.Monto, x.PlazoDias, x.FechaInicioPrevisto, x.IdExpediente, x.CodigoEstado,
                       x.Version, x.Estado, x.RolResponsable, x.Items, x.Pedidos, x.ActualizadoEn
                  FROM (
                    SELECT r.IdRequerimiento, r.Codigo, r.AnoEje, r.CentroCosto,
                           r.Denominacion, r.CodigoTipoContratacion,
                           TipoContratacion = tc.Nombre,
                           r.CodigoDec, r.CondicionCmn, r.Monto, r.PlazoDias,
                           r.FechaInicioPrevisto,
                           e.IdExpediente, e.CodigoEstado, e.Version,
                           Estado = w.Nombre,
                           RolResponsable = w.RolResponsable,
                           Items = (SELECT COUNT(*) FROM requerimiento.RequerimientoItem AS it
                                     WHERE it.IdRequerimiento = r.IdRequerimiento AND it.Activo = 1),
                           Pedidos = (SELECT COUNT(*) FROM requerimiento.RequerimientoPedido AS pe
                                       WHERE pe.IdRequerimiento = r.IdRequerimiento AND pe.Activo = 1),
                           ActualizadoEn = ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria),
                           rn = ROW_NUMBER() OVER (ORDER BY ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria) DESC)
                      FROM requerimiento.Requerimiento AS r
                      JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
                      JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
                      JOIN sigcm.TipoContratacion AS tc ON tc.CodigoTipoContratacion = r.CodigoTipoContratacion
                     WHERE e.Anulado = 0 AND e.Activo = 1 AND r.Activo = 1
                       AND (@SoloMiBandeja = 0
                            OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol))
                       AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
                       AND (@AnoEje       IS NULL OR r.AnoEje       = @AnoEje)
                       AND (@CentroCosto  IS NULL OR r.CentroCosto  = @CentroCosto)
                       AND (@CodigoTipoContratacion IS NULL OR r.CodigoTipoContratacion = @CodigoTipoContratacion)
                       AND (@Texto        IS NULL OR r.Codigo LIKE '%' + @Texto + '%'
                                                  OR r.Denominacion LIKE '%' + @Texto + '%')
                  ) AS x
                 WHERE x.rn > @Desplazamiento AND x.rn <= @Desplazamiento + @Limite
            ) AS t
            ORDER BY t.ActualizadoEn DESC
              FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SET @resultado = N'{"estado":1'
            + N',"total":' + CONVERT(nvarchar(20), @Total)
            + N',"limite":' + CONVERT(nvarchar(20), @Limite)
            + N',"desplazamiento":' + CONVERT(nvarchar(20), @Desplazamiento)
            + N',"Requerimientos":' + @Lista
            + N',"mensaje":"OK"}';

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N',"Requerimientos":[]}';
        SELECT @resultado;
    END CATCH
END
GO
