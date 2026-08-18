/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwTarea
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 4. Tarea   <- dbo.SIG_CENTRO_COSTO_TAREA                                  */
/* ========================================================================== */

/* En SIGA la tarea vive por centro de costo, no como catalogo global. La vista
   respeta ese grano, igual que lo hacia el espejo. */
CREATE   VIEW siga.vwTarea
AS
SELECT
    AnoEje      = CONVERT(smallint, t.ano_eje),
    SecEjec     = CONVERT(int,      t.sec_ejec),
    CentroCosto = CONVERT(varchar(15),  t.centro_costo) COLLATE DATABASE_DEFAULT,
    TipoTarea   = CONVERT(char(1),      t.tipo_tarea)   COLLATE DATABASE_DEFAULT,
    NivelTarea  = CONVERT(char(1),      t.nivel_tarea)  COLLATE DATABASE_DEFAULT,
    CodigoTarea = CONVERT(bigint,       t.codigo_tarea),
    NombreTarea = CONVERT(varchar(150), t.nombre_tarea) COLLATE DATABASE_DEFAULT,
    GrupoTarea  = CONVERT(varchar(2),   t.grupo_tarea)  COLLATE DATABASE_DEFAULT,
    TipoPpto    = CONVERT(int,          t.tipo_ppto),
    TipoUso     = CONVERT(varchar(1),   t.tipo_uso)     COLLATE DATABASE_DEFAULT,
    Estado      = CONVERT(varchar(1),   t.estado)       COLLATE DATABASE_DEFAULT,
    Activo      = CONVERT(bit, CASE WHEN t.estado = 'A' THEN 1 ELSE 0 END)
FROM siga.SIG_CENTRO_COSTO_TAREA AS t WITH (NOLOCK);
GO
