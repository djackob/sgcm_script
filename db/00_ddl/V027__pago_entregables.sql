/*
===============================================================================
  SIGCM - Migracion V027 : Gestion de entregables, conformidades y pagos
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Autoridad : SIGCM

  EDS del modulo de Gestion de Entregables, Conformidades y Pagos del SGCM.
  Un expediente PAGO por entregable del cronograma (TDR / Anexo 5), nacido de
  la orden de servicio notificada (Hito 1). La maquina de estados vive en
  sigcm.Estado / Transicion (S017); aqui solo el payload del modulo.

  SIGA Escritorio no se escribe desde estas tablas. Los hitos 2 a 5 se
  registran en pago.HitoSincronizacion como bitacora (STUB en homologacion)
  hasta que existan usp_ext_* homologados. No se inventan tablas
  sg_conformidad_servicio / sg_interfaz_siaf.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Correlativo PAG-AAAA-000001                                             */
/* -------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sigcm.Correlativo WHERE Nombre = N'pago.SeqExpedientePago')
    INSERT INTO sigcm.Correlativo (Nombre, Valor) VALUES (N'pago.SeqExpedientePago', 0);
GO

/* -------------------------------------------------------------------------- */
/* 2. Expediente de pago (un tramite = un entregable de una O/S)              */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'pago.ExpedientePago', N'U') IS NULL
CREATE TABLE pago.ExpedientePago (
    IdExpedientePago uniqueidentifier NOT NULL
                     CONSTRAINT DF_pago_ExpPago_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_pago_ExpedientePago PRIMARY KEY,
    IdExpediente     uniqueidentifier NOT NULL
                     CONSTRAINT FK_pago_ExpPago_Exp REFERENCES sigcm.Expediente(IdExpediente)
                     CONSTRAINT UQ_pago_ExpPago_Exp UNIQUE,
    IdRequerimiento  uniqueidentifier NOT NULL
                     CONSTRAINT FK_pago_ExpPago_Req REFERENCES requerimiento.Requerimiento(IdRequerimiento),
    IdOrdenServicio  uniqueidentifier NULL
                     CONSTRAINT FK_pago_ExpPago_Os REFERENCES requerimiento.OrdenServicio(IdOrdenServicio),

    CodigoRequerimiento varchar(40)  NOT NULL,
    NumeroOrdenSiga     varchar(40)  NULL,
    NumeroPedidoSiga    varchar(20)  NULL,
    MetaPresupuestal    varchar(20)  NULL,
    ClasificadorGasto   varchar(20)  NULL,

    NumeroEntregable    smallint     NOT NULL,
    NombreEntregable    nvarchar(300) NOT NULL,
    PlazoDias           int          NOT NULL CONSTRAINT DF_pago_ExpPago_Plazo DEFAULT (1),
    MontoEntregable     decimal(18,2) NOT NULL,
    MontoContrato       decimal(18,2) NOT NULL,
    PlazoContratoDias   int          NULL,
    FechaLimiteCronograma date       NULL,
    FechaPresentacion   datetime     NULL,
    FechaRecepcionAu    datetime     NULL,
    FechaConformidadTecnica datetime NULL,
    FechaLimiteSubsanacion datetime  NULL,

    RucLocador          varchar(11)  NULL,
    DniLocador          varchar(15)  NULL,
    NombreLocador       nvarchar(250) NULL,
    CorreoLocador       varchar(200) NULL,
    Cci                 varchar(20)  NULL,
    Banco               nvarchar(120) NULL,

    RheSerie            varchar(20)  NULL,
    RheNumero           varchar(20)  NULL,
    RheValidadoSunat    bit          NOT NULL CONSTRAINT DF_pago_ExpPago_RheOk DEFAULT (0),
    RheOrigenValidacion varchar(40)  NULL,
    BloqueoRendicion    bit          NOT NULL CONSTRAINT DF_pago_ExpPago_Rend DEFAULT (0),
    AplicaRetencion4ta  bit          NOT NULL CONSTRAINT DF_pago_ExpPago_Ret DEFAULT (1),
    SubsanacionTardia   bit          NOT NULL CONSTRAINT DF_pago_ExpPago_SubT DEFAULT (0),
    RetrasoJustificado  bit          NOT NULL CONSTRAINT DF_pago_ExpPago_Just DEFAULT (0),

    DiasAtraso          int          NOT NULL CONSTRAINT DF_pago_ExpPago_Atraso DEFAULT (0),
    PenalidadDiaria     decimal(18,6) NULL,
    MontoPenalidad      decimal(18,2) NOT NULL CONSTRAINT DF_pago_ExpPago_Pen DEFAULT (0),
    MontoPenalidadAcumulada decimal(18,2) NOT NULL CONSTRAINT DF_pago_ExpPago_PenAc DEFAULT (0),
    AlertaResolucion    bit          NOT NULL CONSTRAINT DF_pago_ExpPago_Alert DEFAULT (0),

    ObservacionAu       nvarchar(max) NULL,
    ObservacionUc       nvarchar(max) NULL,
    DestinoDevolucionUc varchar(10)  NULL,

    ExpedienteSiaf      varchar(40)  NULL,
    FechaDevengado      datetime     NULL,
    NotaPagoSiaf        varchar(40)  NULL,
    FechaAbono          datetime     NULL,
    NumeroOperacion     varchar(40)  NULL,
    RetencionCuarta     decimal(18,2) NOT NULL CONSTRAINT DF_pago_ExpPago_RetM DEFAULT (0),
    MontoNeto           decimal(18,2) NULL,
    ProrrogaDias        smallint     NOT NULL CONSTRAINT DF_pago_ExpPago_Pror DEFAULT (0),
    MotivoProrroga      nvarchar(500) NULL,

    InformeDocumento        nvarchar(200) NULL,
    RhePdfDocumento         nvarchar(200) NULL,
    RheXmlDocumento         nvarchar(200) NULL,
    Suspension4taDocumento  nvarchar(200) NULL,
    NotaPagoDocumento       nvarchar(200) NULL,
    ConstanciaDocumento     nvarchar(200) NULL,
    PapeletaPenalidadDocumento nvarchar(200) NULL,

    Activo           bit NOT NULL CONSTRAINT DF_pago_ExpPago_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_pago_ExpPago_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,

    CONSTRAINT UQ_pago_ExpPago_Entregable UNIQUE (IdRequerimiento, NumeroEntregable),
    CONSTRAINT CK_pago_ExpPago_Num CHECK (NumeroEntregable > 0),
    CONSTRAINT CK_pago_ExpPago_Plazo CHECK (PlazoDias > 0),
    CONSTRAINT CK_pago_ExpPago_Monto CHECK (MontoEntregable >= 0 AND MontoContrato >= 0),
    CONSTRAINT CK_pago_ExpPago_Pror CHECK (ProrrogaDias >= 0 AND ProrrogaDias <= 5)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pago_ExpPago_Req' AND object_id = OBJECT_ID(N'pago.ExpedientePago'))
CREATE NONCLUSTERED INDEX IX_pago_ExpPago_Req
    ON pago.ExpedientePago(IdRequerimiento, NumeroEntregable)
    WHERE Activo = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pago_ExpPago_Locador' AND object_id = OBJECT_ID(N'pago.ExpedientePago'))
CREATE NONCLUSTERED INDEX IX_pago_ExpPago_Locador
    ON pago.ExpedientePago(RucLocador, DniLocador)
    WHERE Activo = 1;
GO

/* -------------------------------------------------------------------------- */
/* 3. Anexo 9: catalogo del checklist de control de pagos                     */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'pago.ChecklistItem', N'U') IS NULL
CREATE TABLE pago.ChecklistItem (
    CodigoItem   varchar(40)  NOT NULL CONSTRAINT PK_pago_ChecklistItem PRIMARY KEY,
    Nombre       nvarchar(300) NOT NULL,
    Orden        smallint     NOT NULL,
    Obligatorio  bit          NOT NULL CONSTRAINT DF_pago_ChkItem_Obl DEFAULT (1),
    Activo       bit          NOT NULL CONSTRAINT DF_pago_ChkItem_Act DEFAULT (1)
);
GO

MERGE pago.ChecklistItem AS d
USING (VALUES
    ('OS',            N'Orden de servicio emitida y notificada',                         10, 1),
    ('RHE',           N'Recibo por Honorarios Electronico (PDF y XML) vigente',          20, 1),
    ('RNP',           N'RNP vigente del locador',                                        30, 1),
    ('RUC',           N'Consulta RUC SUNAT (habido / activo)',                           40, 1),
    ('ACTA_A11',      N'Acta de Conformidad (Anexo 11) firmada por el Jefe AU',          50, 1),
    ('ENTREGABLE',    N'Informe de actividades / entregable conforme a TDR',             60, 1),
    ('SUSP_4TA',      N'Constancia de suspension de retenciones de 4ta categoria',       70, 0),
    ('CCI',           N'CCI del locador consignado en la cotizacion (Anexo 6)',          80, 1),
    ('CRONOGRAMA',    N'Presentacion contrastada con el cronograma del TDR',             90, 1),
    ('PENALIDAD_A10', N'Liquidacion de penalidad por mora (Anexo 10), de corresponder', 100, 0)
) AS s(CodigoItem, Nombre, Orden, Obligatorio)
ON d.CodigoItem = s.CodigoItem
WHEN MATCHED THEN
    UPDATE SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Obligatorio = s.Obligatorio, d.Activo = 1
WHEN NOT MATCHED THEN
    INSERT (CodigoItem, Nombre, Orden, Obligatorio, Activo)
    VALUES (s.CodigoItem, s.Nombre, s.Orden, s.Obligatorio, 1);
GO

IF OBJECT_ID(N'pago.ChecklistMarca', N'U') IS NULL
CREATE TABLE pago.ChecklistMarca (
    IdMarca          uniqueidentifier NOT NULL
                     CONSTRAINT DF_pago_ChkMarca_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_pago_ChecklistMarca PRIMARY KEY,
    IdExpedientePago uniqueidentifier NOT NULL
                     CONSTRAINT FK_pago_ChkMarca_Pago REFERENCES pago.ExpedientePago(IdExpedientePago),
    CodigoItem       varchar(40) NOT NULL
                     CONSTRAINT FK_pago_ChkMarca_Item REFERENCES pago.ChecklistItem(CodigoItem),
    /* SI | NO | NO_APLICA */
    Valor            varchar(12) NOT NULL,
    Observacion      nvarchar(400) NULL,

    UsuarioCreacionAuditoria     varchar(30) NULL,
    FechaCreacionAuditoria       datetime    NULL CONSTRAINT DF_pago_ChkMarca_FecCre DEFAULT (GETDATE()),
    UsuarioModificacionAuditoria varchar(30) NULL,
    FechaModificacionAuditoria   datetime    NULL,

    CONSTRAINT UQ_pago_ChkMarca UNIQUE (IdExpedientePago, CodigoItem),
    CONSTRAINT CK_pago_ChkMarca_Valor CHECK (Valor IN ('SI','NO','NO_APLICA'))
);
GO

/* -------------------------------------------------------------------------- */
/* 4. Bitacora de hitos SIGA / SIAF (sin DML ad hoc en SIGA)                  */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'pago.HitoSincronizacion', N'U') IS NULL
CREATE TABLE pago.HitoSincronizacion (
    IdHito           uniqueidentifier NOT NULL
                     CONSTRAINT DF_pago_Hito_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_pago_HitoSincronizacion PRIMARY KEY,
    IdExpedientePago uniqueidentifier NOT NULL
                     CONSTRAINT FK_pago_Hito_Pago REFERENCES pago.ExpedientePago(IdExpedientePago),
    NumeroHito       tinyint      NOT NULL,
    NombreHito       varchar(80)  NOT NULL,
    Direccion        varchar(20)  NOT NULL,
    TablaSiga        varchar(80)  NULL,
    Payload          nvarchar(max) NULL,
    Estado           varchar(20)  NOT NULL CONSTRAINT DF_pago_Hito_Est DEFAULT ('STUB'),
    Mensaje          nvarchar(500) NULL,
    FechaHito        datetime     NOT NULL CONSTRAINT DF_pago_Hito_Fec DEFAULT (GETDATE()),

    CONSTRAINT CK_pago_Hito_Num CHECK (NumeroHito BETWEEN 1 AND 5),
    CONSTRAINT CK_pago_Hito_Dir CHECK (Direccion IN ('SIGA_A_SGCM','SGCM_A_SIGA')),
    CONSTRAINT CK_pago_Hito_Est CHECK (Estado IN ('STUB','REGISTRADO','ERROR'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pago_Hito_Pago' AND object_id = OBJECT_ID(N'pago.HitoSincronizacion'))
CREATE NONCLUSTERED INDEX IX_pago_Hito_Pago
    ON pago.HitoSincronizacion(IdExpedientePago, NumeroHito, FechaHito DESC);
GO

PRINT 'V027 aplicada: pago.ExpedientePago, checklist Anexo 9 y bitacora de hitos SIGA.';
GO
