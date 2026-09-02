/*
===============================================================================
  SIGCM - S003 : Estados, transiciones y documentos del modulo Requerimiento
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Siembra la maquina de estados de Requerimiento a Notificacion, derivada del
  flujo REQ-12 a REQ-31 de Analisis/reglas-negocio-mockup.md.

  Es CONFIGURACION, no datos de prueba: sin estas filas el modulo no tiene por
  donde avanzar. Se instala en todos los ambientes.

  ---------------------------------------------------------------------------
  LA RAMA QUE JUSTIFICA LA MITAD DE LAS TRANSICIONES
  ---------------------------------------------------------------------------
  REQ-14: al firmar, el jefe del Area usuaria remite directo a OA (el jefe de
  la Oficina de Administracion). REQ_REMITIR_OA y REQ_REMITIR_DAI quedan
  declaradas e inactivas: ya no hay un paso extra tras la firma.

  Alcance sembrado: del registro a la revision de la DEC (REQ-12 a REQ-16) mas
  el circuito interno del Area usuaria (Coordinador V.B. y firma del Jefe) y el
  ciclo de observacion. Filtros de idoneidad, CCP y orden de servicio: S004.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Matriz de acceso del modulo                                             */
/* -------------------------------------------------------------------------- */

DECLARE @RolModulo TABLE (CodigoRol varchar(40), CodigoModulo varchar(30));
INSERT INTO @RolModulo VALUES
  ('AREA_JEFE','REQUERIMIENTO'), ('AREA_COORDINADOR','REQUERIMIENTO'),
  ('AREA_ESPECIALISTA','REQUERIMIENTO'),
  ('OA','REQUERIMIENTO'), ('DAI','REQUERIMIENTO'), ('OPP','REQUERIMIENTO'),
  ('ABAST_JEFE','REQUERIMIENTO'), ('ABAST_COORDINADOR','REQUERIMIENTO'),
  ('ABAST_ESPECIALISTA','REQUERIMIENTO'), ('ADMIN_SISTEMA','REQUERIMIENTO');

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
/* 2. Estados                                                                 */
/* -------------------------------------------------------------------------- */

DECLARE @Estado TABLE (CodigoEstado varchar(60), Nombre varchar(150), Orden int,
                       EsInicial bit, EsFinal bit, RolResponsable varchar(40) NULL);
INSERT INTO @Estado VALUES
  ('REQ_BORRADOR',        'Registrar requerimiento',                  10, 1, 0, 'AREA_ESPECIALISTA'),
  ('REQ_DOC_PENDIENTE',   'Elaborar documento tecnico',               20, 0, 0, 'AREA_ESPECIALISTA'),
  ('REQ_PEND_VB_AU',      'Por visto bueno del Coordinador AU',       25, 0, 0, 'AREA_COORDINADOR'),
  ('REQ_PEND_FIRMA_AU',   'Por firmar el Area usuaria',               30, 0, 0, 'AREA_JEFE'),
  ('REQ_FIRMADO_AU',      'Firmado por el Area usuaria',              40, 0, 0, 'AREA_JEFE'),
  ('REQ_EN_EVAL_OA',      'En evaluacion OA',                         50, 0, 0, 'OA'),
  ('REQ_EN_ABAST_JEFE',    'En Abastecimiento - Jefe',                 52, 0, 0, 'ABAST_JEFE'),
  ('REQ_EN_ABAST_COORD',   'En Abastecimiento - Coordinador',          55, 0, 0, 'ABAST_COORDINADOR'),
  ('REQ_EN_EVAL_DEC',     'En revision de la DEC',                    60, 0, 0, 'ABAST_ESPECIALISTA'),
  ('REQ_EN_EVAL_DAI',     'En revision de DAI',                       61, 0, 0, 'DAI'),
  /* La ERF devuelve la observacion al Jefe del Area usuaria. El especialista
     subsana desde ahi (REQ_SUBSANAR sigue habilitado para ambos roles). */
  /* Como CMN_OBSERVADO: el Especialista AU ve la fila en su bandeja y abre la
     subsanacion. El Jefe sigue pudiendo ejecutar REQ_SUBSANAR por TransicionRol. */
  ('REQ_OBSERVADO',       'Observado',                                70, 0, 0, 'AREA_ESPECIALISTA'),
  ('REQ_NO_OBJECION',     'Con mejoras sujetas a no objecion',        75, 0, 0, 'AREA_JEFE'),
  ('REQ_CONFORME',        'Conforme, listo para indagacion',          80, 0, 0, 'ABAST_ESPECIALISTA'),
  ('REQ_ANULADO',         'Anulado',                                 999, 0, 1, NULL);

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
/* 3. Tipos de documento                                                      */
/* -------------------------------------------------------------------------- */

/* REQ-07: un documento tecnico por objeto de contratacion. Son tipos distintos
   y no uno solo con una variante, porque cada uno es un formato oficial con su
   propio contenido y su propia numeracion. */
DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200),
                        NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('REQ_EETT_BIEN',        'Especificaciones tecnicas del bien (Anexo 1)',        'EETT',   0),
  ('REQ_TDR_SERVICIO',     'Terminos de referencia del servicio (Anexo 2)',       'TDR',    0),
  ('REQ_TDR_LOCACION',     'Terminos de referencia de locacion (Anexo 3)',        'TDR-LOC',0),
  ('REQ_TDR_CONSULTORIA',  'Terminos de referencia de consultoria (Anexo 4)',     'TDR-CON',0),
  ('REQ_PROPUESTA_LOCACION','Propuesta del Area usuaria para locacion (Anexo 5)', 'ANX5',   0);

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

/* REQ-10: la firma del documento tecnico es del Jefe o titular del Area
   usuaria. En locacion la ERF agrega la firma previa del Especialista (elabora
   y firma el paquete) y el V.B. del Coordinador, que no es firma de PDF. */
DECLARE @DocFirma TABLE (CodigoTipoDocumento varchar(60), CodigoRol varchar(40), OrdenFirma smallint);
INSERT INTO @DocFirma VALUES
  ('REQ_EETT_BIEN','AREA_JEFE',1),
  ('REQ_TDR_SERVICIO','AREA_JEFE',1),
  ('REQ_TDR_LOCACION','AREA_ESPECIALISTA',1),
  ('REQ_TDR_LOCACION','AREA_JEFE',2),
  ('REQ_TDR_CONSULTORIA','AREA_JEFE',1),
  ('REQ_PROPUESTA_LOCACION','AREA_ESPECIALISTA',1),
  ('REQ_PROPUESTA_LOCACION','AREA_JEFE',2);

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
/* 4. Transiciones                                                            */
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
  ('REQ_ELABORAR_DOC', 'REQ_BORRADOR', 'REQ_DOC_PENDIENTE',
   'Continuar con el documento tecnico', 0, 0, NULL, 0, NULL, 0),

  /* El documento requerido depende del objeto (REQ-07) y por eso va nulo aqui:
     la rutina de negocio comprueba que exista el que corresponde al tipo de
     contratacion. Cablear uno solo obligaria a una transicion por objeto.
     Firma especialista: llega al Coordinador AU. El Coordinador deriva al
     Jefe. El Jefe conserva REQ_DERIVAR_JEFE por si la unidad no tiene
     Coordinador. */
  ('REQ_DERIVAR_COORD', 'REQ_DOC_PENDIENTE', 'REQ_PEND_VB_AU',
   'Firma especialista', 0, 1, NULL, 0, NULL, 0),

  ('REQ_OTORGAR_VB', 'REQ_PEND_VB_AU', 'REQ_PEND_FIRMA_AU',
   'Derivar al Jefe del Area usuaria', 0, 0, NULL, 0, NULL, 0),

  ('REQ_DERIVAR_JEFE', 'REQ_DOC_PENDIENTE', 'REQ_PEND_FIRMA_AU',
   'Derivar al Jefe para firma', 0, 0, NULL, 0, NULL, 0),

  ('REQ_FIRMAR_AU', 'REQ_PEND_FIRMA_AU', 'REQ_EN_EVAL_OA',
   'Firmar y remitir a la Oficina de Administracion', 0, 1, NULL, 0, NULL, 0),

  /* Paso extra tras la firma: inactivo. La firma del jefe ya deja el
     expediente en OA. Se conservan los codigos por trazabilidad. */
  ('REQ_REMITIR_OA', 'REQ_FIRMADO_AU', 'REQ_EN_EVAL_OA',
   'Remitir a la Oficina de Administracion', 0, 0, NULL, 0, NULL, 0),

  /* La ruta a DAI queda declarada pero inactiva: no se ofrece en bandeja. */
  ('REQ_REMITIR_DAI', 'REQ_FIRMADO_AU', 'REQ_EN_EVAL_DAI',
   'Remitir a DAI', 0, 0, NULL, 0, NULL, 0),

  ('REQ_OBSERVAR_OA', 'REQ_EN_EVAL_OA', 'REQ_OBSERVADO',
   'Observar desde OA', 1, 0, NULL, 0, NULL, 1),

  ('REQ_DERIVAR_DEC', 'REQ_EN_EVAL_OA', 'REQ_EN_ABAST_JEFE',
   'Derivar al Jefe de Abastecimiento', 0, 0, NULL, 0, NULL, 0),

  ('REQ_ABAST_JEFE_DERIVAR', 'REQ_EN_ABAST_JEFE', 'REQ_EN_ABAST_COORD',
   'Derivar al Coordinador de Abastecimiento', 0, 0, NULL, 0, NULL, 0),

  ('REQ_ABAST_COORD_DERIVAR', 'REQ_EN_ABAST_COORD', 'REQ_EN_EVAL_DEC',
   'Derivar al Especialista de Abastecimiento', 0, 0, NULL, 0, NULL, 0),

  ('REQ_OBSERVAR_DEC', 'REQ_EN_EVAL_DEC', 'REQ_OBSERVADO',
   'Observar desde la DEC', 1, 0, NULL, 0, NULL, 1),

  ('REQ_OBSERVAR_DAI', 'REQ_EN_EVAL_DAI', 'REQ_OBSERVADO',
   'Observar desde DAI', 1, 0, NULL, 0, NULL, 1),

  /* REQ-16: la tercera salida de la revision, ni conforme ni observado. */
  ('REQ_NO_OBJECION_DEC', 'REQ_EN_EVAL_DEC', 'REQ_NO_OBJECION',
   'Registrar mejoras sujetas a no objecion', 1, 0, NULL, 0, NULL, 0),

  ('REQ_ACEPTAR_NO_OBJECION', 'REQ_NO_OBJECION', 'REQ_CONFORME',
   'Aceptar las mejoras', 0, 0, NULL, 0, NULL, 0),

  ('REQ_CONFORMIDAD_DEC', 'REQ_EN_EVAL_DEC', 'REQ_CONFORME',
   'Declarar conforme', 0, 0, NULL, 0, NULL, 0),

  ('REQ_CONFORMIDAD_DAI', 'REQ_EN_EVAL_DAI', 'REQ_CONFORME',
   'Declarar conforme', 0, 0, NULL, 0, NULL, 0),

  /* REQ-27: primero se recepciona la observacion, despues se subsana. La
     subsanacion devuelve al borrador porque REQ-28 permite corregirlo todo. */
  ('REQ_SUBSANAR', 'REQ_OBSERVADO', 'REQ_BORRADOR',
   'Abrir subsanacion', 1, 0, NULL, 0, NULL, 0),

  ('REQ_ANULAR_BORRADOR', 'REQ_BORRADOR', 'REQ_ANULADO',
   'Anular requerimiento en borrador', 1, 0, NULL, 0, NULL, 0),

  ('REQ_ANULAR_DOC_PEND', 'REQ_DOC_PENDIENTE', 'REQ_ANULADO',
   'Anular requerimiento', 1, 0, NULL, 0, NULL, 0);

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

UPDATE sigcm.Transicion SET Activo = 0 WHERE CodigoTransicion IN ('REQ_REMITIR_DAI', 'REQ_REMITIR_OA');
GO

/* -------------------------------------------------------------------------- */
/* 5. Roles permitidos por transicion                                         */
/* -------------------------------------------------------------------------- */

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('REQ_ELABORAR_DOC','AREA_ESPECIALISTA'), ('REQ_ELABORAR_DOC','AREA_JEFE'),
  ('REQ_DERIVAR_COORD','AREA_ESPECIALISTA'),
  ('REQ_OTORGAR_VB','AREA_COORDINADOR'),
  ('REQ_DERIVAR_JEFE','AREA_JEFE'),
  ('REQ_FIRMAR_AU','AREA_JEFE'),
  ('REQ_OBSERVAR_OA','OA'),
  ('REQ_DERIVAR_DEC','OA'),
  ('REQ_ABAST_JEFE_DERIVAR','ABAST_JEFE'),
  ('REQ_ABAST_COORD_DERIVAR','ABAST_COORDINADOR'),
  ('REQ_OBSERVAR_DEC','ABAST_ESPECIALISTA'), ('REQ_OBSERVAR_DEC','ABAST_COORDINADOR'),
  ('REQ_OBSERVAR_DAI','DAI'),
  /* Tras REQ_ABAST_COORD_DERIVAR el expediente queda con ABAST_ESPECIALISTA.
     El Coordinador ya no lo ve en «Solo mi bandeja», asi que el Especialista
     cierra la revision (conforme / no objecion / observar), igual que en CMN
     el especialista de Abastecimiento conforma u observa. */
  ('REQ_NO_OBJECION_DEC','ABAST_ESPECIALISTA'), ('REQ_NO_OBJECION_DEC','ABAST_COORDINADOR'),
  ('REQ_ACEPTAR_NO_OBJECION','AREA_JEFE'),
  ('REQ_CONFORMIDAD_DEC','ABAST_ESPECIALISTA'), ('REQ_CONFORMIDAD_DEC','ABAST_COORDINADOR'),
  ('REQ_CONFORMIDAD_DAI','DAI'),
  ('REQ_SUBSANAR','AREA_ESPECIALISTA'), ('REQ_SUBSANAR','AREA_JEFE'),
  ('REQ_ANULAR_BORRADOR','AREA_ESPECIALISTA'), ('REQ_ANULAR_BORRADOR','AREA_JEFE'),
  ('REQ_ANULAR_DOC_PEND','AREA_JEFE');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);

/* El Especialista ya no salta al Jefe: pasa por el Coordinador (REQ_DERIVAR_COORD). */
DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_DERIVAR_JEFE' AND CodigoRol = 'AREA_ESPECIALISTA';

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion IN ('REQ_REMITIR_DAI', 'REQ_REMITIR_OA');
GO

/* -------------------------------------------------------------------------- */
/* 6. Parametros del anio                                                     */
/* -------------------------------------------------------------------------- */

/* REQ-06: el tope es de ocho UIT. Para 2026 el mockup usa S/ 44 000, que
   corresponde a una UIT de S/ 5 500. CONFIRMAR con Abastecimiento el valor
   oficial de cada anio antes de desplegar. */
IF NOT EXISTS (SELECT 1 FROM requerimiento.ParametroAnio WHERE AnoEje = 2026)
    INSERT INTO requerimiento.ParametroAnio (AnoEje, ValorUit, TopeUit,
                                             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES (2026, 5500.00, 8, 'seed', 'localhost', 'S003');
GO

DECLARE @msg varchar(300) =
    'S003 aplicada: '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Estado     WHERE CodigoModulo = 'REQUERIMIENTO')) + ' estados, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Transicion WHERE CodigoModulo = 'REQUERIMIENTO')) + ' transiciones, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.TipoDocumento WHERE CodigoModulo = 'REQUERIMIENTO')) + ' tipos de documento.';
PRINT @msg;
GO
