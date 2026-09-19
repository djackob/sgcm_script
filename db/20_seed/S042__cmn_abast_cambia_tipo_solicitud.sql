/*
===============================================================================
  SIGCM - S042 : Tipificacion Abast pre-Anexo 4 (documentacion)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  T3 / observacion CMN 16/09/2026:
  El cambio Ordinaria↔Extraordinaria lo hace Abastecimiento via el endpoint
  api/cmn/cambiarTipoInclusion → cmn.paCambiarTipoInclusion (F002). No mueve
  estado ni requiere TransicionRol, por eso esta semilla no inserta filas.

  Idempotente (no-op). Existe para que el plan y el orden de seeds documenten
  el ticket junto a S041.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

PRINT 'S042: tipificacion Abast via cmn.paCambiarTipoInclusion (sin filas de semilla).';
GO
