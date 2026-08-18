/*
  Base    : DBSIGCM
  Esquema : requerimiento
  Objeto  : requerimiento.Requerimiento
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [requerimiento].[Requerimiento] (
    [IdRequerimiento] uniqueidentifier NOT NULL CONSTRAINT [DF_Requerimiento_IdRequerimiento] DEFAULT (newsequentialid()),
    [IdExpediente] uniqueidentifier NOT NULL,
    [Codigo] varchar(40) NOT NULL,
    [AnoEje] smallint NOT NULL,
    [SecEjec] int NOT NULL,
    [CentroCosto] varchar(15) NOT NULL,
    [Denominacion] varchar(500) NOT NULL,
    [CodigoTipoContratacion] varchar(20) NOT NULL,
    [CodigoDec] varchar(20) NOT NULL,
    [CondicionCmn] varchar(20) NOT NULL,
    [IdSolicitudCmn] uniqueidentifier,
    [GeneradoDocumentoCmn] nvarchar(1000),
    [NombreDocumentoCmn] nvarchar(1000),
    [Monto] decimal(18,2) NOT NULL,
    [PlazoDias] int NOT NULL,
    [FechaInicioPrevisto] date,
    [Ate] varchar(200),
    [RucSugerido] varchar(11),
    [TieneDisponibilidad] bit NOT NULL CONSTRAINT [DF_Requerimiento_TieneDisponibilidad] DEFAULT ((0)),
    [GeneradoDocumentoDisponibilidad] nvarchar(1000),
    [NombreDocumentoDisponibilidad] nvarchar(1000),
    [Sustento] nvarchar(max) NOT NULL,
    [IdResponsable] uniqueidentifier NOT NULL,
    [DatosAdicionales] nvarchar(max) NOT NULL CONSTRAINT [DF_Requerimiento_DatosAdicionales] DEFAULT (N'{}'),
    [Activo] bit NOT NULL CONSTRAINT [DF_Requerimiento_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_Requerimiento_FechaCreacionAuditoria] DEFAULT (getdate()),
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
    CONSTRAINT [UQ_req_Requerimiento_Codigo] UNIQUE ([Codigo] ASC),
    CONSTRAINT [UQ_req_Requerimiento_Expediente] UNIQUE ([IdExpediente] ASC),
    CONSTRAINT [PK_req_Requerimiento] PRIMARY KEY ([IdRequerimiento] ASC),
    CONSTRAINT [FK_req_Requerimiento_Expediente] FOREIGN KEY ([IdExpediente]) REFERENCES [sigcm].[Expediente] ([IdExpediente]),
    CONSTRAINT [FK_req_Requerimiento_Responsable] FOREIGN KEY ([IdResponsable]) REFERENCES [sigcm].[Usuario] ([IdUsuario]),
    CONSTRAINT [FK_req_Requerimiento_SolicitudCmn] FOREIGN KEY ([IdSolicitudCmn]) REFERENCES [cmn].[Solicitud] ([IdSolicitud]),
    CONSTRAINT [FK_req_Requerimiento_TipoCon] FOREIGN KEY ([CodigoTipoContratacion]) REFERENCES [sigcm].[TipoContratacion] ([CodigoTipoContratacion])
);

CREATE INDEX [IX_req_Requerimiento_Centro] ON [requerimiento].[Requerimiento] ([AnoEje] ASC, [SecEjec] ASC, [CentroCosto] ASC);
GO
CREATE INDEX [IX_req_Requerimiento_SolicitudCmn] ON [requerimiento].[Requerimiento] ([IdSolicitudCmn] ASC);
GO
