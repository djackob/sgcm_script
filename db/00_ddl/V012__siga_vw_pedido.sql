/*
===============================================================================
  SIGCM - Migracion V012 : Vista de pedidos SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: 00_servidor/C003__sinonimos_siga.sql (sinonimo siga.SIG_PEDIDOS)

  AUTORIDAD: SIGA. Solo lectura, por construccion.

  V009 dejo escrito que REQ-02 precarga el pedido desde SIGA y que, mientras no
  existiera siga.vwPedido, el formulario lo capturaba a mano. Esta vista cierra
  ese hueco. No se edita V004: ya se aplico en desarrollo; un V nuevo es el
  unico camino para quien ya tiene las diez vistas.

  La clave del pedido en SIGA es AnoEje + SecEjec + TipoPedido + NroPedido.
  El combo del requerimiento filtra por el centro de costo de la unidad
  (area usuaria) y por TipoPedido = 1. El tipo 2 es pedido de almacen.

  Sin NOLOCK: los pedidos se mueven. La doctrina de V004 reserva NOLOCK a
  maestros cuasi estaticos. LOCK_TIMEOUT y DEADLOCK_PRIORITY LOW viven en
  sigcm.paListarMaestroSiga, que es quien consulta esta vista.
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
    Origen       = CONVERT(varchar(1), p.ORIGEN) COLLATE DATABASE_DEFAULT,
    FuenteFinanc = CONVERT(varchar(2), p.FUENTE_FINANC) COLLATE DATABASE_DEFAULT,
    Estado       = CONVERT(char(1), p.ESTADO) COLLATE DATABASE_DEFAULT
FROM siga.SIG_PEDIDOS AS p;
GO

PRINT 'V012 aplicada: siga.vwPedido sobre SIG_PEDIDOS.';
GO
