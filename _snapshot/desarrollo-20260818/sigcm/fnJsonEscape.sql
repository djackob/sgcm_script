/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnJsonEscape
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 0. Lectura y escritura JSON compatible con nivel 100                      */
/* ========================================================================== */

CREATE   FUNCTION sigcm.fnJsonEscape(@s nvarchar(max))
RETURNS nvarchar(max)
AS
BEGIN
    IF @s IS NULL RETURN NULL;
    SET @s = REPLACE(@s, N'\', N'\\');
    SET @s = REPLACE(@s, N'"', N'\"');
    SET @s = REPLACE(@s, NCHAR(13), N'\r');
    SET @s = REPLACE(@s, NCHAR(10), N'\n');
    SET @s = REPLACE(@s, NCHAR(9), N'\t');
    RETURN @s;
END
GO
