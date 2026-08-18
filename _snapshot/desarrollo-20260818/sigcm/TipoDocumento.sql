/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.TipoDocumento
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[TipoDocumento] (
    [CodigoTipoDocumento] varchar(60) NOT NULL,
    [CodigoModulo] varchar(30) NOT NULL,
    [Nombre] varchar(200) NOT NULL,
    [NumeracionVisible] varchar(60) NOT NULL,
    [AdmiteConsolidado] bit NOT NULL CONSTRAINT [DF_TipoDocumento_AdmiteConsolidado] DEFAULT ((0)),
    [Activo] bit NOT NULL CONSTRAINT [DF_TipoDocumento_Activo] DEFAULT ((1)),
    CONSTRAINT [PK_sigcm_TipoDocumento] PRIMARY KEY ([CodigoTipoDocumento] ASC),
    CONSTRAINT [FK_sigcm_TipoDoc_Modulo] FOREIGN KEY ([CodigoModulo]) REFERENCES [sigcm].[Modulo] ([CodigoModulo])
);
GO
