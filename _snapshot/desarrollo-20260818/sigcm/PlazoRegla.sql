/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.PlazoRegla
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[PlazoRegla] (
    [CodigoRegla] varchar(60) NOT NULL,
    [CodigoModulo] varchar(30) NOT NULL,
    [Nombre] varchar(200) NOT NULL,
    [CodigoEstadoInicio] varchar(60) NOT NULL,
    [Dias] int NOT NULL,
    [TipoDia] varchar(10) NOT NULL CONSTRAINT [DF_PlazoRegla_TipoDia] DEFAULT ('HABIL'),
    [Ampliable] bit NOT NULL CONSTRAINT [DF_PlazoRegla_Ampliable] DEFAULT ((0)),
    [BaseNormativa] varchar(200),
    [Activo] bit NOT NULL CONSTRAINT [DF_PlazoRegla_Activo] DEFAULT ((1)),
    CONSTRAINT [PK_sigcm_PlazoRegla] PRIMARY KEY ([CodigoRegla] ASC),
    CONSTRAINT [FK_sigcm_PlazoRegla_Estado] FOREIGN KEY ([CodigoEstadoInicio]) REFERENCES [sigcm].[Estado] ([CodigoEstado]),
    CONSTRAINT [FK_sigcm_PlazoRegla_Modulo] FOREIGN KEY ([CodigoModulo]) REFERENCES [sigcm].[Modulo] ([CodigoModulo])
);
GO
