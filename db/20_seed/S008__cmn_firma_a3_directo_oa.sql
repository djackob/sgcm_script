/*
===============================================================================
  SIGCM - Semilla S008 : Firma del Anexo 3 remite directo a OA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El jefe del area usuaria, al firmar el Anexo 3, envia el expediente a la
  Oficina de Administracion. El estado intermedio CMN_A3_FIRMADO y el boton
  "Enviar Anexo 3 a la Oficina de Administracion" (CMN_ENVIAR_OA) se retiran.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET CodigoEstadoDestino = 'CMN_EN_EVAL_OA',
       NombreAccion        = 'Firmar Anexo 3 y remitir a la Oficina de Administracion',
       Activo              = 1
 WHERE CodigoTransicion = 'CMN_FIRMAR_A3';

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion = 'CMN_ENVIAR_OA';

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'CMN_ENVIAR_OA';

/* Expedientes parados en el estado que ya no tiene salida: pasan a OA. */
UPDATE e
   SET e.CodigoEstado = 'CMN_EN_EVAL_OA',
       e.Version      = e.Version + 1,
       e.UsuarioModificacionAuditoria  = 'seed',
       e.FechaModificacionAuditoria    = GETDATE(),
       e.ProgramaModificacionAuditoria = 'S008'
  FROM sigcm.Expediente AS e
 WHERE e.CodigoModulo = 'CMN'
   AND e.CodigoEstado = 'CMN_A3_FIRMADO'
   AND e.Anulado = 0
   AND e.Activo = 1;

PRINT 'S008 aplicada: CMN_FIRMAR_A3 -> CMN_EN_EVAL_OA; CMN_ENVIAR_OA desactivada.';
GO
