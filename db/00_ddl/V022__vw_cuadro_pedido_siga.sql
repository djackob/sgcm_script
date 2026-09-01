/*
===============================================================================
  SIGCM - V022 : Vista cuadro de adquisicion elegible por pedido SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  En SIGA el pedido de requerimiento (TIPO_PEDIDO=2) se vincula al cuadro de
  adquisicion de servicios por NRO_REQUER en SIG_CUADRO_ADQUISICION o por
  NRO_CUADRO en SIG_DETALLE_PEDIDOS. La tabla SIG_DETALLE_PEDIDO_CUADRO es
  enlace legado (pocas filas).

  Nota: SEC_CUADRO en SIG_DETALLE_PEDIDOS apunta al CMN (SIG_CUADRO_MODIFICADO),
  no al cuadro de adquisicion; no debe usarse en este join.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW siga.vwCuadroAdquisicionPedido
AS
/* Cuadro de adquisicion referenciado por NRO_REQUER (= numero de pedido) */
SELECT DISTINCT
    AnoEje       = CONVERT(smallint, c.ANO_EJE),
    SecEjec      = CONVERT(int,      c.SEC_EJEC),
    TipoPedido   = CONVERT(char(1),     p.TIPO_PEDIDO)  COLLATE DATABASE_DEFAULT,
    NumeroPedido = CONVERT(varchar(6),  p.NRO_PEDIDO)   COLLATE DATABASE_DEFAULT,
    SecCuadro    = CONVERT(bigint,   c.SEC_CUADRO),
    TipoBien     = CONVERT(char(1),     c.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
    CentroCosto  = CONVERT(varchar(15), c.CENTRO_COSTO) COLLATE DATABASE_DEFAULT,
    EstadoCuadro = CONVERT(char(1),     c.ESTADO)       COLLATE DATABASE_DEFAULT
  FROM siga.SIG_CUADRO_ADQUISICION AS c
  JOIN siga.SIG_PEDIDOS AS p
    ON p.ANO_EJE     = c.ANO_EJE
   AND p.SEC_EJEC    = c.SEC_EJEC
   AND p.TIPO_BIEN   = c.TIPO_BIEN
   AND p.TIPO_PEDIDO = '2'
   AND p.NRO_PEDIDO  = RIGHT('000000' + CONVERT(varchar(6), c.NRO_REQUER), 6)
 WHERE c.TIPO_BIEN   = 'S'
   AND c.NRO_REQUER IS NOT NULL
   AND c.NRO_ORDEN IS NULL

UNION

/* Detalle del pedido con NRO_CUADRO enlazado al cuadro de adquisicion */
SELECT DISTINCT
    AnoEje       = CONVERT(smallint, d.ANO_EJE),
    SecEjec      = CONVERT(int,      d.sec_ejec),
    TipoPedido   = CONVERT(char(1),     d.TIPO_PEDIDO)  COLLATE DATABASE_DEFAULT,
    NumeroPedido = CONVERT(varchar(6),  d.NRO_PEDIDO)   COLLATE DATABASE_DEFAULT,
    SecCuadro    = CONVERT(bigint,   c.SEC_CUADRO),
    TipoBien     = CONVERT(char(1),     d.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
    CentroCosto  = CONVERT(varchar(15), c.CENTRO_COSTO) COLLATE DATABASE_DEFAULT,
    EstadoCuadro = CONVERT(char(1),     c.ESTADO)       COLLATE DATABASE_DEFAULT
  FROM siga.SIG_DETALLE_PEDIDOS AS d
  JOIN siga.SIG_CUADRO_ADQUISICION AS c
    ON c.ANO_EJE    = d.ANO_EJE
   AND c.SEC_EJEC   = d.sec_ejec
   AND c.TIPO_BIEN  = d.TIPO_BIEN
   AND c.NRO_CUADRO = d.NRO_CUADRO
 WHERE d.TIPO_BIEN   = 'S'
   AND d.TIPO_PEDIDO = '2'
   AND d.NRO_CUADRO IS NOT NULL
   AND c.NRO_ORDEN IS NULL

UNION

/* Ruta legada */
SELECT DISTINCT
    AnoEje       = CONVERT(smallint, lg.ANO_EJE),
    SecEjec      = CONVERT(int,      lg.SEC_EJEC),
    TipoPedido   = CONVERT(char(1),     lg.TIPO_PEDIDO)  COLLATE DATABASE_DEFAULT,
    NumeroPedido = CONVERT(varchar(6),  lg.NRO_PEDIDO)   COLLATE DATABASE_DEFAULT,
    SecCuadro    = CONVERT(bigint,   lg.SEC_CUADRO),
    TipoBien     = CONVERT(char(1),     lg.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
    CentroCosto  = CONVERT(varchar(15), c2.CENTRO_COSTO) COLLATE DATABASE_DEFAULT,
    EstadoCuadro = CONVERT(char(1),     c2.ESTADO)       COLLATE DATABASE_DEFAULT
  FROM siga.SIG_DETALLE_PEDIDO_CUADRO AS lg
  JOIN siga.SIG_CUADRO_ADQUISICION AS c2
    ON c2.ANO_EJE    = lg.ANO_EJE
   AND c2.SEC_EJEC   = lg.SEC_EJEC
   AND c2.TIPO_BIEN  = lg.TIPO_BIEN
   AND c2.SEC_CUADRO = lg.SEC_CUADRO
 WHERE lg.TIPO_BIEN = 'S'
   AND lg.NRO_PEDIDO IS NOT NULL
   AND c2.NRO_ORDEN IS NULL;
GO

PRINT 'V022 aplicada: vwCuadroAdquisicionPedido (NRO_REQUER, NRO_CUADRO, legado).';
GO
