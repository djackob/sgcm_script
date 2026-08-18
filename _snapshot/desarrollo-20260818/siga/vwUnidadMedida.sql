/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwUnidadMedida
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 5. Unidad de medida   <- dbo.UNIDAD_MEDIDA                                */
/* ========================================================================== */

CREATE   VIEW siga.vwUnidadMedida
AS
SELECT
    UnidadMedida = CONVERT(int, u.UNIDAD_MEDIDA),
    Nombre       = CONVERT(varchar(100), u.NOMBRE)      COLLATE DATABASE_DEFAULT,
    Abreviatura  = CONVERT(varchar(15),  u.ABREVIATURA) COLLATE DATABASE_DEFAULT,
    Estado       = CONVERT(varchar(1),   u.ESTADO)      COLLATE DATABASE_DEFAULT,
    Activo       = CONVERT(bit, CASE WHEN u.ESTADO = 'A' THEN 1 ELSE 0 END)
FROM siga.UNIDAD_MEDIDA AS u WITH (NOLOCK);
GO
