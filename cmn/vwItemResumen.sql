/*
  Base    : DBSIGCM
  Esquema : cmn
  Objeto  : cmn.vwItemResumen
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   VIEW cmn.vwItemResumen
AS
SELECT
    IdSolicitudItem   = i.IdSolicitudItem,
    IdSolicitud       = i.IdSolicitud,
    Orden             = i.Orden,
    TipoMovimiento    = i.TipoMovimiento,
    TipoBien          = i.TipoBien,
    GrupoBien         = i.GrupoBien,
    ClaseBien         = i.ClaseBien,
    FamiliaBien       = i.FamiliaBien,
    ItemBien          = i.ItemBien,
    CodigoItem        = CONVERT(varchar(20),
                            STUFF(
                                ISNULL('.' + NULLIF(RTRIM(i.TipoBien),     ''), '')
                              + ISNULL('.' + NULLIF(RTRIM(i.GrupoBien),    ''), '')
                              + ISNULL('.' + NULLIF(RTRIM(i.ClaseBien),    ''), '')
                              + ISNULL('.' + NULLIF(RTRIM(i.FamiliaBien),  ''), '')
                              + ISNULL('.' + NULLIF(RTRIM(i.ItemBien),     ''), ''),
                                1, 1, '')),
    Descripcion       = COALESCE(i.DescripcionServicio, c.Descripcion),
    UnidadMedida      = i.UnidadMedida,
    UnidadAbreviatura = u.Abreviatura,
    PrecioUnitario    = i.PrecioUnitario,
    SecFunc           = i.SecFunc,
    Clasificador      = i.Clasificador,
    RefSecCuadro      = i.RefSecCuadro,
    RefSecItem        = i.RefSecItem,
    CantidadAno0 = SUM(CASE WHEN p.AnoOffset = 0 THEN p.Cantidad ELSE 0 END),
    CantidadAno1 = SUM(CASE WHEN p.AnoOffset = 1 THEN p.Cantidad ELSE 0 END),
    CantidadAno2 = SUM(CASE WHEN p.AnoOffset = 2 THEN p.Cantidad ELSE 0 END),
    CantidadAno3 = SUM(CASE WHEN p.AnoOffset = 3 THEN p.Cantidad ELSE 0 END),
    MontoAno0    = SUM(CASE WHEN p.AnoOffset = 0 THEN p.Monto ELSE 0 END),
    MontoAno1    = SUM(CASE WHEN p.AnoOffset = 1 THEN p.Monto ELSE 0 END),
    MontoAno2    = SUM(CASE WHEN p.AnoOffset = 2 THEN p.Monto ELSE 0 END),
    MontoAno3    = SUM(CASE WHEN p.AnoOffset = 3 THEN p.Monto ELSE 0 END),
    CantidadTotal = SUM(p.Cantidad),
    MontoTotal    = SUM(p.Monto),
    Periodos      = COUNT_BIG(*)
FROM cmn.SolicitudItem AS i
JOIN cmn.Solicitud AS s
  ON s.IdSolicitud = i.IdSolicitud
LEFT JOIN siga.vwCatalogoItem AS c
       ON  c.SecEjec     = s.SecEjec
       AND c.TipoBien    = i.TipoBien
       AND c.GrupoBien   = i.GrupoBien
       AND c.ClaseBien   = i.ClaseBien
       AND c.FamiliaBien = i.FamiliaBien
       AND c.ItemBien    = i.ItemBien
LEFT JOIN siga.vwUnidadMedida AS u
       ON u.UnidadMedida = i.UnidadMedida
JOIN cmn.SolicitudItemPeriodo AS p
  ON p.IdSolicitudItem = i.IdSolicitudItem
GROUP BY
    i.IdSolicitudItem, i.IdSolicitud, i.Orden, i.TipoMovimiento,
    i.TipoBien, i.GrupoBien, i.ClaseBien, i.FamiliaBien, i.ItemBien,
    i.DescripcionServicio, c.Descripcion, i.UnidadMedida, u.Abreviatura,
    i.PrecioUnitario, i.SecFunc, i.Clasificador, i.RefSecCuadro, i.RefSecItem;
GO
