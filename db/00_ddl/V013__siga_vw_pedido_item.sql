/*
===============================================================================
  SIGCM - Migracion V013 : Vista de items del pedido SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: 00_servidor/C003__sinonimos_siga.sql (sinonimo siga.SIG_DETALLE_PEDIDOS)
            db/00_ddl/V004__maestros_siga_vistas.sql (siga.vwCatalogoItem)

  AUTORIDAD: SIGA. Solo lectura, por construccion.

  El formulario del requerimiento, al elegir un N° de pedido, necesita el nombre
  de la actividad operativa (tarea del centro) y el resumen de items del pedido
  (codigo, nombre, clasificador). En el sistema anterior eso eran dos HTTP
  (listarCentroCostoTarea + listarItemsPedidoResumen). Aqui las lineas viven
  en esta vista; el resumen concatenado lo arma el maestro PEDIDO_DETALLE en F001.

  CodigoItem replica el grano del API viejo: GRUPO+CLASE+FAMILIA+ITEM sin puntos
  (12 caracteres), no el codigo con puntos de vwCatalogoItem.

  Sin NOLOCK: el detalle del pedido se mueve. El catalogo se lee via
  vwCatalogoItem, que ya lleva NOLOCK porque es maestro cuasi estatico.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW siga.vwPedidoItem
AS
SELECT
    AnoEje       = CONVERT(smallint, d.ANO_EJE),
    SecEjec      = CONVERT(int,      d.sec_ejec),
    TipoPedido   = CONVERT(char(1),     d.TIPO_PEDIDO)  COLLATE DATABASE_DEFAULT,
    NumeroPedido = CONVERT(varchar(6),  d.NRO_PEDIDO)   COLLATE DATABASE_DEFAULT,
    Secuencia    = CONVERT(int, d.SECUENCIA),
    CentroCosto  = CONVERT(varchar(15), d.CENTRO_COSTO) COLLATE DATABASE_DEFAULT,
    TipoBien     = CONVERT(char(1),     d.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
    CodigoItem   = CONVERT(varchar(12),
                       CONCAT(d.GRUPO_BIEN, d.CLASE_BIEN, d.FAMILIA_BIEN, d.ITEM_BIEN)
                   ) COLLATE DATABASE_DEFAULT,
    NombreItem   = CONVERT(varchar(350), c.Descripcion) COLLATE DATABASE_DEFAULT,
    Clasificador = CONVERT(varchar(20),  d.CLASIFICADOR) COLLATE DATABASE_DEFAULT
FROM siga.SIG_DETALLE_PEDIDOS AS d
LEFT JOIN siga.vwCatalogoItem AS c
       ON c.SecEjec     = CONVERT(int, d.sec_ejec)
      AND c.TipoBien    = d.TIPO_BIEN
      AND c.GrupoBien   = d.GRUPO_BIEN
      AND c.ClaseBien   = d.CLASE_BIEN
      AND c.FamiliaBien = d.FAMILIA_BIEN
      AND c.ItemBien    = d.ITEM_BIEN;
GO

PRINT 'V013 aplicada: siga.vwPedidoItem sobre SIG_DETALLE_PEDIDOS.';
GO
