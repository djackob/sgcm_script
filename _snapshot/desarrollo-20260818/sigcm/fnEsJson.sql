/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnEsJson
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION sigcm.fnEsJson(@s nvarchar(max))
RETURNS bit
AS
BEGIN
    DECLARE @t nvarchar(max);
    IF @s IS NULL RETURN 0;
    SET @t = LTRIM(RTRIM(@s));
    IF LEN(@t) < 2 RETURN 0;
    IF (LEFT(@t, 1) = N'{' AND RIGHT(@t, 1) = N'}')
        OR (LEFT(@t, 1) = N'[' AND RIGHT(@t, 1) = N']')
        RETURN 1;
    RETURN 0;
END
GO
