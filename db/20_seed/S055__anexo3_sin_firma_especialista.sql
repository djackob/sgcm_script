/*
===============================================================================
  SIGCM - S055 : Anexo 3 sin firma del especialista del area usuaria
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El Anexo 3 (TDR de locacion) lo firma solo el jefe del area usuaria.
  Con el Anexo 5 (S050) tampoco firmado por el especialista, el especialista
  ya no sella ningun documento: deriva con «Derivar al Coordinador»
  (REQ_DERIVAR_SIN_FIRMA), que lleva al mismo estado (REQ_PEND_VB_AU).

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DELETE FROM sigcm.TipoDocumentoFirma
 WHERE CodigoTipoDocumento = 'REQ_TDR_LOCACION'
   AND CodigoRol = 'AREA_ESPECIALISTA';

UPDATE sigcm.TipoDocumentoFirma
   SET OrdenFirma = 1
 WHERE CodigoTipoDocumento = 'REQ_TDR_LOCACION'
   AND CodigoRol = 'AREA_JEFE'
   AND OrdenFirma <> 1;
GO

DELETE FROM sigcm.TransicionRol
 WHERE CodigoRol = 'AREA_ESPECIALISTA'
   AND CodigoTransicion IN ('REQ_DERIVAR_COORD', 'REQ_DERIVAR_COORD_OBS');

/* Sin firma del especialista, derivar es su unica salida: el boton no
   distingue entre firmar o no. */
UPDATE sigcm.Transicion
   SET NombreAccion = 'Derivar al Coordinador'
 WHERE CodigoTransicion IN ('REQ_DERIVAR_SIN_FIRMA', 'REQ_DERIVAR_SIN_FIRMA_OBS')
   AND NombreAccion <> 'Derivar al Coordinador';
GO

PRINT 'S055 aplicada: el Anexo 3 lo firma solo el jefe del area usuaria; el especialista deriva al coordinador.';
GO
