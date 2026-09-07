/*
===============================================================================
  SIGCM - Semilla S021 : Secretaria de Abastecimiento
  Ambito : [DBSIGCM]

  Perfil que recibe y deriva expedientes CMN en Abastecimiento sin facultad de
  firma. Idempotente.
===============================================================================
*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

MERGE sigcm.Rol AS d
USING (VALUES
  ('ABAST_SECRETARIA', 'Abastecimiento - Secretaria',
   'Recibe y deriva expedientes en Abastecimiento; no firma documentos', CAST(0 AS bit))
) AS s(CodigoRol, Nombre, Descripcion, EsTecnico)
ON d.CodigoRol = s.CodigoRol
WHEN MATCHED THEN
  UPDATE SET Nombre = s.Nombre, Descripcion = s.Descripcion, EsTecnico = s.EsTecnico, Activo = 1
WHEN NOT MATCHED THEN
  INSERT (CodigoRol, Nombre, Descripcion, EsTecnico, Activo)
  VALUES (s.CodigoRol, s.Nombre, s.Descripcion, s.EsTecnico, 1);

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('CMN_ABAST_JEFE_DERIVAR', 'ABAST_SECRETARIA'),
  ('CMN_ABAST_COORD_DERIVAR', 'ABAST_SECRETARIA'),
  ('CMN_OBS_COORD_DERIVAR', 'ABAST_SECRETARIA'),
  ('CMN_OBS_JEFE_DEVOLVER', 'ABAST_SECRETARIA');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE EXISTS (SELECT 1 FROM sigcm.Transicion t WHERE t.CodigoTransicion = s.CodigoTransicion AND t.Activo = 1)
   AND NOT EXISTS (
         SELECT 1 FROM sigcm.TransicionRol d
          WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);

DELETE FROM sigcm.TipoDocumentoFirma
 WHERE CodigoRol = 'ABAST_SECRETARIA';

PRINT 'S021: rol ABAST_SECRETARIA y derivaciones sin firma.';
GO
