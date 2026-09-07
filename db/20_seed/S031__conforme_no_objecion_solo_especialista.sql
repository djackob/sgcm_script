/*
===============================================================================
  SIGCM - S031 : Conforme / no objecion solo Especialista DEC
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  En REQ_EN_EVAL_DEC, «Declarar conforme» (REQ_CONFORMIDAD_DEC) y
  «Registrar mejoras sujetas a no objecion» (REQ_NO_OBJECION_DEC) quedan
  solo para ABAST_ESPECIALISTA. El Coordinador de Abastecimiento no las
  ejecuta.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DELETE FROM sigcm.TransicionRol
 WHERE CodigoRol = 'ABAST_COORDINADOR'
   AND CodigoTransicion IN ('REQ_CONFORMIDAD_DEC', 'REQ_NO_OBJECION_DEC');

/* Refuerzo: el Especialista si las conserva. */
IF NOT EXISTS (
    SELECT 1 FROM sigcm.TransicionRol
     WHERE CodigoTransicion = 'REQ_CONFORMIDAD_DEC' AND CodigoRol = 'ABAST_ESPECIALISTA')
    INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
    VALUES ('REQ_CONFORMIDAD_DEC', 'ABAST_ESPECIALISTA');

IF NOT EXISTS (
    SELECT 1 FROM sigcm.TransicionRol
     WHERE CodigoTransicion = 'REQ_NO_OBJECION_DEC' AND CodigoRol = 'ABAST_ESPECIALISTA')
    INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
    VALUES ('REQ_NO_OBJECION_DEC', 'ABAST_ESPECIALISTA');

PRINT 'S031 aplicada: conforme / no objecion solo ABAST_ESPECIALISTA.';
GO
