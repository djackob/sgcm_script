/*
  Base    : DBSIGCM
  Esquema : cmn
  Objeto  : cmn.vwAgrupacionSiga
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* -------------------------------------------------------------------------- */
/* 5. Vista de proyeccion hacia cabeceras SIGA                                */
/* -------------------------------------------------------------------------- */

/* Cada fila corresponde a una cabecera de SIGA. Es el punto exacto donde el
   modelo institucional del SIGCM se traduce al modelo del producto SIGA, y el
   unico lugar del sistema donde esa correspondencia esta escrita.

   array_agg(i.id ORDER BY i.orden) de PostgreSQL se traduce con STRING_AGG ...
   WITHIN GROUP (ORDER BY ...), que es el equivalente exacto. */
CREATE   VIEW cmn.vwAgrupacionSiga
AS
SELECT
    IdSolicitud  = s.IdSolicitud,
    AnoEje       = s.AnoEje,
    SecEjec      = s.SecEjec,
    CentroCosto  = s.CentroCosto,
    TipoTarea    = i.TipoTarea,
    NivelTarea   = i.NivelTarea,
    CodigoTarea  = i.CodigoTarea,
    SecFunc      = i.SecFunc,
    SecFuncProp  = i.SecFuncProp,
    Origen       = i.Origen,
    FuenteFinanc = i.FuenteFinanc,
    Clasificador = i.Clasificador,
    TipoRecurso  = i.TipoRecurso,
    TipoPpto     = i.TipoPpto,
    TipoUso      = i.TipoUso,
    TipoBien     = i.TipoBien,
    Items        = COUNT_BIG(*),
    ItemIds      = STUFF((
                       SELECT ',' + CONVERT(varchar(36), i2.IdSolicitudItem)
                         FROM cmn.SolicitudItem AS i2
                        WHERE i2.IdSolicitud = s.IdSolicitud
                          AND ISNULL(i2.TipoTarea,    '') = ISNULL(i.TipoTarea,    '')
                          AND ISNULL(i2.NivelTarea,   '') = ISNULL(i.NivelTarea,   '')
                          AND ISNULL(i2.CodigoTarea,   0) = ISNULL(i.CodigoTarea,   0)
                          AND ISNULL(i2.SecFunc,       0) = ISNULL(i.SecFunc,       0)
                          AND ISNULL(i2.SecFuncProp,   0) = ISNULL(i.SecFuncProp,   0)
                          AND ISNULL(i2.Origen,       '') = ISNULL(i.Origen,       '')
                          AND ISNULL(i2.FuenteFinanc, '') = ISNULL(i.FuenteFinanc, '')
                          AND ISNULL(i2.Clasificador, '') = ISNULL(i.Clasificador, '')
                          AND ISNULL(i2.TipoRecurso,  '') = ISNULL(i.TipoRecurso,  '')
                          AND ISNULL(i2.TipoPpto,      0) = ISNULL(i.TipoPpto,      0)
                          AND ISNULL(i2.TipoUso,      '') = ISNULL(i.TipoUso,      '')
                          AND ISNULL(i2.TipoBien,     '') = ISNULL(i.TipoBien,     '')
                        ORDER BY i2.Orden
                          FOR XML PATH(''), TYPE
                   ).value('.', 'varchar(max)'), 1, 1, '')
FROM cmn.Solicitud AS s
JOIN cmn.SolicitudItem AS i
  ON i.IdSolicitud = s.IdSolicitud
GROUP BY
    s.IdSolicitud, s.AnoEje, s.SecEjec, s.CentroCosto,
    i.TipoTarea, i.NivelTarea, i.CodigoTarea,
    i.SecFunc, i.SecFuncProp, i.Origen, i.FuenteFinanc,
    i.Clasificador, i.TipoRecurso, i.TipoPpto, i.TipoUso, i.TipoBien;
GO
