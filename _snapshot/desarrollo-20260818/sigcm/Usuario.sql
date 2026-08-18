/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Usuario
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Usuario] (
    [IdUsuario] uniqueidentifier NOT NULL CONSTRAINT [DF_Usuario_IdUsuario] DEFAULT (newsequentialid()),
    [Cuenta] varchar(120) NOT NULL,
    [DocumentoIdentidad] varchar(20),
    [Nombres] varchar(120) NOT NULL,
    [Apellidos] varchar(120) NOT NULL,
    [Correo] varchar(200),
    [Cargo] varchar(180),
    [Activo] bit NOT NULL CONSTRAINT [DF_Usuario_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_Usuario_FechaCreacionAuditoria] DEFAULT (getdate()),
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
    CONSTRAINT [UQ_sigcm_Usuario_Cuenta] UNIQUE ([Cuenta] ASC),
    CONSTRAINT [PK_sigcm_Usuario] PRIMARY KEY ([IdUsuario] ASC)
);
GO
