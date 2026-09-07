/*
===============================================================================
  SIGCM - S028 : Cerrar observacion AU al firmar / salir de OBSERVADO
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Tras S027, REQ_SUBSANAR (que cerraba la observacion) quedo inactivo. El
  Especialista edita en REQ_OBSERVADO y sale con REQ_DERIVAR_COORD_OBS
  (Firma especialista). Sin AccionObservacion='CERRAR' la fila en
  sigcm.Observacion queda PENDIENTE y OA no puede observar de nuevo
  (CONFLICTO_OBSERVACION).

  Requiere V029 (columna AccionObservacion) y F004 vigente.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'sigcm.Transicion', N'AccionObservacion') IS NULL
BEGIN
    RAISERROR('S028 requiere V029 (sigcm.Transicion.AccionObservacion). Aplique V029 primero.', 16, 1);
    RETURN;
END
GO

DECLARE @Accion TABLE (CodigoTransicion varchar(70), AccionObservacion varchar(15));
INSERT INTO @Accion VALUES
  /* Sale de OBSERVADO con firma del Especialista (flujo S027). */
  ('REQ_DERIVAR_COORD_OBS', 'CERRAR'),
  /* Por si el expediente ya estaba en DOC_PENDIENTE con obs abierta. */
  ('REQ_DERIVAR_COORD',     'CERRAR'),
  /* Red de seguridad: al remitir a OA no debe quedar obs AU abierta. */
  ('REQ_FIRMAR_AU',         'CERRAR'),
  /* Legacy (inactivo): por si se reactiva. */
  ('REQ_SUBSANAR',          'CERRAR');

UPDATE d
   SET d.AccionObservacion = s.AccionObservacion
  FROM sigcm.Transicion AS d
  JOIN @Accion AS s ON s.CodigoTransicion = d.CodigoTransicion
 WHERE ISNULL(d.AccionObservacion, '') <> s.AccionObservacion;
GO

/* Observaciones colgadas: expediente ya no esta en el circuito de correccion. */
DECLARE @Circuito TABLE (CodigoEstado varchar(60) PRIMARY KEY);
INSERT INTO @Circuito VALUES
  ('REQ_OBSERVADO'), ('REQ_OBS_AU_JEFE'), ('REQ_OBS_AU_COORD');

UPDATE o
   SET o.Estado = 'CERRADA',
       o.RecepcionadaEn = COALESCE(o.RecepcionadaEn, o.FechaCreacionAuditoria, GETDATE()),
       o.SubsanadaEn    = COALESCE(o.SubsanadaEn, GETDATE()),
       o.CerradaEn      = COALESCE(o.CerradaEn, GETDATE()),
       o.UsuarioModificacionAuditoria  = 'S028',
       o.FechaModificacionAuditoria    = GETDATE(),
       o.ProgramaModificacionAuditoria = 'S028__obs_cerrar_firma_au'
  FROM sigcm.Observacion AS o
  JOIN sigcm.Expediente  AS e ON e.IdExpediente = o.IdExpediente
 WHERE o.Activo = 1
   AND o.Estado IN ('PENDIENTE', 'RECEPCIONADA', 'SUBSANADA')
   AND e.CodigoModulo = 'REQUERIMIENTO'
   AND e.CodigoEstado NOT IN (SELECT CodigoEstado FROM @Circuito);

PRINT CONCAT('S028: observaciones REQ colgadas cerradas: ', @@ROWCOUNT, '.');
PRINT 'S028 aplicada: cierre de observacion en Firma especialista / Firmar AU.';
GO
