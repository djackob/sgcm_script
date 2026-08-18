/*
===============================================================================
  SIGCM - Migracion V003 : Observaciones, plazos y auditoria
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Port de SIGCM/db/00_ddl/V003__nucleo_observaciones_plazos_auditoria.sql.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Observaciones y subsanaciones                                           */
/* -------------------------------------------------------------------------- */

/* CodigoEstadoRetorno guarda el estado al que debe volver el expediente una vez
   subsanado. Aqui vive la regla "lo que observa OA vuelve a OA, lo que observa
   Abastecimiento vuelve a Abastecimiento": es dato, no condicional. Se calcula
   al momento de observar, tomandolo del estado en que se encontraba el
   expediente. Guardarlo evita reconstruir el origen de la devolucion mas tarde,
   que es donde este tipo de flujos suele fallar. */
IF OBJECT_ID(N'sigcm.Observacion', N'U') IS NULL
CREATE TABLE sigcm.Observacion (
    IdObservacion       uniqueidentifier NOT NULL
                        CONSTRAINT DF_sigcm_Observacion_Id DEFAULT (NEWSEQUENTIALID())
                        CONSTRAINT PK_sigcm_Observacion PRIMARY KEY,
    IdExpediente        uniqueidentifier NOT NULL
                        CONSTRAINT FK_sigcm_Observacion_Expediente REFERENCES sigcm.Expediente(IdExpediente) ON DELETE CASCADE,
    /* Version del documento sobre la que se observa, cuando aplica */
    IdDocumentoVersion  uniqueidentifier NULL
                        CONSTRAINT FK_sigcm_Observacion_DocVersion REFERENCES sigcm.DocumentoVersion(IdDocumentoVersion),

    IdUnidadOrigen      uniqueidentifier NOT NULL
                        CONSTRAINT FK_sigcm_Observacion_UnidadOrigen REFERENCES sigcm.Unidad(IdUnidad),
    CodigoRolOrigen     varchar(40) NOT NULL
                        CONSTRAINT FK_sigcm_Observacion_RolOrigen REFERENCES sigcm.Rol(CodigoRol),
    IdUnidadDestino     uniqueidentifier NOT NULL
                        CONSTRAINT FK_sigcm_Observacion_UnidadDestino REFERENCES sigcm.Unidad(IdUnidad),

    CodigoEstadoRetorno varchar(60) NOT NULL
                        CONSTRAINT FK_sigcm_Observacion_EstadoRetorno REFERENCES sigcm.Estado(CodigoEstado),

    Motivo              nvarchar(max) NOT NULL,
    Estado              varchar(15)   NOT NULL CONSTRAINT DF_sigcm_Observacion_Estado DEFAULT ('PENDIENTE'),
    Respuesta           nvarchar(max)     NULL,

    /* El area usuaria debe recepcionar antes de poder corregir */
    IdRecepcionadaPor   uniqueidentifier NULL
                        CONSTRAINT FK_sigcm_Observacion_Recepcionada REFERENCES sigcm.Usuario(IdUsuario),
    RecepcionadaEn      datetime NULL,
    IdSubsanadaPor      uniqueidentifier NULL
                        CONSTRAINT FK_sigcm_Observacion_Subsanada REFERENCES sigcm.Usuario(IdUsuario),
    SubsanadaEn         datetime NULL,
    CerradaEn           datetime NULL,
    Activo              bit NOT NULL CONSTRAINT DF_sigcm_Observacion_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_sigcm_Observacion_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,

    CONSTRAINT CK_sigcm_Observacion_Estado
        CHECK (Estado IN ('PENDIENTE','RECEPCIONADA','SUBSANADA','CERRADA')),
    CONSTRAINT CK_sigcm_Observacion_Recepcion
        CHECK (Estado = 'PENDIENTE' OR RecepcionadaEn IS NOT NULL)
);
GO

/* Un expediente no puede tener dos observaciones abiertas a la vez. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_sigcm_Observacion_Abierta' AND object_id = OBJECT_ID(N'sigcm.Observacion'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_sigcm_Observacion_Abierta
    ON sigcm.Observacion(IdExpediente)
    WHERE Estado IN ('PENDIENTE','RECEPCIONADA') AND Activo = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Observacion_Expediente' AND object_id = OBJECT_ID(N'sigcm.Observacion'))
CREATE NONCLUSTERED INDEX IX_sigcm_Observacion_Expediente
    ON sigcm.Observacion(IdExpediente, FechaCreacionAuditoria DESC);
GO

/* -------------------------------------------------------------------------- */
/* 2. Plazos de la Directiva                                                  */
/* -------------------------------------------------------------------------- */

/* Feriados y dias no laborables declarados. Los sabados y domingos se resuelven
   por calculo; esta tabla solo lleva las excepciones. */
IF OBJECT_ID(N'sigcm.DiaNoHabil', N'U') IS NULL
CREATE TABLE sigcm.DiaNoHabil (
    Fecha       date         NOT NULL CONSTRAINT PK_sigcm_DiaNoHabil PRIMARY KEY,
    Descripcion varchar(200) NOT NULL,
    Activo      bit NOT NULL CONSTRAINT DF_sigcm_DiaNoHabil_Activo DEFAULT (1)
);
GO

/* Los plazos de la Directiva 002-2026-ANIN se declaran como datos. Cambiar un
   plazo por modificacion normativa debe ser un UPDATE, no un despliegue. */
IF OBJECT_ID(N'sigcm.PlazoRegla', N'U') IS NULL
CREATE TABLE sigcm.PlazoRegla (
    CodigoRegla        varchar(60)  NOT NULL CONSTRAINT PK_sigcm_PlazoRegla PRIMARY KEY,
    CodigoModulo       varchar(30)  NOT NULL CONSTRAINT FK_sigcm_PlazoRegla_Modulo REFERENCES sigcm.Modulo(CodigoModulo),
    Nombre             varchar(200) NOT NULL,
    /* Estado cuya entrada inicia el conteo */
    CodigoEstadoInicio varchar(60)  NOT NULL CONSTRAINT FK_sigcm_PlazoRegla_Estado REFERENCES sigcm.Estado(CodigoEstado),
    Dias               int          NOT NULL,
    TipoDia            varchar(10)  NOT NULL CONSTRAINT DF_sigcm_PlazoRegla_TipoDia   DEFAULT ('HABIL'),
    Ampliable          bit          NOT NULL CONSTRAINT DF_sigcm_PlazoRegla_Ampliable DEFAULT (0),
    BaseNormativa      varchar(200)     NULL,
    Activo             bit          NOT NULL CONSTRAINT DF_sigcm_PlazoRegla_Activo    DEFAULT (1),
    CONSTRAINT CK_sigcm_PlazoRegla_Dias CHECK (Dias > 0),
    CONSTRAINT CK_sigcm_PlazoRegla_Tipo CHECK (TipoDia IN ('HABIL','CALENDARIO'))
);
GO

IF OBJECT_ID(N'sigcm.Plazo', N'U') IS NULL
CREATE TABLE sigcm.Plazo (
    IdPlazo          uniqueidentifier NOT NULL
                     CONSTRAINT DF_sigcm_Plazo_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_sigcm_Plazo PRIMARY KEY,
    IdExpediente     uniqueidentifier NOT NULL
                     CONSTRAINT FK_sigcm_Plazo_Expediente REFERENCES sigcm.Expediente(IdExpediente) ON DELETE CASCADE,
    CodigoRegla      varchar(60) NOT NULL
                     CONSTRAINT FK_sigcm_Plazo_Regla REFERENCES sigcm.PlazoRegla(CodigoRegla),
    Inicio           datetime NOT NULL,
    Vencimiento      date     NOT NULL,
    AmpliadoHasta    date         NULL,
    MotivoAmpliacion nvarchar(max) NULL,
    CumplidoEn       datetime     NULL,
    Estado           varchar(15) NOT NULL CONSTRAINT DF_sigcm_Plazo_Estado DEFAULT ('EN_CURSO'),
    Activo           bit NOT NULL CONSTRAINT DF_sigcm_Plazo_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_sigcm_Plazo_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,

    CONSTRAINT CK_sigcm_Plazo_Estado
        CHECK (Estado IN ('EN_CURSO','CUMPLIDO','VENCIDO','ANULADO'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Plazo_Vigilancia' AND object_id = OBJECT_ID(N'sigcm.Plazo'))
CREATE NONCLUSTERED INDEX IX_sigcm_Plazo_Vigilancia
    ON sigcm.Plazo(Estado, Vencimiento)
    WHERE Estado = 'EN_CURSO';
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Plazo_Expediente' AND object_id = OBJECT_ID(N'sigcm.Plazo'))
CREATE NONCLUSTERED INDEX IX_sigcm_Plazo_Expediente
    ON sigcm.Plazo(IdExpediente);
GO

/* -------------------------------------------------------------------------- */
/* 3. Auditoria                                                               */
/* -------------------------------------------------------------------------- */

/* Bitacora de acciones. Es OTRA COSA que el cuarteto de auditoria de cada tabla:
   ese registra quien toco una fila; esta registra que se intento hacer, con que
   resultado y bajo que correlacion, incluidos los intentos denegados que nunca
   llegan a modificar una fila.

   ActorCuenta se guarda como texto ademas del IdActor: la auditoria debe
   sobrevivir a la baja de un usuario. Prohibido registrar contrasenias,
   certificados o datos personales sensibles en DatosAntes, DatosDespues o
   Metadata.

   CorrelacionId une todos los eventos de una misma peticion HTTP, incluidos los
   del worker de integracion. Lo genera el backend y viaja en el sobre JSON.

   OrigenIp era inet en PostgreSQL; SQL Server no tiene ese tipo, asi que va como
   varchar(45), suficiente para IPv6 con zona.

   Esta tabla no lleva Activo ni cuarteto: un evento de auditoria no se modifica,
   no se anula y no se borra. */
IF OBJECT_ID(N'sigcm.EventoAuditoria', N'U') IS NULL
CREATE TABLE sigcm.EventoAuditoria (
    IdEvento       bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_sigcm_EventoAuditoria PRIMARY KEY,
    CorrelacionId  uniqueidentifier NOT NULL CONSTRAINT DF_sigcm_EventoAuditoria_Correlacion DEFAULT (NEWID()),
    CodigoModulo   varchar(30)     NULL,
    Entidad        varchar(80) NOT NULL,
    IdEntidad      uniqueidentifier NULL,
    Accion         varchar(80) NOT NULL,
    Resultado      varchar(15) NOT NULL CONSTRAINT DF_sigcm_EventoAuditoria_Resultado DEFAULT ('OK'),

    IdActor        uniqueidentifier NULL CONSTRAINT FK_sigcm_EventoAuditoria_Actor  REFERENCES sigcm.Usuario(IdUsuario),
    ActorCuenta    varchar(120) NOT NULL,
    ActorRol       varchar(40)      NULL,
    IdActorUnidad  uniqueidentifier NULL CONSTRAINT FK_sigcm_EventoAuditoria_Unidad REFERENCES sigcm.Unidad(IdUnidad),
    OrigenIp       varchar(45)      NULL,
    Equipo         varchar(50)      NULL,
    Programa       varchar(50)      NULL,

    DatosAntes     nvarchar(max)    NULL,
    DatosDespues   nvarchar(max)    NULL,
    Metadata       nvarchar(max) NOT NULL CONSTRAINT DF_sigcm_EventoAuditoria_Metadata DEFAULT (N'{}'),
    OcurridoEn     datetime NOT NULL CONSTRAINT DF_sigcm_EventoAuditoria_Ocurrido DEFAULT (GETDATE()),

    CONSTRAINT CK_sigcm_EventoAuditoria_Resultado CHECK (Resultado IN ('OK','ERROR','DENEGADO')),
    CONSTRAINT CK_sigcm_EventoAuditoria_Antes     CHECK (DatosAntes   IS NULL OR ISJSON(DatosAntes)   = 1),
    CONSTRAINT CK_sigcm_EventoAuditoria_Despues   CHECK (DatosDespues IS NULL OR ISJSON(DatosDespues) = 1),
    CONSTRAINT CK_sigcm_EventoAuditoria_Metadata  CHECK (ISJSON(Metadata) = 1)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_EventoAuditoria_Entidad' AND object_id = OBJECT_ID(N'sigcm.EventoAuditoria'))
CREATE NONCLUSTERED INDEX IX_sigcm_EventoAuditoria_Entidad
    ON sigcm.EventoAuditoria(Entidad, IdEntidad, OcurridoEn DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_EventoAuditoria_Actor' AND object_id = OBJECT_ID(N'sigcm.EventoAuditoria'))
CREATE NONCLUSTERED INDEX IX_sigcm_EventoAuditoria_Actor
    ON sigcm.EventoAuditoria(ActorCuenta, OcurridoEn DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_EventoAuditoria_Correlacion' AND object_id = OBJECT_ID(N'sigcm.EventoAuditoria'))
CREATE NONCLUSTERED INDEX IX_sigcm_EventoAuditoria_Correlacion
    ON sigcm.EventoAuditoria(CorrelacionId);
GO

PRINT 'V003 aplicada.';
GO
