/*
===============================================================================
  SIGCM - Semilla S010 : Generar Anexo 4 no exige firma del especialista
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El especialista arma el PDF y lo remite al jefe. No lo firma. CMN_GENERAR_A4
  solo exige que el documento exista; la unica firma del Anexo 4 es la del jefe.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET RequiereFirma     = 0,
       RolFirmaRequerida = NULL,
       NombreAccion      = 'Generar Anexo 4 y remitir al Jefe',
       Activo            = 1
 WHERE CodigoTransicion = 'CMN_GENERAR_A4';

DELETE FROM sigcm.TipoDocumentoFirma
 WHERE CodigoTipoDocumento = 'CMN_ANEXO_4_APROBACION_MODIFICACION'
   AND CodigoRol = 'ABAST_ESPECIALISTA';

UPDATE sigcm.TipoDocumentoFirma
   SET OrdenFirma = 1
 WHERE CodigoTipoDocumento = 'CMN_ANEXO_4_APROBACION_MODIFICACION'
   AND CodigoRol = 'ABAST_JEFE';

PRINT 'S010 aplicada: Anexo 4 lo firma solo el jefe; generar no exige firma.';
GO
