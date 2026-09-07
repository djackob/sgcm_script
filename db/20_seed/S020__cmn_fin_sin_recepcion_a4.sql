/*
===============================================================================
  SIGCM - Semilla S020 : CMN finaliza al firmar Anexo 4 (sin recepcion AU)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Antes:  CMN_ABAST_JEFE_FIRMAR_A4 → CMN_A4_ENVIADO
          CMN_RECEPCIONAR_A4       → CMN_FINALIZADO  (clic del jefe AU)

  Ahora:  CMN_ABAST_JEFE_FIRMAR_A4 → CMN_FINALIZADO
          (firma del jefe de Abastecimiento + encolado CONSOLIDAR_CMN / SIGA)
          CMN_RECEPCIONAR_A4 queda inactiva.

  El aviso por correo al area usuaria (F013) sigue vigente en CMN_FINALIZADO.
  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET CodigoEstadoDestino = 'CMN_FINALIZADO',
       NombreAccion        = 'Firmar el Anexo 4, aprobar en SIGA y finalizar',
       Activo              = 1
 WHERE CodigoTransicion = 'CMN_ABAST_JEFE_FIRMAR_A4';

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion = 'CMN_RECEPCIONAR_A4';

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'CMN_RECEPCIONAR_A4';

UPDATE sigcm.Estado
   SET Nombre = 'Anexo 4 firmado y aprobado en SIGA - Fin'
 WHERE CodigoEstado = 'CMN_FINALIZADO';

UPDATE sigcm.Estado
   SET Nombre = 'Anexo 4 enviado (legado - sin recepcion)'
 WHERE CodigoEstado = 'CMN_A4_ENVIADO';

/* Expedientes que esperaban el clic de recepcion del AU: se cierran. */
UPDATE e
   SET e.CodigoEstado = 'CMN_FINALIZADO',
       e.Version      = e.Version + 1,
       e.CerradoEn    = COALESCE(e.CerradoEn, GETDATE()),
       e.UsuarioModificacionAuditoria  = 'seed',
       e.FechaModificacionAuditoria    = GETDATE(),
       e.ProgramaModificacionAuditoria = 'S020'
  FROM sigcm.Expediente AS e
 WHERE e.CodigoModulo = 'CMN'
   AND e.CodigoEstado = 'CMN_A4_ENVIADO'
   AND e.Anulado = 0 AND e.Activo = 1;

/* Plazo de recepcion AU ya no aplica. */
UPDATE sigcm.PlazoRegla
   SET Activo = 0
 WHERE CodigoRegla = 'CMN_RECEPCION_A4';
GO
