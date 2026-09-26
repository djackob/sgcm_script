/*
===============================================================================
  SIGCM - S047 : Firma del especialista AU opcional
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El especialista (o punto focal) puede:
    - Firmar y derivar (REQ_DERIVAR_COORD / REQ_DERIVAR_COORD_OBS)
    - Derivar sin firmar (REQ_DERIVAR_SIN_FIRMA / REQ_DERIVAR_SIN_FIRMA_OBS)

  La firma del Jefe del Area usuaria (REQ_FIRMAR_AU) sigue siendo obligatoria:
  es la que remite el expediente a la Oficina de Administracion.

  Requiere V036 (FirmaObligatoria). Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'sigcm.TipoDocumentoFirma', N'FirmaObligatoria') IS NULL
BEGIN
    RAISERROR('S047 requiere V036 (sigcm.TipoDocumentoFirma.FirmaObligatoria).', 16, 1);
    RETURN;
END
GO

/* La firma del especialista no cierra el documento. La del jefe si. */
UPDATE sigcm.TipoDocumentoFirma
   SET FirmaObligatoria = 0
 WHERE CodigoRol = 'AREA_ESPECIALISTA'
   AND CodigoTipoDocumento IN ('REQ_TDR_LOCACION', 'REQ_PROPUESTA_LOCACION')
   AND FirmaObligatoria <> 0;

UPDATE sigcm.TipoDocumentoFirma
   SET FirmaObligatoria = 1
 WHERE CodigoRol = 'AREA_JEFE'
   AND CodigoTipoDocumento LIKE 'REQ_%'
   AND FirmaObligatoria <> 1;
GO

/* Nombres de las acciones que si firman. */
UPDATE sigcm.Transicion
   SET NombreAccion = 'Firmar y derivar',
       RequiereFirma = 1,
       Activo = 1
 WHERE CodigoTransicion IN ('REQ_DERIVAR_COORD', 'REQ_DERIVAR_COORD_OBS');
GO

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
    GeneraObservacion    bit,
    AccionObservacion    varchar(15) NULL
);
INSERT INTO @Tr VALUES
  ('REQ_DERIVAR_SIN_FIRMA', 'REQ_DOC_PENDIENTE', 'REQ_PEND_VB_AU',
   'Derivar sin firmar', 0, 0, NULL, 0, NULL, 0, 'CERRAR'),
  ('REQ_DERIVAR_SIN_FIRMA_OBS', 'REQ_OBSERVADO', 'REQ_PEND_VB_AU',
   'Derivar sin firmar', 0, 0, NULL, 0, NULL, 0, 'CERRAR');

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
       d.AccionObservacion = s.AccionObservacion,
       d.Activo = 1
  FROM sigcm.Transicion AS d
  JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion
      (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
       NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
       EncolaIntegracion, OperacionIntegracion, GeneraObservacion,
       AccionObservacion, Activo)
SELECT s.CodigoTransicion, 'REQUERIMIENTO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion,
       s.AccionObservacion, 1
  FROM @Tr AS s
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('REQ_DERIVAR_SIN_FIRMA', 'AREA_ESPECIALISTA'),
  ('REQ_DERIVAR_SIN_FIRMA_OBS', 'AREA_ESPECIALISTA');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.TransicionRol AS d
        WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

/* El jefe no usa estos atajos: su paso sigue siendo REQ_FIRMAR_AU. */
DELETE FROM sigcm.TransicionRol
 WHERE CodigoRol = 'AREA_JEFE'
   AND CodigoTransicion IN ('REQ_DERIVAR_SIN_FIRMA', 'REQ_DERIVAR_SIN_FIRMA_OBS');

UPDATE sigcm.Transicion
   SET RequiereFirma = 1,
       Activo = 1,
       NombreAccion = 'Firmar y remitir a la Oficina de Administracion'
 WHERE CodigoTransicion = 'REQ_FIRMAR_AU';
GO

PRINT 'S047 aplicada: especialista puede firmar y derivar, o derivar sin firmar. La firma del jefe AU sigue obligatoria.';
GO
