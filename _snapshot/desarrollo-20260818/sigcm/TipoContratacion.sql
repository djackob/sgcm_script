/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.TipoContratacion
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[TipoContratacion] (
    [CodigoTipoContratacion] varchar(20) NOT NULL,
    [Nombre] varchar(120) NOT NULL,
    [TipoBienSiga] char(1) NOT NULL,
    [RutaEntregables] bit NOT NULL CONSTRAINT [DF_TipoContratacion_RutaEntregables] DEFAULT ((0)),
    [RutaRecepcionFisica] bit NOT NULL CONSTRAINT [DF_TipoContratacion_RutaRecepcionFisica] DEFAULT ((0)),
    [Activo] bit NOT NULL CONSTRAINT [DF_TipoContratacion_Activo] DEFAULT ((1)),
    CONSTRAINT [PK_sigcm_TipoContratacion] PRIMARY KEY ([CodigoTipoContratacion] ASC)
);
GO
