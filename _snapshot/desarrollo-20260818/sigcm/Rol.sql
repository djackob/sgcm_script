/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Rol
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Rol] (
    [CodigoRol] varchar(40) NOT NULL,
    [Nombre] varchar(150) NOT NULL,
    [Descripcion] nvarchar(max),
    [EsTecnico] bit NOT NULL CONSTRAINT [DF_Rol_EsTecnico] DEFAULT ((0)),
    [Activo] bit NOT NULL CONSTRAINT [DF_Rol_Activo] DEFAULT ((1)),
    CONSTRAINT [PK_sigcm_Rol] PRIMARY KEY ([CodigoRol] ASC)
);
GO
