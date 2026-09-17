/*
===============================================================================
  SIGCM - S037 : Emitir orden de servicio solo Especialista de Abastecimiento
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  REQ_EMITIR_OS («Emitir orden de servicio») queda solo para ABAST_ESPECIALISTA.
  El coordinador de Abastecimiento no la ve en la bandeja.

  Idempotente. Va despues de S004, que en instalaciones previas asignaba la
  transicion tambien a ABAST_COORDINADOR.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_EMITIR_OS'
   AND CodigoRol IN ('ABAST_COORDINADOR', 'ABAST_JEFE', 'ABAST_SECRETARIA');

IF NOT EXISTS (
    SELECT 1 FROM sigcm.TransicionRol
     WHERE CodigoTransicion = 'REQ_EMITIR_OS'
       AND CodigoRol = 'ABAST_ESPECIALISTA'
)
    INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
    VALUES ('REQ_EMITIR_OS', 'ABAST_ESPECIALISTA');

PRINT 'S037 aplicada: REQ_EMITIR_OS solo ABAST_ESPECIALISTA.';
GO
