/*
===============================================================================
  SIGCM - Semilla S013 : Firma del jefe AU remite directo a OA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Al firmar el documento tecnico, el jefe del Area usuaria envia el expediente
  al Jefe de la Oficina de Administracion. El estado intermedio REQ_FIRMADO_AU
  y el boton "Remitir a la Oficina de Administracion" (REQ_REMITIR_OA) se
  retiran. Misma idea que S008 en CMN.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET CodigoEstadoDestino = 'REQ_EN_EVAL_OA',
       NombreAccion        = 'Firmar y remitir a la Oficina de Administracion',
       Activo              = 1
 WHERE CodigoTransicion = 'REQ_FIRMAR_AU';

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion IN ('REQ_REMITIR_OA', 'REQ_REMITIR_DAI');

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion IN ('REQ_REMITIR_OA', 'REQ_REMITIR_DAI');

/* Unidad OA real (centro SIGA). UO-OA es semilla y no tiene centro. */
DECLARE @IdUnidadOa uniqueidentifier =
    (SELECT TOP 1 n.IdUnidad
       FROM sigcm.UsuarioRol AS ur
       JOIN sigcm.Unidad AS n ON n.IdUnidad = ur.IdUnidad
      WHERE ur.CodigoRol = 'OA' AND ur.Activo = 1 AND n.Activo = 1
        AND NULLIF(LTRIM(RTRIM(n.CentroCostoSiga)), '') IS NOT NULL
      GROUP BY n.IdUnidad
      ORDER BY MIN(n.Codigo));

/* Expedientes parados en el estado que ya no tiene salida: pasan a OA. */
UPDATE e
   SET e.CodigoEstado = 'REQ_EN_EVAL_OA',
       e.IdUnidadActual = ISNULL(@IdUnidadOa, e.IdUnidadActual),
       e.Version      = e.Version + 1,
       e.UsuarioModificacionAuditoria  = 'seed',
       e.FechaModificacionAuditoria    = GETDATE(),
       e.ProgramaModificacionAuditoria = 'S013'
  FROM sigcm.Expediente AS e
 WHERE e.CodigoModulo = 'REQUERIMIENTO'
   AND e.CodigoEstado IN ('REQ_FIRMADO_AU', 'REQ_EN_EVAL_OA')
   AND e.Anulado = 0
   AND e.Activo = 1
   AND (
        e.CodigoEstado = 'REQ_FIRMADO_AU'
     OR (@IdUnidadOa IS NOT NULL AND e.IdUnidadActual <> @IdUnidadOa
         AND EXISTS (SELECT 1 FROM sigcm.Unidad AS n
                      WHERE n.IdUnidad = e.IdUnidadActual AND n.EsAreaUsuaria = 1))
       );

PRINT 'S013 aplicada: REQ_FIRMAR_AU -> REQ_EN_EVAL_OA; REQ_REMITIR_OA desactivada.';
GO
