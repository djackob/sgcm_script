/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.DocumentoVersion
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:39
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [sigcm].[DocumentoVersion] (
    [IdDocumentoVersion] uniqueidentifier NOT NULL CONSTRAINT [DF_DocumentoVersion_IdDocumentoVersion] DEFAULT (newsequentialid()),
    [IdDocumento] uniqueidentifier NOT NULL,
    [Version] int NOT NULL,
    [Estado] varchar(15) NOT NULL CONSTRAINT [DF_DocumentoVersion_Estado] DEFAULT ('BORRADOR'),
    [Payload] nvarchar(max) NOT NULL,
    [GeneradoDocumento] nvarchar(max),
    [ArchivoHash] varchar(128),
    [MotivoVersion] nvarchar(max),
    [FirmadoEn] datetime,
    [Activo] bit NOT NULL CONSTRAINT [DF_DocumentoVersion_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_DocumentoVersion_FechaCreacionAuditoria] DEFAULT (getdate()),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    [UsuarioModificacionAuditoria] varchar(30),
    [FechaModificacionAuditoria] datetime,
    [EquipoModificacionAuditoria] varchar(50),
    [ProgramaModificacionAuditoria] varchar(50),
    [NombreDocumento] nvarchar(1000),
    CONSTRAINT [UQ_sigcm_DocVersion_Documento] UNIQUE ([IdDocumento] ASC, [Version] ASC),
    CONSTRAINT [PK_sigcm_DocumentoVersion] PRIMARY KEY ([IdDocumentoVersion] ASC),
    CONSTRAINT [FK_sigcm_DocVersion_Documento] FOREIGN KEY ([IdDocumento]) REFERENCES [sigcm].[Documento] ([IdDocumento])
);
GO
