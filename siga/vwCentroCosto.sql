/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwCentroCosto
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 1. Centro de costo   <- dbo.SIG_CENTRO_COSTO                              */
/* ========================================================================== */

CREATE   VIEW siga.vwCentroCosto
AS
SELECT
    AnoEje       = CONVERT(smallint, c.ANO_EJE),
    SecEjec      = CONVERT(int,      c.SEC_EJEC),
    CentroCosto  = CONVERT(varchar(15),  c.CENTRO_COSTO)     COLLATE DATABASE_DEFAULT,
    NombreDepend = CONVERT(varchar(100), c.NOMBRE_DEPEND)    COLLATE DATABASE_DEFAULT,
    /* El espejo la llamaba "abreviado" y apuntaba a una columna inexistente. */
    Abreviado    = CONVERT(varchar(50),  c.ABREVIADO_DEPEND) COLLATE DATABASE_DEFAULT,
    TipoDepend   = CONVERT(char(1),      c.TIPO_DEPEND)      COLLATE DATABASE_DEFAULT,
    CentroPadre  = CONVERT(varchar(15),  c.CENTRO_PADRE)     COLLATE DATABASE_DEFAULT,
    Estado       = CONVERT(char(1),      c.ESTADO)           COLLATE DATABASE_DEFAULT,
    Activo       = CONVERT(bit, CASE WHEN c.ESTADO = 'A' THEN 1 ELSE 0 END)
FROM siga.SIG_CENTRO_COSTO AS c WITH (NOLOCK);
GO
