/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwTechoPresupuesto
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 7. Techo presupuestal   <- dbo.SIG_TECHO_PRESUPUESTO                      */
/* ========================================================================== */

/*
  SIN NOLOCK a proposito: el techo se mueve con cada certificacion y compromiso.
  Una lectura sucia aqui puede mostrarle al usuario un saldo que nunca existio.

  CLAVE REAL: (ANO_EJE, SEC_EJEC, ORIGEN, FUENTE_FINANC, SECUENCIA).
  El espejo la declaraba sobre ocho columnas sin SECUENCIA y exigia CentroCosto y
  FaseCuadro NOT NULL. Ambas cosas son falsas contra los datos de 2026. Cualquier
  consumidor debe filtrar por CentroCosto IS NOT NULL cuando quiera el techo de
  un area usuaria concreta.

  MONTOS: LO QUE SE SABE Y LO QUE NO   [PENDIENTE DE CONFIRMACION FUNCIONAL]

    Anio base (offset 0)
      MontoTecho0 = PPTO_APROB    techo aprobado
      MontoUsado0 = MNTO_APROB    monto ya programado contra ese techo
      Verificado: PPTO_APROB >= MNTO_APROB en las filas con techo no nulo.

    Anios 1 a 3 (multianual)
      MontoProg1..3 = MNTO_ANNO_01..03   montos programados. Poblado: 832 de
                                          2 375 filas tienen MNTO_ANNO_01 <> 0.

      PPTO_ANNO_01..03 esta en CERO en las 2 375 filas de 2026. Por lo tanto NO es
      el techo de los anios siguientes, y el techo multianual NO SE HA LOCALIZADO
      en esta tabla. Se exponen igual, crudas, para que quien confirme la
      semantica pueda verlas; pero NINGUNA rutina debe usarlas para autorizar.

  Consecuencia practica: el control de techo sobre los cuatro periodos, que
  usp_ext_registrar_item_cmn daba por resuelto, hoy solo puede hacerse sobre el
  anio base. Es una de las preguntas para el responsable de SIGA.
*/
CREATE   VIEW siga.vwTechoPresupuesto
AS
SELECT
    AnoEje       = CONVERT(smallint, t.ANO_EJE),
    SecEjec      = CONVERT(int,      t.SEC_EJEC),
    Origen       = CONVERT(varchar(1),  t.ORIGEN)        COLLATE DATABASE_DEFAULT,
    FuenteFinanc = CONVERT(varchar(2),  t.FUENTE_FINANC) COLLATE DATABASE_DEFAULT,
    Secuencia    = CONVERT(bigint,      t.SECUENCIA),

    CentroCosto  = CONVERT(varchar(15), t.CENTRO_COSTO)  COLLATE DATABASE_DEFAULT,
    FaseCuadro   = CONVERT(smallint,    t.FASE_CUADRO),
    SecFunc      = CONVERT(int,         t.sec_func),
    SecFuncProp  = CONVERT(int,         t.SEC_FUNC_PROP),
    Clasificador = CONVERT(varchar(20), t.CLASIFICADOR)  COLLATE DATABASE_DEFAULT,
    CategGasto   = CONVERT(varchar(1),  t.CATEG_GASTO)   COLLATE DATABASE_DEFAULT,
    GrupoGasto   = CONVERT(varchar(1),  t.GRUPO_GASTO)   COLLATE DATABASE_DEFAULT,
    TipoTarea    = CONVERT(varchar(1),  t.TIPO_TAREA)    COLLATE DATABASE_DEFAULT,
    NivelTarea   = CONVERT(varchar(1),  t.NIVEL_TAREA)   COLLATE DATABASE_DEFAULT,
    CodigoTarea  = CONVERT(bigint,      t.CODIGO_TAREA),

    /* Derivadas. Solo el anio base es confiable. */
    MontoTecho0  = CONVERT(decimal(18,2), t.PPTO_APROB),
    MontoUsado0  = CONVERT(decimal(18,2), t.MNTO_APROB),
    MontoProg1   = CONVERT(decimal(18,2), t.MNTO_ANNO_01),
    MontoProg2   = CONVERT(decimal(18,2), t.MNTO_ANNO_02),
    MontoProg3   = CONVERT(decimal(18,2), t.MNTO_ANNO_03),

    /* Crudas. PPTO_ANNO_* esta en cero en todo 2026: no usar como techo. */
    PptoAnno01   = CONVERT(decimal(18,2), t.PPTO_ANNO_01),
    PptoAnno02   = CONVERT(decimal(18,2), t.PPTO_ANNO_02),
    PptoAnno03   = CONVERT(decimal(18,2), t.PPTO_ANNO_03),
    PptoPrograma = CONVERT(decimal(18,2), t.PPTO_PROGRA),
    PptoModif    = CONVERT(decimal(18,2), t.PPTO_MODIF),
    MntoPrograma = CONVERT(decimal(18,2), t.MNTO_PROGRA),
    MntoModif    = CONVERT(decimal(18,2), t.MNTO_MODIF)
FROM siga.SIG_TECHO_PRESUPUESTO AS t;
GO
