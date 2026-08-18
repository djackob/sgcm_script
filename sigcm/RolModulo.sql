/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.RolModulo
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[RolModulo] (
    [CodigoRol] varchar(40) NOT NULL,
    [CodigoModulo] varchar(30) NOT NULL,
    [Activo] bit NOT NULL CONSTRAINT [DF_RolModulo_Activo] DEFAULT ((1)),
    CONSTRAINT [PK_sigcm_RolModulo] PRIMARY KEY ([CodigoRol] ASC, [CodigoModulo] ASC),
    CONSTRAINT [FK_sigcm_RolModulo_Modulo] FOREIGN KEY ([CodigoModulo]) REFERENCES [sigcm].[Modulo] ([CodigoModulo]),
    CONSTRAINT [FK_sigcm_RolModulo_Rol] FOREIGN KEY ([CodigoRol]) REFERENCES [sigcm].[Rol] ([CodigoRol])
);
GO
