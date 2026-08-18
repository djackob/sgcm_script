/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Unidad
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Unidad] (
    [IdUnidad] uniqueidentifier NOT NULL CONSTRAINT [DF_Unidad_IdUnidad] DEFAULT (newsequentialid()),
    [Codigo] varchar(30) NOT NULL,
    [Nombre] varchar(200) NOT NULL,
    [Sigla] varchar(30),
    [IdUnidadPadre] uniqueidentifier,
    [CentroCostoSiga] varchar(15),
    [EsAreaUsuaria] bit NOT NULL CONSTRAINT [DF_Unidad_EsAreaUsuaria] DEFAULT ((0)),
    [Activo] bit NOT NULL CONSTRAINT [DF_Unidad_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_Unidad_FechaCreacionAuditoria] DEFAULT (getdate()),
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
    CONSTRAINT [UQ_sigcm_Unidad_Codigo] UNIQUE ([Codigo] ASC),
    CONSTRAINT [PK_sigcm_Unidad] PRIMARY KEY ([IdUnidad] ASC),
    CONSTRAINT [FK_sigcm_Unidad_Padre] FOREIGN KEY ([IdUnidadPadre]) REFERENCES [sigcm].[Unidad] ([IdUnidad])
);

CREATE INDEX [IX_sigcm_Unidad_CentroCosto] ON [sigcm].[Unidad] ([CentroCostoSiga] ASC);
GO
