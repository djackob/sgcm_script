/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Observacion
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Observacion] (
    [IdObservacion] uniqueidentifier NOT NULL CONSTRAINT [DF_Observacion_IdObservacion] DEFAULT (newsequentialid()),
    [IdExpediente] uniqueidentifier NOT NULL,
    [IdDocumentoVersion] uniqueidentifier,
    [IdUnidadOrigen] uniqueidentifier NOT NULL,
    [CodigoRolOrigen] varchar(40) NOT NULL,
    [IdUnidadDestino] uniqueidentifier NOT NULL,
    [CodigoEstadoRetorno] varchar(60) NOT NULL,
    [Motivo] nvarchar(max) NOT NULL,
    [Estado] varchar(15) NOT NULL CONSTRAINT [DF_Observacion_Estado] DEFAULT ('PENDIENTE'),
    [Respuesta] nvarchar(max),
    [IdRecepcionadaPor] uniqueidentifier,
    [RecepcionadaEn] datetime,
    [IdSubsanadaPor] uniqueidentifier,
    [SubsanadaEn] datetime,
    [CerradaEn] datetime,
    [Activo] bit NOT NULL CONSTRAINT [DF_Observacion_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_Observacion_FechaCreacionAuditoria] DEFAULT (getdate()),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    [UsuarioModificacionAuditoria] varchar(30),
    [FechaModificacionAuditoria] datetime,
    [EquipoModificacionAuditoria] varchar(50),
    [ProgramaModificacionAuditoria] varchar(50),
    CONSTRAINT [PK_sigcm_Observacion] PRIMARY KEY ([IdObservacion] ASC),
    CONSTRAINT [FK_sigcm_Observacion_DocVersion] FOREIGN KEY ([IdDocumentoVersion]) REFERENCES [sigcm].[DocumentoVersion] ([IdDocumentoVersion]),
    CONSTRAINT [FK_sigcm_Observacion_EstadoRetorno] FOREIGN KEY ([CodigoEstadoRetorno]) REFERENCES [sigcm].[Estado] ([CodigoEstado]),
    CONSTRAINT [FK_sigcm_Observacion_Expediente] FOREIGN KEY ([IdExpediente]) REFERENCES [sigcm].[Expediente] ([IdExpediente]),
    CONSTRAINT [FK_sigcm_Observacion_Recepcionada] FOREIGN KEY ([IdRecepcionadaPor]) REFERENCES [sigcm].[Usuario] ([IdUsuario]),
    CONSTRAINT [FK_sigcm_Observacion_RolOrigen] FOREIGN KEY ([CodigoRolOrigen]) REFERENCES [sigcm].[Rol] ([CodigoRol]),
    CONSTRAINT [FK_sigcm_Observacion_Subsanada] FOREIGN KEY ([IdSubsanadaPor]) REFERENCES [sigcm].[Usuario] ([IdUsuario]),
    CONSTRAINT [FK_sigcm_Observacion_UnidadDestino] FOREIGN KEY ([IdUnidadDestino]) REFERENCES [sigcm].[Unidad] ([IdUnidad]),
    CONSTRAINT [FK_sigcm_Observacion_UnidadOrigen] FOREIGN KEY ([IdUnidadOrigen]) REFERENCES [sigcm].[Unidad] ([IdUnidad])
);

CREATE INDEX [IX_sigcm_Observacion_Expediente] ON [sigcm].[Observacion] ([IdExpediente] ASC, [FechaCreacionAuditoria] DESC);
GO
CREATE UNIQUE INDEX [UQ_sigcm_Observacion_Abierta] ON [sigcm].[Observacion] ([IdExpediente] ASC);
GO
