/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.UsuarioRol
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[UsuarioRol] (
    [IdUsuarioRol] uniqueidentifier NOT NULL CONSTRAINT [DF_UsuarioRol_IdUsuarioRol] DEFAULT (newsequentialid()),
    [IdUsuario] uniqueidentifier NOT NULL,
    [CodigoRol] varchar(40) NOT NULL,
    [IdUnidad] uniqueidentifier NOT NULL,
    [EsTitular] bit NOT NULL CONSTRAINT [DF_UsuarioRol_EsTitular] DEFAULT ((0)),
    [VigenteDesde] date NOT NULL CONSTRAINT [DF_UsuarioRol_VigenteDesde] DEFAULT (CONVERT([date],getdate())),
    [VigenteHasta] date,
    [Activo] bit NOT NULL CONSTRAINT [DF_UsuarioRol_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_UsuarioRol_FechaCreacionAuditoria] DEFAULT (getdate()),
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
    CONSTRAINT [PK_sigcm_UsuarioRol] PRIMARY KEY ([IdUsuarioRol] ASC),
    CONSTRAINT [FK_sigcm_UsuarioRol_Rol] FOREIGN KEY ([CodigoRol]) REFERENCES [sigcm].[Rol] ([CodigoRol]),
    CONSTRAINT [FK_sigcm_UsuarioRol_Unidad] FOREIGN KEY ([IdUnidad]) REFERENCES [sigcm].[Unidad] ([IdUnidad]),
    CONSTRAINT [FK_sigcm_UsuarioRol_Usuario] FOREIGN KEY ([IdUsuario]) REFERENCES [sigcm].[Usuario] ([IdUsuario])
);

CREATE INDEX [IX_sigcm_UsuarioRol_Unidad] ON [sigcm].[UsuarioRol] ([IdUnidad] ASC, [CodigoRol] ASC);
GO
CREATE UNIQUE INDEX [UQ_sigcm_UsuarioRol_Vigente] ON [sigcm].[UsuarioRol] ([IdUsuario] ASC, [CodigoRol] ASC, [IdUnidad] ASC);
GO
