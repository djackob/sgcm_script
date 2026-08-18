/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.DiaNoHabil
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[DiaNoHabil] (
    [Fecha] date NOT NULL,
    [Descripcion] varchar(200) NOT NULL,
    [Activo] bit NOT NULL CONSTRAINT [DF_DiaNoHabil_Activo] DEFAULT ((1)),
    CONSTRAINT [PK_sigcm_DiaNoHabil] PRIMARY KEY ([Fecha] ASC)
);
GO
