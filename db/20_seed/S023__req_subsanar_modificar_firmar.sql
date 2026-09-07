/*
===============================================================================
  SIGCM - S023 : Tras observar (Coordinador/Jefe AU) → modificar y firmar
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Cuando el Coordinador (o el Jefe) observa, el expediente llega a
  REQ_OBSERVADO. El Especialista AU debe:

    1. Modificar documentos (REQ_SUBSANAR) → pasa a REQ_DOC_PENDIENTE
    2. Firma especialista (REQ_DERIVAR_COORD) → vuelve al Coordinador

  Antes SUBSANAR iba a REQ_BORRADOR y obligaba un paso extra
  (REQ_ELABORAR_DOC) antes de poder firmar de nuevo.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET CodigoEstadoDestino = 'REQ_DOC_PENDIENTE',
       NombreAccion = 'Modificar documentos',
       RequiereComentario = 1,
       RequiereFirma = 0,
       GeneraObservacion = 0,
       Activo = 1
 WHERE CodigoTransicion = 'REQ_SUBSANAR';

/* El Especialista es quien corrige anexos tras la observacion. */
IF NOT EXISTS (
    SELECT 1 FROM sigcm.TransicionRol
     WHERE CodigoTransicion = 'REQ_SUBSANAR' AND CodigoRol = 'AREA_ESPECIALISTA'
)
    INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
    VALUES ('REQ_SUBSANAR', 'AREA_ESPECIALISTA');

/* Coordinador y Jefe no modifican anexos (refuerzo de S022). */
DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_SUBSANAR'
   AND CodigoRol IN ('AREA_COORDINADOR', 'AREA_JEFE');

PRINT 'S023 aplicada: REQ_SUBSANAR = Modificar documentos → REQ_DOC_PENDIENTE.';
GO
