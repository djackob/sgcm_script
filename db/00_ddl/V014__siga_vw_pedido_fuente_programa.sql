/*
===============================================================================
  SIGCM - Migracion V014 : Pedido SIGA, fuente FTO y programa de la meta
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: V012 (siga.vwPedido), V004 (siga.vwMeta)

  En SIG_PEDIDOS, ORIGEN y FUENTE_FINANC suelen ir nulos. El API institucional
  de listarPedidos devolvía ff_rb desde fuente_fto (y el origen equivalente en
  origen_fto). El formulario FF/RR espera ese codigo de 2 caracteres.

  Programa no vive en el pedido: es el programa SIAF de la meta (META.programa)
  ligada a sec_func. REQ-02 lo precarga como dato presupuestal de solo lectura.
  No se edita V012: ya se aplico.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW siga.vwPedido
AS
SELECT
    AnoEje       = CONVERT(smallint, p.ANO_EJE),
    SecEjec      = CONVERT(int,      p.SEC_EJEC),
    CentroCosto  = CONVERT(varchar(15), p.CENTRO_COSTO) COLLATE DATABASE_DEFAULT,
    TipoPedido   = CONVERT(char(1),     p.TIPO_PEDIDO)  COLLATE DATABASE_DEFAULT,
    NumeroPedido = CONVERT(varchar(6),  p.NRO_PEDIDO)   COLLATE DATABASE_DEFAULT,
    MotivoPedido = CONVERT(varchar(520),
                       CONCAT(
                           CONVERT(varchar(6), p.NRO_PEDIDO),
                           N' - ',
                           CONVERT(varchar(500), p.MOTIVO_PEDIDO)
                       )) COLLATE DATABASE_DEFAULT,
    FechaPedido  = CONVERT(date, p.FECHA_PEDIDO),
    SecFunc      = CONVERT(int, p.sec_func),
    ActProy      = CONVERT(varchar(7), p.ACT_PROY) COLLATE DATABASE_DEFAULT,
    CodigoTarea  = CONVERT(int, p.CODIGO_TAREA),
    Origen       = CONVERT(varchar(1), COALESCE(p.ORIGEN, p.origen_fto)) COLLATE DATABASE_DEFAULT,
    FuenteFinanc = CONVERT(varchar(2), COALESCE(p.FUENTE_FINANC, p.fuente_fto)) COLLATE DATABASE_DEFAULT,
    Programa     = CONVERT(varchar(3), m.Programa) COLLATE DATABASE_DEFAULT,
    Estado       = CONVERT(char(1), p.ESTADO) COLLATE DATABASE_DEFAULT
FROM siga.SIG_PEDIDOS AS p
LEFT JOIN siga.vwMeta AS m
       ON m.AnoEje  = CONVERT(smallint, p.ANO_EJE)
      AND m.SecEjec = CONVERT(int,      p.SEC_EJEC)
      AND m.SecFunc = CONVERT(int,      p.sec_func);
GO

PRINT 'V014 aplicada: siga.vwPedido con fuente FTO y programa de la meta.';
GO
