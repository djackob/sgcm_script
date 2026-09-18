/*
===============================================================================
  SIGCM - S039 : Estados, transiciones, documentos y plazos del modulo
                 Modificacion-Ampliacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Directiva 002-2026-ANIN 7.3.4 y 7.3.5. Bizagi "4. MODIFICACION-AMPLIACION".
  Es CONFIGURACION: sin estas filas el modulo no avanza.

  Un modulo (MODIFICACION, esquema ampliacion) y dos cadenas:

    MOD_  modificacion del contrato: la sustenta el AU, la DEC emite el acta,
          la firma el jefe de Abastecimiento y la suscribe el proveedor.
    AMP_  ampliacion de plazo: la pide el proveedor, la DEC la remite al AU
          (2 habiles), el AU opina (3 habiles), la DEC decide y notifica por
          correo (7 habiles; sin pronunciamiento se entiende aceptada).

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
       Ruta   = 'gestion-modificacion',
       Icono  = 'mdi mdi-file-document-edit-outline',
       Nombre = 'Modificacion y ampliacion'
 WHERE CodigoModulo = 'MODIFICACION';
GO

DECLARE @RolModulo TABLE (CodigoRol varchar(40), CodigoModulo varchar(30));
INSERT INTO @RolModulo VALUES
  ('PROVEEDOR','MODIFICACION'),
  ('AREA_ESPECIALISTA','MODIFICACION'), ('AREA_COORDINADOR','MODIFICACION'), ('AREA_JEFE','MODIFICACION'),
  ('ABAST_ESPECIALISTA','MODIFICACION'), ('ABAST_COORDINADOR','MODIFICACION'), ('ABAST_JEFE','MODIFICACION'),
  ('OA','MODIFICACION'), ('ADMIN_SISTEMA','MODIFICACION');

UPDATE d SET d.Activo = 1
  FROM sigcm.RolModulo AS d JOIN @RolModulo AS s ON s.CodigoRol = d.CodigoRol AND s.CodigoModulo = d.CodigoModulo;
INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT s.CodigoRol, s.CodigoModulo FROM @RolModulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS d WHERE d.CodigoRol = s.CodigoRol AND d.CodigoModulo = s.CodigoModulo);
GO

/* ---- Estados ------------------------------------------------------------- */

DECLARE @Estado TABLE (CodigoEstado varchar(60), Nombre varchar(150), Orden int,
                       EsInicial bit, EsFinal bit, RolResponsable varchar(40) NULL);
INSERT INTO @Estado VALUES
  /* Modificacion. EsInicial solo en MOD_PRESENTADA: las rutinas eligen el
     arranque por codigo segun el origen. */
  ('MOD_PRESENTADA',          'Solicitud del proveedor - evaluacion del Area usuaria',      10, 1, 0, 'AREA_ESPECIALISTA'),
  ('MOD_EN_SUSTENTO_AU',      'Elaborando sustento y justificacion (Area usuaria)',         20, 0, 0, 'AREA_ESPECIALISTA'),
  ('MOD_POR_REMITIR_AU',      'Sustento listo - por remitir a la DEC (Jefe AU)',           30, 0, 0, 'AREA_JEFE'),
  ('MOD_RECHAZADA_AU',        'Rechazada por el Area usuaria - por remitir informe',       35, 0, 0, 'AREA_JEFE'),
  ('MOD_EN_EVALUACION_DEC',   'En evaluacion de la DEC',                                   40, 0, 0, 'ABAST_ESPECIALISTA'),
  ('MOD_POR_FIRMA_ACTA',      'Acta de modificacion por firmar (Jefe de Abastecimiento)',  50, 0, 0, 'ABAST_JEFE'),
  ('MOD_POR_SUSCRIPCION',     'Acta por suscribir por el proveedor',                       60, 0, 0, 'PROVEEDOR'),
  ('MOD_APROBADA',            'Modificacion aprobada',                                     90, 0, 1, NULL),
  ('MOD_DENEGADA',            'Modificacion denegada',                                     95, 0, 1, NULL),

  /* Ampliacion de plazo */
  ('AMP_PRESENTADA',          'Ampliacion solicitada - por remitir al Area usuaria (DEC)', 110, 0, 0, 'ABAST_ESPECIALISTA'),
  ('AMP_EN_OPINION_AU',       'En opinion tecnica del Area usuaria',                       120, 0, 0, 'AREA_ESPECIALISTA'),
  ('AMP_EN_DECISION_DEC',     'Opinion recibida - por decidir la DEC',                     130, 0, 0, 'ABAST_ESPECIALISTA'),
  ('AMP_APROBADA',            'Ampliacion de plazo aprobada',                              190, 0, 1, NULL),
  ('AMP_DENEGADA',            'Ampliacion de plazo denegada',                              195, 0, 1, NULL);

UPDATE d SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
             d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable, d.Activo = 1
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;
INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'MODIFICACION', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);
GO

/* ---- Documentos ---------------------------------------------------------- */

DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200), NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('MOD_SOLICITUD',          'Solicitud de modificacion del contrato',                 'SOL-MOD', 0),
  ('MOD_INFORME_AU',         'Informe de sustento del Area usuaria (modificacion)',    'INF-AU',  0),
  ('MOD_INFORME_DEC',        'Informe de la DEC sobre la modificacion',                'INF-DEC', 0),
  ('MOD_ACTA_MODIFICACION',  'Acta de modificacion del contrato menor',                'ACTA',    0),
  ('MOD_CARTA_RESPUESTA',    'Carta de respuesta a la solicitud de modificacion',      'CARTA',   0),
  ('AMP_SOLICITUD',          'Carta de solicitud de ampliacion de plazo',              'SOL-AMP', 0),
  ('AMP_INFORME_AU',         'Informe de opinion del Area usuaria (ampliacion)',       'INF-AU',  0),
  ('AMP_CARTA_RESPUESTA',    'Carta de respuesta a la ampliacion de plazo',            'CARTA',   0);

UPDATE d SET d.Nombre = s.Nombre, d.NumeracionVisible = s.NumeracionVisible, d.AdmiteConsolidado = s.AdmiteConsolidado
  FROM sigcm.TipoDocumento AS d JOIN @TipoDoc AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento;
INSERT INTO sigcm.TipoDocumento (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
SELECT s.CodigoTipoDocumento, 'MODIFICACION', s.Nombre, s.NumeracionVisible, s.AdmiteConsolidado
  FROM @TipoDoc AS s WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento AS d WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento);
GO

/* El acta la firma digitalmente el jefe de Abastecimiento; el proveedor la
   suscribe desde el portal con una transicion propia (7.3.4.3). */
DECLARE @DocFirma TABLE (CodigoTipoDocumento varchar(60), CodigoRol varchar(40), OrdenFirma smallint);
INSERT INTO @DocFirma VALUES ('MOD_ACTA_MODIFICACION','ABAST_JEFE',1);
UPDATE d SET d.OrdenFirma = s.OrdenFirma
  FROM sigcm.TipoDocumentoFirma AS d JOIN @DocFirma AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento AND s.CodigoRol = d.CodigoRol;
INSERT INTO sigcm.TipoDocumentoFirma (CodigoTipoDocumento, CodigoRol, OrdenFirma)
SELECT s.CodigoTipoDocumento, s.CodigoRol, s.OrdenFirma FROM @DocFirma AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumentoFirma AS d WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento AND d.CodigoRol = s.CodigoRol);
GO

/* ---- Transiciones -------------------------------------------------------- */

DECLARE @Tr TABLE (
    CodigoTransicion varchar(70), CodigoEstadoOrigen varchar(60), CodigoEstadoDestino varchar(60),
    NombreAccion varchar(150), RequiereComentario bit, RequiereFirma bit, DocumentoRequerido varchar(60) NULL,
    EncolaIntegracion bit, OperacionIntegracion varchar(30) NULL, GeneraObservacion bit);
INSERT INTO @Tr VALUES
  /* Modificacion */
  ('MOD_ACEPTAR_AU',          'MOD_PRESENTADA',        'MOD_EN_SUSTENTO_AU',    'Aceptar y elaborar sustento',              0, 0, NULL, 0, NULL, 0),
  ('MOD_RECHAZAR_AU',         'MOD_PRESENTADA',        'MOD_RECHAZADA_AU',      'Rechazar con informe de justificacion',    1, 0, NULL, 0, NULL, 0),
  ('MOD_ELEVAR_SUSTENTO',     'MOD_EN_SUSTENTO_AU',    'MOD_POR_REMITIR_AU',    'Elevar sustento al Jefe del Area usuaria', 0, 0, NULL, 0, NULL, 0),
  ('MOD_REMITIR_DEC',         'MOD_POR_REMITIR_AU',    'MOD_EN_EVALUACION_DEC', 'Remitir sustento a la DEC',                0, 0, NULL, 0, NULL, 0),
  ('MOD_REMITIR_RECHAZO_DEC', 'MOD_RECHAZADA_AU',      'MOD_EN_EVALUACION_DEC', 'Remitir informe de rechazo a la DEC',      0, 0, NULL, 0, NULL, 0),
  ('MOD_APROBAR_DEC',         'MOD_EN_EVALUACION_DEC', 'MOD_POR_FIRMA_ACTA',    'Declarar procedente y emitir acta',        0, 0, NULL, 0, NULL, 0),
  ('MOD_DENEGAR_DEC',         'MOD_EN_EVALUACION_DEC', 'MOD_DENEGADA',          'Denegar la modificacion',                  1, 0, NULL, 0, NULL, 0),
  ('MOD_FIRMAR_ACTA',         'MOD_POR_FIRMA_ACTA',    'MOD_POR_SUSCRIPCION',   'Firmar acta de modificacion',              0, 1, 'MOD_ACTA_MODIFICACION', 0, NULL, 0),
  ('MOD_SUSCRIBIR_ACTA',      'MOD_POR_SUSCRIPCION',   'MOD_APROBADA',          'Suscribir el acta de modificacion',        0, 0, NULL, 0, NULL, 0),

  /* Ampliacion */
  ('AMP_DENEGAR_DIRECTO',     'AMP_PRESENTADA',        'AMP_DENEGADA',          'Denegar sin opinion del AU (fuera de plazo o sin sustento)', 1, 0, NULL, 0, NULL, 0),
  ('AMP_REMITIR_AU',          'AMP_PRESENTADA',        'AMP_EN_OPINION_AU',     'Remitir al Area usuaria para opinion',     0, 0, NULL, 0, NULL, 0),
  ('AMP_OPINAR_AU',           'AMP_EN_OPINION_AU',     'AMP_EN_DECISION_DEC',   'Emitir opinion tecnica',                   0, 0, NULL, 0, NULL, 0),
  ('AMP_APROBAR',             'AMP_EN_DECISION_DEC',   'AMP_APROBADA',          'Aprobar la ampliacion de plazo',           0, 0, NULL, 0, NULL, 0),
  ('AMP_DENEGAR',             'AMP_EN_DECISION_DEC',   'AMP_DENEGADA',          'Denegar la ampliacion de plazo',           1, 0, NULL, 0, NULL, 0);

UPDATE d SET d.CodigoEstadoOrigen = s.CodigoEstadoOrigen, d.CodigoEstadoDestino = s.CodigoEstadoDestino,
             d.NombreAccion = s.NombreAccion, d.RequiereComentario = s.RequiereComentario, d.RequiereFirma = s.RequiereFirma,
             d.DocumentoRequerido = s.DocumentoRequerido, d.EncolaIntegracion = s.EncolaIntegracion,
             d.OperacionIntegracion = s.OperacionIntegracion, d.GeneraObservacion = s.GeneraObservacion, d.Activo = 1
  FROM sigcm.Transicion AS d JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;
INSERT INTO sigcm.Transicion (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino, NombreAccion,
                              RequiereComentario, RequiereFirma, DocumentoRequerido, EncolaIntegracion, OperacionIntegracion, GeneraObservacion)
SELECT s.CodigoTransicion, 'MODIFICACION', s.CodigoEstadoOrigen, s.CodigoEstadoDestino, s.NombreAccion,
       s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido, s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('MOD_ACEPTAR_AU','AREA_ESPECIALISTA'), ('MOD_ACEPTAR_AU','AREA_JEFE'),
  ('MOD_RECHAZAR_AU','AREA_ESPECIALISTA'), ('MOD_RECHAZAR_AU','AREA_JEFE'),
  ('MOD_ELEVAR_SUSTENTO','AREA_ESPECIALISTA'),
  ('MOD_REMITIR_DEC','AREA_JEFE'),
  ('MOD_REMITIR_RECHAZO_DEC','AREA_JEFE'),
  ('MOD_APROBAR_DEC','ABAST_ESPECIALISTA'), ('MOD_APROBAR_DEC','ABAST_COORDINADOR'),
  ('MOD_DENEGAR_DEC','ABAST_ESPECIALISTA'), ('MOD_DENEGAR_DEC','ABAST_COORDINADOR'),
  ('MOD_FIRMAR_ACTA','ABAST_JEFE'),
  ('MOD_SUSCRIBIR_ACTA','PROVEEDOR'),
  ('AMP_DENEGAR_DIRECTO','ABAST_ESPECIALISTA'), ('AMP_DENEGAR_DIRECTO','ABAST_COORDINADOR'),
  ('AMP_REMITIR_AU','ABAST_ESPECIALISTA'), ('AMP_REMITIR_AU','ABAST_COORDINADOR'),
  ('AMP_OPINAR_AU','AREA_ESPECIALISTA'), ('AMP_OPINAR_AU','AREA_JEFE'),
  ('AMP_APROBAR','ABAST_ESPECIALISTA'), ('AMP_APROBAR','ABAST_COORDINADOR'),
  ('AMP_DENEGAR','ABAST_ESPECIALISTA'), ('AMP_DENEGAR','ABAST_COORDINADOR');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol FROM @TrRol AS s
 WHERE EXISTS (SELECT 1 FROM sigcm.Transicion AS t WHERE t.CodigoTransicion = s.CodigoTransicion)
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

/* ---- Plazos (7.3.5) ------------------------------------------------------ */

DECLARE @Regla TABLE (CodigoRegla varchar(60), Nombre varchar(200), CodigoEstadoInicio varchar(60),
                      Dias int, TipoDia varchar(10), Ampliable bit, BaseNormativa varchar(200));
INSERT INTO @Regla VALUES
  ('AMP_REMISION_DEC',  'Remision de la solicitud al Area usuaria (2 dias habiles)',      'AMP_PRESENTADA',    2, 'HABIL', 0, 'Directiva 002-2026-ANIN 7.3.5.2'),
  ('AMP_OPINION_AU',    'Informe del Area usuaria sobre la ampliacion (3 dias habiles)',  'AMP_EN_OPINION_AU', 3, 'HABIL', 0, 'Directiva 002-2026-ANIN 7.3.5.2'),
  ('AMP_DECISION_DEC',  'Decision y notificacion de la ampliacion (7 dias habiles; sin pronunciamiento se entiende aceptada)', 'AMP_PRESENTADA', 7, 'HABIL', 0, 'Directiva 002-2026-ANIN 7.3.5.4');

UPDATE d SET d.Nombre = s.Nombre, d.CodigoEstadoInicio = s.CodigoEstadoInicio, d.Dias = s.Dias, d.TipoDia = s.TipoDia,
             d.Ampliable = s.Ampliable, d.BaseNormativa = s.BaseNormativa, d.Activo = 1
  FROM sigcm.PlazoRegla AS d JOIN @Regla AS s ON s.CodigoRegla = d.CodigoRegla;
INSERT INTO sigcm.PlazoRegla (CodigoRegla, CodigoModulo, Nombre, CodigoEstadoInicio, Dias, TipoDia, Ampliable, BaseNormativa, Activo)
SELECT s.CodigoRegla, 'MODIFICACION', s.Nombre, s.CodigoEstadoInicio, s.Dias, s.TipoDia, s.Ampliable, s.BaseNormativa, 1
  FROM @Regla AS s WHERE NOT EXISTS (SELECT 1 FROM sigcm.PlazoRegla AS d WHERE d.CodigoRegla = s.CodigoRegla);
GO

PRINT 'S039 aplicada: modulo MODIFICACION activo, estados MOD_/AMP_, transiciones, documentos y plazos.';
GO
