/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwMeta
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 2. Meta presupuestal   <- dbo.META                                        */
/* ========================================================================== */

CREATE   VIEW siga.vwMeta
AS
SELECT
    AnoEje       = CONVERT(smallint, m.ano_eje),
    SecEjec      = CONVERT(int,      m.sec_ejec),
    SecFunc      = CONVERT(int,      m.sec_func),
    Nombre       = CONVERT(varchar(300), m.nombre)       COLLATE DATABASE_DEFAULT,
    Funcion      = CONVERT(varchar(2),   m.funcion)      COLLATE DATABASE_DEFAULT,
    Programa     = CONVERT(varchar(3),   m.programa)     COLLATE DATABASE_DEFAULT,
    SubPrograma  = CONVERT(varchar(4),   m.sub_programa) COLLATE DATABASE_DEFAULT,
    ActProy      = CONVERT(varchar(7),   m.act_proy)     COLLATE DATABASE_DEFAULT,
    Componente   = CONVERT(varchar(7),   m.componente)   COLLATE DATABASE_DEFAULT,
    Meta         = CONVERT(varchar(5),   m.meta)         COLLATE DATABASE_DEFAULT,
    Finalidad    = CONVERT(varchar(20),  m.finalidad)    COLLATE DATABASE_DEFAULT,
    TipoTarea    = CONVERT(char(1),      m.TIPO_TAREA)   COLLATE DATABASE_DEFAULT,
    NivelTarea   = CONVERT(char(1),      m.NIVEL_TAREA)  COLLATE DATABASE_DEFAULT,
    TareaGeneral = CONVERT(bigint,       m.TAREA_GENERAL),
    Estado       = CONVERT(varchar(1),   m.estado)       COLLATE DATABASE_DEFAULT,
    Activo       = CONVERT(bit, CASE WHEN m.estado = 'A' THEN 1 ELSE 0 END)
    /* SecFuncProp NO se expone: el espejo lo declaraba, pero META no tiene esa
       columna. Vive en SIG_TECHO_PRESUPUESTO, y por ahi se lee. */
FROM siga.META AS m WITH (NOLOCK);
GO
