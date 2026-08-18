/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnJsonValorTexto
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION sigcm.fnJsonValorTexto(@s nvarchar(max))
RETURNS nvarchar(max)
AS
BEGIN
    IF @s IS NULL RETURN N'null';
    RETURN N'"' + sigcm.fnJsonEscape(@s) + N'"';
END
GO
