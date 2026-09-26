/*
===============================================================================
  SIGCM - S048 : Cotizaciones y orden de compra (bien, servicio, consultoria)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Locacion sigue con la invitacion uno a uno (S016).
  Bien, servicio y consultoria, tras la conformidad:
    - Registrar cotizaciones (dos o mas, Anexo 8)
    - Confirmar y solicitar CCP
  El bien se perfecciona con orden de compra (sin encolar la OS de SIGA).
  Servicio y consultoria siguen emitiendo orden de servicio.

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
  ('REQ_INICIAR_COTIZACIONES', 'REQ_CONFORME', 'REQ_INDAGACION_MERCADO',
   'Registrar cotizaciones', 0, 0, NULL, 0, NULL, 0),

  ('REQ_CERRAR_COTIZACIONES', 'REQ_INDAGACION_MERCADO', 'REQ_CCP_SOLICITADO',
   'Confirmar cotizaciones y solicitar CCP', 0, 0, 'REQ_ANEXO_8_COTIZACIONES', 0, NULL, 0),

  ('REQ_EMITIR_OC', 'REQ_CUADRO_GENERADO', 'REQ_OS_EMITIDA',
   'Emitir orden de compra', 0, 0, NULL, 0, NULL, 0);

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
       EncolaIntegracion, OperacionIntegracion, GeneraObservacion)
SELECT s.CodigoTransicion, 'REQUERIMIENTO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('REQ_INICIAR_COTIZACIONES', 'ABAST_ESPECIALISTA'),
  ('REQ_INICIAR_COTIZACIONES', 'ABAST_COORDINADOR'),
  ('REQ_CERRAR_COTIZACIONES', 'ABAST_ESPECIALISTA'),
  ('REQ_EMITIR_OC', 'ABAST_ESPECIALISTA');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.TransicionRol AS d
        WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

PRINT 'S048 aplicada: cotizaciones para bien, servicio y consultoria; orden de compra para bienes.';
GO
