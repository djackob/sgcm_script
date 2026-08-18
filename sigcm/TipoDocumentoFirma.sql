/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.TipoDocumentoFirma
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[TipoDocumentoFirma] (
    [CodigoTipoDocumento] varchar(60) NOT NULL,
    [CodigoRol] varchar(40) NOT NULL,
    [OrdenFirma] smallint NOT NULL CONSTRAINT [DF_TipoDocumentoFirma_OrdenFirma] DEFAULT ((1)),
    CONSTRAINT [PK_sigcm_TipoDocumentoFirma] PRIMARY KEY ([CodigoTipoDocumento] ASC, [CodigoRol] ASC),
    CONSTRAINT [FK_sigcm_TipoDocFirma_Rol] FOREIGN KEY ([CodigoRol]) REFERENCES [sigcm].[Rol] ([CodigoRol]),
    CONSTRAINT [FK_sigcm_TipoDocFirma_Tipo] FOREIGN KEY ([CodigoTipoDocumento]) REFERENCES [sigcm].[TipoDocumento] ([CodigoTipoDocumento])
);
GO
