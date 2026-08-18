/*
===============================================================================
  SIGCM - Migracion V004 : Maestros de SIGA como VISTAS
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: 00_servidor/C003__sinonimos_siga.sql

  AUTORIDAD: SIGA. Aqui no se escribe nada, por construccion: son vistas.

  ---------------------------------------------------------------------------
  POR QUE VISTAS Y NO ESPEJO
  ---------------------------------------------------------------------------
  La version PostgreSQL definia ocho tablas espejo mas una bitacora de
  sincronizacion, porque los dos motores vivian en servidores distintos. Aqui
  DBSIGCM comparte instancia con la base SIGA, y los maestros son diminutos:

      SIG_CENTRO_COSTO         198 filas      META                  2 030
      SIG_CENTRO_COSTO_TAREA 1 870 filas      CATALOGO_BIEN_SERV    5 239
      UNIDAD_MEDIDA            765 filas      SIG_TECHO_PRESUPUESTO 6 632
      FUENTE_FINANC_EJEC       100 filas      FUENTE_FINANC           254

  Unas 17 000 filas. Replicarlas dentro del mismo servidor no compra nada y
  cuesta un sincronizador que hay que escribir, operar y vigilar. Con vistas el
  dato esta siempre fresco y desaparecen ocho tablas, la bitacora
  siga.sincronizacion y la funcion integracion.pa_sincronizar_maestros.

  Lo que NO cambia es la doctrina: estas vistas sirven para poblar formularios y
  validar temprano. NO son la fuente de verdad. La validacion definitiva la hace
  SIGA al escribir. Un maestro desactualizado debe producir un rechazo de SIGA,
  no un dato erroneo aceptado.

  ---------------------------------------------------------------------------
  TRES REGLAS QUE TODAS LAS VISTAS RESPETAN
  ---------------------------------------------------------------------------
  1. Leen SINONIMOS (esquema siga), nunca el nombre de la base. Cambiar de
     entorno es reejecutar C003.

  2. Toda columna de texto sale con COLLATE DATABASE_DEFAULT. En el entorno local
     ambas bases usan Modern_Spanish_CI_AS y no haria falta, pero de la
     intercalacion de produccion no se sabe nada. Sin esto, en cuanto difieran,
     cualquier predicado falla en ejecucion con el error 468.

  3. Los maestros cuasi estaticos llevan WITH (NOLOCK); los datos que si se
     mueven, no. La base SIGA tiene RCSI desactivado, de modo que una lectura
     ordinaria toma bloqueos compartidos y puede frenar a los escritores de SIGA.
     En la copia local no se nota porque no hay nadie mas conectado; en
     produccion si. El riesgo de NOLOCK es aceptable por la doctrina del punto
     anterior: alimenta formularios, no autoriza nada.

     Sin NOLOCK a proposito: vwTechoPresupuesto, vwCuadroVigenteItem y
     vwCuadroEtapaCentro. Ahi una lectura sucia si podria confundir al usuario
     sobre saldos y etapas.

  ---------------------------------------------------------------------------
  DEFECTOS DEL ESPEJO QUE ESTE ARCHIVO CORRIGE
  ---------------------------------------------------------------------------
  Verificados contra SIGA_1750:

  a) siga.techo_presupuesto declaraba una PK de ocho columnas SIN SECUENCIA. En
     2026 hay 2 375 filas para solo 1 909 combinaciones de esa clave: la
     sincronizacion habria perdido 466 filas o fallado por conflicto.
  b) Esa misma PK exigia centro_costo y fase_cuadro NOT NULL. En 2026, 1 658 de
     2 375 filas tienen CENTRO_COSTO nulo y 610 FASE_CUADRO nulo: son filas de
     agregacion. La carga habria reventado en la primera pasada.
  c) siga.fuente_financ.descripcion no existe en FUENTE_FINANC_EJEC. El nombre
     vive en FUENTE_FINANC, que el espejo ni mencionaba.
  d) siga.meta.sec_func_prop no existe en META.
  e) siga.centro_costo.abreviado no existe; la columna es ABREVIADO_DEPEND.
  f) monto_techo_1..3 se mapeaban a columnas inexistentes. Ver la nota extensa en
     vwTechoPresupuesto.

  Dos vistas son nuevas, sin equivalente en PostgreSQL: vwCuadroEtapaCentro y
  vwParametroEjecutoraAnio. Cubren los hallazgos 5.3 y 5.4 de
  SIGCM/docs/mapa-siga-cmn.md.

  Nomenclatura: las vistas exponen columnas en PascalCase, como el resto del
  SIGCM. Los nombres de origen en SIGA quedan a la vista en cada CONVERT.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. Centro de costo   <- dbo.SIG_CENTRO_COSTO                              */
/* ========================================================================== */

CREATE OR ALTER VIEW siga.vwCentroCosto
AS
SELECT
    AnoEje       = CONVERT(smallint, c.ANO_EJE),
    SecEjec      = CONVERT(int,      c.SEC_EJEC),
    CentroCosto  = CONVERT(varchar(15),  c.CENTRO_COSTO)     COLLATE DATABASE_DEFAULT,
    NombreDepend = CONVERT(varchar(100), c.NOMBRE_DEPEND)    COLLATE DATABASE_DEFAULT,
    /* El espejo la llamaba "abreviado" y apuntaba a una columna inexistente. */
    Abreviado    = CONVERT(varchar(50),  c.ABREVIADO_DEPEND) COLLATE DATABASE_DEFAULT,
    TipoDepend   = CONVERT(char(1),      c.TIPO_DEPEND)      COLLATE DATABASE_DEFAULT,
    CentroPadre  = CONVERT(varchar(15),  c.CENTRO_PADRE)     COLLATE DATABASE_DEFAULT,
    Estado       = CONVERT(char(1),      c.ESTADO)           COLLATE DATABASE_DEFAULT,
    Activo       = CONVERT(bit, CASE WHEN c.ESTADO = 'A' THEN 1 ELSE 0 END)
FROM siga.SIG_CENTRO_COSTO AS c WITH (NOLOCK);
GO

/* ========================================================================== */
/* 2. Meta presupuestal   <- dbo.META                                        */
/* ========================================================================== */

CREATE OR ALTER VIEW siga.vwMeta
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

/* ========================================================================== */
/* 3. Fuente de financiamiento                                               */
/*    <- dbo.FUENTE_FINANC_EJEC (monto y estado) x dbo.FUENTE_FINANC (nombre) */
/* ========================================================================== */

/* El espejo declaraba descripcion varchar(250) sobre FUENTE_FINANC_EJEC, que no
   tiene ninguna columna de nombre. La descripcion esta en FUENTE_FINANC, que la
   lleva por (ANO_EJE, ORIGEN, FUENTE_FINANC), sin SEC_EJEC. */
CREATE OR ALTER VIEW siga.vwFuenteFinanc
AS
SELECT
    AnoEje        = CONVERT(smallint, fe.ANO_EJE),
    SecEjec       = CONVERT(int,      fe.SEC_EJEC),
    Origen        = CONVERT(varchar(1), fe.ORIGEN)        COLLATE DATABASE_DEFAULT,
    FuenteFinanc  = CONVERT(varchar(2), fe.FUENTE_FINANC) COLLATE DATABASE_DEFAULT,
    Descripcion   = CONVERT(varchar(250), f.nombre)       COLLATE DATABASE_DEFAULT,
    MontoAsignado = CONVERT(decimal(18,2), fe.monto_asignado),
    Estado        = CONVERT(varchar(1), fe.estado)        COLLATE DATABASE_DEFAULT,
    Activo        = CONVERT(bit, CASE WHEN fe.estado = 'A' THEN 1 ELSE 0 END)
FROM siga.FUENTE_FINANC_EJEC AS fe WITH (NOLOCK)
LEFT JOIN siga.FUENTE_FINANC AS f WITH (NOLOCK)
       ON  f.ANO_EJE       = fe.ANO_EJE
       AND f.ORIGEN        = fe.ORIGEN
       AND f.FUENTE_FINANC = fe.FUENTE_FINANC;
GO

/* ========================================================================== */
/* 4. Tarea   <- dbo.SIG_CENTRO_COSTO_TAREA                                  */
/* ========================================================================== */

/* En SIGA la tarea vive por centro de costo, no como catalogo global. La vista
   respeta ese grano, igual que lo hacia el espejo. */
CREATE OR ALTER VIEW siga.vwTarea
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

/* ========================================================================== */
/* 5. Unidad de medida   <- dbo.UNIDAD_MEDIDA                                */
/* ========================================================================== */

CREATE OR ALTER VIEW siga.vwUnidadMedida
AS
SELECT
    UnidadMedida = CONVERT(int, u.UNIDAD_MEDIDA),
    Nombre       = CONVERT(varchar(100), u.NOMBRE)      COLLATE DATABASE_DEFAULT,
    Abreviatura  = CONVERT(varchar(15),  u.ABREVIATURA) COLLATE DATABASE_DEFAULT,
    Estado       = CONVERT(varchar(1),   u.ESTADO)      COLLATE DATABASE_DEFAULT,
    Activo       = CONVERT(bit, CASE WHEN u.ESTADO = 'A' THEN 1 ELSE 0 END)
FROM siga.UNIDAD_MEDIDA AS u WITH (NOLOCK);
GO

/* ========================================================================== */
/* 6. Catalogo de bienes y servicios   <- dbo.CATALOGO_BIEN_SERV             */
/* ========================================================================== */

/* En PostgreSQL este maestro llevaba un indice GIN sobre
   to_tsvector('spanish', descripcion), porque el area usuaria busca por texto y
   nunca por codigo. Aqui no hay equivalente: Full-Text Search NO esta instalado
   en la instancia (verificado por C000). No es un problema: el catalogo de la
   ejecutora son 5 239 filas y un LIKE '%texto%' las recorre en 28 ms medidos.

   Si algun dia se apunta al catalogo nacional (CATALOGO_BIEN_SERV_ORIGINAL,
   822 184 filas) habria que reconsiderarlo. */
CREATE OR ALTER VIEW siga.vwCatalogoItem
AS
SELECT
    SecEjec      = CONVERT(int, c.SEC_EJEC),
    TipoBien     = CONVERT(char(1),     c.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
    GrupoBien    = CONVERT(varchar(2),  c.GRUPO_BIEN)   COLLATE DATABASE_DEFAULT,
    ClaseBien    = CONVERT(varchar(2),  c.CLASE_BIEN)   COLLATE DATABASE_DEFAULT,
    FamiliaBien  = CONVERT(varchar(4),  c.FAMILIA_BIEN) COLLATE DATABASE_DEFAULT,
    ItemBien     = CONVERT(varchar(4),  c.ITEM_BIEN)    COLLATE DATABASE_DEFAULT,
    /* Codigo compuesto tal como lo muestra la interfaz de SIGA y como lo espera
       el frontend. */
    CodigoItem   = CONVERT(varchar(20),
                       CONCAT_WS('.', c.TIPO_BIEN, c.GRUPO_BIEN, c.CLASE_BIEN,
                                      c.FAMILIA_BIEN, c.ITEM_BIEN)) COLLATE DATABASE_DEFAULT,
    /* La columna se llama NOMBRE_ITEM, no DESCRIPCION. */
    Descripcion  = CONVERT(varchar(350), c.NOMBRE_ITEM) COLLATE DATABASE_DEFAULT,
    UnidadMedida = CONVERT(int, c.UNIDAD_MEDIDA),
    PrecioRef    = CONVERT(decimal(18,6), c.PRECIO_REF),
    Estado       = CONVERT(varchar(1), c.ESTADO)       COLLATE DATABASE_DEFAULT,
    FlagActivo   = CONVERT(varchar(1), c.FLAG_ACTIVO)  COLLATE DATABASE_DEFAULT,
    Activo       = CONVERT(bit, CASE WHEN c.ESTADO = 'A' THEN 1 ELSE 0 END)
FROM siga.CATALOGO_BIEN_SERV AS c WITH (NOLOCK);
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
CREATE OR ALTER VIEW siga.vwTechoPresupuesto
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
CREATE OR ALTER VIEW siga.vwCuadroVigenteItem
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
CREATE OR ALTER VIEW siga.vwCuadroEtapaCentro
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
CREATE OR ALTER VIEW siga.vwParametroEjecutoraAnio
AS
SELECT
    AnoEje      = CONVERT(smallint, p.ANO_EJE),
    SecEjec     = CONVERT(int,      p.SEC_EJEC),
    CodMaestro  = CONVERT(varchar(60),  p.cod_maestro) COLLATE DATABASE_DEFAULT,
    Valor       = CONVERT(varchar(100), p.valor)       COLLATE DATABASE_DEFAULT,
    Estado      = CONVERT(varchar(1),   p.estado)      COLLATE DATABASE_DEFAULT
FROM siga.SIG_PARAMETRO_EJECUTORA_ANIO AS p WITH (NOLOCK);
GO

PRINT 'V004 aplicada: 10 vistas sobre SIGA, cero tablas espejo.';
GO
