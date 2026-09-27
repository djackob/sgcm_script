/*
===============================================================================
  SIGCM - Migracion V037 : Ruta de informe previo del pago
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Copia, al abrir el expediente de pago, los perfiles que el Anexo 3 declaro
  en el numeral 8.1 (informe tecnico / visto bueno previo a la conformidad).
  El pago recorre esas filas en el orden grabado. Un cambio posterior del TDR
  no reescribe un pago ya abierto.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'pago.RutaInformePrevio', N'U') IS NULL
CREATE TABLE pago.RutaInformePrevio (
    IdRuta           uniqueidentifier NOT NULL
                     CONSTRAINT DF_pago_RutaInf_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_pago_RutaInformePrevio PRIMARY KEY,
    IdExpedientePago uniqueidentifier NOT NULL
                     CONSTRAINT FK_pago_RutaInf_Pago REFERENCES pago.ExpedientePago(IdExpedientePago),
    Orden            smallint         NOT NULL,
    IdUnidad         uniqueidentifier NOT NULL
                     CONSTRAINT FK_pago_RutaInf_Unidad REFERENCES sigcm.Unidad(IdUnidad),
    CodigoRol        varchar(40)      NOT NULL
                     CONSTRAINT FK_pago_RutaInf_Rol REFERENCES sigcm.Rol(CodigoRol),
    NombreUnidad     nvarchar(200)    NOT NULL,
    NombreRol        nvarchar(150)    NULL,
    Otorgado         bit              NOT NULL CONSTRAINT DF_pago_RutaInf_Otorg DEFAULT (0),
    OtorgadoEn       datetime         NULL,
    IdUsuarioOtorga  uniqueidentifier NULL,

    CONSTRAINT UQ_pago_RutaInf_Orden UNIQUE (IdExpedientePago, Orden),
    CONSTRAINT UQ_pago_RutaInf_Paso UNIQUE (IdExpedientePago, IdUnidad, CodigoRol),
    CONSTRAINT CK_pago_RutaInf_Orden CHECK (Orden > 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pago_RutaInf_Pendiente' AND object_id = OBJECT_ID(N'pago.RutaInformePrevio'))
CREATE NONCLUSTERED INDEX IX_pago_RutaInf_Pendiente
    ON pago.RutaInformePrevio(IdExpedientePago, Orden)
    WHERE Otorgado = 0;
GO
