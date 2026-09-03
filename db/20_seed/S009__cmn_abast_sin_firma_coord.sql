/*
===============================================================================
  SIGCM - Semilla S009 : Abastecimiento sin firma del coordinador
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El especialista de Abastecimiento, al firmar el Anexo 3, eleva directo al
  jefe. Al generar el Anexo 4, tambien lo remite al jefe. El coordinador deja
  de firmar ambos documentos.

  La bajada jefe -> coordinador -> especialista (derivacion) no se toca.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET CodigoEstadoDestino = 'CMN_A3_FIRMA_JEFE',
       NombreAccion        = 'Firmar el Anexo 3 y elevar al Jefe',
       Activo              = 1
 WHERE CodigoTransicion = 'CMN_ABAST_ESP_FIRMAR_A3';

UPDATE sigcm.Transicion
   SET CodigoEstadoDestino = 'CMN_A4_FIRMA_JEFE',
       NombreAccion        = 'Generar Anexo 4 y remitir al Jefe',
       Activo              = 1
 WHERE CodigoTransicion = 'CMN_GENERAR_A4';

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion IN ('CMN_ABAST_COORD_FIRMAR_A3', 'CMN_ABAST_COORD_FIRMAR_A4');

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion IN ('CMN_ABAST_COORD_FIRMAR_A3', 'CMN_ABAST_COORD_FIRMAR_A4');

/* Firmantes: el coordinador ya no firma Anexo 3 ni Anexo 4. */
DELETE FROM sigcm.TipoDocumentoFirma
 WHERE CodigoTipoDocumento IN (
           'CMN_ANEXO_3_SOLICITUD_MODIFICACION',
           'CMN_ANEXO_4_APROBACION_MODIFICACION')
   AND CodigoRol = 'ABAST_COORDINADOR';

UPDATE sigcm.TipoDocumentoFirma
   SET OrdenFirma = 3
 WHERE CodigoTipoDocumento = 'CMN_ANEXO_3_SOLICITUD_MODIFICACION'
   AND CodigoRol = 'ABAST_JEFE';

UPDATE sigcm.TipoDocumentoFirma
   SET OrdenFirma = 2
 WHERE CodigoTipoDocumento = 'CMN_ANEXO_4_APROBACION_MODIFICACION'
   AND CodigoRol = 'ABAST_JEFE';

UPDATE e
   SET e.CodigoEstado = 'CMN_A3_FIRMA_JEFE',
       e.Version      = e.Version + 1,
       e.UsuarioModificacionAuditoria  = 'seed',
       e.FechaModificacionAuditoria    = GETDATE(),
       e.ProgramaModificacionAuditoria = 'S009'
  FROM sigcm.Expediente AS e
 WHERE e.CodigoModulo = 'CMN'
   AND e.CodigoEstado = 'CMN_A3_FIRMA_COORD'
   AND e.Anulado = 0 AND e.Activo = 1;

UPDATE e
   SET e.CodigoEstado = 'CMN_A4_FIRMA_JEFE',
       e.Version      = e.Version + 1,
       e.UsuarioModificacionAuditoria  = 'seed',
       e.FechaModificacionAuditoria    = GETDATE(),
       e.ProgramaModificacionAuditoria = 'S009'
  FROM sigcm.Expediente AS e
 WHERE e.CodigoModulo = 'CMN'
   AND e.CodigoEstado = 'CMN_A4_FIRMA_COORD'
   AND e.Anulado = 0 AND e.Activo = 1;

PRINT 'S009 aplicada: especialista eleva Anexo 3 y Anexo 4 directo al jefe.';
GO
