/*
  Base    : DBSIGCM
  Esquema : cmn
  Objeto  : cmn.paObtenerSolicitud
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 2. cmn.paObtenerSolicitud                                                 */
/* ========================================================================== */

/* Devuelve la solicitud completa: cabecera, items y los 48 periodos anidados por
   item. Es lo que consume el visor del Anexo 3.

   Entrada: { "Actor": {...}, "IdSolicitud": "..." } */
CREATE   PROCEDURE cmn.paObtenerSolicitud
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

        DECLARE @IdSolicitud uniqueidentifier;
        SET @IdSolicitud = sigcm.fnTryGuid(sigcm.fnJsonTexto(@parametro, 'IdSolicitud'));

        IF @IdSolicitud IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta IdSolicitud o no es un identificador valido.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM cmn.Solicitud WHERE IdSolicitud = @IdSolicitud AND Activo = 1)
            RAISERROR('NO_ENCONTRADO: la solicitud no existe.', 16, 1);

        DECLARE @ItemsJson nvarchar(max);
        SET @ItemsJson = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"IdSolicitudItem":'   + sigcm.fnJsonValorTexto(CONVERT(varchar(36), r.IdSolicitudItem))
                + N',"Orden":'             + CONVERT(nvarchar(20), r.Orden)
                + N',"TipoMovimiento":'    + sigcm.fnJsonValorTexto(r.TipoMovimiento)
                + N',"CodigoItem":'        + sigcm.fnJsonValorTexto(r.CodigoItem)
                + N',"Descripcion":'       + sigcm.fnJsonValorTexto(r.Descripcion)
                + N',"UnidadMedida":'      + CASE WHEN r.UnidadMedida IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), r.UnidadMedida) END
                + N',"UnidadAbreviatura":' + sigcm.fnJsonValorTexto(r.UnidadAbreviatura)
                + N',"PrecioUnitario":'    + CASE WHEN r.PrecioUnitario IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.PrecioUnitario) END
                + N',"SecFunc":'           + CASE WHEN r.SecFunc IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), r.SecFunc) END
                + N',"Clasificador":'      + sigcm.fnJsonValorTexto(r.Clasificador)
                + N',"RefSecCuadro":'      + CASE WHEN r.RefSecCuadro IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), r.RefSecCuadro) END
                + N',"RefSecItem":'        + CASE WHEN r.RefSecItem IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), r.RefSecItem) END
                + N',"CantidadAno0":'      + CASE WHEN r.CantidadAno0 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.CantidadAno0) END
                + N',"CantidadAno1":'      + CASE WHEN r.CantidadAno1 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.CantidadAno1) END
                + N',"CantidadAno2":'      + CASE WHEN r.CantidadAno2 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.CantidadAno2) END
                + N',"CantidadAno3":'      + CASE WHEN r.CantidadAno3 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.CantidadAno3) END
                + N',"MontoAno0":'         + CASE WHEN r.MontoAno0 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.MontoAno0) END
                + N',"MontoAno1":'         + CASE WHEN r.MontoAno1 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.MontoAno1) END
                + N',"MontoAno2":'         + CASE WHEN r.MontoAno2 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.MontoAno2) END
                + N',"MontoAno3":'         + CASE WHEN r.MontoAno3 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.MontoAno3) END
                + N',"CantidadTotal":'     + CASE WHEN r.CantidadTotal IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.CantidadTotal) END
                + N',"MontoTotal":'        + CASE WHEN r.MontoTotal IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.MontoTotal) END
                + N',"Periodos":'          + pj.PeriodosJson
                + N'}'
            FROM cmn.vwItemResumen AS r
            CROSS APPLY (
                SELECT PeriodosJson = N'[' + ISNULL(STUFF((
                    SELECT N',' + N'{'
                        + N'"AnoOffset":' + CONVERT(nvarchar(20), p.AnoOffset)
                        + N',"Mes":'       + CONVERT(nvarchar(20), p.Mes)
                        + N',"Cantidad":'  + CONVERT(nvarchar(40), p.Cantidad)
                        + N',"Monto":'     + CONVERT(nvarchar(40), p.Monto)
                        + N'}'
                    FROM cmn.SolicitudItemPeriodo AS p
                    WHERE p.IdSolicitudItem = r.IdSolicitudItem
                    ORDER BY p.AnoOffset, p.Mes
                    FOR XML PATH(N''), TYPE
                ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']'
            ) AS pj
            WHERE r.IdSolicitud = @IdSolicitud
            ORDER BY r.Orden
            FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SELECT @resultado = N'{"estado":1'
            + N',"IdSolicitud":'       + sigcm.fnJsonValorTexto(CONVERT(varchar(36), s.IdSolicitud))
            + N',"Codigo":'             + sigcm.fnJsonValorTexto(s.Codigo)
            + N',"AnoEje":'             + CONVERT(nvarchar(10), s.AnoEje)
            + N',"SecEjec":'            + CONVERT(nvarchar(20), s.SecEjec)
            + N',"CentroCosto":'        + sigcm.fnJsonValorTexto(s.CentroCosto)
            + N',"TipoOperacion":'      + sigcm.fnJsonValorTexto(s.TipoOperacion)
            + N',"TipoInclusion":'      + sigcm.fnJsonValorTexto(s.TipoInclusion)
            + N',"Sustento":'           + sigcm.fnJsonValorTexto(s.Sustento)
            + N',"FechaSolicitud":'     + sigcm.fnJsonValorTexto(CONVERT(varchar(10), s.FechaSolicitud, 23))
            + N',"IdExpediente":'       + sigcm.fnJsonValorTexto(CONVERT(varchar(36), e.IdExpediente))
            + N',"CodigoEstado":'       + sigcm.fnJsonValorTexto(e.CodigoEstado)
            + N',"Version":'            + CONVERT(nvarchar(20), e.Version)
            + N',"Anulado":'            + CASE WHEN e.Anulado = 1 THEN N'true' ELSE N'false' END
            + N',"Estado":'             + sigcm.fnJsonValorTexto(w.Nombre)
            + N',"Responsable":'        + sigcm.fnJsonValorTexto(LTRIM(RTRIM(ISNULL(u.Nombres, '') + N' ' + ISNULL(u.Apellidos, ''))))
            + N',"CentroCostoNombre":'  + sigcm.fnJsonValorTexto(cc.NombreDepend)
            + N',"Items":'              + ISNULL(@ItemsJson, N'[]')
            + N',"mensaje":"OK"}'
          FROM cmn.Solicitud AS s
          JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
          JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
          JOIN sigcm.Usuario    AS u ON u.IdUsuario    = s.IdResponsable
          LEFT JOIN siga.vwCentroCosto AS cc
                 ON cc.AnoEje = s.AnoEje AND cc.SecEjec = s.SecEjec
                AND cc.CentroCosto = s.CentroCosto
         WHERE s.IdSolicitud = @IdSolicitud;

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N'}';
        SELECT @resultado;
    END CATCH
END
GO
