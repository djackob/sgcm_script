/*
===============================================================================
  SIGCM - S038 : Estados, transiciones, documentos y plazos del modulo Ejecucion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Directiva 002-2026-ANIN 7.3 y Bizagi "3. EJECUCION". Es CONFIGURACION: sin
  estas filas el modulo no avanza. Se instala en todos los ambientes.

  Dos maquinas bajo el mismo modulo, distinguidas por prefijo:

    EJE_      el CONTRATO en ejecucion (una fila por orden notificada)
    EJE_ENT_  cada ENTREGA fisica de bienes (7.3.6.3), colgada del contrato

  Rutas de la entrega segun el lugar (7.3.6.3 a / b):

    ALMACEN (Sede Central)                 SEDE (desconcentrada)
    POR_AUTORIZAR_ALMACEN     DEC          POR_AUTORIZAR_SEDE      AU esp
    POR_DESIGNAR_VERIFICADOR  AU jefe      EN_VERIFICACION_SEDE    AU esp
    EN_VERIFICACION_ALMACEN   DEC          RECEPCIONADA_SEDE       DEC (firma la guia)
    RECEPCIONADA_ALMACEN      DEC          GUIA_REGISTRADA         fin
    ENTREGADA_AU              fin
                    OBSERVADA (proveedor) -> RETIRADA (fin), en las dos rutas

  La rama de servicios (presentar entregable -> Anexo 11) es el modulo PAGO y
  no se repite aqui.

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
       Ruta   = 'gestion-ejecucion',
       Icono  = 'mdi mdi-progress-check',
       Nombre = 'Ejecucion contractual'
 WHERE CodigoModulo = 'EJECUCION';
GO

/* -------------------------------------------------------------------------- */
/* 2. Matriz de acceso                                                        */
/* -------------------------------------------------------------------------- */

DECLARE @RolModulo TABLE (CodigoRol varchar(40), CodigoModulo varchar(30));
INSERT INTO @RolModulo VALUES
  ('PROVEEDOR','EJECUCION'),
  ('AREA_ESPECIALISTA','EJECUCION'), ('AREA_COORDINADOR','EJECUCION'), ('AREA_JEFE','EJECUCION'),
  ('ABAST_ESPECIALISTA','EJECUCION'), ('ABAST_COORDINADOR','EJECUCION'), ('ABAST_JEFE','EJECUCION'),
  ('OA','EJECUCION'),
  ('ADMIN_SISTEMA','EJECUCION');

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
  /* Contrato. Solo EJE_VIGENTE lleva EsInicial: es el que buscan las rutinas
     que abren el contrato. Los estados de entrega arrancan por codigo. */
  ('EJE_VIGENTE',                     'Contrato en ejecucion',                                 10, 1, 0, 'AREA_ESPECIALISTA'),
  ('EJE_CULMINADO',                   'Contrato culminado',                                    90, 0, 1, NULL),

  /* Entrega - ruta Almacen (Sede Central) */
  ('EJE_ENT_POR_AUTORIZAR_ALMACEN',   'Entrega anunciada - por autorizar ingreso a Almacen',   110, 0, 0, 'ABAST_ESPECIALISTA'),
  ('EJE_ENT_POR_DESIGNAR_VERIFICADOR','Ingreso autorizado - por designar responsable del AU',  120, 0, 0, 'AREA_JEFE'),
  ('EJE_ENT_EN_VERIFICACION_ALMACEN', 'En verificacion en Almacen',                            130, 0, 0, 'ABAST_ESPECIALISTA'),
  ('EJE_ENT_RECEPCIONADA_ALMACEN',    'Recepcionada en Almacen - por entregar al AU',          140, 0, 0, 'ABAST_ESPECIALISTA'),
  ('EJE_ENT_ENTREGADA_AU',            'Entregada al Area usuaria (Pecosa)',                    190, 0, 1, NULL),

  /* Entrega - ruta Sede desconcentrada */
  ('EJE_ENT_POR_AUTORIZAR_SEDE',      'Entrega anunciada - por autorizar ingreso en sede',     210, 0, 0, 'AREA_ESPECIALISTA'),
  ('EJE_ENT_EN_VERIFICACION_SEDE',    'En verificacion por el Area usuaria',                   230, 0, 0, 'AREA_ESPECIALISTA'),
  ('EJE_ENT_RECEPCIONADA_SEDE',       'Recepcionada en sede - guia por registrar en Almacen',  240, 0, 0, 'ABAST_ESPECIALISTA'),
  ('EJE_ENT_GUIA_REGISTRADA',         'Guia de remision registrada en Almacen',                290, 0, 1, NULL),

  /* Comun a las dos rutas */
  ('EJE_ENT_OBSERVADA',               'Observada - bienes por retirar (acta de incumplimiento)', 300, 0, 0, 'PROVEEDOR'),
  ('EJE_ENT_RETIRADA',                'Bienes retirados por el proveedor',                     390, 0, 1, NULL);

UPDATE d
   SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable, d.Activo = 1
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'EJECUCION', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);
GO

/* -------------------------------------------------------------------------- */
/* 4. Tipos de documento                                                      */
/* -------------------------------------------------------------------------- */

DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200),
                        NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('EJE_GUIA_REMISION',          'Guia de remision del proveedor',                         'GR',    0),
  ('EJE_GUIA_REMISION_SUSCRITA', 'Guia de remision suscrita (visto bueno del AU / Almacen)', 'GR-VB', 0),
  ('EJE_ACTA_INCUMPLIMIENTO',    'Acta de incumplimiento y retiro de bienes',              'ACTA',  0),
  ('EJE_PECOSA',                 'Pedido-comprobante de salida (Pecosa)',                  'PECOSA',0),
  ('EJE_INFORME_INCIDENCIA',     'Informe de incidencia del Area usuaria',                 'INC',   0);

UPDATE d SET d.Nombre = s.Nombre, d.NumeracionVisible = s.NumeracionVisible,
             d.AdmiteConsolidado = s.AdmiteConsolidado
  FROM sigcm.TipoDocumento AS d
  JOIN @TipoDoc AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento;

INSERT INTO sigcm.TipoDocumento (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
SELECT s.CodigoTipoDocumento, 'EJECUCION', s.Nombre, s.NumeracionVisible, s.AdmiteConsolidado
  FROM @TipoDoc AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento AS d
                    WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento);
GO

/* -------------------------------------------------------------------------- */
/* 5. Transiciones                                                            */
/* -------------------------------------------------------------------------- */

/* Ningun documento va como DocumentoRequerido del motor: el acta y la guia
   suscrita se suben desde la misma accion que las exige, y es la rutina del
   modulo (F016) la que comprueba que vengan. Exigirlos ademas en el motor
   obligaria a dos viajes para un solo gesto. */
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
  /* Contrato */
  ('EJE_CULMINAR',                    'EJE_VIGENTE',                      'EJE_CULMINADO',
   'Culminar contrato', 0, 0, NULL, 0, NULL, 0),

  /* Ruta Almacen */
  ('EJE_ENT_AUTORIZAR_INGRESO_ALMACEN','EJE_ENT_POR_AUTORIZAR_ALMACEN',   'EJE_ENT_POR_DESIGNAR_VERIFICADOR',
   'Autorizar ingreso a Almacen y solicitar acompanamiento del AU', 0, 0, NULL, 0, NULL, 0),
  ('EJE_ENT_DESIGNAR_VERIFICADOR',    'EJE_ENT_POR_DESIGNAR_VERIFICADOR', 'EJE_ENT_EN_VERIFICACION_ALMACEN',
   'Designar responsable de verificacion', 0, 0, NULL, 0, NULL, 0),
  ('EJE_ENT_OBSERVAR_ALMACEN',        'EJE_ENT_EN_VERIFICACION_ALMACEN',  'EJE_ENT_OBSERVADA',
   'Observar y solicitar retiro de los bienes', 1, 0, NULL, 0, NULL, 0),
  ('EJE_ENT_RECEPCIONAR_ALMACEN',     'EJE_ENT_EN_VERIFICACION_ALMACEN',  'EJE_ENT_RECEPCIONADA_ALMACEN',
   'Recepcionar bienes con guia suscrita', 0, 0, NULL, 0, NULL, 0),
  ('EJE_ENT_ENTREGAR_AU',             'EJE_ENT_RECEPCIONADA_ALMACEN',     'EJE_ENT_ENTREGADA_AU',
   'Entregar al Area usuaria con Pecosa', 0, 0, NULL, 0, NULL, 0),

  /* Ruta Sede desconcentrada */
  ('EJE_ENT_AUTORIZAR_INGRESO_SEDE',  'EJE_ENT_POR_AUTORIZAR_SEDE',       'EJE_ENT_EN_VERIFICACION_SEDE',
   'Autorizar ingreso en sede', 0, 0, NULL, 0, NULL, 0),
  ('EJE_ENT_OBSERVAR_SEDE',           'EJE_ENT_EN_VERIFICACION_SEDE',     'EJE_ENT_OBSERVADA',
   'Observar y solicitar retiro de los bienes', 1, 0, NULL, 0, NULL, 0),
  ('EJE_ENT_RECEPCIONAR_SEDE',        'EJE_ENT_EN_VERIFICACION_SEDE',     'EJE_ENT_RECEPCIONADA_SEDE',
   'Recepcionar bienes con guia suscrita', 0, 0, NULL, 0, NULL, 0),
  ('EJE_ENT_REGISTRAR_GUIA_ALMACEN',  'EJE_ENT_RECEPCIONADA_SEDE',        'EJE_ENT_GUIA_REGISTRADA',
   'Registrar guia suscrita en Almacen', 0, 0, NULL, 0, NULL, 0),

  /* Comun */
  ('EJE_ENT_RETIRAR',                 'EJE_ENT_OBSERVADA',                'EJE_ENT_RETIRADA',
   'Confirmar retiro de los bienes', 0, 0, NULL, 0, NULL, 0);

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
SELECT s.CodigoTransicion, 'EJECUCION', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

/* Las acciones de Almacen las ejercen el especialista y el coordinador de
   Abastecimiento: la Directiva ubica al encargado de Almacen dentro de la DEC
   y el padron del SSO no lo distingue como rol propio. */
DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('EJE_CULMINAR','AREA_JEFE'),

  ('EJE_ENT_AUTORIZAR_INGRESO_ALMACEN','ABAST_ESPECIALISTA'), ('EJE_ENT_AUTORIZAR_INGRESO_ALMACEN','ABAST_COORDINADOR'),
  ('EJE_ENT_DESIGNAR_VERIFICADOR','AREA_JEFE'),
  ('EJE_ENT_OBSERVAR_ALMACEN','ABAST_ESPECIALISTA'), ('EJE_ENT_OBSERVAR_ALMACEN','ABAST_COORDINADOR'),
  ('EJE_ENT_RECEPCIONAR_ALMACEN','ABAST_ESPECIALISTA'), ('EJE_ENT_RECEPCIONAR_ALMACEN','ABAST_COORDINADOR'),
  ('EJE_ENT_ENTREGAR_AU','ABAST_ESPECIALISTA'), ('EJE_ENT_ENTREGAR_AU','ABAST_COORDINADOR'),

  ('EJE_ENT_AUTORIZAR_INGRESO_SEDE','AREA_ESPECIALISTA'), ('EJE_ENT_AUTORIZAR_INGRESO_SEDE','AREA_JEFE'),
  ('EJE_ENT_OBSERVAR_SEDE','AREA_ESPECIALISTA'), ('EJE_ENT_OBSERVAR_SEDE','AREA_JEFE'),
  ('EJE_ENT_RECEPCIONAR_SEDE','AREA_ESPECIALISTA'), ('EJE_ENT_RECEPCIONAR_SEDE','AREA_JEFE'),
  ('EJE_ENT_REGISTRAR_GUIA_ALMACEN','ABAST_ESPECIALISTA'), ('EJE_ENT_REGISTRAR_GUIA_ALMACEN','ABAST_COORDINADOR'),

  ('EJE_ENT_RETIRAR','PROVEEDOR');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE EXISTS (SELECT 1 FROM sigcm.Transicion AS t WHERE t.CodigoTransicion = s.CodigoTransicion)
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 6. Plazos                                                                  */
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
  /* Dias = 1 es un marcador: el plazo real es el de cada contrato y el
     vencimiento lo fija F016 al abrirlo. El nombre lo lee el usuario. */
  ('EJE_EJECUCION_CONTRATO',
   'Plazo de ejecucion del contrato',
   'EJE_VIGENTE', 1, 'CALENDARIO', 1,
   'Directiva 002-2026-ANIN 7.3.1 - inicio el dia siguiente a la notificacion'),

  ('EJE_CONFORMIDAD_BIEN',
   'Conformidad del bien recibido (7 dias calendario desde la recepcion)',
   'EJE_ENT_RECEPCIONADA_ALMACEN', 7, 'CALENDARIO', 0,
   'Directiva 002-2026-ANIN 7.3.6.1'),

  ('EJE_CONFORMIDAD_BIEN_SEDE',
   'Conformidad del bien recibido en sede (7 dias calendario desde la recepcion)',
   'EJE_ENT_RECEPCIONADA_SEDE', 7, 'CALENDARIO', 0,
   'Directiva 002-2026-ANIN 7.3.6.1');

UPDATE d
   SET d.Nombre = s.Nombre, d.CodigoEstadoInicio = s.CodigoEstadoInicio, d.Dias = s.Dias,
       d.TipoDia = s.TipoDia, d.Ampliable = s.Ampliable, d.BaseNormativa = s.BaseNormativa,
       d.Activo = 1
  FROM sigcm.PlazoRegla AS d JOIN @Regla AS s ON s.CodigoRegla = d.CodigoRegla;

INSERT INTO sigcm.PlazoRegla
      (CodigoRegla, CodigoModulo, Nombre, CodigoEstadoInicio, Dias, TipoDia,
       Ampliable, BaseNormativa, Activo)
SELECT s.CodigoRegla, 'EJECUCION', s.Nombre, s.CodigoEstadoInicio, s.Dias, s.TipoDia,
       s.Ampliable, s.BaseNormativa, 1
  FROM @Regla AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.PlazoRegla AS d WHERE d.CodigoRegla = s.CodigoRegla);
GO

PRINT 'S038 aplicada: modulo EJECUCION activo, estados, transiciones, documentos y plazos.';
GO
