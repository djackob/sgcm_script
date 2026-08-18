/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Plazo
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Plazo] (
    [IdPlazo] uniqueidentifier NOT NULL CONSTRAINT [DF_Plazo_IdPlazo] DEFAULT (newsequentialid()),
    [IdExpediente] uniqueidentifier NOT NULL,
    [CodigoRegla] varchar(60) NOT NULL,
    [Inicio] datetime NOT NULL,
    [Vencimiento] date NOT NULL,
    [AmpliadoHasta] date,
    [MotivoAmpliacion] nvarchar(max),
    [CumplidoEn] datetime,
    [Estado] varchar(15) NOT NULL CONSTRAINT [DF_Plazo_Estado] DEFAULT ('EN_CURSO'),
    [Activo] bit NOT NULL CONSTRAINT [DF_Plazo_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_Plazo_FechaCreacionAuditoria] DEFAULT (getdate()),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    [UsuarioModificacionAuditoria] varchar(30),
    [FechaModificacionAuditoria] datetime,
    [EquipoModificacionAuditoria] varchar(50),
    [ProgramaModificacionAuditoria] varchar(50),
    CONSTRAINT [PK_sigcm_Plazo] PRIMARY KEY ([IdPlazo] ASC),
    CONSTRAINT [FK_sigcm_Plazo_Expediente] FOREIGN KEY ([IdExpediente]) REFERENCES [sigcm].[Expediente] ([IdExpediente]),
    CONSTRAINT [FK_sigcm_Plazo_Regla] FOREIGN KEY ([CodigoRegla]) REFERENCES [sigcm].[PlazoRegla] ([CodigoRegla])
);

CREATE INDEX [IX_sigcm_Plazo_Expediente] ON [sigcm].[Plazo] ([IdExpediente] ASC);
GO
CREATE INDEX [IX_sigcm_Plazo_Vigilancia] ON [sigcm].[Plazo] ([Estado] ASC, [Vencimiento] ASC);
GO
