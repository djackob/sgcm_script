/*
  Base    : DBSIGCM
  Esquema : requerimiento
  Objeto  : requerimiento.vwRequerimientoResumen
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* -------------------------------------------------------------------------- */
/* 5. Vista de resumen                                                        */
/* -------------------------------------------------------------------------- */

/* El monto y el conteo de items en un solo lugar, para que la bandeja y el
   visor no repitan la suma. */
CREATE   VIEW requerimiento.vwRequerimientoResumen
AS
SELECT r.IdRequerimiento,
       r.IdExpediente,
       r.Codigo,
       r.AnoEje,
       r.CentroCosto,
       r.Denominacion,
       r.CodigoTipoContratacion,
       r.CodigoDec,
       r.CondicionCmn,
       r.Monto,
       r.PlazoDias,
       r.FechaInicioPrevisto,
       Items       = (SELECT COUNT(*) FROM requerimiento.RequerimientoItem AS i
                       WHERE i.IdRequerimiento = r.IdRequerimiento AND i.Activo = 1),
       MontoItems  = ISNULL((SELECT SUM(i.Monto) FROM requerimiento.RequerimientoItem AS i
                              WHERE i.IdRequerimiento = r.IdRequerimiento AND i.Activo = 1), 0),
       Pedidos     = (SELECT COUNT(*) FROM requerimiento.RequerimientoPedido AS p
                       WHERE p.IdRequerimiento = r.IdRequerimiento AND p.Activo = 1)
  FROM requerimiento.Requerimiento AS r
 WHERE r.Activo = 1;
GO
