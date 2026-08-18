/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.fnEsDiaHabil
  Tipo    : SQL_SCALAR_FUNCTION
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 1. sigcm.fnEsDiaHabil / sigcm.fnSumarDiasHabiles                          */
/* ========================================================================== */

/* Sabados y domingos por calculo; los feriados salen de sigcm.DiaNoHabil, que
   solo lleva las excepciones.

   DATEFIRST no se puede fijar dentro de una funcion y su valor de sesion cambia
   segun el idioma del login, asi que el dia de la semana se calcula de forma
   independiente: DATEDIFF en dias desde un lunes conocido (1900-01-01 lo fue). */
CREATE   FUNCTION sigcm.fnEsDiaHabil (@Fecha date)
RETURNS bit
AS
BEGIN
    IF @Fecha IS NULL RETURN NULL;

    /* 0 = lunes ... 5 = sabado, 6 = domingo */
    IF (DATEDIFF(day, '19000101', @Fecha) % 7) >= 5 RETURN 0;

    IF EXISTS (SELECT 1 FROM sigcm.DiaNoHabil
                WHERE Fecha = @Fecha AND Activo = 1) RETURN 0;

    RETURN 1;
END
GO
