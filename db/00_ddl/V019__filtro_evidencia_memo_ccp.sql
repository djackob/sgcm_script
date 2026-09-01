/*
===============================================================================
  SIGCM - Migracion V019 : Evidencias de filtros y cuerpo del memorando CCP
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF COL_LENGTH('requerimiento.FiltroIdoneidad', 'GeneradoDocumentoEvidencia') IS NULL
    ALTER TABLE requerimiento.FiltroIdoneidad
        ADD GeneradoDocumentoEvidencia nvarchar(1000) NULL,
            NombreDocumentoEvidencia   nvarchar(1000) NULL;
GO

IF COL_LENGTH('requerimiento.CertificacionCcp', 'CuerpoMemorando') IS NULL
    ALTER TABLE requerimiento.CertificacionCcp
        ADD CuerpoMemorando nvarchar(max) NULL;
GO

UPDATE requerimiento.FiltroTipo
   SET Nombre = N'Relación de Proveedores Sancionados por el OSCE (sanción vigente)'
 WHERE CodigoFiltro = 'RPS_TCP';
GO

PRINT 'V019 aplicada: evidencias de filtros y cuerpo del memorando CCP.';
GO
