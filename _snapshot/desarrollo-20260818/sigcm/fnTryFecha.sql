/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnTryFecha
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION sigcm.fnTryFecha(@s varchar(50))
RETURNS date
AS
BEGIN
    DECLARE @t varchar(50);
    IF @s IS NULL RETURN NULL;
    SET @t = LTRIM(RTRIM(@s));
    IF @t = '' OR ISDATE(@t) = 0 RETURN NULL;
    RETURN CONVERT(date, @t);
END
GO
