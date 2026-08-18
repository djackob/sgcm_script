/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnJsonArray
  Tipo    : SQL_TABLE_VALUED_FUNCTION
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION sigcm.fnJsonArray(@json nvarchar(max), @ruta varchar(400))
RETURNS @filas TABLE (
    Orden int NOT NULL,
    Valor nvarchar(max) NOT NULL
)
AS
BEGIN
    DECLARE @rest nvarchar(max), @arr nvarchar(max), @seg varchar(128), @dot int;
    DECLARE @n int, @i int, @c nchar(1), @orden int, @tok nvarchar(max);

    IF @json IS NULL RETURN;
    SET @rest = LTRIM(RTRIM(@json));

    IF NULLIF(LTRIM(RTRIM(@ruta)), '') IS NULL
        SET @arr = @rest;
    ELSE
    BEGIN
        WHILE LEN(@ruta) > 0
        BEGIN
            SET @dot = CHARINDEX('.', @ruta);
            IF @dot > 0
            BEGIN
                SET @seg = LEFT(@ruta, @dot - 1);
                SET @ruta = SUBSTRING(@ruta, @dot + 1, 400);
                SET @rest = sigcm.fnJsonToken(@rest, @seg);
                IF @rest IS NULL RETURN;
            END
            ELSE
            BEGIN
                SET @arr = sigcm.fnJsonToken(@rest, @ruta);
                SET @ruta = '';
            END
        END
    END

    SET @arr = LTRIM(RTRIM(@arr));
    IF @arr IS NULL OR LEFT(@arr, 1) <> N'[' RETURN;

    SET @n = DATALENGTH(@arr) / 2;
    SET @i = 2;
    SET @orden = 0;

    WHILE @i <= @n
    BEGIN
        WHILE @i <= @n AND SUBSTRING(@arr, @i, 1) IN (N' ', NCHAR(9), NCHAR(10), NCHAR(13), N',')
            SET @i = @i + 1;
        IF @i > @n OR SUBSTRING(@arr, @i, 1) = N']' BREAK;

        SET @tok = sigcm.fnJsonLeerValor(@arr, @i);
        IF @tok IS NULL RETURN;
        SET @orden = @orden + 1;
        INSERT INTO @filas (Orden, Valor) VALUES (@orden, @tok);
        SET @i = @i + DATALENGTH(@tok) / 2;
    END

    RETURN;
END
GO
