/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwCuadroEtapaCentro
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 9. Etapa del cuadro por area usuaria   <- dbo.SIG_CUADRO_X_CENTRO         */
/* ========================================================================== */

/*
  VISTA NUEVA, sin equivalente en la version PostgreSQL.

  Hallazgo 5.4 del mapa: esta tabla gobierna en que etapa esta el cuadro de cada
  area usuaria, y ninguno de los procedimientos propuestos hasta ahora la
  consideraba. En 2026 hay 26 centros en estado '4' y 20 en estado '6'.

  Toda escritura externa debe ser coherente con esta tabla, y su coherencia debe
  verificarse antes y despues. Que significa la transicion de '4' a '6', y que la
  dispara, es una de las preguntas abiertas para el responsable de SIGA.
*/
CREATE   VIEW siga.vwCuadroEtapaCentro
AS
SELECT
    AnoEje      = CONVERT(smallint, x.ano_eje),
    SecEjec     = CONVERT(int,      x.sec_ejec),
    CentroCosto = CONVERT(varchar(15), x.centro_costo) COLLATE DATABASE_DEFAULT,
    Estado      = CONVERT(char(1),  x.estado)      COLLATE DATABASE_DEFAULT,
    FlagPadre   = CONVERT(char(1),  x.flag_padre)  COLLATE DATABASE_DEFAULT,
    FlagModif   = CONVERT(char(1),  x.flag_modif)  COLLATE DATABASE_DEFAULT,
    FlagDaProg  = CONVERT(varchar(1), x.flag_da_prog)  COLLATE DATABASE_DEFAULT,
    FlagDaAprob = CONVERT(varchar(1), x.flag_da_aprob) COLLATE DATABASE_DEFAULT,
    FechaReg    = x.fecha_reg
FROM siga.SIG_CUADRO_X_CENTRO AS x;
GO
