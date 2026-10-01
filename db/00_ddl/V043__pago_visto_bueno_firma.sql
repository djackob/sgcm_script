/*
===============================================================================
  SIGCM - Migracion V043 : Visto bueno previo a la firma del Acta (Anexo 11)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Con el acta por firmar, el Jefe o la Secretaria del area usuaria derivan el
  expediente a una persona por cada fila del numeral 8.1 del Anexo 3
  (pago.RutaInformePrevio). Responden una por una, en el orden grabado. El
  jefe firma y envia a Administracion solo cuando la ronda vigente quedo
  completa.

  Cada derivacion abre una ronda nueva. Una observacion cierra la ronda y
  devuelve el expediente al jefe, que vuelve a derivar.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'pago.VistoBuenoFirma', N'U') IS NULL
CREATE TABLE pago.VistoBuenoFirma (
    IdVistoBueno         uniqueidentifier NOT NULL
                         CONSTRAINT DF_pago_VbFirma_Id DEFAULT (NEWSEQUENTIALID())
                         CONSTRAINT PK_pago_VistoBuenoFirma PRIMARY KEY,
    IdExpedientePago     uniqueidentifier NOT NULL
                         CONSTRAINT FK_pago_VbFirma_Pago REFERENCES pago.ExpedientePago(IdExpedientePago),
    Ronda                smallint         NOT NULL,
    Orden                smallint         NOT NULL,
    IdUnidad             uniqueidentifier NOT NULL
                         CONSTRAINT FK_pago_VbFirma_Unidad REFERENCES sigcm.Unidad(IdUnidad),
    CodigoRol            varchar(40)      NOT NULL
                         CONSTRAINT FK_pago_VbFirma_Rol REFERENCES sigcm.Rol(CodigoRol),
    NombreUnidad         nvarchar(200)    NOT NULL,
    NombreRol            nvarchar(150)    NULL,
    IdUsuarioDestino     uniqueidentifier NOT NULL
                         CONSTRAINT FK_pago_VbFirma_Usuario REFERENCES sigcm.Usuario(IdUsuario),
    NombreUsuarioDestino nvarchar(250)    NOT NULL,
    Estado               varchar(15)      NOT NULL
                         CONSTRAINT DF_pago_VbFirma_Estado DEFAULT ('PENDIENTE'),
    Comentario           nvarchar(2000)   NULL,
    GeneradoDocumento    nvarchar(200)    NULL,
    NombreDocumento      nvarchar(260)    NULL,
    RespondidoEn         datetime         NULL,
    IdUsuarioDeriva      uniqueidentifier NOT NULL,
    DerivadoEn           datetime         NOT NULL
                         CONSTRAINT DF_pago_VbFirma_Derivado DEFAULT (GETDATE()),

    CONSTRAINT UQ_pago_VbFirma_Paso UNIQUE (IdExpedientePago, Ronda, Orden),
    CONSTRAINT CK_pago_VbFirma_Estado CHECK (Estado IN ('PENDIENTE', 'OTORGADO', 'OBSERVADO', 'ANULADO')),
    CONSTRAINT CK_pago_VbFirma_Orden CHECK (Orden > 0 AND Ronda > 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pago_VbFirma_Pendiente' AND object_id = OBJECT_ID(N'pago.VistoBuenoFirma'))
CREATE NONCLUSTERED INDEX IX_pago_VbFirma_Pendiente
    ON pago.VistoBuenoFirma(IdExpedientePago, Ronda, Orden)
    WHERE Estado = 'PENDIENTE';
GO

PRINT 'V043 aplicada: pago.VistoBuenoFirma.';
GO
