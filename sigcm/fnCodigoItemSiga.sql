/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnCodigoItemSiga
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION sigcm.fnCodigoItemSiga(
    @TipoBien varchar(10),
    @GrupoBien varchar(10),
    @ClaseBien varchar(10),
    @FamiliaBien varchar(10),
    @ItemBien varchar(10))
RETURNS varchar(50)
AS
BEGIN
    RETURN STUFF(
          CASE WHEN @TipoBien    IS NULL THEN N'' ELSE N'.' + @TipoBien    END
        + CASE WHEN @GrupoBien   IS NULL THEN N'' ELSE N'.' + @GrupoBien   END
        + CASE WHEN @ClaseBien   IS NULL THEN N'' ELSE N'.' + @ClaseBien   END
        + CASE WHEN @FamiliaBien IS NULL THEN N'' ELSE N'.' + @FamiliaBien END
        + CASE WHEN @ItemBien    IS NULL THEN N'' ELSE N'.' + @ItemBien    END,
        1, 1, N'');
END
GO
