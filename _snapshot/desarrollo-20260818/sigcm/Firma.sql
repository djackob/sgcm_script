/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.Firma
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[Firma] (
    [IdFirma] uniqueidentifier NOT NULL CONSTRAINT [DF_Firma_IdFirma] DEFAULT (newsequentialid()),
    [IdDocumentoVersion] uniqueidentifier NOT NULL,
    [CodigoRol] varchar(40) NOT NULL,
    [OrdenFirma] smallint NOT NULL CONSTRAINT [DF_Firma_OrdenFirma] DEFAULT ((1)),
    [IdFirmante] uniqueidentifier NOT NULL,
    [FirmanteNombre] varchar(200) NOT NULL,
    [FirmanteCargo] varchar(200) NOT NULL,
    [Estado] varchar(15) NOT NULL CONSTRAINT [DF_Firma_Estado] DEFAULT ('FIRMADA'),
    [CertificadoSerie] varchar(250),
    [FirmaHash] varchar(256) NOT NULL,
    [FirmaPayload] nvarchar(max) NOT NULL CONSTRAINT [DF_Firma_FirmaPayload] DEFAULT (N'{}'),
    [FirmadoEn] datetime NOT NULL CONSTRAINT [DF_Firma_FirmadoEn] DEFAULT (getdate()),
    [InvalidadaEn] datetime,
    [MotivoInvalidacion] nvarchar(max),
    [UsuarioCreacionAuditoria] varchar(30),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    CONSTRAINT [UQ_sigcm_Firma_VersionRol] UNIQUE ([IdDocumentoVersion] ASC, [CodigoRol] ASC),
    CONSTRAINT [PK_sigcm_Firma] PRIMARY KEY ([IdFirma] ASC),
    CONSTRAINT [FK_sigcm_Firma_Firmante] FOREIGN KEY ([IdFirmante]) REFERENCES [sigcm].[Usuario] ([IdUsuario]),
    CONSTRAINT [FK_sigcm_Firma_Rol] FOREIGN KEY ([CodigoRol]) REFERENCES [sigcm].[Rol] ([CodigoRol]),
    CONSTRAINT [FK_sigcm_Firma_Version] FOREIGN KEY ([IdDocumentoVersion]) REFERENCES [sigcm].[DocumentoVersion] ([IdDocumentoVersion])
);
GO
