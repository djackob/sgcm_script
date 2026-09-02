/*
===============================================================================
  SIGCM - Semilla S011 : Accion del especialista AU
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  REQ_DERIVAR_COORD no se llama «Enviar a firmar» ni «Firmar anexos».
  El boton de bandeja y el titulo del modal quedan como «Firma especialista».

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET NombreAccion = 'Firma especialista',
       Activo       = 1
 WHERE CodigoTransicion = 'REQ_DERIVAR_COORD';

PRINT 'S011 aplicada: REQ_DERIVAR_COORD se ofrece como Firma especialista.';
GO
