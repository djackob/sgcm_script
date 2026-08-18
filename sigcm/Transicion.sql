/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Transicion
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Transicion] (
    [CodigoTransicion] varchar(70) NOT NULL,
    [CodigoModulo] varchar(30) NOT NULL,
    [CodigoEstadoOrigen] varchar(60) NOT NULL,
    [CodigoEstadoDestino] varchar(60) NOT NULL,
    [NombreAccion] varchar(180) NOT NULL,
    [RequiereComentario] bit NOT NULL CONSTRAINT [DF_Transicion_RequiereComentario] DEFAULT ((0)),
    [RequiereFirma] bit NOT NULL CONSTRAINT [DF_Transicion_RequiereFirma] DEFAULT ((0)),
    [DocumentoRequerido] varchar(60),
    [EncolaIntegracion] bit NOT NULL CONSTRAINT [DF_Transicion_EncolaIntegracion] DEFAULT ((0)),
    [OperacionIntegracion] varchar(30),
    [GeneraObservacion] bit NOT NULL CONSTRAINT [DF_Transicion_GeneraObservacion] DEFAULT ((0)),
    [Activo] bit NOT NULL CONSTRAINT [DF_Transicion_Activo] DEFAULT ((1)),
    CONSTRAINT [PK_sigcm_Transicion] PRIMARY KEY ([CodigoTransicion] ASC),
    CONSTRAINT [FK_sigcm_Transicion_Destino] FOREIGN KEY ([CodigoEstadoDestino]) REFERENCES [sigcm].[Estado] ([CodigoEstado]),
    CONSTRAINT [FK_sigcm_Transicion_Documento] FOREIGN KEY ([DocumentoRequerido]) REFERENCES [sigcm].[TipoDocumento] ([CodigoTipoDocumento]),
    CONSTRAINT [FK_sigcm_Transicion_Modulo] FOREIGN KEY ([CodigoModulo]) REFERENCES [sigcm].[Modulo] ([CodigoModulo]),
    CONSTRAINT [FK_sigcm_Transicion_Origen] FOREIGN KEY ([CodigoEstadoOrigen]) REFERENCES [sigcm].[Estado] ([CodigoEstado])
);

CREATE INDEX [IX_sigcm_Transicion_Origen] ON [sigcm].[Transicion] ([CodigoModulo] ASC, [CodigoEstadoOrigen] ASC);
GO
