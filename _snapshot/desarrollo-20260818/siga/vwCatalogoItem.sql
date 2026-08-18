/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwCatalogoItem
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
CREATE   VIEW siga.vwCatalogoItem
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
                       STUFF(
                           ISNULL('.' + NULLIF(RTRIM(CONVERT(varchar(10), c.TIPO_BIEN)),     ''), '')
                         + ISNULL('.' + NULLIF(RTRIM(CONVERT(varchar(10), c.GRUPO_BIEN)),    ''), '')
                         + ISNULL('.' + NULLIF(RTRIM(CONVERT(varchar(10), c.CLASE_BIEN)),    ''), '')
                         + ISNULL('.' + NULLIF(RTRIM(CONVERT(varchar(10), c.FAMILIA_BIEN)),  ''), '')
                         + ISNULL('.' + NULLIF(RTRIM(CONVERT(varchar(10), c.ITEM_BIEN)),     ''), ''),
                           1, 1, '')) COLLATE DATABASE_DEFAULT,
    /* La columna se llama NOMBRE_ITEM, no DESCRIPCION. */
    Descripcion  = CONVERT(varchar(350), c.NOMBRE_ITEM) COLLATE DATABASE_DEFAULT,
    UnidadMedida = CONVERT(int, c.UNIDAD_MEDIDA),
    PrecioRef    = CONVERT(decimal(18,6), c.PRECIO_REF),
    Estado       = CONVERT(varchar(1), c.ESTADO)       COLLATE DATABASE_DEFAULT,
    FlagActivo   = CONVERT(varchar(1), c.FLAG_ACTIVO)  COLLATE DATABASE_DEFAULT,
    Activo       = CONVERT(bit, CASE WHEN c.ESTADO = 'A' THEN 1 ELSE 0 END)
FROM siga.CATALOGO_BIEN_SERV AS c WITH (NOLOCK);
GO
