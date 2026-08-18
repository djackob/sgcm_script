/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Estado
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Estado] (
    [CodigoEstado] varchar(60) NOT NULL,
    [CodigoModulo] varchar(30) NOT NULL,
    [Nombre] varchar(150) NOT NULL,
    [Orden] int NOT NULL,
    [EsInicial] bit NOT NULL CONSTRAINT [DF_Estado_EsInicial] DEFAULT ((0)),
    [EsFinal] bit NOT NULL CONSTRAINT [DF_Estado_EsFinal] DEFAULT ((0)),
    [RolResponsable] varchar(40),
    [Activo] bit NOT NULL CONSTRAINT [DF_Estado_Activo] DEFAULT ((1)),
    CONSTRAINT [PK_sigcm_Estado] PRIMARY KEY ([CodigoEstado] ASC),
    CONSTRAINT [FK_sigcm_Estado_Modulo] FOREIGN KEY ([CodigoModulo]) REFERENCES [sigcm].[Modulo] ([CodigoModulo]),
    CONSTRAINT [FK_sigcm_Estado_Rol] FOREIGN KEY ([RolResponsable]) REFERENCES [sigcm].[Rol] ([CodigoRol])
);

CREATE UNIQUE INDEX [UQ_sigcm_Estado_Inicial] ON [sigcm].[Estado] ([CodigoModulo] ASC);
GO
