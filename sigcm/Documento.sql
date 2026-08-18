/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Documento
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Documento] (
    [IdDocumento] uniqueidentifier NOT NULL CONSTRAINT [DF_Documento_IdDocumento] DEFAULT (newsequentialid()),
    [CodigoTipoDocumento] varchar(60) NOT NULL,
    [Numero] varchar(80) NOT NULL,
    [Consolidado] bit NOT NULL CONSTRAINT [DF_Documento_Consolidado] DEFAULT ((0)),
    [VersionVigente] int NOT NULL CONSTRAINT [DF_Documento_VersionVigente] DEFAULT ((1)),
    [Anulado] bit NOT NULL CONSTRAINT [DF_Documento_Anulado] DEFAULT ((0)),
    [Activo] bit NOT NULL CONSTRAINT [DF_Documento_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_Documento_FechaCreacionAuditoria] DEFAULT (getdate()),
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
    CONSTRAINT [UQ_sigcm_Documento_TipoNumero] UNIQUE ([CodigoTipoDocumento] ASC, [Numero] ASC),
    CONSTRAINT [PK_sigcm_Documento] PRIMARY KEY ([IdDocumento] ASC),
    CONSTRAINT [FK_sigcm_Documento_Tipo] FOREIGN KEY ([CodigoTipoDocumento]) REFERENCES [sigcm].[TipoDocumento] ([CodigoTipoDocumento])
);
GO
