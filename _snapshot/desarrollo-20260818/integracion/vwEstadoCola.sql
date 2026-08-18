/*
  Base    : DBSIGCM
  Esquema : integracion
  Objeto  : integracion.vwEstadoCola
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* -------------------------------------------------------------------------- */
/* 4. Vista operativa de la cola                                              */
/* -------------------------------------------------------------------------- */

CREATE   VIEW integracion.vwEstadoCola
AS
SELECT
    Estado               = o.Estado,
    Operacion            = o.Operacion,
    Operaciones          = COUNT_BIG(*),
    MasAntigua           = MIN(o.FechaCreacionAuditoria),
    MaxIntentosAlcanzado = MAX(o.Intentos),
    Agotadas             = SUM(CASE WHEN o.Intentos >= o.MaxIntentos THEN 1 ELSE 0 END)
FROM integracion.Operacion AS o
GROUP BY o.Estado, o.Operacion;
GO
