/*
===============================================================================
  SIGCM - S022 : AU Coordinador/Jefe — observar, devolver y archivar
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El Especialista elabora y puede corregir anexos. El Coordinador AU
  (REQ_PEND_VB_AU) y el Jefe AU (REQ_PEND_FIRMA_AU) NO modifican anexos:
  revisan (ver PDF), observan, devuelven al eslabon anterior o archivan.

  Coordinador AU:
    - Observar  → REQ_OBSERVADO (subsana el Especialista)
    - Devolver  → REQ_DOC_PENDIENTE (vuelve al Especialista)
    - Archivar  → REQ_ANULADO

  Jefe AU:
    - Observar  → REQ_OBSERVADO
    - Devolver  → REQ_PEND_VB_AU (vuelve al Coordinador)
    - Archivar  → REQ_ANULADO

  Ademas se quita AREA_JEFE de REQ_ELABORAR_DOC y REQ_SUBSANAR para que no
  abra la edicion de anexos desde la bandeja.

  Idempotente. Va despues de S003 / S013.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Transiciones                                                            */
/* -------------------------------------------------------------------------- */

DECLARE @Tr TABLE (
    CodigoTransicion     varchar(70),
    CodigoEstadoOrigen   varchar(60),
    CodigoEstadoDestino  varchar(60),
    NombreAccion         varchar(150),
    RequiereComentario   bit,
    RequiereFirma        bit,
    DocumentoRequerido   varchar(60) NULL,
    EncolaIntegracion    bit,
    OperacionIntegracion varchar(30) NULL,
    GeneraObservacion    bit
);
INSERT INTO @Tr VALUES
  ('REQ_OBSERVAR_COORD', 'REQ_PEND_VB_AU', 'REQ_OBSERVADO',
   'Observar documento', 1, 0, NULL, 0, NULL, 1),

  ('REQ_DEVOLVER_COORD', 'REQ_PEND_VB_AU', 'REQ_DOC_PENDIENTE',
   'Devolver al Especialista', 1, 0, NULL, 0, NULL, 0),

  ('REQ_ARCHIVAR_VB', 'REQ_PEND_VB_AU', 'REQ_ANULADO',
   'Archivar expediente', 1, 0, NULL, 0, NULL, 0),

  ('REQ_OBSERVAR_JEFE', 'REQ_PEND_FIRMA_AU', 'REQ_OBSERVADO',
   'Observar documento', 1, 0, NULL, 0, NULL, 1),

  ('REQ_DEVOLVER_JEFE', 'REQ_PEND_FIRMA_AU', 'REQ_PEND_VB_AU',
   'Devolver al Coordinador', 1, 0, NULL, 0, NULL, 0),

  ('REQ_ARCHIVAR_FIRMA', 'REQ_PEND_FIRMA_AU', 'REQ_ANULADO',
   'Archivar expediente', 1, 0, NULL, 0, NULL, 0);

UPDATE d
   SET d.CodigoEstadoOrigen = s.CodigoEstadoOrigen,
       d.CodigoEstadoDestino = s.CodigoEstadoDestino,
       d.NombreAccion = s.NombreAccion,
       d.RequiereComentario = s.RequiereComentario,
       d.RequiereFirma = s.RequiereFirma,
       d.DocumentoRequerido = s.DocumentoRequerido,
       d.EncolaIntegracion = s.EncolaIntegracion,
       d.OperacionIntegracion = s.OperacionIntegracion,
       d.GeneraObservacion = s.GeneraObservacion,
       d.Activo = 1
  FROM sigcm.Transicion AS d
  JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion
      (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
       NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
       EncolaIntegracion, OperacionIntegracion, GeneraObservacion, Activo)
SELECT s.CodigoTransicion, 'REQUERIMIENTO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion, 1
  FROM @Tr AS s
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

/* -------------------------------------------------------------------------- */
/* 2. Roles por transicion                                                    */
/* -------------------------------------------------------------------------- */

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('REQ_OBSERVAR_COORD', 'AREA_COORDINADOR'),
  ('REQ_DEVOLVER_COORD', 'AREA_COORDINADOR'),
  ('REQ_ARCHIVAR_VB',    'AREA_COORDINADOR'),
  ('REQ_OBSERVAR_JEFE',  'AREA_JEFE'),
  ('REQ_DEVOLVER_JEFE',  'AREA_JEFE'),
  ('REQ_ARCHIVAR_FIRMA', 'AREA_JEFE');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.TransicionRol AS d
        WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 3. El Jefe AU no elabora ni abre subsanacion de anexos                     */
/* -------------------------------------------------------------------------- */

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion IN ('REQ_ELABORAR_DOC', 'REQ_SUBSANAR')
   AND CodigoRol = 'AREA_JEFE';

/* Por si alguna semilla dio al Coordinador edicion de anexos. */
DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion IN ('REQ_ELABORAR_DOC', 'REQ_SUBSANAR')
   AND CodigoRol = 'AREA_COORDINADOR';
GO

PRINT 'S022 aplicada: observar / devolver / archivar para Coordinador y Jefe AU.';
GO

/* -------------------------------------------------------------------------- */
/* 4. Coordinador AU: solo deriva al Jefe (nunca firma)                       */
/* -------------------------------------------------------------------------- */

UPDATE sigcm.Transicion
   SET NombreAccion = 'Derivar al Jefe del Area usuaria',
       RequiereFirma = 0,
       RequiereComentario = 0,
       GeneraObservacion = 0,
       Activo = 1
 WHERE CodigoTransicion = 'REQ_OTORGAR_VB';

DELETE FROM sigcm.TransicionRol
 WHERE CodigoRol = 'AREA_COORDINADOR'
   AND CodigoTransicion IN ('REQ_FIRMAR_AU', 'REQ_DERIVAR_COORD', 'REQ_ELABORAR_DOC', 'REQ_SUBSANAR');

DELETE FROM sigcm.TipoDocumentoFirma
 WHERE CodigoRol = 'AREA_COORDINADOR'
   AND CodigoTipoDocumento LIKE 'REQ_%';

PRINT 'S022b: Coordinador AU sin firma; REQ_OTORGAR_VB = solo derivar al Jefe.';
GO
