/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Modulo
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Modulo] (
    [CodigoModulo] varchar(30) NOT NULL,
    [Nombre] varchar(150) NOT NULL,
    [Orden] int NOT NULL,
    [Activo] bit NOT NULL CONSTRAINT [DF_Modulo_Activo] DEFAULT ((1)),
    [Ruta] varchar(100),
    [Icono] varchar(60),
    CONSTRAINT [PK_sigcm_Modulo] PRIMARY KEY ([CodigoModulo] ASC)
);
GO
