/*
===============================================================================
  SIGCM - S017 : Estados, transiciones y documentos del modulo Pago
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Maquina de estados de Gestion de Entregables, Conformidades y Pagos (EDS).
  Es CONFIGURACION: sin estas filas el modulo no avanza. Se instala en todos
  los ambientes.

  Cadena:

    Locador     PAG_PENDIENTE -> PAG_ENTREGABLE_PRESENTADO
                  (observado)  -> PAG_OBSERVADO_AU -> (subsana) PRESENTADO
    AU esp      PRESENTADO -> PAG_CONFORMIDAD_PEND_FIRMA
    AU jefe     firma Anexo 11 -> PAG_CONFORMIDAD_APROBADA
    DEC         checklist 9 + Anexo 10 -> PAG_EXPEDIENTE_LIQUIDADO
    UC          devengado SIAF -> PAG_DEVENGADO_APROBADO
                  o devuelve a DEC / AU
    UT          giro SIAF + CCI -> PAG_PAGO_EFECTUADO (cierre)

  Prefijo PAG_ porque sigcm.Estado.CodigoEstado es global.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Activar el modulo y su ruta                                             */
/* -------------------------------------------------------------------------- */

UPDATE sigcm.Modulo
   SET Activo = 1,
       Ruta   = 'gestion-pago',
       Icono  = 'mdi mdi-cash-multiple',
       Nombre = 'Entregables y pagos'
 WHERE CodigoModulo = 'PAGO';
GO

/* -------------------------------------------------------------------------- */
/* 2. Matriz de acceso                                                        */
/* -------------------------------------------------------------------------- */

DECLARE @RolModulo TABLE (CodigoRol varchar(40), CodigoModulo varchar(30));
INSERT INTO @RolModulo VALUES
  ('PROVEEDOR','PAGO'),
  ('AREA_ESPECIALISTA','PAGO'), ('AREA_COORDINADOR','PAGO'), ('AREA_JEFE','PAGO'),
  ('ABAST_ESPECIALISTA','PAGO'), ('ABAST_COORDINADOR','PAGO'), ('ABAST_JEFE','PAGO'),
  ('DAI','PAGO'),
  ('CONTABILIDAD','PAGO'),
  ('TESORERIA','PAGO'),
  ('OA','PAGO'),
  ('ADMIN_SISTEMA','PAGO');

UPDATE d SET d.Activo = 1
  FROM sigcm.RolModulo AS d
  JOIN @RolModulo AS s ON s.CodigoRol = d.CodigoRol AND s.CodigoModulo = d.CodigoModulo;

INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT s.CodigoRol, s.CodigoModulo
  FROM @RolModulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS d
                    WHERE d.CodigoRol = s.CodigoRol AND d.CodigoModulo = s.CodigoModulo);
GO

/* -------------------------------------------------------------------------- */
/* 3. Estados                                                                 */
/* -------------------------------------------------------------------------- */

DECLARE @Estado TABLE (CodigoEstado varchar(60), Nombre varchar(150), Orden int,
                       EsInicial bit, EsFinal bit, RolResponsable varchar(40) NULL);
INSERT INTO @Estado VALUES
  ('PAG_PENDIENTE',                'Entregable pendiente de presentacion',           10, 1, 0, 'PROVEEDOR'),
  ('PAG_ENTREGABLE_PRESENTADO',    'Entregable presentado - revision AU',            20, 0, 0, 'AREA_ESPECIALISTA'),
  ('PAG_OBSERVADO_AU',             'Observado por el Area usuaria',                  25, 0, 0, 'PROVEEDOR'),
  ('PAG_CONFORMIDAD_PEND_FIRMA',   'Acta de conformidad por firmar (Jefe AU)',       30, 0, 0, 'AREA_JEFE'),
  ('PAG_CONFORMIDAD_APROBADA',     'Conformidad aprobada - liquidacion DEC',         40, 0, 0, 'ABAST_ESPECIALISTA'),
  ('PAG_EXPEDIENTE_LIQUIDADO',     'Expediente liquidado - control previo UC',       50, 0, 0, 'CONTABILIDAD'),
  ('PAG_OBS_UC_DEC',               'Observado por Contabilidad - vuelve a DEC',      55, 0, 0, 'ABAST_ESPECIALISTA'),
  ('PAG_OBS_UC_AU',                'Observado por Contabilidad - vuelve a AU',       56, 0, 0, 'AREA_ESPECIALISTA'),
  ('PAG_DEVENGADO_APROBADO',       'Devengado aprobado - giro Tesoreria',            60, 0, 0, 'TESORERIA'),
  ('PAG_PAGO_EFECTUADO',           'Pago efectuado (cierre)',                        90, 0, 1, NULL);

UPDATE d
   SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable, d.Activo = 1
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'PAGO', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);
GO

/* -------------------------------------------------------------------------- */
/* 4. Tipos de documento                                                      */
/* -------------------------------------------------------------------------- */

DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200),
                        NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('PAG_INFORME_ENTREGABLE',    'Informe de actividades / entregable',                    'INF',    0),
  ('PAG_RHE_PDF',               'Recibo por Honorarios Electronico (PDF)',                'RHE',    0),
  ('PAG_RHE_XML',               'Recibo por Honorarios Electronico (XML)',                'RHE-XML',0),
  ('PAG_SUSPENSION_4TA',        'Constancia de suspension de retenciones de 4ta',         '4TA',    0),
  ('PAG_ACTA_ANEXO11',          'Acta de Conformidad (Anexo 11)',                         'A11',    0),
  ('PAG_CHECKLIST_ANEXO9',      'Checklist de control de pagos (Anexo 9)',                'A9',     0),
  ('PAG_PENALIDAD_ANEXO10',     'Liquidacion de penalidad por mora (Anexo 10)',           'A10',    0),
  ('PAG_NOTA_PAGO_SIAF',        'Nota de pago SIAF',                                      'NP',     0),
  ('PAG_CONSTANCIA_TRANSFERENCIA','Constancia de transferencia electronica',              'CCI',    0),
  ('PAG_PAPELETA_PENALIDAD',    'Papeleta de deposito de penalidades ANIN',               'PEN',    0);

UPDATE d SET d.Nombre = s.Nombre, d.NumeracionVisible = s.NumeracionVisible,
             d.AdmiteConsolidado = s.AdmiteConsolidado
  FROM sigcm.TipoDocumento AS d
  JOIN @TipoDoc AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento;

INSERT INTO sigcm.TipoDocumento (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
SELECT s.CodigoTipoDocumento, 'PAGO', s.Nombre, s.NumeracionVisible, s.AdmiteConsolidado
  FROM @TipoDoc AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento AS d
                    WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento);
GO

DECLARE @DocFirma TABLE (CodigoTipoDocumento varchar(60), CodigoRol varchar(40), OrdenFirma smallint);
INSERT INTO @DocFirma VALUES
  ('PAG_ACTA_ANEXO11','AREA_JEFE',1);

UPDATE d SET d.OrdenFirma = s.OrdenFirma
  FROM sigcm.TipoDocumentoFirma AS d
  JOIN @DocFirma AS s
    ON s.CodigoTipoDocumento = d.CodigoTipoDocumento AND s.CodigoRol = d.CodigoRol;

INSERT INTO sigcm.TipoDocumentoFirma (CodigoTipoDocumento, CodigoRol, OrdenFirma)
SELECT s.CodigoTipoDocumento, s.CodigoRol, s.OrdenFirma
  FROM @DocFirma AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumentoFirma AS d
                    WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento AND d.CodigoRol = s.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 5. Transiciones                                                            */
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
  ('PAG_PRESENTAR',          'PAG_PENDIENTE',              'PAG_ENTREGABLE_PRESENTADO',
   'Presentar entregable y RHE', 0, 0, NULL, 0, NULL, 0),

  ('PAG_SUBSANAR',           'PAG_OBSERVADO_AU',           'PAG_ENTREGABLE_PRESENTADO',
   'Subsanar observaciones del Area usuaria', 0, 0, NULL, 0, NULL, 0),

  ('PAG_OBSERVAR_AU',        'PAG_ENTREGABLE_PRESENTADO',  'PAG_OBSERVADO_AU',
   'Observar entregable (Area usuaria)', 1, 0, NULL, 0, NULL, 0),

  ('PAG_APROBAR_TECNICO',    'PAG_ENTREGABLE_PRESENTADO',  'PAG_CONFORMIDAD_PEND_FIRMA',
   'Aprobar conformidad tecnica', 0, 0, NULL, 0, NULL, 0),

  ('PAG_FIRMAR_ANEXO11',     'PAG_CONFORMIDAD_PEND_FIRMA', 'PAG_CONFORMIDAD_APROBADA',
   'Firmar Acta de Conformidad (Anexo 11)', 0, 1, 'PAG_ACTA_ANEXO11', 0, NULL, 0),

  ('PAG_LIQUIDAR',           'PAG_CONFORMIDAD_APROBADA',   'PAG_EXPEDIENTE_LIQUIDADO',
   'Completar checklist y liquidar (Anexos 9 y 10)', 0, 0, NULL, 0, NULL, 0),

  ('PAG_OBSERVAR_UC_DEC',    'PAG_EXPEDIENTE_LIQUIDADO',   'PAG_OBS_UC_DEC',
   'Devolver a DEC con observaciones contables', 1, 0, NULL, 0, NULL, 0),

  ('PAG_OBSERVAR_UC_AU',     'PAG_EXPEDIENTE_LIQUIDADO',   'PAG_OBS_UC_AU',
   'Devolver al Area usuaria con observaciones', 1, 0, NULL, 0, NULL, 0),

  ('PAG_DEVOLVER_UC_DEC',    'PAG_OBS_UC_DEC',             'PAG_EXPEDIENTE_LIQUIDADO',
   'Remitir subsanado a Contabilidad', 0, 0, NULL, 0, NULL, 0),

  ('PAG_DEVOLVER_UC_AU',     'PAG_OBS_UC_AU',              'PAG_EXPEDIENTE_LIQUIDADO',
   'Remitir subsanado a Contabilidad', 0, 0, NULL, 0, NULL, 0),

  ('PAG_APROBAR_DEVENGADO',  'PAG_EXPEDIENTE_LIQUIDADO',   'PAG_DEVENGADO_APROBADO',
   'Registrar devengado SIAF / MADAF', 0, 0, NULL, 0, NULL, 0),

  ('PAG_CONFIRMAR_PAGO',     'PAG_DEVENGADO_APROBADO',     'PAG_PAGO_EFECTUADO',
   'Registrar giro SIAF y abono CCI', 0, 0, NULL, 0, NULL, 0);

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
  FROM sigcm.Transicion AS d JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion
      (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
       NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
       EncolaIntegracion, OperacionIntegracion, GeneraObservacion)
SELECT s.CodigoTransicion, 'PAGO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('PAG_PRESENTAR','PROVEEDOR'),
  ('PAG_SUBSANAR','PROVEEDOR'),
  ('PAG_OBSERVAR_AU','AREA_ESPECIALISTA'),
  ('PAG_APROBAR_TECNICO','AREA_ESPECIALISTA'),
  ('PAG_FIRMAR_ANEXO11','AREA_JEFE'),
  ('PAG_LIQUIDAR','ABAST_ESPECIALISTA'), ('PAG_LIQUIDAR','ABAST_COORDINADOR'),
  ('PAG_OBSERVAR_UC_DEC','CONTABILIDAD'),
  ('PAG_OBSERVAR_UC_AU','CONTABILIDAD'),
  ('PAG_DEVOLVER_UC_DEC','ABAST_ESPECIALISTA'),
  ('PAG_DEVOLVER_UC_AU','AREA_ESPECIALISTA'), ('PAG_DEVOLVER_UC_AU','AREA_JEFE'),
  ('PAG_APROBAR_DEVENGADO','CONTABILIDAD'),
  ('PAG_CONFIRMAR_PAGO','TESORERIA');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 6. Plazos de la EDS                                                        */
/* -------------------------------------------------------------------------- */

DECLARE @Regla TABLE (
    CodigoRegla        varchar(60),
    Nombre             varchar(200),
    CodigoEstadoInicio varchar(60),
    Dias               int,
    TipoDia            varchar(10),
    Ampliable          bit,
    BaseNormativa      varchar(200)
);
INSERT INTO @Regla VALUES
  ('PAG_REVISION_AU',
   'Revision tecnica del Area usuaria (7 dias calendario desde el dia siguiente)',
   'PAG_ENTREGABLE_PRESENTADO', 7, 'CALENDARIO', 0,
   'Directiva 002-2026-ANIN - conformidad tecnica 7 dias calendario'),

  ('PAG_SUBSANACION_AU',
   'Subsanacion del locador (tope 30% del plazo del entregable; se calcula en F012)',
   'PAG_OBSERVADO_AU', 1, 'CALENDARIO', 1,
   'Directiva 002-2026-ANIN - subsanacion sin penalidad si es oportuna'),

  ('PAG_LIQUIDACION_DEC',
   'Checklist y liquidacion DEC (3 dias habiles)',
   'PAG_CONFORMIDAD_APROBADA', 3, 'HABIL', 0,
   'Directiva 002-2026-ANIN - Anexo 9 / Anexo 10'),

  ('PAG_CONTROL_PREVIO_UC',
   'Control previo contable (2 dias habiles)',
   'PAG_EXPEDIENTE_LIQUIDADO', 2, 'HABIL', 0,
   'Directiva 002-2026-ANIN - Unidad de Contabilidad'),

  ('PAG_PAGO_GLOBAL',
   'Pago neto (10 dias habiles desde la conformidad tecnica; +5 justificados)',
   'PAG_CONFORMIDAD_APROBADA', 10, 'HABIL', 1,
   'Directiva 002-2026-ANIN - plazo global de pago');

UPDATE d
   SET d.Nombre = s.Nombre, d.CodigoEstadoInicio = s.CodigoEstadoInicio, d.Dias = s.Dias,
       d.TipoDia = s.TipoDia, d.Ampliable = s.Ampliable, d.BaseNormativa = s.BaseNormativa,
       d.Activo = 1
  FROM sigcm.PlazoRegla AS d JOIN @Regla AS s ON s.CodigoRegla = d.CodigoRegla;

INSERT INTO sigcm.PlazoRegla
      (CodigoRegla, CodigoModulo, Nombre, CodigoEstadoInicio, Dias, TipoDia,
       Ampliable, BaseNormativa, Activo)
SELECT s.CodigoRegla, 'PAGO', s.Nombre, s.CodigoEstadoInicio, s.Dias, s.TipoDia,
       s.Ampliable, s.BaseNormativa, 1
  FROM @Regla AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.PlazoRegla AS d WHERE d.CodigoRegla = s.CodigoRegla);
GO

PRINT 'S017 aplicada: modulo PAGO activo, estados, transiciones, documentos y plazos.';
GO
