/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Historial
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Historial] (
    [IdHistorial] bigint IDENTITY(1,1) NOT NULL,
    [IdExpediente] uniqueidentifier NOT NULL,
    [CodigoEstadoOrigen] varchar(60),
    [CodigoEstadoDestino] varchar(60) NOT NULL,
    [CodigoTransicion] varchar(70),
    [Comentario] nvarchar(max),
    [IdActor] uniqueidentifier NOT NULL,
    [ActorRol] varchar(40) NOT NULL,
    [IdActorUnidad] uniqueidentifier,
    [Metadata] nvarchar(max) NOT NULL CONSTRAINT [DF_Historial_Metadata] DEFAULT (N'{}'),
    [OcurridoEn] datetime NOT NULL CONSTRAINT [DF_Historial_OcurridoEn] DEFAULT (getdate()),
    [UsuarioCreacionAuditoria] varchar(30),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    CONSTRAINT [PK_sigcm_Historial] PRIMARY KEY ([IdHistorial] ASC),
    CONSTRAINT [FK_sigcm_Historial_Actor] FOREIGN KEY ([IdActor]) REFERENCES [sigcm].[Usuario] ([IdUsuario]),
    CONSTRAINT [FK_sigcm_Historial_Expediente] FOREIGN KEY ([IdExpediente]) REFERENCES [sigcm].[Expediente] ([IdExpediente]),
    CONSTRAINT [FK_sigcm_Historial_Unidad] FOREIGN KEY ([IdActorUnidad]) REFERENCES [sigcm].[Unidad] ([IdUnidad])
);

CREATE INDEX [IX_sigcm_Historial_Expediente] ON [sigcm].[Historial] ([IdExpediente] ASC, [OcurridoEn] DESC);
GO
