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
  ('AREA_JEFE',          'Area usuaria - Jefe',             'Firma el Anexo 3, remite a OA y recepciona el Anexo 4', 0),
  ('AREA_COORDINADOR',   'Area usuaria - Coordinador',      'Deriva entre el especialista y el jefe del area usuaria', 0),
  ('AREA_ESPECIALISTA',  'Area usuaria - Especialista',     'Registra el Anexo 3 y subsana observaciones', 0),
  ('OA',                 'Oficina de Administracion',       'Revisa; observa o deriva a Abastecimiento', 0),
  ('ABAST_JEFE',         'Abastecimiento - Jefe',           'Recibe, deriva y pone la ultima firma del Anexo 3 y del Anexo 4', 0),
  ('ABAST_COORDINADOR',  'Abastecimiento - Coordinador',    'Deriva al especialista y firma en segundo lugar', 0),
  ('ABAST_ESPECIALISTA', 'Abastecimiento - Especialista',   'Evalua el Anexo 3, lo observa o lo firma, y genera el Anexo 4', 0),
  ('MAX_AUT_ADMIN',      'Maxima autoridad administrativa', 'Sin participacion en el flujo CMN vigente', 0),
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
  ('ADMIN_SISTEMA','CMN');

INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT s.CodigoRol, s.CodigoModulo
  FROM @RolModulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS d
                    WHERE d.CodigoRol = s.CodigoRol AND d.CodigoModulo = s.CodigoModulo);
GO

/* -------------------------------------------------------------------------- */
/* 5. Estados del modulo CMN                                                  */
/* -------------------------------------------------------------------------- */

/*
  El estado dice DE QUIEN es el expediente ahora mismo: RolResponsable es lo que
  cmn.paListarSolicitud cruza contra el rol del actor para armar su bandeja. Por
  eso cada escalon de derivacion es un estado y no un comentario: si el paso del
  coordinador al especialista no fuera un estado, el expediente le aparaceria a
  los dos a la vez y ninguno sabria si le toca.

  La cadena completa, en el orden del flujo aprobado por Abastecimiento:

    area usuaria          BORRADOR -> PEND_FIRMA_A3 -> A3_FIRMADO
    OA                    EN_EVAL_OA
    Abastecimiento        EN_ABAST_JEFE -> EN_ABAST_COORD -> EN_ABAST_ESP
      con observacion     OBS_ABAST_COORD -> OBS_ABAST_JEFE
                          -> OBS_AU_JEFE -> OBS_AU_COORD -> OBSERVADO
                          -> SUBS_AU_COORD -> SUBS_AU_JEFE -> EN_ABAST_JEFE
      sin observacion     A3_FIRMA_COORD -> A3_FIRMA_JEFE -> A3_APROBADO
    Anexo 4               A4_FIRMA_COORD -> A4_FIRMA_JEFE
    cierre                A4_ENVIADO -> FINALIZADO

  Los dos momentos de escritura en SIGA caen en A3_FIRMA_JEFE -> A3_APROBADO
  (registro del Anexo 3) y en A4_FIRMA_JEFE -> A4_ENVIADO (aprobacion del
  Anexo 4). Ambos son la firma del jefe de Abastecimiento, que es donde el
  flujo los ubica.
*/
DECLARE @Estado TABLE (CodigoEstado varchar(60), Nombre varchar(150), Orden int,
                       EsInicial bit, EsFinal bit, RolResponsable varchar(40) NULL);
INSERT INTO @Estado VALUES
  ('CMN_BORRADOR',        'Registrar Anexo 3',                                  10, 1, 0, 'AREA_ESPECIALISTA'),
  ('CMN_PEND_FIRMA_A3',   'Por firmar Anexo 3',                                 20, 0, 0, 'AREA_JEFE'),
  ('CMN_A3_FIRMADO',      'Anexo 3 firmado por el area usuaria',                30, 0, 0, 'AREA_JEFE'),
  ('CMN_EN_EVAL_OA',      'En evaluacion - Oficina de Administracion',          40, 0, 0, 'OA'),

  ('CMN_EN_ABAST_JEFE',   'En Abastecimiento - Jefe',                           45, 0, 0, 'ABAST_JEFE'),
  ('CMN_EN_ABAST_COORD',  'En Abastecimiento - Coordinador',                    50, 0, 0, 'ABAST_COORDINADOR'),
  ('CMN_EN_ABAST_ESP',    'En Abastecimiento - Especialista',                   55, 0, 0, 'ABAST_ESPECIALISTA'),

  ('CMN_OBS_ABAST_COORD', 'Observado - Coordinador de Abastecimiento',          56, 0, 0, 'ABAST_COORDINADOR'),
  ('CMN_OBS_ABAST_JEFE',  'Observado - Jefe de Abastecimiento',                 57, 0, 0, 'ABAST_JEFE'),
  ('CMN_OBS_AU_JEFE',     'Observado - Jefe del area usuaria',                  58, 0, 0, 'AREA_JEFE'),
  ('CMN_OBS_AU_COORD',    'Observado - Coordinador del area usuaria',           59, 0, 0, 'AREA_COORDINADOR'),
  ('CMN_OBSERVADO',       'Observado - por subsanar',                           60, 0, 0, 'AREA_ESPECIALISTA'),
  ('CMN_SUBS_AU_COORD',   'Subsanado - Coordinador del area usuaria',           62, 0, 0, 'AREA_COORDINADOR'),
  ('CMN_SUBS_AU_JEFE',    'Subsanado - Jefe del area usuaria',                  64, 0, 0, 'AREA_JEFE'),

  ('CMN_A3_FIRMA_COORD',  'Anexo 3 por firmar - Coordinador de Abastecimiento', 68, 0, 0, 'ABAST_COORDINADOR'),
  ('CMN_A3_FIRMA_JEFE',   'Anexo 3 por firmar - Jefe de Abastecimiento',        70, 0, 0, 'ABAST_JEFE'),
  ('CMN_A3_APROBADO',     'Anexo 3 aprobado - por generar Anexo 4',             72, 0, 0, 'ABAST_ESPECIALISTA'),

  ('CMN_A4_FIRMA_COORD',  'Anexo 4 por firmar - Coordinador de Abastecimiento', 80, 0, 0, 'ABAST_COORDINADOR'),
  ('CMN_A4_FIRMA_JEFE',   'Anexo 4 por firmar - Jefe de Abastecimiento',        85, 0, 0, 'ABAST_JEFE'),

  ('CMN_A4_ENVIADO',      'Anexo 4 enviado al area usuaria',                   100, 0, 0, 'AREA_JEFE'),
  ('CMN_FINALIZADO',      'Anexo 4 recepcionado - Fin',                        110, 0, 1, NULL),
  ('CMN_ANULADO',         'Anulado',                                           999, 0, 1, NULL);

UPDATE d
   SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'CMN', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);

/*
  Reubicacion de los expedientes que quedaron en estados retirados.

  El flujo anterior tenia un solo escalon en Abastecimiento. Los estados que lo
  representaban ya no tienen transiciones de salida, y un expediente parado en
  uno de ellos no le aparece a nadie: quedaria invisible y sin acciones, que es
  peor que un error, porque nadie lo reporta.

  Se los mueve al equivalente mas cercano de la cadena nueva. La equivalencia es
  conservadora: se elige siempre el escalon que REPITE la revision, no el que la
  da por hecha, porque los pasos nuevos —la firma del especialista y la del
  coordinador— nunca ocurrieron sobre estos expedientes.

  No toca la unidad actual: los cuatro estados retirados vivian en
  Abastecimiento, que es donde tambien viven sus reemplazos.
*/
DECLARE @Remapeo TABLE (Viejo varchar(60), Nuevo varchar(60));
INSERT INTO @Remapeo VALUES
  ('CMN_EN_EVAL_UA',    'CMN_EN_ABAST_ESP'),
  ('CMN_VALIDADO_UA',   'CMN_EN_ABAST_ESP'),
  ('CMN_PEND_FIRMA_A4', 'CMN_A3_APROBADO'),
  ('CMN_A4_FIRMADO',    'CMN_A4_ENVIADO');

UPDATE e
   SET e.CodigoEstado = r.Nuevo,
       e.Version      = e.Version + 1,
       e.UsuarioModificacionAuditoria = 'seed',
       e.FechaModificacionAuditoria   = GETDATE(),
       e.ProgramaModificacionAuditoria = 'S001'
  FROM sigcm.Expediente AS e
  JOIN @Remapeo AS r ON r.Viejo = e.CodigoEstado
 WHERE e.CodigoModulo = 'CMN';

IF @@ROWCOUNT > 0
    PRINT '  Expedientes reubicados desde estados retirados del flujo anterior.';
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
   'Aprobacion de modificaciones al Cuadro Multianual de Necesidades', 'Anexo 4', 1),
  /* El informe, nota tecnica o expediente con que el area usuaria sustenta una
     solicitud extraordinaria. No lleva firmas propias: no es un documento del
     flujo que alguien tenga que suscribir, es el respaldo que Abastecimiento
     lee para validar la urgencia. Va por la misma via que los anexos -subir al
     file server y registrar- para que herede versionado y trazabilidad en vez
     de quedar como un adjunto suelto. */
  ('CMN_SUSTENTO_URGENCIA',
   'Sustento de la urgencia de una solicitud extraordinaria', 'Sustento', 0);

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

/* Sustituye a firmas_requeridas varchar(40)[]. Cada anexo lleva varias firmas y
   el orden es el del flujo, no una preferencia de impresion.

   ESTA TABLA SOLO PUDO CRECER CUANDO paFirmarDocumento APRENDIO A CONTAR.
   Hasta V010 declaraba un firmante por documento, y no por decision funcional:
   sigcm.paFirmarDocumento marcaba la version como FIRMADO en la PRIMERA firma,
   sin llevar cuenta de las que faltaban. Con dos firmantes declarados, el
   primero que entraba daba el documento por firmado y el segundo recibia "la
   version vigente ya esta firmada". La segunda firma no existia: estaba escrita
   y nada mas. Por eso en su momento se retiro MAX_AUT_ADMIN.

   F003 ahora registra firma por firma en sigcm.Firma —que siempre estuvo
   disenada para eso, con UNIQUE (version, rol)— y solo cierra la version cuando
   estan todas las de esta tabla. Recien con eso las siete filas de abajo
   significan algo.

   Anexo 3: lo firma el jefe del area usuaria y despues lo refrendan
   especialista y jefe de Abastecimiento. Anexo 4: lo arma el especialista y lo
   firma unicamente el jefe de Abastecimiento. */
DECLARE @DocFirma TABLE (CodigoTipoDocumento varchar(60), CodigoRol varchar(40), OrdenFirma smallint);
INSERT INTO @DocFirma VALUES
  ('CMN_ANEXO_3_SOLICITUD_MODIFICACION',  'AREA_JEFE',          1),
  ('CMN_ANEXO_3_SOLICITUD_MODIFICACION',  'ABAST_ESPECIALISTA', 2),
  ('CMN_ANEXO_3_SOLICITUD_MODIFICACION',  'ABAST_JEFE',         3),

  ('CMN_ANEXO_4_APROBACION_MODIFICACION', 'ABAST_JEFE',         1);

UPDATE d SET d.OrdenFirma = s.OrdenFirma
  FROM sigcm.TipoDocumentoFirma AS d
  JOIN @DocFirma AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento AND s.CodigoRol = d.CodigoRol;

INSERT INTO sigcm.TipoDocumentoFirma (CodigoTipoDocumento, CodigoRol, OrdenFirma)
SELECT s.CodigoTipoDocumento, s.CodigoRol, s.OrdenFirma
  FROM @DocFirma AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumentoFirma AS d
                    WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento AND d.CodigoRol = s.CodigoRol);

/* Retira firmantes de CMN que ya no corresponden. Sin este DELETE, una base
   sembrada con la version anterior conservaria MAX_AUT_ADMIN para siempre:
   la semilla solo inserta y actualiza. */
DELETE d
  FROM sigcm.TipoDocumentoFirma AS d
  JOIN sigcm.TipoDocumento AS td ON td.CodigoTipoDocumento = d.CodigoTipoDocumento
 WHERE td.CodigoModulo = 'CMN'
   AND NOT EXISTS (SELECT 1 FROM @DocFirma AS s
                    WHERE s.CodigoTipoDocumento = d.CodigoTipoDocumento
                      AND s.CodigoRol = d.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 7. Transiciones del modulo CMN                                             */
/* -------------------------------------------------------------------------- */

/*
  Una fila por accion posible. El motor (F004) no sabe nada del CMN: lee de aqui
  desde donde sale la accion, a donde lleva, que exige y si encola hacia SIGA.
  Agregar un escalon al flujo es agregar filas en esta tabla y en @TrRol.

  RolFirmaRequerida (V011) es lo que hace posible la firma en cadena. Antes,
  DocumentoRequerido significaba "la version vigente esta FIRMADA", y con cuatro
  firmantes eso solo se cumple al final: el jefe del area usuaria no habria
  podido enviar a OA un Anexo 3 al que todavia le faltan las tres firmas de
  Abastecimiento. Con RolFirmaRequerida cada paso exige exactamente la firma que
  lo respalda, y solo la recepcion final del Anexo 4 exige el documento completo.
*/
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
    GeneraObservacion    bit,
    RolFirmaRequerida    varchar(40) NULL
);
INSERT INTO @Tr VALUES

  /* ---------------------------------------------------------------------- */
  /* Area usuaria: registro del Anexo 3                                     */
  /* ---------------------------------------------------------------------- */

  ('CMN_GENERAR_A3', 'CMN_BORRADOR', 'CMN_PEND_FIRMA_A3',
   'Generar Anexo 3', 0, 0, NULL, 0, NULL, 0, NULL),

  ('CMN_FIRMAR_A3', 'CMN_PEND_FIRMA_A3', 'CMN_EN_EVAL_OA',
   'Firmar Anexo 3 y remitir a la Oficina de Administracion', 0, 1,
   'CMN_ANEXO_3_SOLICITUD_MODIFICACION', 0, NULL, 0, 'AREA_JEFE'),

  /* ---------------------------------------------------------------------- */
  /* Oficina de Administracion                                              */
  /* ---------------------------------------------------------------------- */

  /* Paso 1 del flujo: OA remite al JEFE de Abastecimiento, no al coordinador.
     La entrada a Abastecimiento es siempre por la jefatura, tambien cuando el
     expediente vuelve subsanado. */
  ('CMN_OA_DERIVAR', 'CMN_EN_EVAL_OA', 'CMN_EN_ABAST_JEFE',
   'Derivar al Jefe de Abastecimiento', 0, 0, NULL, 0, NULL, 0, NULL),

  ('CMN_OA_OBSERVAR', 'CMN_EN_EVAL_OA', 'CMN_OBS_AU_JEFE',
   'Observar desde la Oficina de Administracion', 1, 0, NULL, 0, NULL, 1, NULL),

  /* ---------------------------------------------------------------------- */
  /* Abastecimiento: bajada jefe -> coordinador -> especialista             */
  /* ---------------------------------------------------------------------- */

  ('CMN_ABAST_JEFE_DERIVAR', 'CMN_EN_ABAST_JEFE', 'CMN_EN_ABAST_COORD',
   'Derivar al Coordinador de Abastecimiento', 0, 0, NULL, 0, NULL, 0, NULL),

  ('CMN_ABAST_COORD_DERIVAR', 'CMN_EN_ABAST_COORD', 'CMN_EN_ABAST_ESP',
   'Derivar al Especialista de Abastecimiento', 0, 0, NULL, 0, NULL, 0, NULL),

  /* ---------------------------------------------------------------------- */
  /* Abastecimiento: evaluacion del especialista                            */
  /* ---------------------------------------------------------------------- */

  /* El especialista es quien evalua. De aqui salen los dos unicos desenlaces
     posibles: observar o firmar. El formulario de evaluacion del frontend se
     resuelve eligiendo una de estas dos acciones; no hay un tercer camino
     "sin decidir" porque un expediente sin decision es un expediente parado. */
  ('CMN_ABAST_ESP_OBSERVAR', 'CMN_EN_ABAST_ESP', 'CMN_OBS_ABAST_COORD',
   'Observar el Anexo 3', 1, 0, NULL, 0, NULL, 1, NULL),

  ('CMN_ABAST_ESP_FIRMAR_A3', 'CMN_EN_ABAST_ESP', 'CMN_A3_FIRMA_JEFE',
   'Firmar el Anexo 3 y elevar al Jefe', 0, 1,
   'CMN_ANEXO_3_SOLICITUD_MODIFICACION', 0, NULL, 0, 'ABAST_ESPECIALISTA'),

  /* PRIMER MOMENTO DE ESCRITURA EN SIGA.
     La firma del jefe cierra el Anexo 3 y recien ahi los items entran a
     SIG_CUADRO_MODIFICADO_DET. Quedan registrados con MOTIVO_SOLICITUD distinto
     de '0': existen en SIGA pero todavia no se pueden pedir. Lo que los habilita
     es la aprobacion del Anexo 4, mas abajo. */
  ('CMN_ABAST_JEFE_FIRMAR_A3', 'CMN_A3_FIRMA_JEFE', 'CMN_A3_APROBADO',
   'Firmar el Anexo 3 y registrarlo en SIGA', 0, 1,
   'CMN_ANEXO_3_SOLICITUD_MODIFICACION', 1, 'ITEMS_ANEXO_3', 0, 'ABAST_JEFE'),

  /* ---------------------------------------------------------------------- */
  /* Devolucion de observaciones, escalon por escalon                       */
  /* ---------------------------------------------------------------------- */

  /* La observacion no salta de Abastecimiento al especialista del area: sube
     por la jerarquia de Abastecimiento y baja por la del area usuaria. Son
     cinco pasos y cada uno es un estado porque cada uno tiene un responsable
     distinto que debe verlo en su bandeja. */
  ('CMN_OBS_COORD_DERIVAR', 'CMN_OBS_ABAST_COORD', 'CMN_OBS_ABAST_JEFE',
   'Elevar la observacion al Jefe de Abastecimiento', 0, 0, NULL, 0, NULL, 0, NULL),

  ('CMN_OBS_JEFE_DEVOLVER', 'CMN_OBS_ABAST_JEFE', 'CMN_OBS_AU_JEFE',
   'Devolver observado al Jefe del area usuaria', 0, 0, NULL, 0, NULL, 0, NULL),

  ('CMN_OBS_AU_JEFE_DERIVAR', 'CMN_OBS_AU_JEFE', 'CMN_OBS_AU_COORD',
   'Derivar al Coordinador del area usuaria', 0, 0, NULL, 0, NULL, 0, NULL),

  ('CMN_OBS_AU_COORD_DERIVAR', 'CMN_OBS_AU_COORD', 'CMN_OBSERVADO',
   'Derivar al Especialista para subsanar', 0, 0, NULL, 0, NULL, 0, NULL),

  /* ---------------------------------------------------------------------- */
  /* Subsanacion y retorno                                                  */
  /* ---------------------------------------------------------------------- */

  /* CMN_SUBSANAR ya no vuelve a CMN_BORRADOR. Volver a borrador significaba
     recorrer otra vez el circuito de registro completo, incluida la firma del
     jefe como si fuera una solicitud nueva. El flujo aprobado dice otra cosa:
     el especialista corrige sobre el mismo expediente y lo devuelve por la
     linea, coordinador y jefe, hasta Abastecimiento. */
  ('CMN_SUBSANAR', 'CMN_OBSERVADO', 'CMN_SUBS_AU_COORD',
   'Registrar la subsanacion y derivar al Coordinador', 1, 0, NULL, 0, NULL, 0, NULL),

  ('CMN_SUBS_COORD_DERIVAR', 'CMN_SUBS_AU_COORD', 'CMN_SUBS_AU_JEFE',
   'Derivar lo subsanado al Jefe del area usuaria', 0, 0, NULL, 0, NULL, 0, NULL),

  /* Exige firma otra vez, y no es burocracia: al subsanar se regenera el Anexo 3
     y sigcm.paRegistrarDocumento abre una version nueva, que invalida todas las
     firmas de la anterior. Mandar a Abastecimiento un documento cuya firma ya no
     corresponde al contenido es exactamente lo que el versionado existe para
     impedir. Si el especialista no cambio nada, la version sigue siendo la misma
     y F003 reconoce la firma vigente sin pedir una nueva. */
  ('CMN_SUBS_JEFE_ENVIAR', 'CMN_SUBS_AU_JEFE', 'CMN_EN_ABAST_JEFE',
   'Firmar y remitir subsanado a Abastecimiento', 0, 1,
   'CMN_ANEXO_3_SOLICITUD_MODIFICACION', 0, NULL, 0, 'AREA_JEFE'),

  /* ---------------------------------------------------------------------- */
  /* Anexo 4                                                                */
  /* ---------------------------------------------------------------------- */

  /* El expediente sale de CMN_A3_APROBADO cuando el especialista lo incluye en
     un Anexo 4, solo o junto a otros. La transicion se ejecuta sobre TODOS los
     expedientes del paquete a la vez —F004 acepta IdExpedientes— porque un
     Anexo 4 a medio armar, con unos expedientes movidos y otros no, no es un
     estado recuperable. */
  ('CMN_GENERAR_A4', 'CMN_A3_APROBADO', 'CMN_A4_FIRMA_JEFE',
   'Generar Anexo 4 y remitir al Jefe', 0, 0,
   'CMN_ANEXO_4_APROBACION_MODIFICACION', 0, NULL, 0, NULL),

  /* SEGUNDO MOMENTO DE ESCRITURA EN SIGA.
     Aqui se aprueban las solicitudes: MOTIVO_SOLICITUD pasa a '0' y el item
     queda pedible. Se encola una operacion por expediente del paquete, que es
     el "multiple registro de aprobaciones" del flujo: un Anexo 4 con cinco
     Anexos 3 produce cinco aprobaciones en SIGA, una por area usuaria.

     El destino es CMN_A4_ENVIADO y no un estado intermedio de firmado: el flujo
     pide que tras la firma del jefe el expediente pase automaticamente al jefe
     del area usuaria. Un estado intermedio obligaria a un clic mas que nadie
     pidio. */
  ('CMN_ABAST_JEFE_FIRMAR_A4', 'CMN_A4_FIRMA_JEFE', 'CMN_A4_ENVIADO',
   'Firmar el Anexo 4, aprobar en SIGA y remitir al area usuaria', 0, 1,
   'CMN_ANEXO_4_APROBACION_MODIFICACION', 1, 'CONSOLIDAR_CMN', 0, 'ABAST_JEFE'),

  /* Unica transicion sin RolFirmaRequerida entre las que exigen documento: al
     recepcionar, el Anexo 4 ya debe estar firmado por el jefe de Abastecimiento. */
  ('CMN_RECEPCIONAR_A4', 'CMN_A4_ENVIADO', 'CMN_FINALIZADO',
   'Recepcionar Anexo 4', 0, 0,
   'CMN_ANEXO_4_APROBACION_MODIFICACION', 0, NULL, 0, NULL),

  /* ---------------------------------------------------------------------- */
  /* Anulacion                                                              */
  /* ---------------------------------------------------------------------- */

  ('CMN_ANULAR_BORRADOR', 'CMN_BORRADOR', 'CMN_ANULADO',
   'Anular solicitud en borrador', 1, 0, NULL, 0, NULL, 0, NULL),

  ('CMN_ANULAR_FIRMA_PEND', 'CMN_PEND_FIRMA_A3', 'CMN_ANULADO',
   'Anular solicitud pendiente de firma', 1, 0, NULL, 0, NULL, 0, NULL);

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
       d.RolFirmaRequerida = s.RolFirmaRequerida,
       d.Activo = 1
  FROM sigcm.Transicion AS d JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion
      (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
       NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
       EncolaIntegracion, OperacionIntegracion, GeneraObservacion, RolFirmaRequerida)
SELECT s.CodigoTransicion, 'CMN', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion, s.RolFirmaRequerida
  FROM @Tr AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);

/*
  Una transicion retirada de la semilla debe dejar de ofrecerse.

  Sin esto, las transiciones del flujo anterior —CMN_DERIVAR_UA, CMN_VALIDAR_UA,
  CMN_OBSERVAR_UA, CMN_FIRMAR_A4, CMN_ENVIAR_A4, CMN_REENVIAR_UA— seguirian
  activas y F004 las seguiria ofreciendo desde los estados que aun las tienen
  como origen. El resultado seria un expediente con botones de dos flujos
  distintos, y el usuario eligiendo entre ellos sin saberlo.

  Se desactivan en vez de borrarse: sigcm.Historial las referencia y la
  trazabilidad de lo ya tramitado tiene que seguir leyendose.
*/
UPDATE d
   SET d.Activo = 0
  FROM sigcm.Transicion AS d
 WHERE d.CodigoModulo = 'CMN'
   AND NOT EXISTS (SELECT 1 FROM @Tr AS s WHERE s.CodigoTransicion = d.CodigoTransicion);
GO

/* Roles permitidos por transicion. Sustituye a roles_permitidos varchar(40)[]. */
DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  /* Area usuaria */
  ('CMN_GENERAR_A3','AREA_ESPECIALISTA'), ('CMN_GENERAR_A3','AREA_COORDINADOR'),
  ('CMN_GENERAR_A3','AREA_JEFE'),
  ('CMN_FIRMAR_A3','AREA_JEFE'),

  /* Oficina de Administracion */
  ('CMN_OA_DERIVAR','OA'),
  ('CMN_OA_OBSERVAR','OA'),

  /* Abastecimiento: bajada y evaluacion.
     Cada accion la ejecuta UN rol. La version anterior dejaba que coordinador y
     especialista hicieran indistintamente lo mismo, y eso era justamente lo que
     borraba la diferencia entre los dos perfiles. */
  ('CMN_ABAST_JEFE_DERIVAR','ABAST_JEFE'),
  ('CMN_ABAST_COORD_DERIVAR','ABAST_COORDINADOR'),
  ('CMN_ABAST_ESP_OBSERVAR','ABAST_ESPECIALISTA'),
  ('CMN_ABAST_ESP_FIRMAR_A3','ABAST_ESPECIALISTA'),
  ('CMN_ABAST_JEFE_FIRMAR_A3','ABAST_JEFE'),

  /* Devolucion de observaciones */
  ('CMN_OBS_COORD_DERIVAR','ABAST_COORDINADOR'),
  ('CMN_OBS_JEFE_DEVOLVER','ABAST_JEFE'),
  ('CMN_OBS_AU_JEFE_DERIVAR','AREA_JEFE'),
  ('CMN_OBS_AU_COORD_DERIVAR','AREA_COORDINADOR'),

  /* Subsanacion */
  ('CMN_SUBSANAR','AREA_ESPECIALISTA'),
  ('CMN_SUBS_COORD_DERIVAR','AREA_COORDINADOR'),
  ('CMN_SUBS_JEFE_ENVIAR','AREA_JEFE'),

  /* Anexo 4 */
  ('CMN_GENERAR_A4','ABAST_ESPECIALISTA'),
  ('CMN_ABAST_JEFE_FIRMAR_A4','ABAST_JEFE'),
  ('CMN_RECEPCIONAR_A4','AREA_JEFE'),

  /* Anulacion */
  ('CMN_ANULAR_BORRADOR','AREA_ESPECIALISTA'), ('CMN_ANULAR_BORRADOR','AREA_COORDINADOR'),
  ('CMN_ANULAR_BORRADOR','AREA_JEFE'),
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
