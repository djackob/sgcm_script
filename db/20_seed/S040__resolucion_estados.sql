/*
===============================================================================
  SIGCM - S040 : Estados, transiciones, documentos y plazos del modulo Resolucion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Directiva 002-2026-ANIN 7.3.7. Los cinco diagramas de "5. RESOLUCION" son una
  sola maquina con dos entradas (el AU informa; el proveedor solicita) y un
  desvio -el apercibimiento- que solo aplica al incumplimiento reversible
  (7.3.7.2). Analisis en docs/analisis-modulos-modificacion-resolucion.md.

  Ademas agrega al modulo EJECUCION el estado final EJE_RESUELTO y la
  transicion EJE_RESOLVER, que ejecuta la rutina de resolucion al firmarse la
  carta: el contrato se cierra desde aqui, no desde la pantalla de Ejecucion.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Modulo
   SET Activo = 1,
       Ruta   = 'gestion-resolucion',
       Icono  = 'mdi mdi-file-cancel-outline',
       Nombre = 'Resolucion del contrato'
 WHERE CodigoModulo = 'RESOLUCION';
GO

DECLARE @RolModulo TABLE (CodigoRol varchar(40), CodigoModulo varchar(30));
INSERT INTO @RolModulo VALUES
  ('PROVEEDOR','RESOLUCION'),
  ('AREA_ESPECIALISTA','RESOLUCION'), ('AREA_COORDINADOR','RESOLUCION'), ('AREA_JEFE','RESOLUCION'),
  ('ABAST_ESPECIALISTA','RESOLUCION'), ('ABAST_COORDINADOR','RESOLUCION'), ('ABAST_JEFE','RESOLUCION'),
  ('OA','RESOLUCION'), ('ADMIN_SISTEMA','RESOLUCION');
UPDATE d SET d.Activo = 1
  FROM sigcm.RolModulo AS d JOIN @RolModulo AS s ON s.CodigoRol = d.CodigoRol AND s.CodigoModulo = d.CodigoModulo;
INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT s.CodigoRol, s.CodigoModulo FROM @RolModulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS d WHERE d.CodigoRol = s.CodigoRol AND d.CodigoModulo = s.CodigoModulo);
GO

/* ---- Estados ------------------------------------------------------------- */

DECLARE @Estado TABLE (CodigoEstado varchar(60), CodigoModulo varchar(30), Nombre varchar(150), Orden int,
                       EsInicial bit, EsFinal bit, RolResponsable varchar(40) NULL);
INSERT INTO @Estado VALUES
  ('RES_INFORMADA',                 'RESOLUCION', 'Causal informada por el Area usuaria - por remitir a la DEC', 10, 1, 0, 'AREA_JEFE'),
  ('RES_SOLICITADA',                'RESOLUCION', 'Solicitud del proveedor - pronunciamiento del Area usuaria',  15, 0, 0, 'AREA_ESPECIALISTA'),
  ('RES_EN_EVALUACION_DEC',         'RESOLUCION', 'En evaluacion de la DEC',                                     20, 0, 0, 'ABAST_ESPECIALISTA'),
  ('RES_POR_FIRMA_APERCIBIMIENTO',  'RESOLUCION', 'Carta de apercibimiento por firmar (Jefe de Abastecimiento)', 30, 0, 0, 'ABAST_JEFE'),
  ('RES_APERCIBIDO',                'RESOLUCION', 'Apercibido - plazo para cumplir la prestacion',               40, 0, 0, 'PROVEEDOR'),
  ('RES_RESPUESTA_EN_EVALUACION',   'RESOLUCION', 'Respuesta del proveedor en evaluacion del Area usuaria',     50, 0, 0, 'AREA_ESPECIALISTA'),
  ('RES_POR_RESOLVER',              'RESOLUCION', 'Carta de resolucion por firmar (Jefe de Abastecimiento)',     60, 0, 0, 'ABAST_JEFE'),
  ('RES_RESUELTO',                  'RESOLUCION', 'Contrato resuelto',                                           90, 0, 1, NULL),
  ('RES_SUBSANADO',                 'RESOLUCION', 'Incumplimiento subsanado - contrato continua',                91, 0, 1, NULL),
  ('RES_DESESTIMADA',               'RESOLUCION', 'Desestimada por la DEC',                                      92, 0, 1, NULL),
  ('RES_DENEGADA',                  'RESOLUCION', 'Solicitud del proveedor denegada',                            93, 0, 1, NULL),
  /* Cierre del contrato en Ejecucion. */
  ('EJE_RESUELTO',                  'EJECUCION',  'Contrato resuelto',                                           95, 0, 1, NULL);

UPDATE d SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
             d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable, d.Activo = 1
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;
INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, s.CodigoModulo, s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);
GO

/* ---- Documentos ---------------------------------------------------------- */

DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200), NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('RES_INFORME_AU',            'Informe del Area usuaria sobre la causal de resolucion',  'INF-AU',  0),
  ('RES_SOLICITUD_PROVEEDOR',   'Solicitud de resolucion del proveedor',                    'SOL-RES', 0),
  ('RES_CARTA_APERCIBIMIENTO',  'Carta de apercibimiento de resolucion',                    'CARTA-AP',0),
  ('RES_RESPUESTA_PROVEEDOR',   'Respuesta del proveedor al apercibimiento',                'RESP',    0),
  ('RES_CARTA_RESOLUCION',      'Carta de resolucion del contrato menor',                   'CARTA-RS',0),
  ('RES_CARTA_RESPUESTA',       'Carta de respuesta negando la resolucion',                 'CARTA',   0);

UPDATE d SET d.Nombre = s.Nombre, d.NumeracionVisible = s.NumeracionVisible, d.AdmiteConsolidado = s.AdmiteConsolidado
  FROM sigcm.TipoDocumento AS d JOIN @TipoDoc AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento;
INSERT INTO sigcm.TipoDocumento (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
SELECT s.CodigoTipoDocumento, 'RESOLUCION', s.Nombre, s.NumeracionVisible, s.AdmiteConsolidado
  FROM @TipoDoc AS s WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento AS d WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento);
GO

DECLARE @DocFirma TABLE (CodigoTipoDocumento varchar(60), CodigoRol varchar(40), OrdenFirma smallint);
INSERT INTO @DocFirma VALUES
  ('RES_CARTA_APERCIBIMIENTO','ABAST_JEFE',1),
  ('RES_CARTA_RESOLUCION','ABAST_JEFE',1);
UPDATE d SET d.OrdenFirma = s.OrdenFirma
  FROM sigcm.TipoDocumentoFirma AS d JOIN @DocFirma AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento AND s.CodigoRol = d.CodigoRol;
INSERT INTO sigcm.TipoDocumentoFirma (CodigoTipoDocumento, CodigoRol, OrdenFirma)
SELECT s.CodigoTipoDocumento, s.CodigoRol, s.OrdenFirma FROM @DocFirma AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumentoFirma AS d WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento AND d.CodigoRol = s.CodigoRol);
GO

/* ---- Transiciones -------------------------------------------------------- */

DECLARE @Tr TABLE (
    CodigoTransicion varchar(70), CodigoModulo varchar(30), CodigoEstadoOrigen varchar(60), CodigoEstadoDestino varchar(60),
    NombreAccion varchar(150), RequiereComentario bit, RequiereFirma bit, DocumentoRequerido varchar(60) NULL,
    EncolaIntegracion bit, OperacionIntegracion varchar(30) NULL, GeneraObservacion bit);
INSERT INTO @Tr VALUES
  ('RES_REMITIR_DEC',             'RESOLUCION', 'RES_INFORMADA',                'RES_EN_EVALUACION_DEC',        'Remitir informe a la DEC',                          0, 0, NULL, 0, NULL, 0),
  ('RES_OPINAR_FAVORABLE',        'RESOLUCION', 'RES_SOLICITADA',               'RES_EN_EVALUACION_DEC',        'Pronunciamiento favorable - remitir a la DEC',      0, 0, NULL, 0, NULL, 0),
  ('RES_OPINAR_DESFAVORABLE',     'RESOLUCION', 'RES_SOLICITADA',               'RES_DENEGADA',                 'Pronunciamiento desfavorable - negar la solicitud', 1, 0, NULL, 0, NULL, 0),
  ('RES_DESESTIMAR',              'RESOLUCION', 'RES_EN_EVALUACION_DEC',        'RES_DESESTIMADA',              'Desestimar',                                        1, 0, NULL, 0, NULL, 0),
  ('RES_APERCIBIR',               'RESOLUCION', 'RES_EN_EVALUACION_DEC',        'RES_POR_FIRMA_APERCIBIMIENTO', 'Requerir cumplimiento bajo apercibimiento',         0, 0, NULL, 0, NULL, 0),
  ('RES_RESOLVER_DIRECTO',        'RESOLUCION', 'RES_EN_EVALUACION_DEC',        'RES_POR_RESOLVER',             'Resolver sin apercibimiento previo',                1, 0, NULL, 0, NULL, 0),
  ('RES_FIRMAR_APERCIBIMIENTO',   'RESOLUCION', 'RES_POR_FIRMA_APERCIBIMIENTO', 'RES_APERCIBIDO',               'Firmar y notificar la carta de apercibimiento',     0, 1, 'RES_CARTA_APERCIBIMIENTO', 0, NULL, 0),
  ('RES_RESPONDER_APERCIBIMIENTO','RESOLUCION', 'RES_APERCIBIDO',               'RES_RESPUESTA_EN_EVALUACION',  'Responder al apercibimiento',                       0, 0, NULL, 0, NULL, 0),
  ('RES_VENCER_APERCIBIMIENTO',   'RESOLUCION', 'RES_APERCIBIDO',               'RES_POR_RESOLVER',             'Declarar vencido el plazo sin cumplimiento',        0, 0, NULL, 0, NULL, 0),
  ('RES_EVALUAR_SUBSANADO',       'RESOLUCION', 'RES_RESPUESTA_EN_EVALUACION',  'RES_SUBSANADO',                'Declarar subsanado el incumplimiento',              0, 0, NULL, 0, NULL, 0),
  ('RES_EVALUAR_NO_SUBSANADO',    'RESOLUCION', 'RES_RESPUESTA_EN_EVALUACION',  'RES_POR_RESOLVER',             'Declarar no subsanado - resolver',                  1, 0, NULL, 0, NULL, 0),
  ('RES_FIRMAR_RESOLUCION',       'RESOLUCION', 'RES_POR_RESOLVER',             'RES_RESUELTO',                 'Firmar y notificar la carta de resolucion',         0, 1, 'RES_CARTA_RESOLUCION', 0, NULL, 0),
  /* La ejecuta resolucion.paFirmarResolucion, no una persona. */
  ('EJE_RESOLVER',                'EJECUCION',  'EJE_VIGENTE',                  'EJE_RESUELTO',                 'Resolver el contrato',                              0, 0, NULL, 0, NULL, 0);

UPDATE d SET d.CodigoEstadoOrigen = s.CodigoEstadoOrigen, d.CodigoEstadoDestino = s.CodigoEstadoDestino,
             d.NombreAccion = s.NombreAccion, d.RequiereComentario = s.RequiereComentario, d.RequiereFirma = s.RequiereFirma,
             d.DocumentoRequerido = s.DocumentoRequerido, d.EncolaIntegracion = s.EncolaIntegracion,
             d.OperacionIntegracion = s.OperacionIntegracion, d.GeneraObservacion = s.GeneraObservacion, d.Activo = 1
  FROM sigcm.Transicion AS d JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;
INSERT INTO sigcm.Transicion (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino, NombreAccion,
                              RequiereComentario, RequiereFirma, DocumentoRequerido, EncolaIntegracion, OperacionIntegracion, GeneraObservacion)
SELECT s.CodigoTransicion, s.CodigoModulo, s.CodigoEstadoOrigen, s.CodigoEstadoDestino, s.NombreAccion,
       s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido, s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('RES_REMITIR_DEC','AREA_JEFE'),
  ('RES_OPINAR_FAVORABLE','AREA_ESPECIALISTA'), ('RES_OPINAR_FAVORABLE','AREA_JEFE'),
  ('RES_OPINAR_DESFAVORABLE','AREA_ESPECIALISTA'), ('RES_OPINAR_DESFAVORABLE','AREA_JEFE'),
  ('RES_DESESTIMAR','ABAST_ESPECIALISTA'), ('RES_DESESTIMAR','ABAST_COORDINADOR'),
  ('RES_APERCIBIR','ABAST_ESPECIALISTA'), ('RES_APERCIBIR','ABAST_COORDINADOR'),
  ('RES_RESOLVER_DIRECTO','ABAST_ESPECIALISTA'), ('RES_RESOLVER_DIRECTO','ABAST_COORDINADOR'),
  ('RES_FIRMAR_APERCIBIMIENTO','ABAST_JEFE'),
  ('RES_RESPONDER_APERCIBIMIENTO','PROVEEDOR'),
  ('RES_VENCER_APERCIBIMIENTO','ABAST_ESPECIALISTA'), ('RES_VENCER_APERCIBIMIENTO','ABAST_COORDINADOR'),
  ('RES_EVALUAR_SUBSANADO','AREA_ESPECIALISTA'), ('RES_EVALUAR_SUBSANADO','AREA_JEFE'),
  ('RES_EVALUAR_NO_SUBSANADO','AREA_ESPECIALISTA'), ('RES_EVALUAR_NO_SUBSANADO','AREA_JEFE'),
  ('RES_FIRMAR_RESOLUCION','ABAST_JEFE'),
  ('EJE_RESOLVER','ABAST_JEFE');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol FROM @TrRol AS s
 WHERE EXISTS (SELECT 1 FROM sigcm.Transicion AS t WHERE t.CodigoTransicion = s.CodigoTransicion)
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

/* ---- Plazos -------------------------------------------------------------- */

DECLARE @Regla TABLE (CodigoRegla varchar(60), Nombre varchar(200), CodigoEstadoInicio varchar(60),
                      Dias int, TipoDia varchar(10), Ampliable bit, BaseNormativa varchar(200));
INSERT INTO @Regla VALUES
  /* Dias = 1 es marcador: el plazo real lo elige la DEC dentro del 10-15 % del
     plazo vigente y lo fija F018 al firmar la carta. */
  ('RES_SUBSANACION_APERCIBIMIENTO', 'Plazo para cumplir la prestacion bajo apercibimiento', 'RES_APERCIBIDO', 1, 'CALENDARIO', 0,
   'Directiva 002-2026-ANIN 7.3.7.2.b');

UPDATE d SET d.Nombre = s.Nombre, d.CodigoEstadoInicio = s.CodigoEstadoInicio, d.Dias = s.Dias, d.TipoDia = s.TipoDia,
             d.Ampliable = s.Ampliable, d.BaseNormativa = s.BaseNormativa, d.Activo = 1
  FROM sigcm.PlazoRegla AS d JOIN @Regla AS s ON s.CodigoRegla = d.CodigoRegla;
INSERT INTO sigcm.PlazoRegla (CodigoRegla, CodigoModulo, Nombre, CodigoEstadoInicio, Dias, TipoDia, Ampliable, BaseNormativa, Activo)
SELECT s.CodigoRegla, 'RESOLUCION', s.Nombre, s.CodigoEstadoInicio, s.Dias, s.TipoDia, s.Ampliable, s.BaseNormativa, 1
  FROM @Regla AS s WHERE NOT EXISTS (SELECT 1 FROM sigcm.PlazoRegla AS d WHERE d.CodigoRegla = s.CodigoRegla);
GO

PRINT 'S040 aplicada: modulo RESOLUCION activo, estados, transiciones, documentos y plazo; EJE_RESUELTO en Ejecucion.';
GO
