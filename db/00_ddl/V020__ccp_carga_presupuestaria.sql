/*
===============================================================================
  SIGCM - V020 : Campos adicionales para carga de CCP (DEC)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF COL_LENGTH('requerimiento.CertificacionCcp', 'NumeroExpedienteSiaf') IS NULL
    ALTER TABLE requerimiento.CertificacionCcp
        ADD NumeroExpedienteSiaf varchar(20) NULL;
GO

IF COL_LENGTH('requerimiento.CertificacionCcp', 'MontoCertificado') IS NULL
    ALTER TABLE requerimiento.CertificacionCcp
        ADD MontoCertificado decimal(18, 2) NULL;
GO

IF COL_LENGTH('requerimiento.CertificacionCcp', 'GeneradoDocumentoMemoUp') IS NULL
    ALTER TABLE requerimiento.CertificacionCcp
        ADD GeneradoDocumentoMemoUp nvarchar(1000) NULL;
GO

IF COL_LENGTH('requerimiento.CertificacionCcp', 'NombreDocumentoMemoUp') IS NULL
    ALTER TABLE requerimiento.CertificacionCcp
        ADD NombreDocumentoMemoUp nvarchar(1000) NULL;
GO

IF COL_LENGTH('requerimiento.CertificacionCcp', 'GeneradoDocumentoPrevision') IS NULL
    ALTER TABLE requerimiento.CertificacionCcp
        ADD GeneradoDocumentoPrevision nvarchar(1000) NULL;
GO

IF COL_LENGTH('requerimiento.CertificacionCcp', 'NombreDocumentoPrevision') IS NULL
    ALTER TABLE requerimiento.CertificacionCcp
        ADD NombreDocumentoPrevision nvarchar(1000) NULL;
GO

PRINT 'V020 aplicada: campos de carga CCP (SIAF, monto, memo UP, prevision).';
GO
