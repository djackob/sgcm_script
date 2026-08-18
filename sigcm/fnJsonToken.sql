/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnJsonToken
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION sigcm.fnJsonToken(@json nvarchar(max), @clave varchar(128))
RETURNS nvarchar(max)
AS
BEGIN
    DECLARE @n int, @i int, @c nchar(1);
    DECLARE @inStr bit, @esc bit, @depth int;
    DECLARE @keyStart int, @key nvarchar(128);
    DECLARE @tok nvarchar(max);

    IF @json IS NULL OR @clave IS NULL RETURN NULL;
    SET @n = DATALENGTH(@json) / 2;
    SET @i = 1;
    SET @inStr = 0;
    SET @esc = 0;
    SET @depth = 0;

    WHILE @i <= @n
    BEGIN
        SET @c = SUBSTRING(@json, @i, 1);

        IF @inStr = 1
        BEGIN
            IF @esc = 1 SET @esc = 0;
            ELSE IF @c = N'\' SET @esc = 1;
            ELSE IF @c = N'"' SET @inStr = 0;
            SET @i = @i + 1;
            CONTINUE;
        END

        IF @c = N'"'
        BEGIN
            SET @keyStart = @i + 1;
            SET @i = @i + 1;
            SET @esc = 0;
            WHILE @i <= @n
            BEGIN
                SET @c = SUBSTRING(@json, @i, 1);
                IF @esc = 1 SET @esc = 0;
                ELSE IF @c = N'\' SET @esc = 1;
                ELSE IF @c = N'"' BREAK;
                SET @i = @i + 1;
            END
            SET @key = SUBSTRING(@json, @keyStart, @i - @keyStart);
            SET @i = @i + 1;

            WHILE @i <= @n AND SUBSTRING(@json, @i, 1) IN (N' ', NCHAR(9), NCHAR(10), NCHAR(13))
                SET @i = @i + 1;

            IF @i <= @n AND SUBSTRING(@json, @i, 1) = N':'
            BEGIN
                SET @i = @i + 1;
                WHILE @i <= @n AND SUBSTRING(@json, @i, 1) IN (N' ', NCHAR(9), NCHAR(10), NCHAR(13))
                    SET @i = @i + 1;

                IF @depth = 1 AND @key = @clave
                    RETURN sigcm.fnJsonLeerValor(@json, @i);

                SET @tok = sigcm.fnJsonLeerValor(@json, @i);
                IF @tok IS NULL RETURN NULL;
                SET @i = @i + DATALENGTH(@tok) / 2;
                CONTINUE;
            END

            CONTINUE;
        END

        IF @c = N'{' OR @c = N'[' SET @depth = @depth + 1;
        ELSE IF @c = N'}' OR @c = N']' SET @depth = @depth - 1;

        SET @i = @i + 1;
    END

    RETURN NULL;
END
GO
