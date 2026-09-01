/*
===============================================================================
  SIGCM - S004 : Locacion posterior al Area usuaria
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Completa la maquina de estados de Requerimiento a partir de REQ_CONFORME,
  segun la ERF de contratacion de locadores (contratos menores <= 8 UIT):

    - Filtros de idoneidad (PID o conformidad manual)
    - Solicitud y carga de la CCP (transito por UP, 1 dia habil)
    - Emision de la Orden de Servicio y notificacion al locador

  Tambien siembra:
    - AREA_COORDINADOR ya entra al modulo en S003
    - Tipos Anexo 6 (cotizacion), Anexo 7 (DJ), memorando CCP, CCP y O/S
    - Plazos de 2 / 2 / 1 dias habiles confirmados por la ERF

  El circuito AU hasta REQ_CONFORME vive en S003. Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Estados posteriores a la conformidad                                    */
/* -------------------------------------------------------------------------- */

DECLARE @Estado TABLE (CodigoEstado varchar(60), Nombre varchar(150), Orden int,
                       EsInicial bit, EsFinal bit, RolResponsable varchar(40) NULL);
INSERT INTO @Estado VALUES
  ('REQ_FILTROS',         'Aprobado para indagacion / filtros de idoneidad', 90,  0, 0, 'ABAST_ESPECIALISTA'),
  ('REQ_CCP_SOLICITADO',  'Solicitado a CCP (OPP)',                        100, 0, 0, 'OPP'),
  ('REQ_CCP_CARGADA',     'CCP cargada, lista para generar el cuadro SIGA',  110, 0, 0, 'ABAST_ESPECIALISTA'),
  ('REQ_CUADRO_GENERADO', 'Cuadro de adquisicion generado en SIGA',          115, 0, 0, 'ABAST_ESPECIALISTA'),
  ('REQ_OS_EMITIDA',      'Orden de servicio emitida',                       120, 0, 0, 'ABAST_ESPECIALISTA'),
  ('REQ_NOTIFICADO',      'Orden notificada, inicio del plazo de ejecucion', 130, 0, 1, NULL);

UPDATE d
   SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'REQUERIMIENTO', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);
GO

/* -------------------------------------------------------------------------- */
/* 2. Tipos de documento de la rama locacion                                  */
/* -------------------------------------------------------------------------- */

DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200),
                        NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('REQ_COTIZACION_ANEXO6', 'Cotizacion del locador (Anexo 6)',              'ANX6', 0),
  ('REQ_DJ_ANEXO7',         'Declaracion jurada del locador (Anexo 7)',      'ANX7', 0),
  ('REQ_MEMO_CCP',          'Memorando de solicitud de CCP',                 'MEMO', 0),
  ('REQ_CCP',               'Certificacion de credito presupuestario',       'CCP',  0),
  ('REQ_MEMO_UP_CCP',       'Memorando de respuesta de la UP (CCP)',         'MEMO UP', 0),
  ('REQ_PREVISION_PRESUP',  'Prevision presupuestal aprobada por OPP',       'PREV.', 0),
  ('REQ_ORDEN_SERVICIO',    'Orden de servicio',                             'OS',   0);

UPDATE d SET d.Nombre = s.Nombre, d.NumeracionVisible = s.NumeracionVisible,
             d.AdmiteConsolidado = s.AdmiteConsolidado
  FROM sigcm.TipoDocumento AS d
  JOIN @TipoDoc AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento;

INSERT INTO sigcm.TipoDocumento (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
SELECT s.CodigoTipoDocumento, 'REQUERIMIENTO', s.Nombre, s.NumeracionVisible, s.AdmiteConsolidado
  FROM @TipoDoc AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento AS d
                    WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento);
GO

/* -------------------------------------------------------------------------- */
/* 3. Transiciones                                                            */
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
  ('REQ_GENERAR_CUADRO', 'REQ_CCP_CARGADA', 'REQ_CUADRO_GENERADO',
   'Generar cuadro de adquisicion', 0, 0, NULL, 1, 'CREAR_CUADRO_ADQUISICION', 0),

  ('REQ_EMITIR_OS', 'REQ_CUADRO_GENERADO', 'REQ_OS_EMITIDA',
   'Emitir orden de servicio', 0, 0, NULL, 1, 'CREAR_ORDEN_SERVICIO', 0);

UPDATE d
   SET d.CodigoEstadoOrigen = s.CodigoEstadoOrigen,
       d.CodigoEstadoDestino = s.CodigoEstadoDestino,
       d.NombreAccion = s.NombreAccion,
       d.RequiereComentario = s.RequiereComentario,
       d.RequiereFirma = s.RequiereFirma,
       d.DocumentoRequerido = s.DocumentoRequerido,
       d.EncolaIntegracion = s.EncolaIntegracion,
       d.OperacionIntegracion = s.OperacionIntegracion,
       d.GeneraObservacion = s.GeneraObservacion
  FROM sigcm.Transicion AS d JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion
      (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
       NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
       EncolaIntegracion, OperacionIntegracion, GeneraObservacion)
SELECT s.CodigoTransicion, 'REQUERIMIENTO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('REQ_INICIAR_FILTROS','ABAST_ESPECIALISTA'),
  ('REQ_INICIAR_FILTROS','ABAST_COORDINADOR'),
  ('REQ_REGISTRAR_CCP','OPP'),
  ('REQ_GENERAR_CUADRO','ABAST_ESPECIALISTA'),
  ('REQ_GENERAR_CUADRO','ABAST_COORDINADOR'),
  ('REQ_EMITIR_OS','ABAST_ESPECIALISTA'),
  ('REQ_EMITIR_OS','ABAST_COORDINADOR'),
  ('REQ_NOTIFICAR_OS','ABAST_ESPECIALISTA'),
  ('REQ_NOTIFICAR_OS','ABAST_COORDINADOR');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 4. Plazos de la ERF (activos: ya ratificados en mesa de trabajo)           */
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
  ('REQ_REVISION_DEC',
   'Revision tecnica del requerimiento por la DEC',
   'REQ_EN_EVAL_DEC', 2, 'HABIL', 0,
   'ERF locacion <= 8 UIT - 2 dias habiles'),

  ('REQ_SUBSANACION',
   'Subsanacion de observaciones por el area usuaria',
   'REQ_OBSERVADO', 2, 'HABIL', 1,
   'ERF locacion <= 8 UIT - 2 dias habiles'),

  ('REQ_CCP_UP',
   'Emision de la certificacion presupuestaria por la UP',
   'REQ_CCP_SOLICITADO', 1, 'HABIL', 0,
   'ERF locacion <= 8 UIT - 1 dia habil');

UPDATE d
   SET d.Nombre = s.Nombre, d.CodigoEstadoInicio = s.CodigoEstadoInicio, d.Dias = s.Dias,
       d.TipoDia = s.TipoDia, d.Ampliable = s.Ampliable, d.BaseNormativa = s.BaseNormativa
  FROM sigcm.PlazoRegla AS d JOIN @Regla AS s ON s.CodigoRegla = d.CodigoRegla;

INSERT INTO sigcm.PlazoRegla
      (CodigoRegla, CodigoModulo, Nombre, CodigoEstadoInicio, Dias, TipoDia,
       Ampliable, BaseNormativa, Activo)
SELECT s.CodigoRegla, 'REQUERIMIENTO', s.Nombre, s.CodigoEstadoInicio, s.Dias, s.TipoDia,
       s.Ampliable, s.BaseNormativa, 1
  FROM @Regla AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.PlazoRegla AS d WHERE d.CodigoRegla = s.CodigoRegla);
GO

DECLARE @msg varchar(300) =
    'S004 aplicada: '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Estado WHERE CodigoModulo = 'REQUERIMIENTO')) + ' estados REQ, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Transicion WHERE CodigoModulo = 'REQUERIMIENTO')) + ' transiciones REQ.';
PRINT @msg;
GO
