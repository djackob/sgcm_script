/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwCuadroVigenteItem
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 8. Cuadro vigente, item por item                                          */
/*    <- dbo.SIG_CUADRO_MODIFICADO_DET                                       */
/* ========================================================================== */

/*
  SIN NOLOCK: es el cuadro sobre el que el area usuaria elige que excluir o
  modificar. Una fila fantasma aqui produce una solicitud invalida.

  LA FORMA IMPORTA. En la ruta de MODIFICACION, SIGA guarda cuatro filas por
  item, una por ANNO_PROG (2026..2029), cada una con CANT_01..12 y CANT_TOTAL. En
  la ruta de FORMULACION guarda una sola fila con 48 columnas. Son rutas tecnicas
  distintas; el MVP usa la de modificacion (ADR-002).

  La vista colapsa las cuatro filas en una por item, con CantAno0..3 indexado por
  desplazamiento respecto del anio base. Es exactamente la forma que consume
  cmn.SolicitudItemPeriodo (AnoOffset x Mes), asi que la proyeccion de ida y
  vuelta no necesita rediseno. Verificado: 102 752 filas de detalle producen
  25 688 items, es decir exactamente cuatro filas por item.

  SecCuaModSal es la secuencia global por (SEC_EJEC, ANNO_EJEC) que enlaza _DET
  con _SALDO y con _CMN. Se asigna en bloques consecutivos de cuatro, uno por
  ANNO_PROG. Se expone la del anio base, que es la que guarda integracion.MapeoCmn.

  Los ejes ESTADO / PROCEDENCIA / MOTIVO_SOLICITUD se exponen crudos y ademas
  traducidos. La traduccion es INFERIDA de la co-variacion observada en los datos
  de 2026 (seccion 3 de SIGCM/docs/mapa-siga-cmn.md) y esta pendiente de
  ratificacion con el responsable de SIGA. Por eso conviven ambas: ninguna rutina
  debe depender solo de la lectura inferida.
*/
CREATE   VIEW siga.vwCuadroVigenteItem
AS
SELECT
    AnoEje      = CONVERT(smallint, d.ANNO_EJEC),
    SecEjec     = CONVERT(int,      d.SEC_EJEC),
    CentroCosto = CONVERT(varchar(15), d.CENTRO_COSTO) COLLATE DATABASE_DEFAULT,
    SecCuadro   = CONVERT(bigint,   d.SEC_CUADRO),
    SecItem     = CONVERT(bigint,   d.SEC_ITEM),

    /* SEC_CUA_MOD_SAL del anio base (ANNO_PROG = ANNO_EJEC). */
    SecCuaModSal = CONVERT(bigint,
        MAX(CASE WHEN d.ANNO_PROG = d.ANNO_EJEC THEN d.SEC_CUA_MOD_SAL END)),

    EstadoSiga      = CONVERT(varchar(2), MAX(d.ESTADO))           COLLATE DATABASE_DEFAULT,
    Procedencia     = CONVERT(varchar(1), MAX(d.PROCEDENCIA))      COLLATE DATABASE_DEFAULT,
    MotivoSolicitud = CONVERT(varchar(1), MAX(d.MOTIVO_SOLICITUD)) COLLATE DATABASE_DEFAULT,
    FlagModificado  = CONVERT(bit, MAX(CASE WHEN d.FLAG_MODIFICADO = '1' THEN 1 ELSE 0 END)),
    FlagSolicitud   = CONVERT(bit, MAX(CASE WHEN d.FLAG_SOLICITUD  = '1' THEN 1 ELSE 0 END)),

    /* Lecturas inferidas. Ver la nota de arriba antes de usarlas. */
    ProcedenciaDesc = CONVERT(varchar(20),
        CASE MAX(d.PROCEDENCIA)
             WHEN 'N' THEN 'NUEVO'
             WHEN 'C' THEN 'DEL_CUADRO'
             WHEN 'T' THEN 'TRANSFERENCIA'
             ELSE NULL END)                            COLLATE DATABASE_DEFAULT,
    MotivoDesc = CONVERT(varchar(20),
        CASE MAX(d.MOTIVO_SOLICITUD)
             WHEN '0' THEN 'SIN_SOLICITUD'
             WHEN '1' THEN 'INCLUSION'
             WHEN '2' THEN 'EXCLUSION'
             WHEN '3' THEN 'MODIFICACION'
             ELSE NULL END)                            COLLATE DATABASE_DEFAULT,

    TipoBien     = CONVERT(char(1),    MAX(d.TIPO_BIEN))    COLLATE DATABASE_DEFAULT,
    GrupoBien    = CONVERT(varchar(2), MAX(d.GRUPO_BIEN))   COLLATE DATABASE_DEFAULT,
    ClaseBien    = CONVERT(varchar(2), MAX(d.CLASE_BIEN))   COLLATE DATABASE_DEFAULT,
    FamiliaBien  = CONVERT(varchar(4), MAX(d.FAMILIA_BIEN)) COLLATE DATABASE_DEFAULT,
    ItemBien     = CONVERT(varchar(4), MAX(d.ITEM_BIEN))    COLLATE DATABASE_DEFAULT,
    UnidadMedida = CONVERT(int, MAX(d.UNIDAD_MEDIDA)),
    PrecioUnit   = CONVERT(decimal(18,6), MAX(d.PRECIO_UNIT)),

    TipoTarea    = CONVERT(char(1),     MAX(d.TIPO_TAREA))    COLLATE DATABASE_DEFAULT,
    NivelTarea   = CONVERT(char(1),     MAX(d.NIVEL_TAREA))   COLLATE DATABASE_DEFAULT,
    CodigoTarea  = CONVERT(bigint,      MAX(d.CODIGO_TAREA)),
    SecFunc      = CONVERT(int,         MAX(d.SEC_FUNC)),
    Origen       = CONVERT(varchar(1),  MAX(d.ORIGEN))        COLLATE DATABASE_DEFAULT,
    FuenteFinanc = CONVERT(varchar(2),  MAX(d.FUENTE_FINANC)) COLLATE DATABASE_DEFAULT,
    Clasificador = CONVERT(varchar(20), MAX(d.CLASIFICADOR))  COLLATE DATABASE_DEFAULT,
    TipoUso      = CONVERT(varchar(1),  MAX(d.TIPO_USO))      COLLATE DATABASE_DEFAULT,

    /* Cantidad y monto totales por anio programado, por desplazamiento 0..3. */
    CantAno0 = CONVERT(decimal(18,2), SUM(CASE WHEN d.ANNO_PROG = d.ANNO_EJEC     THEN d.CANT_TOTAL ELSE 0 END)),
    CantAno1 = CONVERT(decimal(18,2), SUM(CASE WHEN d.ANNO_PROG = d.ANNO_EJEC + 1 THEN d.CANT_TOTAL ELSE 0 END)),
    CantAno2 = CONVERT(decimal(18,2), SUM(CASE WHEN d.ANNO_PROG = d.ANNO_EJEC + 2 THEN d.CANT_TOTAL ELSE 0 END)),
    CantAno3 = CONVERT(decimal(18,2), SUM(CASE WHEN d.ANNO_PROG = d.ANNO_EJEC + 3 THEN d.CANT_TOTAL ELSE 0 END)),
    MntoAno0 = CONVERT(decimal(18,2), SUM(CASE WHEN d.ANNO_PROG = d.ANNO_EJEC     THEN d.MNTO_TOTAL ELSE 0 END)),
    MntoAno1 = CONVERT(decimal(18,2), SUM(CASE WHEN d.ANNO_PROG = d.ANNO_EJEC + 1 THEN d.MNTO_TOTAL ELSE 0 END)),
    MntoAno2 = CONVERT(decimal(18,2), SUM(CASE WHEN d.ANNO_PROG = d.ANNO_EJEC + 2 THEN d.MNTO_TOTAL ELSE 0 END)),
    MntoAno3 = CONVERT(decimal(18,2), SUM(CASE WHEN d.ANNO_PROG = d.ANNO_EJEC + 3 THEN d.MNTO_TOTAL ELSE 0 END)),

    AniosProgramados = CONVERT(int, COUNT(*))
FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
GROUP BY d.ANNO_EJEC, d.SEC_EJEC, d.CENTRO_COSTO, d.SEC_CUADRO, d.SEC_ITEM;
GO
