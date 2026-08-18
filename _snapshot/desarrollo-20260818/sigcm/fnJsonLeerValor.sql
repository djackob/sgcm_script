/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnJsonLeerValor
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION sigcm.fnJsonLeerValor(@json nvarchar(max), @pos int)
RETURNS nvarchar(max)
AS
BEGIN
    DECLARE @n int, @c nchar(1), @i int, @inStr bit, @esc bit, @depth int;

    IF @json IS NULL OR @pos IS NULL OR @pos < 1 RETURN NULL;
    SET @n = DATALENGTH(@json) / 2;
    IF @pos > @n RETURN NULL;

    SET @c = SUBSTRING(@json, @pos, 1);

    IF @c = N'"'
    BEGIN
        SET @i = @pos + 1;
        SET @esc = 0;
        WHILE @i <= @n
        BEGIN
            SET @c = SUBSTRING(@json, @i, 1);
            IF @esc = 1 SET @esc = 0;
            ELSE IF @c = N'\' SET @esc = 1;
            ELSE IF @c = N'"'
                RETURN SUBSTRING(@json, @pos, @i - @pos + 1);
            SET @i = @i + 1;
        END
        RETURN NULL;
    END

    IF @c = N'{' OR @c = N'['
    BEGIN
        SET @depth = 0;
        SET @i = @pos;
        SET @inStr = 0;
        SET @esc = 0;
        WHILE @i <= @n
        BEGIN
            SET @c = SUBSTRING(@json, @i, 1);
            IF @inStr = 1
            BEGIN
                IF @esc = 1 SET @esc = 0;
                ELSE IF @c = N'\' SET @esc = 1;
                ELSE IF @c = N'"' SET @inStr = 0;
            END
            ELSE
            BEGIN
                IF @c = N'"' SET @inStr = 1;
                ELSE IF @c = N'{' OR @c = N'[' SET @depth = @depth + 1;
                ELSE IF @c = N'}' OR @c = N']'
                BEGIN
                    SET @depth = @depth - 1;
                    IF @depth = 0
                        RETURN SUBSTRING(@json, @pos, @i - @pos + 1);
                END
            END
            SET @i = @i + 1;
        END
        RETURN NULL;
    END

    IF @c = N't' AND SUBSTRING(@json, @pos, 4) = N'true'  RETURN N'true';
    IF @c = N'f' AND SUBSTRING(@json, @pos, 5) = N'false' RETURN N'false';
    IF @c = N'n' AND SUBSTRING(@json, @pos, 4) = N'null'  RETURN N'null';

    SET @i = @pos;
    WHILE @i <= @n AND SUBSTRING(@json, @i, 1) LIKE N'[0-9eE+.-]'
        SET @i = @i + 1;
    IF @i = @pos RETURN NULL;
    RETURN SUBSTRING(@json, @pos, @i - @pos);
END
GO
