/*
===============================================================================
  SIGCM - V024 : Numero consecutivo del memorando de solicitud de CCP
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El PDF lleva MEMORANDO N° 001-AAAA-ANIN/OA-UA. El correlativo es por anio
  (sigcm.Correlativo: requerimiento.SeqMemoCcp|{anio}) y se reutiliza si el
  requerimiento ya tiene numero asignado.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF COL_LENGTH('requerimiento.CertificacionCcp', 'NumeroMemorando') IS NULL
    ALTER TABLE requerimiento.CertificacionCcp
        ADD NumeroMemorando varchar(40) NULL;
GO

PRINT 'V024 aplicada: NumeroMemorando en CertificacionCcp.';
GO
