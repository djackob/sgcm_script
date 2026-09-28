/*
  V039 - Constancia de prestacion.

  Una constancia por orden (requerimiento): se emite cuando el ultimo
  entregable queda girado (PAG_PAGO_EFECTUADO) y se notifica al proveedor.
  El PDF se registra tambien como documento del expediente del ultimo pago
  (PAG_CONSTANCIA_PRESTACION) para que forme parte del expediente descargable.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'pago.ConstanciaPrestacion', N'U') IS NULL
CREATE TABLE pago.ConstanciaPrestacion (
    IdConstancia      uniqueidentifier NOT NULL
                      CONSTRAINT DF_pago_Constancia_Id DEFAULT (NEWSEQUENTIALID())
                      CONSTRAINT PK_pago_ConstanciaPrestacion PRIMARY KEY,
    IdRequerimiento   uniqueidentifier NOT NULL
                      CONSTRAINT FK_pago_Constancia_Req REFERENCES requerimiento.Requerimiento(IdRequerimiento),
    IdExpediente      uniqueidentifier NOT NULL
                      CONSTRAINT FK_pago_Constancia_Exp REFERENCES sigcm.Expediente(IdExpediente),
    AnoEje            smallint     NOT NULL,
    Correlativo       int          NOT NULL,
    Numero            varchar(30)  NOT NULL CONSTRAINT UQ_pago_Constancia_Numero UNIQUE,
    FechaEmision      datetime     NOT NULL CONSTRAINT DF_pago_Constancia_Fecha DEFAULT (GETDATE()),
    MontoContrato     decimal(18,2) NULL,
    MontoPagado       decimal(18,2) NULL,
    MontoPenalidad    decimal(18,2) NULL,
    GeneradoDocumento nvarchar(200) NULL,
    NombreDocumento   nvarchar(250) NULL,
    CorreoDestino     varchar(200)  NULL,
    NotificadaEn      datetime      NULL,
    ResultadoNotificacion nvarchar(300) NULL,
    IdUsuarioEmisor   uniqueidentifier NULL,
    NombreEmisor      varchar(250)  NULL,
    CargoEmisor       varchar(180)  NULL,
    Activo            bit NOT NULL CONSTRAINT DF_pago_Constancia_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_pago_Constancia_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_pago_Constancia_Req' AND object_id = OBJECT_ID(N'pago.ConstanciaPrestacion'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_pago_Constancia_Req
    ON pago.ConstanciaPrestacion(IdRequerimiento) WHERE Activo = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento WHERE CodigoTipoDocumento = 'PAG_CONSTANCIA_PRESTACION')
INSERT INTO sigcm.TipoDocumento (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
VALUES ('PAG_CONSTANCIA_PRESTACION', 'PAGO', 'Constancia de prestacion', 'CP', 0);
GO

PRINT 'V039 aplicada: pago.ConstanciaPrestacion y tipo de documento PAG_CONSTANCIA_PRESTACION.';
GO
