/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.TransicionRol
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[TransicionRol] (
    [CodigoTransicion] varchar(70) NOT NULL,
    [CodigoRol] varchar(40) NOT NULL,
    CONSTRAINT [PK_sigcm_TransicionRol] PRIMARY KEY ([CodigoTransicion] ASC, [CodigoRol] ASC),
    CONSTRAINT [FK_sigcm_TransicionRol_Rol] FOREIGN KEY ([CodigoRol]) REFERENCES [sigcm].[Rol] ([CodigoRol]),
    CONSTRAINT [FK_sigcm_TransicionRol_Transicion] FOREIGN KEY ([CodigoTransicion]) REFERENCES [sigcm].[Transicion] ([CodigoTransicion])
);
GO
