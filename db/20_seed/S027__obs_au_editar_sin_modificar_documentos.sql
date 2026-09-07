/*
===============================================================================
  SIGCM - S027 : Observado AU → editar de frente (sin «Modificar documentos»)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Tras Observar (Jefe o Coordinador AU) el expediente queda en REQ_OBSERVADO.
  El Especialista no debe pasar por un boton/estado intermedio
  «Modificar documentos» (REQ_SUBSANAR → REQ_DOC_PENDIENTE).

  Flujo:
    REQ_OBSERVADO → edita anexos (mismo estado)
                  → Firma especialista (REQ_DERIVAR_COORD_OBS) → REQ_PEND_VB_AU

  REQ_SUBSANAR se desactiva. REQ_DERIVAR_COORD sigue vigente desde
  REQ_DOC_PENDIENTE (expedientes que ya estaban ahi).

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion = 'REQ_SUBSANAR';

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_SUBSANAR';

DECLARE @FirmaObs TABLE (
    CodigoTransicion     varchar(70),
    CodigoEstadoOrigen   varchar(60),
    CodigoEstadoDestino  varchar(60),
    NombreAccion         varchar(180),
    RequiereComentario   bit,
    RequiereFirma        bit,
    DocumentoRequerido   varchar(60) NULL,
    EncolaIntegracion    bit,
    OperacionIntegracion varchar(40) NULL,
    GeneraObservacion    bit
);
INSERT INTO @FirmaObs VALUES
  ('REQ_DERIVAR_COORD_OBS', 'REQ_OBSERVADO', 'REQ_PEND_VB_AU',
   'Firma especialista', 0, 1, NULL, 0, NULL, 0);

UPDATE d
   SET d.CodigoEstadoOrigen   = s.CodigoEstadoOrigen,
       d.CodigoEstadoDestino  = s.CodigoEstadoDestino,
       d.NombreAccion         = s.NombreAccion,
       d.RequiereComentario   = s.RequiereComentario,
       d.RequiereFirma        = s.RequiereFirma,
       d.DocumentoRequerido   = s.DocumentoRequerido,
       d.EncolaIntegracion    = s.EncolaIntegracion,
       d.OperacionIntegracion = s.OperacionIntegracion,
       d.GeneraObservacion    = s.GeneraObservacion,
       d.Activo               = 1
  FROM sigcm.Transicion AS d
  JOIN @FirmaObs AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion (
    CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
    NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
    EncolaIntegracion, OperacionIntegracion, GeneraObservacion, Activo)
SELECT s.CodigoTransicion, 'REQUERIMIENTO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion, 1
  FROM @FirmaObs AS s
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.Transicion AS t
        WHERE t.CodigoTransicion = s.CodigoTransicion);

IF NOT EXISTS (
    SELECT 1 FROM sigcm.TransicionRol
     WHERE CodigoTransicion = 'REQ_DERIVAR_COORD_OBS'
       AND CodigoRol = 'AREA_ESPECIALISTA'
)
    INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
    VALUES ('REQ_DERIVAR_COORD_OBS', 'AREA_ESPECIALISTA');

PRINT 'S027 aplicada: Observado AU sin Modificar documentos; Firma especialista directa.';
GO
