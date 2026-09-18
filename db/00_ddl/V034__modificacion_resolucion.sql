/*
===============================================================================
  SIGCM - Migracion V034 : Modificacion-Ampliacion y Resolucion del contrato menor
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Autoridad : SIGCM

  Directiva 002-2026-ANIN 7.3.4 (modificacion), 7.3.5 (ampliacion de plazo),
  7.3.7 (resolucion). Bizagi "4. MODIFICACION-AMPLIACION" y "5. RESOLUCION".
  Analisis en docs/analisis-modulos-modificacion-resolucion.md.

  Los esquemas [ampliacion] y [resolucion] existen desde V001. Las dos tablas
  cuelgan de ejecucion.Contrato: son flujos alternos del contrato en
  ejecucion, y de ahi leen proveedor, plazo y monto.

    ampliacion.Solicitud     Una solicitud de MODIFICACION o de AMPLIACION_PLAZO.
                             Expediente propio MOD-*; el tipo elige la cadena
                             de estados (MOD_* o AMP_*).
    resolucion.Procedimiento Un procedimiento de resolucion, por cualquiera de
                             las causales del 7.3.7.1 mas mutuo acuerdo y
                             unilateral. Expediente propio RES-*.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sigcm.Correlativo WHERE Nombre = N'ampliacion.SeqSolicitud')
    INSERT INTO sigcm.Correlativo (Nombre, Valor) VALUES (N'ampliacion.SeqSolicitud', 0);
IF NOT EXISTS (SELECT 1 FROM sigcm.Correlativo WHERE Nombre = N'resolucion.SeqProcedimiento')
    INSERT INTO sigcm.Correlativo (Nombre, Valor) VALUES (N'resolucion.SeqProcedimiento', 0);
GO

/* -------------------------------------------------------------------------- */
/* 1. Solicitud de modificacion o de ampliacion de plazo                      */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'ampliacion.Solicitud', N'U') IS NULL
CREATE TABLE ampliacion.Solicitud (
    IdSolicitud       uniqueidentifier NOT NULL
                      CONSTRAINT DF_amp_Sol_Id DEFAULT (NEWSEQUENTIALID())
                      CONSTRAINT PK_amp_Solicitud PRIMARY KEY,
    IdExpediente      uniqueidentifier NOT NULL
                      CONSTRAINT FK_amp_Sol_Exp REFERENCES sigcm.Expediente(IdExpediente)
                      CONSTRAINT UQ_amp_Sol_Exp UNIQUE,
    IdContrato        uniqueidentifier NOT NULL
                      CONSTRAINT FK_amp_Sol_Contrato REFERENCES ejecucion.Contrato(IdContrato),

    /* MODIFICACION | AMPLIACION_PLAZO */
    Tipo              varchar(20)      NOT NULL,
    /* PROVEEDOR | AREA_USUARIA. La ampliacion solo la pide el proveedor (7.3.5.1). */
    Origen            varchar(15)      NOT NULL,
    FechaPresentacion datetime         NOT NULL CONSTRAINT DF_amp_Sol_Pres DEFAULT (GETDATE()),
    Asunto            nvarchar(300)    NOT NULL,
    Sustento          nvarchar(max)    NOT NULL,
    SolicitudDocumento nvarchar(200)   NULL,

    /* Ampliacion (7.3.5.1): hecho generador, dias pedidos y si entro en los 10
       dias habiles. Lo calcula la rutina al presentar. */
    FechaFinHechoGenerador date        NULL,
    FechaLimitePresentacion date       NULL,
    PresentadaEnPlazo bit              NULL,
    DiasSolicitados   int              NULL,
    DiasOtorgados     int              NULL,
    FechaFinAnterior  date             NULL,
    NuevaFechaFin     date             NULL,

    /* Modificacion (7.3.4.1): que cambia. Nunca el monto. */
    DetalleModificacion nvarchar(max)  NULL,

    /* Opinion del area usuaria (7.3.4.2 / 7.3.5.2). */
    ResultadoAu       varchar(15)      NULL,
    InformeAu         nvarchar(max)    NULL,
    InformeAuDocumento nvarchar(200)   NULL,
    OpinionAuEn       datetime         NULL,
    IdActorOpinionAu  uniqueidentifier NULL
                      CONSTRAINT FK_amp_Sol_OpAu REFERENCES sigcm.Usuario(IdUsuario),

    /* Decision de la DEC (7.3.4.3 / 7.3.5.3 / 7.3.5.4). */
    ResultadoDec      varchar(15)      NULL,
    MotivoDec         nvarchar(max)    NULL,
    InformeDecDocumento nvarchar(200)  NULL,
    DecisionEn        datetime         NULL,
    IdActorDecision   uniqueidentifier NULL
                      CONSTRAINT FK_amp_Sol_Dec REFERENCES sigcm.Usuario(IdUsuario),
    /* La decision de la ampliacion llego despues de los 7 dias habiles: se
       entiende aceptada (7.3.5.4) y asi queda dicho. */
    AceptacionTacita  bit              NOT NULL CONSTRAINT DF_amp_Sol_Tacita DEFAULT (0),

    /* Acta de modificacion (7.3.4.3) y carta de respuesta. */
    NumeroActa        varchar(40)      NULL,
    ActaDocumento     nvarchar(200)    NULL,
    RegistroPladicop  varchar(60)      NULL,
    SuscritaProveedorEn datetime       NULL,
    NumeroCarta       varchar(40)      NULL,
    CartaDocumento    nvarchar(200)    NULL,

    /* Notificacion al proveedor: correo (7.3.5.4) o registro manual. */
    NotificadaEn      datetime         NULL,
    MedioNotificacion varchar(15)      NULL,
    ResultadoNotificacion nvarchar(300) NULL,

    Activo            bit NOT NULL CONSTRAINT DF_amp_Sol_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_amp_Sol_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,

    CONSTRAINT CK_amp_Sol_Tipo   CHECK (Tipo IN ('MODIFICACION','AMPLIACION_PLAZO')),
    CONSTRAINT CK_amp_Sol_Origen CHECK (Origen IN ('PROVEEDOR','AREA_USUARIA')),
    CONSTRAINT CK_amp_Sol_ResAu  CHECK (ResultadoAu IS NULL OR ResultadoAu IN ('PROCEDE','NO_PROCEDE')),
    CONSTRAINT CK_amp_Sol_ResDec CHECK (ResultadoDec IS NULL OR ResultadoDec IN ('APROBADA','DENEGADA')),
    CONSTRAINT CK_amp_Sol_Medio  CHECK (MedioNotificacion IS NULL OR MedioNotificacion IN ('CORREO','NOTARIAL','PLADICOP','MESA_PARTES')),
    CONSTRAINT CK_amp_Sol_Dias   CHECK (DiasSolicitados IS NULL OR DiasSolicitados > 0),
    CONSTRAINT CK_amp_Sol_Otorg  CHECK (DiasOtorgados IS NULL OR DiasOtorgados >= 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_amp_Sol_Contrato' AND object_id = OBJECT_ID(N'ampliacion.Solicitud'))
CREATE NONCLUSTERED INDEX IX_amp_Sol_Contrato
    ON ampliacion.Solicitud(IdContrato, FechaPresentacion DESC)
    WHERE Activo = 1;
GO

/* -------------------------------------------------------------------------- */
/* 2. Procedimiento de resolucion                                             */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'resolucion.Procedimiento', N'U') IS NULL
CREATE TABLE resolucion.Procedimiento (
    IdProcedimiento   uniqueidentifier NOT NULL
                      CONSTRAINT DF_res_Proc_Id DEFAULT (NEWSEQUENTIALID())
                      CONSTRAINT PK_res_Procedimiento PRIMARY KEY,
    IdExpediente      uniqueidentifier NOT NULL
                      CONSTRAINT FK_res_Proc_Exp REFERENCES sigcm.Expediente(IdExpediente)
                      CONSTRAINT UQ_res_Proc_Exp UNIQUE,
    IdContrato        uniqueidentifier NOT NULL
                      CONSTRAINT FK_res_Proc_Contrato REFERENCES ejecucion.Contrato(IdContrato),

    /* 7.3.7.1: INCUMPLIMIENTO (a) | CASO_FORTUITO (b) | HECHO_SOBREVINIENTE (c)
       | ANTICORRUPCION (d) | DOCUMENTACION_FALSA (e) | PENALIDAD_MAXIMA (f)
       | MUTUO_ACUERDO | UNILATERAL (ultimo parrafo y 7.3.7.4). */
    Causal            varchar(25)      NOT NULL,
    /* AREA_USUARIA | PROVEEDOR */
    Origen            varchar(15)      NOT NULL,
    /* TOTAL | PARCIAL (7.3.7.5). Parcial exige decir que parte. */
    Alcance           varchar(10)      NOT NULL CONSTRAINT DF_res_Proc_Alc DEFAULT ('TOTAL'),
    ParteResuelta     nvarchar(1000)   NULL,
    FechaInicio       datetime         NOT NULL CONSTRAINT DF_res_Proc_Ini DEFAULT (GETDATE()),
    Hechos            nvarchar(max)    NOT NULL,
    InformeAuDocumento nvarchar(200)   NULL,
    SolicitudDocumento nvarchar(200)   NULL,

    /* Pronunciamiento del AU cuando pide el proveedor (mutuo acuerdo, hecho
       sobreviniente) o al evaluar la respuesta al apercibimiento. */
    PronunciamientoAu varchar(15)      NULL,
    InformeAu         nvarchar(max)    NULL,
    PronunciamientoEn datetime         NULL,

    /* Apercibimiento (7.3.7.2.b). Los dias los elige la DEC dentro del rango
       que la rutina calcula: 10 %-15 % del plazo vigente, redondeo arriba,
       minimo 3 si el plazo es menor a 30. */
    RequiereApercibimiento bit         NOT NULL CONSTRAINT DF_res_Proc_ReqAp DEFAULT (0),
    PlazoBaseDias     int              NULL,
    PlazoApercibimientoMin int         NULL,
    PlazoApercibimientoMax int         NULL,
    PlazoApercibimientoDias int        NULL,
    NumeroCartaApercibimiento varchar(40) NULL,
    CartaApercibimientoDocumento nvarchar(200) NULL,
    ApercibimientoNotificadoEn datetime NULL,
    FechaLimiteSubsanacion date        NULL,
    RespuestaProveedor nvarchar(max)   NULL,
    RespuestaDocumento nvarchar(200)   NULL,
    RespondidaEn      datetime         NULL,
    /* SUBSANO | NO_SUBSANO | SIN_RESPUESTA */
    ResultadoApercibimiento varchar(15) NULL,

    /* Decision de la DEC y carta de resolucion (o de respuesta negando). */
    ResultadoDec      varchar(15)      NULL,
    MotivoDec         nvarchar(max)    NULL,
    DecisionEn        datetime         NULL,
    IdActorDecision   uniqueidentifier NULL
                      CONSTRAINT FK_res_Proc_Dec REFERENCES sigcm.Usuario(IdUsuario),
    NumeroCarta       varchar(40)      NULL,
    CartaDocumento    nvarchar(200)    NULL,
    /* NOTARIAL | PLADICOP | CORREO (7.3.7.2.e, 7.3.7.3) */
    MedioNotificacion varchar(15)      NULL,
    NotificadaEn      datetime         NULL,
    ResultadoNotificacion nvarchar(300) NULL,
    RegistroPladicop  varchar(60)      NULL,
    FechaResolucion   date             NULL,

    Activo            bit NOT NULL CONSTRAINT DF_res_Proc_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_res_Proc_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,

    CONSTRAINT CK_res_Proc_Causal CHECK (Causal IN ('INCUMPLIMIENTO','CASO_FORTUITO','HECHO_SOBREVINIENTE',
                                                    'ANTICORRUPCION','DOCUMENTACION_FALSA','PENALIDAD_MAXIMA',
                                                    'MUTUO_ACUERDO','UNILATERAL')),
    CONSTRAINT CK_res_Proc_Origen CHECK (Origen IN ('AREA_USUARIA','PROVEEDOR')),
    CONSTRAINT CK_res_Proc_Alcance CHECK (Alcance IN ('TOTAL','PARCIAL')),
    CONSTRAINT CK_res_Proc_Parcial CHECK (Alcance = 'TOTAL' OR NULLIF(LTRIM(RTRIM(ParteResuelta)), N'') IS NOT NULL),
    CONSTRAINT CK_res_Proc_PronAu CHECK (PronunciamientoAu IS NULL OR PronunciamientoAu IN ('FAVORABLE','DESFAVORABLE')),
    CONSTRAINT CK_res_Proc_ResAp CHECK (ResultadoApercibimiento IS NULL OR ResultadoApercibimiento IN ('SUBSANO','NO_SUBSANO','SIN_RESPUESTA')),
    CONSTRAINT CK_res_Proc_ResDec CHECK (ResultadoDec IS NULL OR ResultadoDec IN ('RESUELTO','DESESTIMADO','DENEGADO','SUBSANADO')),
    CONSTRAINT CK_res_Proc_Medio CHECK (MedioNotificacion IS NULL OR MedioNotificacion IN ('NOTARIAL','PLADICOP','CORREO'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_res_Proc_Contrato' AND object_id = OBJECT_ID(N'resolucion.Procedimiento'))
CREATE NONCLUSTERED INDEX IX_res_Proc_Contrato
    ON resolucion.Procedimiento(IdContrato, FechaInicio DESC)
    WHERE Activo = 1;
GO

PRINT 'V034 aplicada: ampliacion.Solicitud y resolucion.Procedimiento.';
GO
