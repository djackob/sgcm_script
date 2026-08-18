/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.DocumentoExpediente
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[DocumentoExpediente] (
    [IdDocumento] uniqueidentifier NOT NULL,
    [IdExpediente] uniqueidentifier NOT NULL,
    CONSTRAINT [PK_sigcm_DocumentoExpediente] PRIMARY KEY ([IdDocumento] ASC, [IdExpediente] ASC),
    CONSTRAINT [FK_sigcm_DocExp_Documento] FOREIGN KEY ([IdDocumento]) REFERENCES [sigcm].[Documento] ([IdDocumento]),
    CONSTRAINT [FK_sigcm_DocExp_Expediente] FOREIGN KEY ([IdExpediente]) REFERENCES [sigcm].[Expediente] ([IdExpediente])
);

CREATE INDEX [IX_sigcm_DocExp_Inverso] ON [sigcm].[DocumentoExpediente] ([IdExpediente] ASC, [IdDocumento] ASC);
GO
