/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnSumarDiasHabiles
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* Devuelve la fecha resultante de sumar @Dias habiles a @Desde. El dia de
   partida no cuenta: sumar 1 dia habil a un viernes da el lunes siguiente. */
CREATE   FUNCTION sigcm.fnSumarDiasHabiles (@Desde date, @Dias int)
RETURNS date
AS
BEGIN
    IF @Desde IS NULL OR @Dias IS NULL RETURN NULL;

    DECLARE @Fecha date;
    DECLARE @Restantes int;

    SET @Fecha = @Desde;
    SET @Restantes = @Dias;

    WHILE @Restantes > 0
    BEGIN
        SET @Fecha = DATEADD(day, 1, @Fecha);
        IF sigcm.fnEsDiaHabil(@Fecha) = 1
            SET @Restantes = @Restantes - 1;
    END

    RETURN @Fecha;
END
GO
