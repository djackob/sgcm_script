/*
===============================================================================
  SIGCM - S025 : Quitar «Devolver» del Coordinador AU
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  En REQ_PEND_VB_AU el Coordinador solo conserva Observar / Derivar / Archivar.
  REQ_DEVOLVER_COORD (Devolver al Especialista) queda inactivo.

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
 WHERE CodigoTransicion = 'REQ_DEVOLVER_COORD';

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_DEVOLVER_COORD';

PRINT 'S025 aplicada: REQ_DEVOLVER_COORD desactivado.';
GO
