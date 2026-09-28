/*
===============================================================================
  SIGCM - S053 : Menu "Reportes" (Abastecimiento)

  Expediente documental completo: todos los documentos generados en el
  sistema a lo largo del expediente (CMN, requerimiento, ejecucion,
  modificacion, resolucion y pagos). Solo perfiles de Abastecimiento; las
  rutinas de reporte (F026) vuelven a validar el rol. Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Modulo TABLE (CodigoModulo varchar(30), Nombre varchar(150), Orden int,
                       Activo bit, Ruta varchar(100), Icono varchar(60));
INSERT INTO @Modulo VALUES
  ('REPORTES', 'Reportes', 70, 1, 'reportes-expediente', 'mdi mdi-file-document-multiple-outline');

UPDATE d SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Activo = s.Activo,
             d.Ruta = s.Ruta, d.Icono = s.Icono
  FROM sigcm.Modulo AS d JOIN @Modulo AS s ON s.CodigoModulo = d.CodigoModulo;

INSERT INTO sigcm.Modulo (CodigoModulo, Nombre, Orden, Activo, Ruta, Icono)
SELECT s.CodigoModulo, s.Nombre, s.Orden, s.Activo, s.Ruta, s.Icono
  FROM @Modulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Modulo AS d WHERE d.CodigoModulo = s.CodigoModulo);
GO

DECLARE @Rol TABLE (CodigoRol varchar(40));
INSERT INTO @Rol VALUES ('ABAST_JEFE'), ('ABAST_COORDINADOR'), ('ABAST_ESPECIALISTA'), ('ABAST_SECRETARIA');

UPDATE rm SET rm.Activo = 1
  FROM sigcm.RolModulo AS rm
  JOIN @Rol AS r ON r.CodigoRol = rm.CodigoRol
 WHERE rm.CodigoModulo = 'REPORTES';

INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT r.CodigoRol, 'REPORTES'
  FROM @Rol AS r
 WHERE EXISTS (SELECT 1 FROM sigcm.Rol AS x WHERE x.CodigoRol = r.CodigoRol)
   AND NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS rm
                    WHERE rm.CodigoRol = r.CodigoRol AND rm.CodigoModulo = 'REPORTES');

DELETE FROM sigcm.RolModulo
 WHERE CodigoModulo = 'REPORTES'
   AND CodigoRol NOT IN (SELECT CodigoRol FROM @Rol);
GO

PRINT 'S053 aplicada: menu REPORTES para los perfiles de Abastecimiento.';
GO
