/*
  V042 - Dos lecturas de SIGA para validar el Anexo 3 igual que SIGA.

  siga.vwFamiliaClasificador
    Clasificadores de gasto que SIGA admite para cada familia del catalogo
    (SIG_FAMILIA_CLASIFICADOR). Un dispensador (B.64.61.0005) admite 2.3.1 5.3 1
    o 2.3.1 7.1 1, nunca 2.3.2 9.1 1, que es locacion de servicios.

  siga.fnDisponibleCuadro
    Lo que queda del techo del cuadro en el anio base para una combinacion
    centro + meta + origen + fuente + clasificador: MNTO_APROB de la fase 5
    menos lo ya programado en SIG_CUADRO_MODIFICADO_DET (sin excluidos). Es la
    misma cuenta que hace usp_ext_incluir_item_cmn antes de incluir; si el
    SGCM no la hace, acepta Anexos 3 que SIGA despues rechaza.

  Requiere los sinonimos SIG_FAMILIA_CLASIFICADOR y SIG_CLASIFICADOR_GASTO
  (00_servidor/C003).
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW siga.vwFamiliaClasificador
AS
SELECT
    AnoEje       = CONVERT(smallint,    f.ANO_EJE),
    TipoBien     = CONVERT(char(1),     f.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
    GrupoBien    = CONVERT(varchar(2),  f.GRUPO_BIEN)   COLLATE DATABASE_DEFAULT,
    ClaseBien    = CONVERT(varchar(2),  f.CLASE_BIEN)   COLLATE DATABASE_DEFAULT,
    FamiliaBien  = CONVERT(varchar(4),  f.FAMILIA_BIEN) COLLATE DATABASE_DEFAULT,
    Clasificador = CONVERT(varchar(20), f.CLASIFICADOR) COLLATE DATABASE_DEFAULT,
    TipoUso      = CONVERT(varchar(1),  f.TIPO_USO)     COLLATE DATABASE_DEFAULT,
    TipoActProy  = CONVERT(varchar(1),  f.TIPO_ACT_PROY) COLLATE DATABASE_DEFAULT,
    NombreClasificador = CONVERT(varchar(250), g.NOMBRE_CLASIF) COLLATE DATABASE_DEFAULT,
    Activo       = CONVERT(bit, CASE WHEN f.ESTADO = 'A' THEN 1 ELSE 0 END)
FROM siga.SIG_FAMILIA_CLASIFICADOR AS f WITH (NOLOCK)
LEFT JOIN siga.SIG_CLASIFICADOR_GASTO AS g WITH (NOLOCK)
       ON g.ANO_EJE = f.ANO_EJE AND g.CLASIFICADOR = f.CLASIFICADOR;
GO

CREATE OR ALTER FUNCTION siga.fnDisponibleCuadro
(
    @AnoEje       smallint,
    @SecEjec      int,
    @CentroCosto  varchar(15),
    @SecFunc      int,
    @Origen       varchar(1),
    @FuenteFinanc varchar(2),
    @Clasificador varchar(20)
)
RETURNS TABLE
AS
RETURN
    SELECT FilasTecho = t.Filas,
           Techo      = t.Techo,
           Usado      = ISNULL(u.Usado, 0),
           Disponible = t.Techo - ISNULL(u.Usado, 0)
      FROM (SELECT Filas = COUNT(*),
                   Techo = CONVERT(decimal(18,2), ISNULL(SUM(ISNULL(MNTO_APROB, 0)), 0))
              FROM siga.SIG_TECHO_PRESUPUESTO
             WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec AND CENTRO_COSTO = @CentroCosto
               AND FASE_CUADRO = 5 AND ORIGEN = @Origen AND FUENTE_FINANC = @FuenteFinanc
               AND sec_func = @SecFunc AND CLASIFICADOR = @Clasificador) AS t
     CROSS APPLY (SELECT Usado = CONVERT(decimal(18,2), SUM(MNTO_TOTAL))
                    FROM siga.SIG_CUADRO_MODIFICADO_DET
                   WHERE SEC_EJEC = @SecEjec AND ANNO_EJEC = @AnoEje AND CENTRO_COSTO = @CentroCosto
                     AND ANNO_PROG = @AnoEje AND sec_func = @SecFunc AND CLASIFICADOR = @Clasificador
                     AND ORIGEN = @Origen AND FUENTE_FINANC = @FuenteFinanc
                     AND ESTADO NOT IN ('E', 'ET', 'IC')) AS u;
GO

PRINT 'V042 aplicada: siga.vwFamiliaClasificador, siga.fnDisponibleCuadro.';
GO
