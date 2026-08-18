/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnJsonTexto
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION sigcm.fnJsonTexto(@json nvarchar(max), @ruta varchar(400))
RETURNS nvarchar(max)
AS
BEGIN
    DECLARE @rest nvarchar(max), @seg varchar(128), @dot int, @token nvarchar(max), @s nvarchar(max);

    IF @json IS NULL OR NULLIF(LTRIM(RTRIM(@ruta)), '') IS NULL RETURN NULL;
    SET @rest = LTRIM(RTRIM(@json));

    WHILE LEN(@ruta) > 0
    BEGIN
        SET @dot = CHARINDEX('.', @ruta);
        IF @dot > 0
        BEGIN
            SET @seg = LEFT(@ruta, @dot - 1);
            SET @ruta = SUBSTRING(@ruta, @dot + 1, 400);
            SET @token = sigcm.fnJsonToken(@rest, @seg);
            IF @token IS NULL RETURN NULL;
            SET @rest = @token;
        END
        ELSE
        BEGIN
            SET @token = sigcm.fnJsonToken(@rest, @ruta);
            SET @ruta = '';
            IF @token IS NULL RETURN NULL;
            IF @token = N'null' RETURN NULL;
            IF LEFT(@token, 1) = N'"'
            BEGIN
                SET @s = SUBSTRING(@token, 2, DATALENGTH(@token) / 2 - 2);
                SET @s = REPLACE(@s, N'\\', NCHAR(1));
                SET @s = REPLACE(@s, N'\"', N'"');
                SET @s = REPLACE(@s, N'\r', NCHAR(13));
                SET @s = REPLACE(@s, N'\n', NCHAR(10));
                SET @s = REPLACE(@s, N'\t', NCHAR(9));
                SET @s = REPLACE(@s, NCHAR(1), N'\');
                RETURN @s;
            END
            RETURN @token;
        END
    END
    RETURN NULL;
END
GO
