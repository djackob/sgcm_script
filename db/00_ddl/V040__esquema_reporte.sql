/*
  V040 - Esquema [reporte]: consultas transversales a todos los modulos
  (expediente documental completo). Solo lectura.
*/
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'reporte')
    EXEC (N'CREATE SCHEMA reporte AUTHORIZATION dbo;');
GO

PRINT 'V040 aplicada: esquema reporte.';
GO
