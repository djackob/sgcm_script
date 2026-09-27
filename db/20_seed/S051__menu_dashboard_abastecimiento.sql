/*
===============================================================================
  SIGCM - S051 : Menu "Dashboard de especialistas" (Abastecimiento)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Solo ABAST_JEFE y ABAST_COORDINADOR ven la opcion. La rutina
  sigcm.paDashboardEspecialistas (F022) vuelve a validar el rol.
  Idempotente.
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
  ('DASHBOARD_ABAST', 'Dashboard de especialistas', 80, 1,
   'dashboard-abastecimiento', 'mdi mdi-chart-bar');

UPDATE d SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Activo = s.Activo,
             d.Ruta = s.Ruta, d.Icono = s.Icono
  FROM sigcm.Modulo AS d JOIN @Modulo AS s ON s.CodigoModulo = d.CodigoModulo;

INSERT INTO sigcm.Modulo (CodigoModulo, Nombre, Orden, Activo, Ruta, Icono)
SELECT s.CodigoModulo, s.Nombre, s.Orden, s.Activo, s.Ruta, s.Icono
  FROM @Modulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Modulo AS d WHERE d.CodigoModulo = s.CodigoModulo);
GO

DECLARE @Rol TABLE (CodigoRol varchar(40));
INSERT INTO @Rol VALUES ('ABAST_JEFE'), ('ABAST_COORDINADOR');

UPDATE rm SET rm.Activo = 1
  FROM sigcm.RolModulo AS rm
  JOIN @Rol AS r ON r.CodigoRol = rm.CodigoRol
 WHERE rm.CodigoModulo = 'DASHBOARD_ABAST';

INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT r.CodigoRol, 'DASHBOARD_ABAST'
  FROM @Rol AS r
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS rm
                    WHERE rm.CodigoRol = r.CodigoRol AND rm.CodigoModulo = 'DASHBOARD_ABAST');

DELETE FROM sigcm.RolModulo
 WHERE CodigoModulo = 'DASHBOARD_ABAST'
   AND CodigoRol NOT IN (SELECT CodigoRol FROM @Rol);
GO

PRINT 'S051 aplicada: menu DASHBOARD_ABAST para ABAST_JEFE y ABAST_COORDINADOR.';
GO
