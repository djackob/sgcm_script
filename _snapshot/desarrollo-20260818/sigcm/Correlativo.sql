/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Correlativo
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Correlativo] (
    [Nombre] nvarchar(128) NOT NULL,
    [Valor] bigint NOT NULL,
    CONSTRAINT [PK_sigcm_Correlativo] PRIMARY KEY ([Nombre] ASC)
);
GO
