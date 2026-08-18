/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwParametroEjecutoraAnio
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 10. Parametros de la ejecutora por anio                                   */
/*     <- dbo.SIG_PARAMETRO_EJECUTORA_ANIO                                   */
/* ========================================================================== */

/*
  VISTA NUEVA, sin equivalente en la version PostgreSQL.

  Hallazgo 5.3 del mapa: LA FASE NO DEBE FIJARSE POR CONSTANTE. SIGA la deriva de
  esta tabla mediante SP_INT_FASE_SIGA. El procedimiento
  usp_ext_registrar_item_cmn la cableaba en 5, que es uno de sus tres defectos.

  Valores vigentes de la ejecutora 1750 para 2023-2026:
      FLAG_FASE_CN = 1        FLAG_TECHO_ETAPAS = 2

  Con FLAG_TECHO_ETAPAS = 2, SP_INT_FASE_SIGA no ejecuta el calculo por etapas y
  toma la rama alternativa. Pese a ello los datos vigentes estan en
  FASE_CUADRO = 5. Esa discrepancia sigue sin aclararse y debe resolverse antes
  de homologar cualquier escritura.
*/
CREATE   VIEW siga.vwParametroEjecutoraAnio
AS
SELECT
    AnoEje      = CONVERT(smallint, p.ANO_EJE),
    SecEjec     = CONVERT(int,      p.SEC_EJEC),
    CodMaestro  = CONVERT(varchar(60),  p.cod_maestro) COLLATE DATABASE_DEFAULT,
    Valor       = CONVERT(varchar(100), p.valor)       COLLATE DATABASE_DEFAULT,
    Estado      = CONVERT(varchar(1),   p.estado)      COLLATE DATABASE_DEFAULT
FROM siga.SIG_PARAMETRO_EJECUTORA_ANIO AS p WITH (NOLOCK);
GO
