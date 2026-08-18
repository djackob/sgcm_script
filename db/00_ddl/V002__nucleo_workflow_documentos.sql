/*
===============================================================================
  SIGCM - Migracion V002 : Expediente, maquina de estados, documentos y firmas
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Port de SIGCM/db/00_ddl/V002__nucleo_workflow_documentos.sql (PostgreSQL 14).

  Estos objetos son transversales. El modulo CMN los usa tal cual; Requerimiento
  a Notificacion, Ejecucion, Pago, Modificacion-Ampliacion y Resolucion se
  incorporan agregando filas en sigcm.Modulo, sigcm.Estado, sigcm.Transicion y
  sigcm.TipoDocumento, sin DDL nuevo.

  DIFERENCIA CON POSTGRESQL
  -------------------------
  Dos columnas eran arreglos nativos: sigcm.transicion.roles_permitidos y
  sigcm.tipo_documento.firmas_requeridas, ambas varchar(40)[]. SQL Server no tiene
  arreglos. Se resuelven con tablas hijas (sigcm.TransicionRol y
  sigcm.TipoDocumentoFirma) en vez de una cadena delimitada: asi el rol queda unido
  por clave foranea a sigcm.Rol y no se puede escribir un rol inexistente, que es
  justamente lo que una cadena con separadores no puede garantizar.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Expediente: identidad del tramite                                       */
/* -------------------------------------------------------------------------- */

/* Identidad estable del tramite. El payload especifico vive en el esquema del
   modulo (cmn.Solicitud para la v1) con relacion 1:1. Permite que bandejas,
   trazabilidad, documentos, plazos y auditoria sean codigo unico.

   IdExpedientePadre encadena tramites derivados: un requerimiento que nace de un
   CMN aprobado, una ampliacion sobre una orden. Sin esto la trazabilidad entre
   modulos se pierde.

   Version es control de concurrencia optimista: toda escritura compara y sube
   Version.

   Anulado convive con Activo y NO es redundante: Activo = 0 es baja logica de
   mantenimiento (el registro se retira del sistema), Anulado = 1 es un estado
   del tramite con motivo, que sigue siendo visible y auditable. */
IF OBJECT_ID(N'sigcm.Expediente', N'U') IS NULL
CREATE TABLE sigcm.Expediente (
    IdExpediente           uniqueidentifier NOT NULL
                           CONSTRAINT DF_sigcm_Expediente_Id DEFAULT (NEWSEQUENTIALID())
                           CONSTRAINT PK_sigcm_Expediente PRIMARY KEY,
    Codigo                 varchar(40) NOT NULL CONSTRAINT UQ_sigcm_Expediente_Codigo UNIQUE,
    CodigoModulo           varchar(30) NOT NULL
                           CONSTRAINT FK_sigcm_Expediente_Modulo REFERENCES sigcm.Modulo(CodigoModulo),
    CodigoTipoContratacion varchar(20)     NULL
                           CONSTRAINT FK_sigcm_Expediente_TipoCon REFERENCES sigcm.TipoContratacion(CodigoTipoContratacion),

    AnoEje                 smallint NOT NULL,
    IdUnidadOrigen         uniqueidentifier NOT NULL
                           CONSTRAINT FK_sigcm_Expediente_UnidadOrigen REFERENCES sigcm.Unidad(IdUnidad),

    CodigoEstado           varchar(60) NOT NULL,
    IdUnidadActual         uniqueidentifier NULL
                           CONSTRAINT FK_sigcm_Expediente_UnidadActual REFERENCES sigcm.Unidad(IdUnidad),
    IdResponsableActual    uniqueidentifier NULL
                           CONSTRAINT FK_sigcm_Expediente_Responsable REFERENCES sigcm.Usuario(IdUsuario),

    Version                int NOT NULL CONSTRAINT DF_sigcm_Expediente_Version DEFAULT (1),

    IdExpedientePadre      uniqueidentifier NULL
                           CONSTRAINT FK_sigcm_Expediente_Padre REFERENCES sigcm.Expediente(IdExpediente),
    Anulado                bit NOT NULL CONSTRAINT DF_sigcm_Expediente_Anulado DEFAULT (0),
    MotivoAnulacion        nvarchar(max) NULL,
    CerradoEn              datetime NULL,
    Activo                 bit NOT NULL CONSTRAINT DF_sigcm_Expediente_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_sigcm_Expediente_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,
    UsuarioEliminacionAuditoria   varchar(30) NULL,
    FechaEliminacionAuditoria     datetime    NULL,
    EquipoEliminacionAuditoria    varchar(50) NULL,
    ProgramaEliminacionAuditoria  varchar(50) NULL,

    CONSTRAINT CK_sigcm_Expediente_Version CHECK (Version > 0),
    CONSTRAINT CK_sigcm_Expediente_Anulado CHECK (Anulado = 0 OR MotivoAnulacion IS NOT NULL)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Expediente_Bandeja' AND object_id = OBJECT_ID(N'sigcm.Expediente'))
CREATE NONCLUSTERED INDEX IX_sigcm_Expediente_Bandeja
    ON sigcm.Expediente(CodigoModulo, CodigoEstado, IdUnidadActual)
    WHERE Anulado = 0 AND Activo = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Expediente_Responsable' AND object_id = OBJECT_ID(N'sigcm.Expediente'))
CREATE NONCLUSTERED INDEX IX_sigcm_Expediente_Responsable
    ON sigcm.Expediente(IdResponsableActual, FechaModificacionAuditoria DESC)
    WHERE Anulado = 0 AND Activo = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Expediente_Origen' AND object_id = OBJECT_ID(N'sigcm.Expediente'))
CREATE NONCLUSTERED INDEX IX_sigcm_Expediente_Origen
    ON sigcm.Expediente(IdUnidadOrigen, AnoEje);
GO

/* -------------------------------------------------------------------------- */
/* 2. Maquina de estados configurable                                         */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'sigcm.Estado', N'U') IS NULL
CREATE TABLE sigcm.Estado (
    CodigoEstado    varchar(60)  NOT NULL CONSTRAINT PK_sigcm_Estado PRIMARY KEY,
    CodigoModulo    varchar(30)  NOT NULL CONSTRAINT FK_sigcm_Estado_Modulo REFERENCES sigcm.Modulo(CodigoModulo),
    Nombre          varchar(150) NOT NULL,
    Orden           int          NOT NULL,
    EsInicial       bit NOT NULL CONSTRAINT DF_sigcm_Estado_Inicial DEFAULT (0),
    EsFinal         bit NOT NULL CONSTRAINT DF_sigcm_Estado_Final   DEFAULT (0),
    /* Rol responsable por defecto mientras el expediente esta en este estado */
    RolResponsable  varchar(40) NULL CONSTRAINT FK_sigcm_Estado_Rol REFERENCES sigcm.Rol(CodigoRol),
    Activo          bit NOT NULL CONSTRAINT DF_sigcm_Estado_Activo DEFAULT (1)
);
GO

/* Solo un estado inicial por modulo. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_sigcm_Estado_Inicial' AND object_id = OBJECT_ID(N'sigcm.Estado'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_sigcm_Estado_Inicial
    ON sigcm.Estado(CodigoModulo)
    WHERE EsInicial = 1;
GO

/* La clave foranea de sigcm.Expediente.CodigoEstado se agrega aqui porque sigcm.Estado
   se declara despues de la tabla que la referencia. El nombre de una restriccion
   se resuelve en el esquema de su tabla padre, de ahi el prefijo sigcm. */
IF OBJECT_ID(N'sigcm.FK_sigcm_Expediente_Estado', N'F') IS NOT NULL
    ALTER TABLE sigcm.Expediente DROP CONSTRAINT FK_sigcm_Expediente_Estado;
GO
ALTER TABLE sigcm.Expediente
    ADD CONSTRAINT FK_sigcm_Expediente_Estado FOREIGN KEY (CodigoEstado) REFERENCES sigcm.Estado(CodigoEstado);
GO

/* EncolaIntegracion marca la transicion que dispara el outbox. Mantenerlo como
   dato permite mover el momento de registro en SIGA sin tocar codigo.

   OperacionIntegracion no existia en PostgreSQL: alli el escalon estaba
   implicito, y por eso el comentario de integracion.operacion y la unica transicion
   sembrada se contradecian. Hacerlo explicito resuelve esa inconsistencia. */
IF OBJECT_ID(N'sigcm.Transicion', N'U') IS NULL
CREATE TABLE sigcm.Transicion (
    CodigoTransicion     varchar(70)  NOT NULL CONSTRAINT PK_sigcm_Transicion PRIMARY KEY,
    CodigoModulo         varchar(30)  NOT NULL CONSTRAINT FK_sigcm_Transicion_Modulo  REFERENCES sigcm.Modulo(CodigoModulo),
    CodigoEstadoOrigen   varchar(60)  NOT NULL CONSTRAINT FK_sigcm_Transicion_Origen  REFERENCES sigcm.Estado(CodigoEstado),
    CodigoEstadoDestino  varchar(60)  NOT NULL CONSTRAINT FK_sigcm_Transicion_Destino REFERENCES sigcm.Estado(CodigoEstado),
    NombreAccion         varchar(180) NOT NULL,
    RequiereComentario   bit NOT NULL CONSTRAINT DF_sigcm_Transicion_Coment DEFAULT (0),
    RequiereFirma        bit NOT NULL CONSTRAINT DF_sigcm_Transicion_Firma  DEFAULT (0),
    /* Tipo de documento que debe existir y estar firmado para permitir el paso */
    DocumentoRequerido   varchar(60) NULL,
    EncolaIntegracion    bit NOT NULL CONSTRAINT DF_sigcm_Transicion_Encola DEFAULT (0),
    OperacionIntegracion varchar(30) NULL,
    /* La transicion abre una observacion que despues debe subsanarse. El estado
       al que se retorna tras subsanar no se cablea: se guarda en
       sigcm.Observacion.CodigoEstadoRetorno tomandolo del estado en que estaba el
       expediente al observarse. Asi se cumple la regla del mockup —lo que observa
       OA vuelve a OA, lo que observa Abastecimiento vuelve a Abastecimiento— sin
       un condicional por unidad. */
    GeneraObservacion    bit NOT NULL CONSTRAINT DF_sigcm_Transicion_Observa DEFAULT (0),
    Activo               bit NOT NULL CONSTRAINT DF_sigcm_Transicion_Activo DEFAULT (1),
    CONSTRAINT CK_sigcm_Transicion_Distinta CHECK (CodigoEstadoOrigen <> CodigoEstadoDestino),
    CONSTRAINT CK_sigcm_Transicion_Encola
        CHECK ((EncolaIntegracion = 0 AND OperacionIntegracion IS NULL)
            OR (EncolaIntegracion = 1 AND OperacionIntegracion IS NOT NULL))
);
GO

/* Alta de columna para instalaciones que ya tenian la tabla. Una migracion no
   solo debe funcionar sobre base limpia: tiene que llevar de la version anterior
   a la nueva sin recrear nada. */
IF COL_LENGTH(N'sigcm.Transicion', N'GeneraObservacion') IS NULL
    ALTER TABLE sigcm.Transicion
        ADD GeneraObservacion bit NOT NULL
            CONSTRAINT DF_sigcm_Transicion_Observa DEFAULT (0);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Transicion_Origen' AND object_id = OBJECT_ID(N'sigcm.Transicion'))
CREATE NONCLUSTERED INDEX IX_sigcm_Transicion_Origen
    ON sigcm.Transicion(CodigoModulo, CodigoEstadoOrigen)
    WHERE Activo = 1;
GO

/* Sustituye a sigcm.transicion.roles_permitidos varchar(40)[] de PostgreSQL. */
IF OBJECT_ID(N'sigcm.TransicionRol', N'U') IS NULL
CREATE TABLE sigcm.TransicionRol (
    CodigoTransicion varchar(70) NOT NULL
                     CONSTRAINT FK_sigcm_TransicionRol_Transicion REFERENCES sigcm.Transicion(CodigoTransicion) ON DELETE CASCADE,
    CodigoRol        varchar(40) NOT NULL
                     CONSTRAINT FK_sigcm_TransicionRol_Rol REFERENCES sigcm.Rol(CodigoRol),
    CONSTRAINT PK_sigcm_TransicionRol PRIMARY KEY (CodigoTransicion, CodigoRol)
);
GO

IF OBJECT_ID(N'sigcm.Historial', N'U') IS NULL
CREATE TABLE sigcm.Historial (
    IdHistorial         bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_sigcm_Historial PRIMARY KEY,
    IdExpediente        uniqueidentifier NOT NULL
                        CONSTRAINT FK_sigcm_Historial_Expediente REFERENCES sigcm.Expediente(IdExpediente) ON DELETE CASCADE,
    CodigoEstadoOrigen  varchar(60)     NULL,
    CodigoEstadoDestino varchar(60) NOT NULL,
    CodigoTransicion    varchar(70)     NULL,
    Comentario          nvarchar(max)   NULL,
    IdActor             uniqueidentifier NOT NULL
                        CONSTRAINT FK_sigcm_Historial_Actor REFERENCES sigcm.Usuario(IdUsuario),
    ActorRol            varchar(40) NOT NULL,
    IdActorUnidad       uniqueidentifier NULL
                        CONSTRAINT FK_sigcm_Historial_Unidad REFERENCES sigcm.Unidad(IdUnidad),
    Metadata            nvarchar(max) NOT NULL CONSTRAINT DF_sigcm_Historial_Metadata DEFAULT (N'{}'),
    OcurridoEn          datetime NOT NULL CONSTRAINT DF_sigcm_Historial_Ocurrido DEFAULT (GETDATE()),
    /* El historial no se modifica ni se borra: solo lleva usuario y equipo de
       creacion. Un historial editable no es un historial. */
    UsuarioCreacionAuditoria  varchar(30) NULL,
    EquipoCreacionAuditoria   varchar(50) NULL,
    ProgramaCreacionAuditoria varchar(50) NULL,
    CONSTRAINT CK_sigcm_Historial_Metadata CHECK (ISJSON(Metadata) = 1)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Historial_Expediente' AND object_id = OBJECT_ID(N'sigcm.Historial'))
CREATE NONCLUSTERED INDEX IX_sigcm_Historial_Expediente
    ON sigcm.Historial(IdExpediente, OcurridoEn DESC);
GO

/* -------------------------------------------------------------------------- */
/* 3. Documentos, versiones y firmas                                          */
/* -------------------------------------------------------------------------- */

/* El codigo es funcional y unico en todo el sistema
   (CMN_ANEXO_3_SOLICITUD_MODIFICACION). NumeracionVisible conserva el rotulo de
   la directiva, que SI se repite entre modulos: el Anexo 3 de CMN no es el
   Anexo 3 de Requerimiento. Tablas, APIs y permisos usan siempre el codigo. */
IF OBJECT_ID(N'sigcm.TipoDocumento', N'U') IS NULL
CREATE TABLE sigcm.TipoDocumento (
    CodigoTipoDocumento varchar(60)  NOT NULL CONSTRAINT PK_sigcm_TipoDocumento PRIMARY KEY,
    CodigoModulo        varchar(30)  NOT NULL CONSTRAINT FK_sigcm_TipoDoc_Modulo REFERENCES sigcm.Modulo(CodigoModulo),
    Nombre              varchar(200) NOT NULL,
    NumeracionVisible   varchar(60)  NOT NULL,
    AdmiteConsolidado   bit NOT NULL CONSTRAINT DF_sigcm_TipoDoc_Consolidado DEFAULT (0),
    Activo              bit NOT NULL CONSTRAINT DF_sigcm_TipoDoc_Activo      DEFAULT (1)
);
GO

/* Sustituye a sigcm.tipo_documento.firmas_requeridas varchar(40)[]. OrdenFirma
   estaba implicito en la posicion del arreglo; aqui es explicito. */
IF OBJECT_ID(N'sigcm.TipoDocumentoFirma', N'U') IS NULL
CREATE TABLE sigcm.TipoDocumentoFirma (
    CodigoTipoDocumento varchar(60) NOT NULL
                        CONSTRAINT FK_sigcm_TipoDocFirma_Tipo REFERENCES sigcm.TipoDocumento(CodigoTipoDocumento) ON DELETE CASCADE,
    CodigoRol           varchar(40) NOT NULL
                        CONSTRAINT FK_sigcm_TipoDocFirma_Rol REFERENCES sigcm.Rol(CodigoRol),
    OrdenFirma          smallint NOT NULL CONSTRAINT DF_sigcm_TipoDocFirma_Orden DEFAULT (1),
    CONSTRAINT PK_sigcm_TipoDocumentoFirma PRIMARY KEY (CodigoTipoDocumento, CodigoRol)
);
GO

/* La clave foranea de sigcm.Transicion.DocumentoRequerido se agrega aqui porque
   sigcm.TipoDocumento se declara despues de sigcm.Transicion. */
IF OBJECT_ID(N'sigcm.FK_sigcm_Transicion_Documento', N'F') IS NOT NULL
    ALTER TABLE sigcm.Transicion DROP CONSTRAINT FK_sigcm_Transicion_Documento;
GO
ALTER TABLE sigcm.Transicion
    ADD CONSTRAINT FK_sigcm_Transicion_Documento
    FOREIGN KEY (DocumentoRequerido) REFERENCES sigcm.TipoDocumento(CodigoTipoDocumento);
GO

IF OBJECT_ID(N'sigcm.Documento', N'U') IS NULL
CREATE TABLE sigcm.Documento (
    IdDocumento         uniqueidentifier NOT NULL
                        CONSTRAINT DF_sigcm_Documento_Id DEFAULT (NEWSEQUENTIALID())
                        CONSTRAINT PK_sigcm_Documento PRIMARY KEY,
    CodigoTipoDocumento varchar(60) NOT NULL
                        CONSTRAINT FK_sigcm_Documento_Tipo REFERENCES sigcm.TipoDocumento(CodigoTipoDocumento),
    Numero              varchar(80) NOT NULL,
    Consolidado         bit NOT NULL CONSTRAINT DF_sigcm_Documento_Consolidado DEFAULT (0),
    VersionVigente      int NOT NULL CONSTRAINT DF_sigcm_Documento_Version     DEFAULT (1),
    Anulado             bit NOT NULL CONSTRAINT DF_sigcm_Documento_Anulado     DEFAULT (0),
    Activo              bit NOT NULL CONSTRAINT DF_sigcm_Documento_Activo      DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_sigcm_Documento_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,
    UsuarioEliminacionAuditoria   varchar(30) NULL,
    FechaEliminacionAuditoria     datetime    NULL,
    EquipoEliminacionAuditoria    varchar(50) NULL,
    ProgramaEliminacionAuditoria  varchar(50) NULL,

    CONSTRAINT UQ_sigcm_Documento_TipoNumero UNIQUE (CodigoTipoDocumento, Numero)
);
GO

/* N:M. Un Anexo 4 consolidado cubre varias solicitudes; un expediente acumula
   varios documentos a lo largo del flujo.

   Nota SQL Server: solo el lado del documento cascadea. Si ambas claves
   cascadearan, el motor rechaza la tabla por rutas de cascada multiples
   (error 1785). El expediente no se borra fisicamente: se anula. */
IF OBJECT_ID(N'sigcm.DocumentoExpediente', N'U') IS NULL
CREATE TABLE sigcm.DocumentoExpediente (
    IdDocumento  uniqueidentifier NOT NULL
                 CONSTRAINT FK_sigcm_DocExp_Documento REFERENCES sigcm.Documento(IdDocumento) ON DELETE CASCADE,
    IdExpediente uniqueidentifier NOT NULL
                 CONSTRAINT FK_sigcm_DocExp_Expediente REFERENCES sigcm.Expediente(IdExpediente),
    CONSTRAINT PK_sigcm_DocumentoExpediente PRIMARY KEY (IdDocumento, IdExpediente)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_DocExp_Inverso' AND object_id = OBJECT_ID(N'sigcm.DocumentoExpediente'))
CREATE NONCLUSTERED INDEX IX_sigcm_DocExp_Inverso
    ON sigcm.DocumentoExpediente(IdExpediente, IdDocumento);
GO

/* Payload es un snapshot inmutable. Nunca se recalcula desde la solicitud: si se
   recalculara, un anexo ya firmado cambiaria de contenido al subsanar, que es
   precisamente lo que la version pretende evitar. */
IF OBJECT_ID(N'sigcm.DocumentoVersion', N'U') IS NULL
CREATE TABLE sigcm.DocumentoVersion (
    IdDocumentoVersion uniqueidentifier NOT NULL
                       CONSTRAINT DF_sigcm_DocVersion_Id DEFAULT (NEWSEQUENTIALID())
                       CONSTRAINT PK_sigcm_DocumentoVersion PRIMARY KEY,
    IdDocumento        uniqueidentifier NOT NULL
                       CONSTRAINT FK_sigcm_DocVersion_Documento REFERENCES sigcm.Documento(IdDocumento) ON DELETE CASCADE,
    Version            int         NOT NULL,
    Estado             varchar(15) NOT NULL CONSTRAINT DF_sigcm_DocVersion_Estado DEFAULT ('BORRADOR'),
    Payload            nvarchar(max) NOT NULL,
    ArchivoUri         nvarchar(max)  NULL,
    ArchivoHash        varchar(128)   NULL,
    MotivoVersion      nvarchar(max)  NULL,
    FirmadoEn          datetime       NULL,
    Activo             bit NOT NULL CONSTRAINT DF_sigcm_DocVersion_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_sigcm_DocVersion_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,

    CONSTRAINT UQ_sigcm_DocVersion_Documento UNIQUE (IdDocumento, Version),
    CONSTRAINT CK_sigcm_DocVersion_Pos     CHECK (Version > 0),
    CONSTRAINT CK_sigcm_DocVersion_Payload CHECK (ISJSON(Payload) = 1),
    CONSTRAINT CK_sigcm_DocVersion_Estado
        CHECK (Estado IN ('BORRADOR','FIRMADO','SUPERADA','ANULADA'))
);
GO

/* La firma cuelga de la VERSION, no del documento. Al generar una version nueva
   las firmas de la anterior pasan a INVALIDADA y el flujo vuelve a exigir firma.
   Es la regla del mockup y un criterio de aceptacion del MVP.

   FirmanteNombre y FirmanteCargo se copian al firmar: si la persona cambia de
   cargo o deja la entidad, el documento firmado debe seguir mostrando lo que era
   cierto en ese momento. */
IF OBJECT_ID(N'sigcm.Firma', N'U') IS NULL
CREATE TABLE sigcm.Firma (
    IdFirma             uniqueidentifier NOT NULL
                        CONSTRAINT DF_sigcm_Firma_Id DEFAULT (NEWSEQUENTIALID())
                        CONSTRAINT PK_sigcm_Firma PRIMARY KEY,
    IdDocumentoVersion  uniqueidentifier NOT NULL
                        CONSTRAINT FK_sigcm_Firma_Version REFERENCES sigcm.DocumentoVersion(IdDocumentoVersion) ON DELETE CASCADE,
    CodigoRol           varchar(40)  NOT NULL CONSTRAINT FK_sigcm_Firma_Rol      REFERENCES sigcm.Rol(CodigoRol),
    OrdenFirma          smallint     NOT NULL CONSTRAINT DF_sigcm_Firma_Orden DEFAULT (1),
    IdFirmante          uniqueidentifier NOT NULL CONSTRAINT FK_sigcm_Firma_Firmante REFERENCES sigcm.Usuario(IdUsuario),
    FirmanteNombre      varchar(200) NOT NULL,
    FirmanteCargo       varchar(200) NOT NULL,
    Estado              varchar(15)  NOT NULL CONSTRAINT DF_sigcm_Firma_Estado DEFAULT ('FIRMADA'),
    CertificadoSerie    varchar(250)     NULL,
    FirmaHash           varchar(256) NOT NULL,
    FirmaPayload        nvarchar(max) NOT NULL CONSTRAINT DF_sigcm_Firma_Payload DEFAULT (N'{}'),
    FirmadoEn           datetime NOT NULL CONSTRAINT DF_sigcm_Firma_Firmado DEFAULT (GETDATE()),
    InvalidadaEn        datetime      NULL,
    MotivoInvalidacion  nvarchar(max) NULL,

    UsuarioCreacionAuditoria  varchar(30) NULL,
    EquipoCreacionAuditoria   varchar(50) NULL,
    ProgramaCreacionAuditoria varchar(50) NULL,

    CONSTRAINT UQ_sigcm_Firma_VersionRol UNIQUE (IdDocumentoVersion, CodigoRol),
    CONSTRAINT CK_sigcm_Firma_Estado  CHECK (Estado IN ('FIRMADA','INVALIDADA')),
    CONSTRAINT CK_sigcm_Firma_Payload CHECK (ISJSON(FirmaPayload) = 1),
    CONSTRAINT CK_sigcm_Firma_Invalidacion
        CHECK (Estado = 'FIRMADA' OR InvalidadaEn IS NOT NULL)
);
GO

PRINT 'V002 aplicada.';
GO
