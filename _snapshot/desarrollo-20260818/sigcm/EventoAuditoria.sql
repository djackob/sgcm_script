/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.EventoAuditoria
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[EventoAuditoria] (
    [IdEvento] bigint IDENTITY(1,1) NOT NULL,
    [CorrelacionId] uniqueidentifier NOT NULL CONSTRAINT [DF_EventoAuditoria_CorrelacionId] DEFAULT (newid()),
    [CodigoModulo] varchar(30),
    [Entidad] varchar(80) NOT NULL,
    [IdEntidad] uniqueidentifier,
    [Accion] varchar(80) NOT NULL,
    [Resultado] varchar(15) NOT NULL CONSTRAINT [DF_EventoAuditoria_Resultado] DEFAULT ('OK'),
    [IdActor] uniqueidentifier,
    [ActorCuenta] varchar(120) NOT NULL,
    [ActorRol] varchar(40),
    [IdActorUnidad] uniqueidentifier,
    [OrigenIp] varchar(45),
    [Equipo] varchar(50),
    [Programa] varchar(50),
    [DatosAntes] nvarchar(max),
    [DatosDespues] nvarchar(max),
    [Metadata] nvarchar(max) NOT NULL CONSTRAINT [DF_EventoAuditoria_Metadata] DEFAULT (N'{}'),
    [OcurridoEn] datetime NOT NULL CONSTRAINT [DF_EventoAuditoria_OcurridoEn] DEFAULT (getdate()),
    CONSTRAINT [PK_sigcm_EventoAuditoria] PRIMARY KEY ([IdEvento] ASC),
    CONSTRAINT [FK_sigcm_EventoAuditoria_Actor] FOREIGN KEY ([IdActor]) REFERENCES [sigcm].[Usuario] ([IdUsuario]),
    CONSTRAINT [FK_sigcm_EventoAuditoria_Unidad] FOREIGN KEY ([IdActorUnidad]) REFERENCES [sigcm].[Unidad] ([IdUnidad])
);

CREATE INDEX [IX_sigcm_EventoAuditoria_Actor] ON [sigcm].[EventoAuditoria] ([ActorCuenta] ASC, [OcurridoEn] DESC);
GO
CREATE INDEX [IX_sigcm_EventoAuditoria_Correlacion] ON [sigcm].[EventoAuditoria] ([CorrelacionId] ASC);
GO
CREATE INDEX [IX_sigcm_EventoAuditoria_Entidad] ON [sigcm].[EventoAuditoria] ([Entidad] ASC, [IdEntidad] ASC, [OcurridoEn] DESC);
GO
