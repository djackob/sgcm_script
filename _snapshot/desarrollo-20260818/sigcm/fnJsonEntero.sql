/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnJsonEntero
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION sigcm.fnJsonEntero(@json nvarchar(max), @ruta varchar(400))
RETURNS int
AS
BEGIN
    DECLARE @t nvarchar(40);
    SET @t = sigcm.fnJsonTexto(@json, @ruta);
    IF @t IS NULL OR @t = N'' RETURN NULL;
    IF @t LIKE N'%[^0-9-]%' RETURN NULL;
    RETURN CONVERT(int, @t);
END
GO
