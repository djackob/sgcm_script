/*
  Base    : DBSIGCM
  Esquema : integracion
  Objeto  : integracion.Conciliacion
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [integracion].[Conciliacion] (
    [IdConciliacion] bigint IDENTITY(1,1) NOT NULL,
    [EjecutadoEn] datetime NOT NULL CONSTRAINT [DF_Conciliacion_EjecutadoEn] DEFAULT (getdate()),
    [AnoEje] smallint NOT NULL,
    [SecEjec] int NOT NULL,
    [CentroCosto] varchar(15),
    [ItemsSigcm] int NOT NULL CONSTRAINT [DF_Conciliacion_ItemsSigcm] DEFAULT ((0)),
    [ItemsSiga] int NOT NULL CONSTRAINT [DF_Conciliacion_ItemsSiga] DEFAULT ((0)),
    [Coincidentes] int NOT NULL CONSTRAINT [DF_Conciliacion_Coincidentes] DEFAULT ((0)),
    [HuerfanosSigcm] int NOT NULL CONSTRAINT [DF_Conciliacion_HuerfanosSigcm] DEFAULT ((0)),
    [HuerfanosSiga] int NOT NULL CONSTRAINT [DF_Conciliacion_HuerfanosSiga] DEFAULT ((0)),
    [Diferencias] nvarchar(max) NOT NULL CONSTRAINT [DF_Conciliacion_Diferencias] DEFAULT (N'[]'),
    [Resultado] varchar(15) NOT NULL CONSTRAINT [DF_Conciliacion_Resultado] DEFAULT ('OK'),
    [UsuarioCreacionAuditoria] varchar(30),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    CONSTRAINT [PK_integracion_Conciliacion] PRIMARY KEY ([IdConciliacion] ASC)
);

CREATE INDEX [IX_integracion_Conciliacion_Fecha] ON [integracion].[Conciliacion] ([EjecutadoEn] DESC);
GO
