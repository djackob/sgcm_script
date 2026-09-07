/*
===============================================================================
  SIGCM - S029 : Observacion OA → Jefe AU → Coordinador AU → Especialista
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  CMN ya tiene ese camino (CMN_OA_OBSERVAR → CMN_OBS_AU_JEFE →
  CMN_OBS_AU_COORD → CMN_OBSERVADO). Aqui se replica en Requerimiento y se
  refuerza CMN desactivando el salto directo Jefe → Especialista
  (CMN_OBS_AU_JEFE_DERIVAR_ESP de S006), para que ambos modulos coincidan:

    OA observa
      → bandeja del Jefe AU
      → Jefe deriva al Coordinador AU
      → Coordinador envia al Especialista AU (subsanar)

  Idempotente. Requiere V029 / AccionObservacion (RECEPCIONAR en el ultimo
  escalon hacia el Especialista).
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. CMN: sin salto Jefe AU → Especialista                                   */
/* -------------------------------------------------------------------------- */

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion = 'CMN_OBS_AU_JEFE_DERIVAR_ESP';

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'CMN_OBS_AU_JEFE_DERIVAR_ESP';

/* Asegura el destino de OA observar → Jefe AU. */
UPDATE sigcm.Transicion
   SET CodigoEstadoDestino = 'CMN_OBS_AU_JEFE',
       NombreAccion = 'Observar desde la Oficina de Administracion',
       GeneraObservacion = 1,
       Activo = 1
 WHERE CodigoTransicion = 'CMN_OA_OBSERVAR';
GO

/* -------------------------------------------------------------------------- */
/* 2. Requerimiento: estados intermedios                                      */
/* -------------------------------------------------------------------------- */

DECLARE @Est TABLE (
    CodigoEstado varchar(60),
    Nombre varchar(120),
    Orden int,
    EsInicial bit,
    EsFinal bit,
    RolResponsable varchar(40)
);
INSERT INTO @Est VALUES
  ('REQ_OBS_AU_JEFE',  'Observado - Jefe del Area usuaria',         66, 0, 0, 'AREA_JEFE'),
  ('REQ_OBS_AU_COORD', 'Observado - Coordinador del Area usuaria',  68, 0, 0, 'AREA_COORDINADOR');

UPDATE d
   SET d.Nombre = s.Nombre,
       d.Orden = s.Orden,
       d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal,
       d.RolResponsable = s.RolResponsable,
       d.Activo = 1
  FROM sigcm.Estado AS d
  JOIN @Est AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable, Activo)
SELECT s.CodigoEstado, 'REQUERIMIENTO', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable, 1
  FROM @Est AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS e WHERE e.CodigoEstado = s.CodigoEstado);
GO

/* -------------------------------------------------------------------------- */
/* 3. Requerimiento: transiciones                                             */
/* -------------------------------------------------------------------------- */

DECLARE @Tr TABLE (
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
INSERT INTO @Tr VALUES
  ('REQ_OBSERVAR_OA',          'REQ_EN_EVAL_OA',   'REQ_OBS_AU_JEFE',
   'Observar desde OA', 1, 0, NULL, 0, NULL, 1),
  ('REQ_OBS_AU_JEFE_DERIVAR',  'REQ_OBS_AU_JEFE',  'REQ_OBS_AU_COORD',
   'Derivar al Coordinador del Area usuaria', 0, 0, NULL, 0, NULL, 0),
  ('REQ_OBS_AU_COORD_DERIVAR', 'REQ_OBS_AU_COORD', 'REQ_OBSERVADO',
   'Enviar al Especialista para subsanar', 0, 0, NULL, 0, NULL, 0);

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
  JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion (
    CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
    NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
    EncolaIntegracion, OperacionIntegracion, GeneraObservacion, Activo)
SELECT s.CodigoTransicion, 'REQUERIMIENTO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion, 1
  FROM @Tr AS s
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.Transicion AS t WHERE t.CodigoTransicion = s.CodigoTransicion);
GO

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('REQ_OBSERVAR_OA',          'OA'),
  ('REQ_OBS_AU_JEFE_DERIVAR',  'AREA_JEFE'),
  ('REQ_OBS_AU_COORD_DERIVAR', 'AREA_COORDINADOR');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE EXISTS (SELECT 1 FROM sigcm.Transicion t WHERE t.CodigoTransicion = s.CodigoTransicion)
   AND NOT EXISTS (
       SELECT 1 FROM sigcm.TransicionRol d
        WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 4. AccionObservacion: recepcion al llegar al Especialista                  */
/* -------------------------------------------------------------------------- */

IF COL_LENGTH(N'sigcm.Transicion', N'AccionObservacion') IS NOT NULL
BEGIN
    UPDATE sigcm.Transicion
       SET AccionObservacion = 'RECEPCIONAR'
     WHERE CodigoTransicion IN ('REQ_OBS_AU_COORD_DERIVAR', 'CMN_OBS_AU_COORD_DERIVAR')
       AND ISNULL(AccionObservacion, '') <> 'RECEPCIONAR';

    /* El cierre sigue en Firma especialista / Firmar AU (S028). */
END
GO

PRINT 'S029 aplicada: observacion OA → Jefe AU → Coordinador → Especialista (CMN y REQ).';
GO
