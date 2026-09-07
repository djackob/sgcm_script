/*
===============================================================================
  SIGCM - S030 : Jefe Abastecimiento observa y devuelve al Jefe AU
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Desde la bandeja del Jefe de Abastecimiento (CMN_EN_ABAST_JEFE /
  REQ_EN_ABAST_JEFE) puede observar el expediente y devolverlo de inmediato
  al Jefe del Area usuaria (CMN_OBS_AU_JEFE / REQ_OBS_AU_JEFE), sin pasar por
  el circuito interno OBS_ABAST_COORD → OBS_ABAST_JEFE.

  CMN ya tenia CMN_OBS_JEFE_DEVOLVER para cuando la observacion subia por
  Coordinador/Especialista; esta semilla agrega la observacion directa del
  Jefe y el equivalente en Requerimiento.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Tr TABLE (
    CodigoTransicion     varchar(70),
    CodigoModulo         varchar(30),
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
  ('CMN_ABAST_JEFE_OBSERVAR', 'CMN', 'CMN_EN_ABAST_JEFE', 'CMN_OBS_AU_JEFE',
   'Observar y devolver al Jefe del Area usuaria', 1, 0, NULL, 0, NULL, 1),
  ('REQ_ABAST_JEFE_OBSERVAR', 'REQUERIMIENTO', 'REQ_EN_ABAST_JEFE', 'REQ_OBS_AU_JEFE',
   'Observar y devolver al Jefe del Area usuaria', 1, 0, NULL, 0, NULL, 1);

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
SELECT s.CodigoTransicion, s.CodigoModulo, s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion, 1
  FROM @Tr AS s
 WHERE EXISTS (SELECT 1 FROM sigcm.Estado e WHERE e.CodigoEstado = s.CodigoEstadoOrigen)
   AND EXISTS (SELECT 1 FROM sigcm.Estado e WHERE e.CodigoEstado = s.CodigoEstadoDestino)
   AND NOT EXISTS (
       SELECT 1 FROM sigcm.Transicion t WHERE t.CodigoTransicion = s.CodigoTransicion);
GO

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT v.CodigoTransicion, v.CodigoRol
  FROM (VALUES
          ('CMN_ABAST_JEFE_OBSERVAR', 'ABAST_JEFE'),
          ('REQ_ABAST_JEFE_OBSERVAR', 'ABAST_JEFE')
       ) AS v(CodigoTransicion, CodigoRol)
 WHERE EXISTS (SELECT 1 FROM sigcm.Transicion t WHERE t.CodigoTransicion = v.CodigoTransicion)
   AND NOT EXISTS (
       SELECT 1 FROM sigcm.TransicionRol d
        WHERE d.CodigoTransicion = v.CodigoTransicion AND d.CodigoRol = v.CodigoRol);
GO

PRINT 'S030 aplicada: Jefe Abastecimiento observa y devuelve al Jefe AU (CMN y REQ).';
GO
