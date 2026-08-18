/*
===============================================================================
  SIGCM - S900 : Datos de prueba
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  NO INSTALAR EN PRODUCCION. Crea una unidad organica y cuatro usuarios ficticios
  para poder recorrer el flujo de punta a punta sin depender del SSO.

  La unidad se enlaza al centro de costo 01.01 de SIGA porque es uno de los que
  si tiene tareas activas en 2026, y sin tarea activa el registro de un item se
  rechaza por MAESTRO_TAREA. Elegir un centro al azar hace fallar la prueba por
  un motivo que no tiene nada que ver con lo que se esta probando.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @CentroCosto varchar(15) = '01.01';

/* -------------------------------------------------------------------------- */
/* 1. Unidad organica                                                         */
/* -------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sigcm.Unidad WHERE Codigo = 'UO-PRUEBA')
    INSERT INTO sigcm.Unidad (Codigo, Nombre, Sigla, CentroCostoSiga, EsAreaUsuaria,
                              UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES ('UO-PRUEBA', 'Unidad de prueba (Jefatura)', 'UOP', @CentroCosto, 1,
            'seed', 'localhost', 'S900');
ELSE
    UPDATE sigcm.Unidad SET CentroCostoSiga = @CentroCosto WHERE Codigo = 'UO-PRUEBA';

/* Abastecimiento y OA no son areas usuarias y no llevan centro de costo. */
IF NOT EXISTS (SELECT 1 FROM sigcm.Unidad WHERE Codigo = 'UO-ABAST')
    INSERT INTO sigcm.Unidad (Codigo, Nombre, Sigla, EsAreaUsuaria,
                              UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES ('UO-ABAST', 'Unidad de Abastecimiento', 'UA', 0, 'seed', 'localhost', 'S900');

IF NOT EXISTS (SELECT 1 FROM sigcm.Unidad WHERE Codigo = 'UO-OA')
    INSERT INTO sigcm.Unidad (Codigo, Nombre, Sigla, EsAreaUsuaria,
                              UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES ('UO-OA', 'Oficina de Administracion', 'OA', 0, 'seed', 'localhost', 'S900');
GO

/* -------------------------------------------------------------------------- */
/* 2. Usuarios                                                                */
/* -------------------------------------------------------------------------- */

DECLARE @Usuario TABLE (Cuenta varchar(120), Nombres varchar(120),
                        Apellidos varchar(120), Cargo varchar(180));
INSERT INTO @Usuario VALUES
  ('prueba.especialista', 'Ana',    'Quispe Rojas',   'Especialista del area usuaria'),
  ('prueba.jefe',         'Carlos', 'Mendoza Diaz',   'Jefe del area usuaria'),
  ('prueba.oa',           'Lucia',  'Fernandez Paz',  'Analista de la Oficina de Administracion'),
  ('prueba.abastecim',    'Jorge',  'Ramos Salazar',  'Coordinador de Abastecimiento');

INSERT INTO sigcm.Usuario (Cuenta, Nombres, Apellidos, Cargo,
                           UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
SELECT s.Cuenta, s.Nombres, s.Apellidos, s.Cargo, 'seed', 'localhost', 'S900'
  FROM @Usuario AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Usuario AS d WHERE d.Cuenta = s.Cuenta);
GO

/* -------------------------------------------------------------------------- */
/* 3. Asignacion de roles                                                     */
/* -------------------------------------------------------------------------- */

DECLARE @Asignacion TABLE (Cuenta varchar(120), CodigoRol varchar(40),
                           CodigoUnidad varchar(30), EsTitular bit);
INSERT INTO @Asignacion VALUES
  ('prueba.especialista', 'AREA_ESPECIALISTA',  'UO-PRUEBA', 0),
  ('prueba.jefe',         'AREA_JEFE',          'UO-PRUEBA', 1),
  ('prueba.oa',           'OA',                 'UO-OA',     0),
  ('prueba.abastecim',    'ABAST_COORDINADOR',  'UO-ABAST',  0),
  ('prueba.abastecim',    'ABAST_JEFE',         'UO-ABAST',  1);

INSERT INTO sigcm.UsuarioRol (IdUsuario, CodigoRol, IdUnidad, EsTitular,
                              UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
SELECT u.IdUsuario, a.CodigoRol, n.IdUnidad, a.EsTitular, 'seed', 'localhost', 'S900'
  FROM @Asignacion AS a
  JOIN sigcm.Usuario AS u ON u.Cuenta = a.Cuenta
  JOIN sigcm.Unidad  AS n ON n.Codigo = a.CodigoUnidad
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.UsuarioRol AS d
                    WHERE d.IdUsuario = u.IdUsuario
                      AND d.CodigoRol = a.CodigoRol
                      AND d.IdUnidad  = n.IdUnidad);
GO

DECLARE @msg varchar(300) =
    'S900 aplicada: '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Unidad     WHERE Codigo LIKE 'UO-%'))      + ' unidades, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Usuario    WHERE Cuenta LIKE 'prueba.%'))  + ' usuarios, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.UsuarioRol)) + ' asignaciones de rol.';
PRINT @msg;
GO
