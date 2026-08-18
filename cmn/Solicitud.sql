/*
  Base    : DBSIGCM
  Esquema : cmn
  Objeto  : cmn.Solicitud
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [cmn].[Solicitud] (
    [IdSolicitud] uniqueidentifier NOT NULL CONSTRAINT [DF_Solicitud_IdSolicitud] DEFAULT (newsequentialid()),
    [IdExpediente] uniqueidentifier NOT NULL,
    [Codigo] varchar(40) NOT NULL,
    [AnoEje] smallint NOT NULL,
    [SecEjec] int NOT NULL,
    [CentroCosto] varchar(15) NOT NULL,
    [TipoOperacion] varchar(20) NOT NULL CONSTRAINT [DF_Solicitud_TipoOperacion] DEFAULT ('MODIFICACION'),
    [TipoInclusion] varchar(15),
    [Sustento] nvarchar(max) NOT NULL,
    [FechaSolicitud] date NOT NULL CONSTRAINT [DF_Solicitud_FechaSolicitud] DEFAULT (CONVERT([date],getdate())),
    [IdResponsable] uniqueidentifier NOT NULL,
    [DatosAdicionales] nvarchar(max) NOT NULL CONSTRAINT [DF_Solicitud_DatosAdicionales] DEFAULT (N'{}'),
    [Activo] bit NOT NULL CONSTRAINT [DF_Solicitud_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_Solicitud_FechaCreacionAuditoria] DEFAULT (getdate()),
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
    CONSTRAINT [UQ_cmn_Solicitud_Codigo] UNIQUE ([Codigo] ASC),
    CONSTRAINT [UQ_cmn_Solicitud_Expediente] UNIQUE ([IdExpediente] ASC),
    CONSTRAINT [PK_cmn_Solicitud] PRIMARY KEY ([IdSolicitud] ASC),
    CONSTRAINT [FK_cmn_Solicitud_Expediente] FOREIGN KEY ([IdExpediente]) REFERENCES [sigcm].[Expediente] ([IdExpediente]),
    CONSTRAINT [FK_cmn_Solicitud_Responsable] FOREIGN KEY ([IdResponsable]) REFERENCES [sigcm].[Usuario] ([IdUsuario])
);

CREATE INDEX [IX_cmn_Solicitud_Centro] ON [cmn].[Solicitud] ([AnoEje] ASC, [SecEjec] ASC, [CentroCosto] ASC);
GO
