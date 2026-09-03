/*
===============================================================================
  SIGCM - S015 : Anexo 8 — Cuadro de cotizaciones
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El Anexo 8 no aplica a locacion con una sola cotizacion. El tipo queda
  disponible para bienes y servicios generales (indagacion con 2+ postores).
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento WHERE CodigoTipoDocumento = 'REQ_ANEXO_8_COTIZACIONES')
INSERT INTO sigcm.TipoDocumento
    (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado, Activo)
VALUES
    ('REQ_ANEXO_8_COTIZACIONES', 'REQUERIMIENTO',
     'Cuadro de cotizaciones (Anexo 8)', 'ANX8', 0, 1);
ELSE
UPDATE sigcm.TipoDocumento
   SET Nombre = 'Cuadro de cotizaciones (Anexo 8)',
       NumeracionVisible = 'ANX8',
       Activo = 1
 WHERE CodigoTipoDocumento = 'REQ_ANEXO_8_COTIZACIONES';
GO

DECLARE @Firma TABLE (CodigoRol varchar(40), OrdenFirma smallint);
INSERT INTO @Firma VALUES
  ('ABAST_ESPECIALISTA', 1),
  ('ABAST_COORDINADOR', 2),
  ('ABAST_JEFE', 3);

INSERT INTO sigcm.TipoDocumentoFirma (CodigoTipoDocumento, CodigoRol, OrdenFirma)
SELECT 'REQ_ANEXO_8_COTIZACIONES', s.CodigoRol, s.OrdenFirma
  FROM @Firma AS s
 WHERE NOT EXISTS (
        SELECT 1 FROM sigcm.TipoDocumentoFirma AS d
         WHERE d.CodigoTipoDocumento = 'REQ_ANEXO_8_COTIZACIONES'
           AND d.CodigoRol = s.CodigoRol);
GO

PRINT 'S015 aplicada: REQ_ANEXO_8_COTIZACIONES.';
GO
