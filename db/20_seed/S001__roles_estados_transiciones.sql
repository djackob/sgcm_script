/*
===============================================================================
  SIGCM - Semilla S001 : Modulos, roles, matriz de acceso, estados, documentos
                         y transiciones
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Port de SIGCM/db/20_seed/S001__roles_estados_transiciones.sql.
  Fuente funcional: README del mockup y Directiva N.o 002-2026-ANIN.

  Idempotente. PostgreSQL usaba ON CONFLICT ... DO UPDATE; aqui se emplea el
  patron UPDATE ...; INSERT ... WHERE NOT EXISTS sobre una variable de tabla con
  los valores. Se evita MERGE a proposito: acumula defectos conocidos con
  concurrencia y con claves foraneas, y aqui no aporta nada.

  DOS CAMBIOS RESPECTO DE LA VERSION POSTGRESQL
  ---------------------------------------------
  1. roles_permitidos y firmas_requeridas eran arreglos. Ahora son filas en
     sigcm.TransicionRol y sigcm.TipoDocumentoFirma.

  2. EL ENCOLADO OCURRE EN DOS ESCALONES, NO EN UNO.
     La version PostgreSQL marcaba encola_integracion solo en CMN_FIRMAR_A4, pero
     el comentario de integracion.operacion decia que INCLUIR_ITEM / EXCLUIR_ITEM /
     MODIFICAR_CANTIDADES corresponden al Anexo 3 validado. Las dos cosas no
     podian ser ciertas a la vez. Se resuelve segun el mapa funcional
     (SIGCM/docs/mapa-siga-cmn.md, seccion 4), que observo en los datos reales
     que _DET y _SALDO se escriben al validar el Anexo 3, mientras que _CMN se
     puebla recien en la consolidacion:

         CMN_VALIDAR_UA  -> ITEMS_ANEXO_3  (F004 deriva la operacion por item
                                            segun su TipoMovimiento)
         CMN_FIRMAR_A4   -> CONSOLIDAR_CMN
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Modulos                                                                 */
/* -------------------------------------------------------------------------- */

/* Activo = 0 en los cuatro pendientes: estan declarados para que la matriz de
   acceso y la maquina de estados no cambien de forma, pero no son navegables.
   CMN y REQUERIMIENTO ya tienen pantalla y por eso van activos y con ruta.

   Ruta e Icono se siembran AQUI y no en V007. La columna la crea V007, que es
   estructura; el valor es dato de semilla y este es el archivo que lo tiene.
   Cuando estaban separados, una instalacion limpia dejaba el menu vacio: V007
   corre antes que este seed, encontraba la tabla recien creada y su UPDATE no
   tocaba ninguna fila. El sintoma era que ni CMN aparecia en el menu lateral.

   Ruta NULL = declarado sin pantalla. paObtenerSesion filtra por Ruta IS NOT
   NULL, asi que el modulo no entra al menu hasta que exista su componente en
   el frontend. La ruta debe coincidir con el path de plantilla.routes.ts: el
   guard compara menu.url contra route.routeConfig.path. */
DECLARE @Modulo TABLE (CodigoModulo varchar(30), Nombre varchar(150), Orden int,
                       Activo bit, Ruta varchar(100), Icono varchar(60));
INSERT INTO @Modulo VALUES
  ('CMN',           'Gestion CMN',                  10, 1, 'gestion-cmn', 'mdi mdi-clipboard-list-outline'),
  ('REQUERIMIENTO', 'Requerimiento a Notificacion', 20, 1, 'gestion-requerimiento', 'mdi mdi-clipboard-text-outline'),
  ('EJECUCION',     'Ejecucion',                    30, 0, NULL,          'mdi mdi-progress-check'),
  ('PAGO',          'Pago',                         40, 0, NULL,          'mdi mdi-cash-multiple'),
  ('MODIFICACION',  'Modificacion-Ampliacion',      50, 0, NULL,          'mdi mdi-file-document-edit-outline'),
  ('RESOLUCION',    'Resolucion',                   60, 0, NULL,          'mdi mdi-file-cancel-outline');

/* Activo va en el UPDATE junto con el resto. Es dato de semilla igual que la
   ruta —declara si el modulo ya tiene pantalla—, y dejarlo fuera hacia que
   estrenar un modulo funcionara solo al recrear la base: sobre una base ya
   instalada el UPDATE le cambiaba la ruta y lo dejaba apagado. */
UPDATE d SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Activo = s.Activo,
             d.Ruta   = s.Ruta,   d.Icono = s.Icono
  FROM sigcm.Modulo AS d JOIN @Modulo AS s ON s.CodigoModulo = d.CodigoModulo;

INSERT INTO sigcm.Modulo (CodigoModulo, Nombre, Orden, Activo, Ruta, Icono)
SELECT s.CodigoModulo, s.Nombre, s.Orden, s.Activo, s.Ruta, s.Icono
  FROM @Modulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Modulo AS d WHERE d.CodigoModulo = s.CodigoModulo);
GO

/* -------------------------------------------------------------------------- */
/* 2. Tipos de contratacion                                                   */
/* -------------------------------------------------------------------------- */

DECLARE @TipoCon TABLE (CodigoTipoContratacion varchar(20), Nombre varchar(120),
                        TipoBienSiga char(1), RutaEntregables bit, RutaRecepcionFisica bit);
INSERT INTO @TipoCon VALUES
  ('BIEN',        'Bien',                  'B', 0, 1),
  ('SERVICIO',    'Servicio',              'S', 1, 0),
  ('LOCACION',    'Locacion de servicios', 'S', 1, 0),
  ('CONSULTORIA', 'Consultoria',           'S', 1, 0);

UPDATE d
   SET d.Nombre = s.Nombre, d.TipoBienSiga = s.TipoBienSiga,
       d.RutaEntregables = s.RutaEntregables, d.RutaRecepcionFisica = s.RutaRecepcionFisica
  FROM sigcm.TipoContratacion AS d
  JOIN @TipoCon AS s ON s.CodigoTipoContratacion = d.CodigoTipoContratacion;

INSERT INTO sigcm.TipoContratacion
      (CodigoTipoContratacion, Nombre, TipoBienSiga, RutaEntregables, RutaRecepcionFisica)
SELECT s.CodigoTipoContratacion, s.Nombre, s.TipoBienSiga, s.RutaEntregables, s.RutaRecepcionFisica
  FROM @TipoCon AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoContratacion AS d
                    WHERE d.CodigoTipoContratacion = s.CodigoTipoContratacion);
GO

/* -------------------------------------------------------------------------- */
/* 3. Roles                                                                   */
/* -------------------------------------------------------------------------- */

/* Los perfiles del mockup. Area usuaria y Abastecimiento van desagregados
   porque sus firmas y autorizaciones no son intercambiables. */
DECLARE @Rol TABLE (CodigoRol varchar(40), Nombre varchar(150),
                    Descripcion nvarchar(400), EsTecnico bit);
INSERT INTO @Rol VALUES
  ('AREA_JEFE',          'Area usuaria - Jefe',             'Firma Anexo 3, remite y recepciona Anexo 4', 0),
  ('AREA_ESPECIALISTA',  'Area usuaria - Especialista',     'Registra el Anexo 3 y subsana observaciones', 0),
  ('OA',                 'Oficina de Administracion',       'Revisa; observa o deriva a Abastecimiento', 0),
  ('ABAST_JEFE',         'Abastecimiento - Jefe',           'Firma el Anexo 4 y remite', 0),
  ('ABAST_COORDINADOR',  'Abastecimiento - Coordinador',    'Valida solicitudes y decide observaciones', 0),
  ('ABAST_ESPECIALISTA', 'Abastecimiento - Especialista',   'Revisa el Anexo 3 y opera expedientes', 0),
  ('MAX_AUT_ADMIN',      'Maxima autoridad administrativa', 'Segunda firma del Anexo 4', 0),
  ('DAI',                'DAI',                             'DEC en el modulo de requerimientos', 0),
  ('OPP',                'Planeamiento y Presupuesto',      'Previsiones y certificaciones', 0),
  ('CONTABILIDAD',       'Unidad de Contabilidad',          'Control previo y devengado', 0),
  ('TESORERIA',          'Unidad de Tesoreria',             'Giro y pago', 0),
  ('MESA_PARTES',        'Mesa de Partes',                  'Recepcion documental externa', 0),
  ('PROVEEDOR',          'Proveedor',                       'Acceso externo a sus contrataciones', 0),
  ('ADMIN_SISTEMA',      'Administrador del sistema',       'Administracion funcional y tecnica', 0),
  ('SVC_INTEGRACION',    'Servicio de integracion SIGA',    'Cuenta tecnica de minimo privilegio', 1),
  ('SVC_CONCILIACION',   'Servicio de conciliacion',        'Cuenta tecnica de solo lectura comparativa', 1);

UPDATE d SET d.Nombre = s.Nombre, d.Descripcion = s.Descripcion, d.EsTecnico = s.EsTecnico
  FROM sigcm.Rol AS d JOIN @Rol AS s ON s.CodigoRol = d.CodigoRol;

INSERT INTO sigcm.Rol (CodigoRol, Nombre, Descripcion, EsTecnico)
SELECT s.CodigoRol, s.Nombre, s.Descripcion, s.EsTecnico
  FROM @Rol AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Rol AS d WHERE d.CodigoRol = s.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 4. Matriz de acceso modulo <-> rol                                         */
/* -------------------------------------------------------------------------- */

DECLARE @RolModulo TABLE (CodigoRol varchar(40), CodigoModulo varchar(30));
INSERT INTO @RolModulo VALUES
  ('AREA_JEFE','CMN'), ('AREA_ESPECIALISTA','CMN'), ('OA','CMN'),
  ('ABAST_JEFE','CMN'), ('ABAST_COORDINADOR','CMN'), ('ABAST_ESPECIALISTA','CMN'),
  ('MAX_AUT_ADMIN','CMN'), ('ADMIN_SISTEMA','CMN');

INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT s.CodigoRol, s.CodigoModulo
  FROM @RolModulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS d
                    WHERE d.CodigoRol = s.CodigoRol AND d.CodigoModulo = s.CodigoModulo);
GO

/* -------------------------------------------------------------------------- */
/* 5. Estados del modulo CMN                                                  */
/* -------------------------------------------------------------------------- */

DECLARE @Estado TABLE (CodigoEstado varchar(60), Nombre varchar(150), Orden int,
                       EsInicial bit, EsFinal bit, RolResponsable varchar(40) NULL);
INSERT INTO @Estado VALUES
  ('CMN_BORRADOR',      'Registrar Anexo 3',                       10, 1, 0, 'AREA_ESPECIALISTA'),
  ('CMN_PEND_FIRMA_A3', 'Por firmar Anexo 3',                      20, 0, 0, 'AREA_JEFE'),
  ('CMN_A3_FIRMADO',    'Anexo 3 firmado',                         30, 0, 0, 'AREA_JEFE'),
  ('CMN_EN_EVAL_OA',    'En evaluacion OA',                        40, 0, 0, 'OA'),
  ('CMN_EN_EVAL_UA',    'En evaluacion Unidad de Abastecimiento',  50, 0, 0, 'ABAST_ESPECIALISTA'),
  ('CMN_OBSERVADO',     'Observado',                               60, 0, 0, 'AREA_ESPECIALISTA'),
  ('CMN_VALIDADO_UA',   'Validado por Abastecimiento',             70, 0, 0, 'ABAST_COORDINADOR'),
  ('CMN_PEND_FIRMA_A4', 'Por firmar Anexo 4',                      80, 0, 0, 'ABAST_JEFE'),
  ('CMN_A4_FIRMADO',    'Anexo 4 firmado',                         90, 0, 0, 'ABAST_JEFE'),
  ('CMN_A4_ENVIADO',    'Anexo 4 enviado al area usuaria',        100, 0, 0, 'AREA_JEFE'),
  ('CMN_FINALIZADO',    'Anexo 4 recepcionado - Fin',             110, 0, 1, NULL),
  ('CMN_ANULADO',       'Anulado',                                999, 0, 1, NULL);

UPDATE d
   SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'CMN', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);
GO

/* -------------------------------------------------------------------------- */
/* 6. Tipos de documento y sus firmas                                         */
/* -------------------------------------------------------------------------- */

DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200),
                        NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('CMN_ANEXO_3_SOLICITUD_MODIFICACION',
   'Solicitud de modificacion del Cuadro Multianual de Necesidades', 'Anexo 3', 0),
  ('CMN_ANEXO_4_APROBACION_MODIFICACION',
   'Aprobacion de modificaciones al Cuadro Multianual de Necesidades', 'Anexo 4', 1);

UPDATE d
   SET d.Nombre = s.Nombre, d.NumeracionVisible = s.NumeracionVisible,
       d.AdmiteConsolidado = s.AdmiteConsolidado
  FROM sigcm.TipoDocumento AS d
  JOIN @TipoDoc AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento;

INSERT INTO sigcm.TipoDocumento (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
SELECT s.CodigoTipoDocumento, 'CMN', s.Nombre, s.NumeracionVisible, s.AdmiteConsolidado
  FROM @TipoDoc AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento AS d
                    WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento);

/* Sustituye a firmas_requeridas varchar(40)[]. El Anexo 4 lleva dos firmantes:
   el responsable de Abastecimiento y la maxima autoridad administrativa. */
DECLARE @DocFirma TABLE (CodigoTipoDocumento varchar(60), CodigoRol varchar(40), OrdenFirma smallint);
INSERT INTO @DocFirma VALUES
  ('CMN_ANEXO_3_SOLICITUD_MODIFICACION',  'AREA_JEFE',     1),
  ('CMN_ANEXO_4_APROBACION_MODIFICACION', 'ABAST_JEFE',    1),
  ('CMN_ANEXO_4_APROBACION_MODIFICACION', 'MAX_AUT_ADMIN', 2);

UPDATE d SET d.OrdenFirma = s.OrdenFirma
  FROM sigcm.TipoDocumentoFirma AS d
  JOIN @DocFirma AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento AND s.CodigoRol = d.CodigoRol;

INSERT INTO sigcm.TipoDocumentoFirma (CodigoTipoDocumento, CodigoRol, OrdenFirma)
SELECT s.CodigoTipoDocumento, s.CodigoRol, s.OrdenFirma
  FROM @DocFirma AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumentoFirma AS d
                    WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento AND d.CodigoRol = s.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 7. Transiciones del modulo CMN                                             */
/* -------------------------------------------------------------------------- */

DECLARE @Tr TABLE (
    CodigoTransicion     varchar(70),
    CodigoEstadoOrigen   varchar(60),
    CodigoEstadoDestino  varchar(60),
    NombreAccion         varchar(180),
    RequiereComentario   bit,
    RequiereFirma        bit,
    DocumentoRequerido   varchar(60) NULL,
    EncolaIntegracion    bit,
    OperacionIntegracion varchar(30) NULL,
    GeneraObservacion    bit
);
INSERT INTO @Tr VALUES
  ('CMN_GENERAR_A3', 'CMN_BORRADOR', 'CMN_PEND_FIRMA_A3',
   'Generar Anexo 3', 0, 0, NULL, 0, NULL, 0),

  ('CMN_FIRMAR_A3', 'CMN_PEND_FIRMA_A3', 'CMN_A3_FIRMADO',
   'Firmar Anexo 3', 0, 1, 'CMN_ANEXO_3_SOLICITUD_MODIFICACION', 0, NULL, 0),

  ('CMN_ENVIAR_OA', 'CMN_A3_FIRMADO', 'CMN_EN_EVAL_OA',
   'Enviar Anexo 3 a la Oficina de Administracion', 0, 0,
   'CMN_ANEXO_3_SOLICITUD_MODIFICACION', 0, NULL, 0),

  /* Retorno directo a Abastecimiento cuando la observacion subsanada provino de
     Abastecimiento. La rutina de negocio elige entre CMN_ENVIAR_OA y esta
     leyendo sigcm.Observacion.CodigoEstadoRetorno; sin ambas transiciones el
     expediente subsanado volveria siempre a OA, repitiendo una revision ya
     hecha. */
  ('CMN_REENVIAR_UA', 'CMN_A3_FIRMADO', 'CMN_EN_EVAL_UA',
   'Reenviar Anexo 3 subsanado a Abastecimiento', 0, 0,
   'CMN_ANEXO_3_SOLICITUD_MODIFICACION', 0, NULL, 0),

  ('CMN_OBSERVAR_OA', 'CMN_EN_EVAL_OA', 'CMN_OBSERVADO',
   'Observar desde OA', 1, 0, NULL, 0, NULL, 1),

  ('CMN_DERIVAR_UA', 'CMN_EN_EVAL_OA', 'CMN_EN_EVAL_UA',
   'Derivar a la Unidad de Abastecimiento', 0, 0, NULL, 0, NULL, 0),

  ('CMN_OBSERVAR_UA', 'CMN_EN_EVAL_UA', 'CMN_OBSERVADO',
   'Observar desde Abastecimiento', 1, 0, NULL, 0, NULL, 1),

  /* PRIMER ESCALON DE ENCOLADO. Al validar el Anexo 3, SIGA recibe las
     inclusiones, exclusiones y modificaciones de cantidades sobre
     SIG_CUADRO_MODIFICADO_DET y _SALDO. F004 expande esta marca en una operacion
     por item segun su TipoMovimiento. */
  ('CMN_VALIDAR_UA', 'CMN_EN_EVAL_UA', 'CMN_VALIDADO_UA',
   'Validar Anexo 3', 0, 0, NULL, 1, 'ITEMS_ANEXO_3', 0),

  /* La subsanacion vuelve a borrador; el estado de retorno posterior lo guarda
     sigcm.Observacion.CodigoEstadoRetorno, no esta transicion. */
  ('CMN_SUBSANAR', 'CMN_OBSERVADO', 'CMN_BORRADOR',
   'Abrir subsanacion', 1, 0, NULL, 0, NULL, 0),

  ('CMN_GENERAR_A4', 'CMN_VALIDADO_UA', 'CMN_PEND_FIRMA_A4',
   'Generar Anexo 4', 0, 0, NULL, 0, NULL, 0),

  /* SEGUNDO ESCALON DE ENCOLADO. La consolidacion escribe en
     SIG_CUADRO_MODIFICADO_CMN, que segun los datos de 2026 no se puebla hasta
     este momento. */
  ('CMN_FIRMAR_A4', 'CMN_PEND_FIRMA_A4', 'CMN_A4_FIRMADO',
   'Completar firmas del Anexo 4', 0, 1,
   'CMN_ANEXO_4_APROBACION_MODIFICACION', 1, 'CONSOLIDAR_CMN', 0),

  ('CMN_ENVIAR_A4', 'CMN_A4_FIRMADO', 'CMN_A4_ENVIADO',
   'Enviar Anexo 4 al area usuaria', 0, 0,
   'CMN_ANEXO_4_APROBACION_MODIFICACION', 0, NULL, 0),

  ('CMN_RECEPCIONAR_A4', 'CMN_A4_ENVIADO', 'CMN_FINALIZADO',
   'Recepcionar Anexo 4', 0, 0, NULL, 0, NULL, 0),

  ('CMN_ANULAR_BORRADOR', 'CMN_BORRADOR', 'CMN_ANULADO',
   'Anular solicitud en borrador', 1, 0, NULL, 0, NULL, 0),

  ('CMN_ANULAR_FIRMA_PEND', 'CMN_PEND_FIRMA_A3', 'CMN_ANULADO',
   'Anular solicitud pendiente de firma', 1, 0, NULL, 0, NULL, 0);

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
SELECT s.CodigoTransicion, 'CMN', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

/* Roles permitidos por transicion. Sustituye a roles_permitidos varchar(40)[]. */
DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('CMN_GENERAR_A3','AREA_ESPECIALISTA'), ('CMN_GENERAR_A3','AREA_JEFE'),
  ('CMN_FIRMAR_A3','AREA_JEFE'),
  ('CMN_ENVIAR_OA','AREA_JEFE'),
  ('CMN_REENVIAR_UA','AREA_JEFE'),
  ('CMN_OBSERVAR_OA','OA'),
  ('CMN_DERIVAR_UA','OA'),
  ('CMN_OBSERVAR_UA','ABAST_ESPECIALISTA'), ('CMN_OBSERVAR_UA','ABAST_COORDINADOR'),
  ('CMN_VALIDAR_UA','ABAST_ESPECIALISTA'),  ('CMN_VALIDAR_UA','ABAST_COORDINADOR'),
  ('CMN_SUBSANAR','AREA_ESPECIALISTA'),     ('CMN_SUBSANAR','AREA_JEFE'),
  ('CMN_GENERAR_A4','ABAST_ESPECIALISTA'),  ('CMN_GENERAR_A4','ABAST_COORDINADOR'),
  ('CMN_GENERAR_A4','ABAST_JEFE'),
  ('CMN_FIRMAR_A4','ABAST_JEFE'),           ('CMN_FIRMAR_A4','MAX_AUT_ADMIN'),
  ('CMN_ENVIAR_A4','ABAST_JEFE'),           ('CMN_ENVIAR_A4','ABAST_ESPECIALISTA'),
  ('CMN_RECEPCIONAR_A4','AREA_JEFE'),
  ('CMN_ANULAR_BORRADOR','AREA_ESPECIALISTA'), ('CMN_ANULAR_BORRADOR','AREA_JEFE'),
  ('CMN_ANULAR_FIRMA_PEND','AREA_JEFE');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);

/* Un rol retirado de la semilla debe dejar de estar permitido. Sin esta limpieza
   la reejecucion solo acumularia. */
DELETE d
  FROM sigcm.TransicionRol AS d
 WHERE d.CodigoTransicion LIKE 'CMN[_]%'
   AND NOT EXISTS (SELECT 1 FROM @TrRol AS s
                    WHERE s.CodigoTransicion = d.CodigoTransicion AND s.CodigoRol = d.CodigoRol);
GO

DECLARE @msg varchar(300) =
    'S001 aplicada: '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Modulo))        + ' modulos, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Rol))           + ' roles, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Estado))         + ' estados, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Transicion))     + ' transiciones, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.TransicionRol))  + ' permisos de transicion.';
PRINT @msg;
GO
