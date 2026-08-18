/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Expediente
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Expediente] (
    [IdExpediente] uniqueidentifier NOT NULL CONSTRAINT [DF_Expediente_IdExpediente] DEFAULT (newsequentialid()),
    [Codigo] varchar(40) NOT NULL,
    [CodigoModulo] varchar(30) NOT NULL,
    [CodigoTipoContratacion] varchar(20),
    [AnoEje] smallint NOT NULL,
    [IdUnidadOrigen] uniqueidentifier NOT NULL,
    [CodigoEstado] varchar(60) NOT NULL,
    [IdUnidadActual] uniqueidentifier,
    [IdResponsableActual] uniqueidentifier,
    [Version] int NOT NULL CONSTRAINT [DF_Expediente_Version] DEFAULT ((1)),
    [IdExpedientePadre] uniqueidentifier,
    [Anulado] bit NOT NULL CONSTRAINT [DF_Expediente_Anulado] DEFAULT ((0)),
    [MotivoAnulacion] nvarchar(max),
    [CerradoEn] datetime,
    [Activo] bit NOT NULL CONSTRAINT [DF_Expediente_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_Expediente_FechaCreacionAuditoria] DEFAULT (getdate()),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    [UsuarioModificacionAuditoria] varchar(30),
    [FechaModificacionAuditoria] datetime,
    [EquipoModificacionAuditoria] varchar(50),
    [ProgramaModificacionAuditoria] varchar(50),
    [UsuarioEliminacionAuditoria] varchar(30),
    [FechaEliminacionAuditoria] datetime,
    [EquipoEliminacionAuditoria] varchar(50),
    [ProgramaEliminacionAuditoria] varchar(50),
    CONSTRAINT [UQ_sigcm_Expediente_Codigo] UNIQUE ([Codigo] ASC),
    CONSTRAINT [PK_sigcm_Expediente] PRIMARY KEY ([IdExpediente] ASC),
    CONSTRAINT [FK_sigcm_Expediente_Estado] FOREIGN KEY ([CodigoEstado]) REFERENCES [sigcm].[Estado] ([CodigoEstado]),
    CONSTRAINT [FK_sigcm_Expediente_Modulo] FOREIGN KEY ([CodigoModulo]) REFERENCES [sigcm].[Modulo] ([CodigoModulo]),
    CONSTRAINT [FK_sigcm_Expediente_Padre] FOREIGN KEY ([IdExpedientePadre]) REFERENCES [sigcm].[Expediente] ([IdExpediente]),
    CONSTRAINT [FK_sigcm_Expediente_Responsable] FOREIGN KEY ([IdResponsableActual]) REFERENCES [sigcm].[Usuario] ([IdUsuario]),
    CONSTRAINT [FK_sigcm_Expediente_TipoCon] FOREIGN KEY ([CodigoTipoContratacion]) REFERENCES [sigcm].[TipoContratacion] ([CodigoTipoContratacion]),
    CONSTRAINT [FK_sigcm_Expediente_UnidadActual] FOREIGN KEY ([IdUnidadActual]) REFERENCES [sigcm].[Unidad] ([IdUnidad]),
    CONSTRAINT [FK_sigcm_Expediente_UnidadOrigen] FOREIGN KEY ([IdUnidadOrigen]) REFERENCES [sigcm].[Unidad] ([IdUnidad])
);

CREATE INDEX [IX_sigcm_Expediente_Bandeja] ON [sigcm].[Expediente] ([CodigoModulo] ASC, [CodigoEstado] ASC, [IdUnidadActual] ASC);
GO
CREATE INDEX [IX_sigcm_Expediente_Origen] ON [sigcm].[Expediente] ([IdUnidadOrigen] ASC, [AnoEje] ASC);
GO
CREATE INDEX [IX_sigcm_Expediente_Responsable] ON [sigcm].[Expediente] ([IdResponsableActual] ASC, [FechaModificacionAuditoria] DESC);
GO
