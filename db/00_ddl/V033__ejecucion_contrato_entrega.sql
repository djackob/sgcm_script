/*
===============================================================================
  SIGCM - Migracion V033 : Ejecucion contractual - contrato, entregas e incidencias
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Autoridad : SIGCM

  Directiva 002-2026-ANIN, numeral 7.3. Bizagi "3. EJECUCION".

  El esquema [ejecucion] existe desde V001, declarado vacio. Aqui recibe el
  payload del modulo; la maquina de estados vive en sigcm.Estado / Transicion
  y la siembra S038.

  Tres tablas:

    ejecucion.Contrato    Un contrato menor en ejecucion por orden notificada.
                          Nace con REQ_NOTIFICAR_OS (7.3.1: la ejecucion
                          empieza el dia siguiente a la notificacion).
    ejecucion.Entrega     Una entrega fisica de bienes. Tiene su propio
                          sigcm.Expediente colgado del contrato, porque
                          recorre su propia maquina: autorizar ingreso,
                          verificar, recepcionar o hacer retirar (7.3.6.3).
    ejecucion.Incidencia  Lo que el AU comunica a la DEC (7.3.3). Registro
                          plano: no mueve el expediente.

  La rama de SERVICIOS (presentar entregable -> conformidad -> Anexo 11) NO
  esta aqui: es el modulo de Pagos, que ya la implementa. La entrega guarda a
  que entregable de pago corresponde y nada mas.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Correlativos EJE-AAAA-000001 y ENT-AAAA-000001                          */
/* -------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sigcm.Correlativo WHERE Nombre = N'ejecucion.SeqContrato')
    INSERT INTO sigcm.Correlativo (Nombre, Valor) VALUES (N'ejecucion.SeqContrato', 0);
IF NOT EXISTS (SELECT 1 FROM sigcm.Correlativo WHERE Nombre = N'ejecucion.SeqEntrega')
    INSERT INTO sigcm.Correlativo (Nombre, Valor) VALUES (N'ejecucion.SeqEntrega', 0);
GO

/* -------------------------------------------------------------------------- */
/* 2. Contrato en ejecucion                                                   */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'ejecucion.Contrato', N'U') IS NULL
CREATE TABLE ejecucion.Contrato (
    IdContrato        uniqueidentifier NOT NULL
                      CONSTRAINT DF_eje_Contrato_Id DEFAULT (NEWSEQUENTIALID())
                      CONSTRAINT PK_eje_Contrato PRIMARY KEY,
    IdExpediente      uniqueidentifier NOT NULL
                      CONSTRAINT FK_eje_Contrato_Exp REFERENCES sigcm.Expediente(IdExpediente)
                      CONSTRAINT UQ_eje_Contrato_Exp UNIQUE,
    IdRequerimiento   uniqueidentifier NOT NULL
                      CONSTRAINT FK_eje_Contrato_Req REFERENCES requerimiento.Requerimiento(IdRequerimiento)
                      CONSTRAINT UQ_eje_Contrato_Req UNIQUE,
    IdOrdenServicio   uniqueidentifier NULL
                      CONSTRAINT FK_eje_Contrato_Os REFERENCES requerimiento.OrdenServicio(IdOrdenServicio),

    CodigoRequerimiento varchar(40)   NOT NULL,
    NumeroOrdenSiga     varchar(40)   NULL,
    Denominacion        varchar(500)  NOT NULL,
    /* BIEN | SERVICIO | CONSULTORIA | LOCACION, copiado de sigcm.TipoContratacion.
       Decide que rama del Bizagi aplica: solo BIEN tiene entregas fisicas. */
    TipoPrestacion      varchar(20)   NOT NULL,

    FechaNotificacion   datetime      NOT NULL,
    /* 7.3.1: dia calendario siguiente a la notificacion, nunca anterior. */
    FechaInicio         date          NOT NULL,
    PlazoDias           int           NOT NULL,
    FechaFinPrevista    date          NOT NULL,
    FechaFinReal        date          NULL,

    /* SEDE_CENTRAL | SEDE_DESCONCENTRADA (7.3.6.3 a/b). Nulo hasta que el AU o
       la DEC lo fijen; sin lugar no se puede anunciar una entrega de bienes. */
    LugarEntrega        varchar(25)   NULL,
    DireccionEntrega    nvarchar(300) NULL,
    /* Quien supervisa por el AU (7.3.2). Sugerencia para la bandeja, no filtro. */
    IdSupervisor        uniqueidentifier NULL
                        CONSTRAINT FK_eje_Contrato_Sup REFERENCES sigcm.Usuario(IdUsuario),

    MontoContrato       decimal(18,2) NOT NULL,
    RucProveedor        varchar(11)   NULL,
    DniProveedor        varchar(15)   NULL,
    NombreProveedor     nvarchar(250) NULL,
    CorreoProveedor     varchar(200)  NULL,

    Activo              bit NOT NULL CONSTRAINT DF_eje_Contrato_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_eje_Contrato_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,

    CONSTRAINT CK_eje_Contrato_Tipo  CHECK (TipoPrestacion IN ('BIEN','SERVICIO','CONSULTORIA','LOCACION')),
    CONSTRAINT CK_eje_Contrato_Lugar CHECK (LugarEntrega IS NULL OR LugarEntrega IN ('SEDE_CENTRAL','SEDE_DESCONCENTRADA')),
    CONSTRAINT CK_eje_Contrato_Plazo CHECK (PlazoDias > 0),
    CONSTRAINT CK_eje_Contrato_Fechas CHECK (FechaInicio > CONVERT(date, FechaNotificacion) AND FechaFinPrevista >= FechaInicio)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_eje_Contrato_Fin' AND object_id = OBJECT_ID(N'ejecucion.Contrato'))
CREATE NONCLUSTERED INDEX IX_eje_Contrato_Fin
    ON ejecucion.Contrato(FechaFinPrevista)
    WHERE Activo = 1;
GO

/* -------------------------------------------------------------------------- */
/* 3. Entrega fisica de bienes                                                */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'ejecucion.Entrega', N'U') IS NULL
CREATE TABLE ejecucion.Entrega (
    IdEntrega         uniqueidentifier NOT NULL
                      CONSTRAINT DF_eje_Entrega_Id DEFAULT (NEWSEQUENTIALID())
                      CONSTRAINT PK_eje_Entrega PRIMARY KEY,
    IdExpediente      uniqueidentifier NOT NULL
                      CONSTRAINT FK_eje_Entrega_Exp REFERENCES sigcm.Expediente(IdExpediente)
                      CONSTRAINT UQ_eje_Entrega_Exp UNIQUE,
    IdContrato        uniqueidentifier NOT NULL
                      CONSTRAINT FK_eje_Entrega_Contrato REFERENCES ejecucion.Contrato(IdContrato),
    NumeroEntrega     smallint         NOT NULL,

    /* A que entregable del cronograma corresponde; el expediente de pago sigue
       su propio camino y aqui solo se apunta. */
    NumeroEntregable  smallint         NULL,
    IdExpedientePago  uniqueidentifier NULL
                      CONSTRAINT FK_eje_Entrega_Pago REFERENCES pago.ExpedientePago(IdExpedientePago),

    /* Copia del lugar del contrato en el momento de anunciar: si el contrato
       cambia de lugar despues, esta entrega ya tomo su ruta. */
    Lugar             varchar(25)      NOT NULL,
    Detalle           nvarchar(1000)   NOT NULL,
    FechaAnuncio      datetime         NOT NULL CONSTRAINT DF_eje_Entrega_Anuncio DEFAULT (GETDATE()),
    FechaPrevista     date             NOT NULL,
    FechaIngreso      datetime         NULL,
    FechaVerificacion datetime         NULL,
    FechaRecepcion    datetime         NULL,
    FechaRetiro       datetime         NULL,

    NumeroGuiaRemision       varchar(40)   NOT NULL,
    GuiaDocumento            nvarchar(200) NULL,
    GuiaSuscritaDocumento    nvarchar(200) NULL,
    ActaIncumplimientoDocumento nvarchar(200) NULL,
    NumeroPecosa             varchar(40)   NULL,
    PecosaDocumento          nvarchar(200) NULL,

    /* Responsable de verificacion designado por el AU (7.3.6.3 a/b). */
    IdVerificador       uniqueidentifier NULL
                        CONSTRAINT FK_eje_Entrega_Verif REFERENCES sigcm.Usuario(IdUsuario),
    /* CONFORME | OBSERVADO, y el detalle que va al acta o a la guia. */
    ResultadoVerificacion varchar(12)    NULL,
    DetalleVerificacion   nvarchar(max)  NULL,

    Activo            bit NOT NULL CONSTRAINT DF_eje_Entrega_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_eje_Entrega_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,

    CONSTRAINT UQ_eje_Entrega_Numero UNIQUE (IdContrato, NumeroEntrega),
    CONSTRAINT CK_eje_Entrega_Numero CHECK (NumeroEntrega > 0),
    CONSTRAINT CK_eje_Entrega_Lugar  CHECK (Lugar IN ('SEDE_CENTRAL','SEDE_DESCONCENTRADA')),
    CONSTRAINT CK_eje_Entrega_Result CHECK (ResultadoVerificacion IS NULL OR ResultadoVerificacion IN ('CONFORME','OBSERVADO'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_eje_Entrega_Contrato' AND object_id = OBJECT_ID(N'ejecucion.Entrega'))
CREATE NONCLUSTERED INDEX IX_eje_Entrega_Contrato
    ON ejecucion.Entrega(IdContrato, NumeroEntrega)
    WHERE Activo = 1;
GO

/* -------------------------------------------------------------------------- */
/* 4. Incidencias del contrato (7.3.3)                                        */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'ejecucion.Incidencia', N'U') IS NULL
CREATE TABLE ejecucion.Incidencia (
    IdIncidencia      uniqueidentifier NOT NULL
                      CONSTRAINT DF_eje_Incidencia_Id DEFAULT (NEWSEQUENTIALID())
                      CONSTRAINT PK_eje_Incidencia PRIMARY KEY,
    IdContrato        uniqueidentifier NOT NULL
                      CONSTRAINT FK_eje_Incidencia_Contrato REFERENCES ejecucion.Contrato(IdContrato),
    /* INCIDENCIA | INCUMPLIMIENTO | RIESGO: las tres palabras del 7.3.3. */
    Tipo              varchar(20)      NOT NULL,
    Detalle           nvarchar(max)    NOT NULL,
    /* Numero del documento con que el AU lo comunico por el SGD. */
    DocumentoSgd      varchar(60)      NULL,
    InformeDocumento  nvarchar(200)    NULL,
    /* COMUNICADA -> ATENDIDA */
    Estado            varchar(15)      NOT NULL CONSTRAINT DF_eje_Incidencia_Estado DEFAULT ('COMUNICADA'),
    Respuesta         nvarchar(max)    NULL,
    IdActorRegistro   uniqueidentifier NOT NULL
                      CONSTRAINT FK_eje_Incidencia_Reg REFERENCES sigcm.Usuario(IdUsuario),
    RegistradaEn      datetime         NOT NULL CONSTRAINT DF_eje_Incidencia_Reg DEFAULT (GETDATE()),
    IdActorAtencion   uniqueidentifier NULL
                      CONSTRAINT FK_eje_Incidencia_Ate REFERENCES sigcm.Usuario(IdUsuario),
    AtendidaEn        datetime         NULL,

    Activo            bit NOT NULL CONSTRAINT DF_eje_Incidencia_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_eje_Incidencia_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,

    CONSTRAINT CK_eje_Incidencia_Tipo   CHECK (Tipo IN ('INCIDENCIA','INCUMPLIMIENTO','RIESGO')),
    CONSTRAINT CK_eje_Incidencia_Estado CHECK (Estado IN ('COMUNICADA','ATENDIDA'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_eje_Incidencia_Contrato' AND object_id = OBJECT_ID(N'ejecucion.Incidencia'))
CREATE NONCLUSTERED INDEX IX_eje_Incidencia_Contrato
    ON ejecucion.Incidencia(IdContrato, RegistradaEn DESC)
    WHERE Activo = 1;
GO

PRINT 'V033 aplicada: ejecucion.Contrato, ejecucion.Entrega y ejecucion.Incidencia.';
GO
