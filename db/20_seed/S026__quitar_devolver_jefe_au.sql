/*
===============================================================================
  SIGCM - S026 : Quitar «Devolver» del Jefe AU
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  En REQ_PEND_FIRMA_AU el Jefe conserva Observar / Firmar / Archivar.
  REQ_DEVOLVER_JEFE (Devolver al Coordinador) queda inactivo.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion = 'REQ_DEVOLVER_JEFE';

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_DEVOLVER_JEFE';

PRINT 'S026 aplicada: REQ_DEVOLVER_JEFE desactivado.';
GO
