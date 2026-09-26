/*
===============================================================================
  SIGCM - S046 : El alta nace en Elaborar documento tecnico
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  "Registrar requerimiento" (REQ_BORRADOR) y "Elaborar documento tecnico"
  (REQ_DOC_PENDIENTE) eran el mismo especialista. El paso entre ambos
  (REQ_ELABORAR_DOC) no pedia firma ni un documento distinto: solo cambiaba
  el rotulo. El alta queda directo en elaboracion.

  Los expedientes que aun estan en registrar pasan a elaboracion.
  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRAN;

UPDATE sigcm.Estado
   SET EsInicial = 0,
       Activo = 0
 WHERE CodigoEstado = 'REQ_BORRADOR';

UPDATE sigcm.Estado
   SET EsInicial = 1,
       Activo = 1
 WHERE CodigoEstado = 'REQ_DOC_PENDIENTE';

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion IN ('REQ_ELABORAR_DOC', 'REQ_ANULAR_BORRADOR');

INSERT INTO sigcm.Historial (
    IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
    Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
    UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
SELECT e.IdExpediente, 'REQ_BORRADOR', 'REQ_DOC_PENDIENTE', NULL,
       N'El registro deja el expediente en elaboracion del documento tecnico.',
       COALESCE(e.IdResponsableActual, r.IdResponsable),
       'AREA_ESPECIALISTA', e.IdUnidadActual, N'{}',
       'seed', 'QA', 'S046'
  FROM sigcm.Expediente AS e
  JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente
 WHERE e.CodigoModulo = 'REQUERIMIENTO'
   AND e.CodigoEstado = 'REQ_BORRADOR'
   AND e.Anulado = 0
   AND e.Activo = 1
   AND COALESCE(e.IdResponsableActual, r.IdResponsable) IS NOT NULL;

UPDATE e
   SET e.CodigoEstado = 'REQ_DOC_PENDIENTE',
       e.Version = e.Version + 1,
       e.UsuarioModificacionAuditoria = 'seed',
       e.FechaModificacionAuditoria = GETDATE(),
       e.ProgramaModificacionAuditoria = 'S046'
  FROM sigcm.Expediente AS e
 WHERE e.CodigoModulo = 'REQUERIMIENTO'
   AND e.CodigoEstado = 'REQ_BORRADOR'
   AND e.Anulado = 0
   AND e.Activo = 1;

COMMIT;

PRINT 'S046 aplicada: el alta nace en Elaborar documento tecnico.';
GO
