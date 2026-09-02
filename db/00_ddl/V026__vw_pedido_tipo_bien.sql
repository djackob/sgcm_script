/*
===============================================================================
  SIGCM - V026 : siga.vwPedido expone TIPO_BIEN
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: V014 (siga.vwPedido)

  En SIG_PEDIDOS la clave incluye TIPO_BIEN: B = bienes (compras), S = servicios.
  El combo N.° Pedido SIGA del requerimiento de locacion / servicio solo debe
  listar S. Sin esta columna el maestro PEDIDO mezclaba ambos.
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
    TipoBien     = CONVERT(char(1),     p.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
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

PRINT 'V026 aplicada: siga.vwPedido con TipoBien (B compras / S servicios).';
GO
