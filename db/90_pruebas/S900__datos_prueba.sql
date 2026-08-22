/*
===============================================================================
  SIGCM - S900 : Datos de prueba
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  NO INSTALAR EN PRODUCCION. Crea unidades organicas y usuarios ficticios para
  poder recorrer el flujo de punta a punta sin depender del SSO.

  DOS AREAS USUARIAS, Y POR QUE
  ----------------------------
  UO-PRUEBA -> centro de costo 01.01       (Jefatura)
  UO-OTI    -> centro de costo 01.07.05.03 (Oficina de Tecnologias de la
                                            Informacion)

  Dos condiciones, y la primera se leyo al reves en la primera version de este
  archivo. Queda escrita con el error a la vista para que no se repita.

  1. EL CENTRO TIENE QUE ESTAR EN "CONSOLIDACION Y APROBACION".
     SIG_CUADRO_X_CENTRO.estado gobierna la columna "Estado C.M.N." de la
     pantalla "Registro de C.M.N. por Area Usuaria":

         estado '4'  ->  "Consolidacion y Aprobacion"   26 centros en 2026
         estado '6'  ->  "C.C.M.N."                     17 centros en 2026

     Es el estado '4' el que habilita la Demanda Adicional. Con un centro en
     '6' el aplicativo responde "El Area Usuaria debe estar en estado
     Consolidacion y Aprobacion" y no abre la pantalla.

     La primera version de este archivo eligio OGP (01.06.03) por tener el
     estado '6', razonando que "C.C.M.N." significaba cuadro abierto. Es al
     reves: '6' es el cuadro ya cerrado. La inclusion de prueba llego igual a
     SIG_CUADRO_MODIFICADO -la base no valida eso- pero no habia forma de verla
     desde el aplicativo, que es de lo que se trataba.

  2. TIENE QUE QUEDAR TECHO LIBRE.
     El techo se compara por CENTRO_COSTO + SEC_FUNC + CLASIFICADOR + ORIGEN +
     FUENTE_FINANC, no por centro entero. Al 2026-08-19, sobre la meta 15 y el
     clasificador 2.3. 2  9. 1  1, OTI tiene S/ 131 994 libres del anio base.

  Se eligio OTI y no uno de los grandes (SEI tiene 20 millones libres) porque
  su cuadro tiene 16 items: en una pantalla con 4 175 lineas no se distingue la
  que acaba de registrarse.

  01.01 se conserva por compatibilidad con pruebas anteriores, pero esta en
  estado '6': sirve para probar la escritura en base, no para verla en el
  aplicativo.

  Para elegir otro centro, la consulta esta en
  C:\SIGA_MEF\integracion\ANALISIS_CMN.md, seccion "Elegir un area usuaria".

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

/*
  AREAS USUARIAS REALES, PARA PROBAR EL ANEXO 4 MULTIPLE
  ------------------------------------------------------
  Cuatro, y no una: un Anexo 4 que agrupa Anexos 3 de varias oficinas no se
  puede probar con una sola area.

  Las cuatro se eligieron consultando SIGA_1750 con las tres condiciones que
  hacen falta para que la inclusion sea VISIBLE en el aplicativo (ver
  ANALISIS_CMN.md, seccion 4ter):

      centro         area   cuadro   meta   clasificador       libre 2026
      01.07.05.03    OTI      4       15    2.3. 2  9. 1  1     123 994
      01.07.05.01    UDS      4       11    2.3. 2  5. 1 99     360 731
      01.07.05.02    US       4       14    2.3. 2  9. 1  1     102 999
      01.07.04       ORH      4       18    2.3. 2  7. 3  1      68 700

  Las cuatro tienen el cuadro en estado '4' y tarea activa en esa meta, que es
  todo lo que hace falta. flag_da_aprob solo la pide la pantalla "Demanda
  Adicional", que no usamos: lo que registra el SIGCM se verifica en
  Modificacion de C.M.N., y esa ruta no mira la bandera. Sobre SIGA_1750 solo
  escribe el flujo; este script no la toca ni debe tocarla.

  UO-PRUEBA (centro 01.01, JEFATURA) se conserva, pero OJO: su cuadro esta en
  estado '6', no '4'. Sirve para ejercitar el SIGCM —S903 la usa— pero lo que se
  registre ahi NO se vera en el aplicativo SIGA. Para la prueba de punta a punta
  hay que usar las cuatro de arriba.
*/
DECLARE @AreaUsuaria TABLE (Codigo varchar(30), Nombre varchar(150),
                            Sigla varchar(20), Centro varchar(15));
INSERT INTO @AreaUsuaria VALUES
  ('UO-OTI', 'Oficina de Tecnologias de la Informacion', 'OTI', '01.07.05.03'),
  ('UO-UDS', 'Unidad de Desarrollo de Sistemas',         'UDS', '01.07.05.01'),
  ('UO-US',  'Unidad de Soporte',                        'US',  '01.07.05.02'),
  ('UO-ORH', 'Oficina de Recursos Humanos',              'ORH', '01.07.04');

UPDATE d
   SET d.Nombre = s.Nombre, d.Sigla = s.Sigla,
       d.CentroCostoSiga = s.Centro, d.EsAreaUsuaria = 1
  FROM sigcm.Unidad AS d JOIN @AreaUsuaria AS s ON s.Codigo = d.Codigo;

INSERT INTO sigcm.Unidad (Codigo, Nombre, Sigla, CentroCostoSiga, EsAreaUsuaria,
                          UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
SELECT s.Codigo, s.Nombre, s.Sigla, s.Centro, 1, 'seed', 'localhost', 'S900'
  FROM @AreaUsuaria AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Unidad AS d WHERE d.Codigo = s.Codigo);

/* Retira el perfil UO-OGP que sembro la version anterior de este archivo. Se
   eligio por el criterio equivocado (estado '6') y no sirve para la prueba. Solo
   se borra si no dejo expedientes atras; si los dejo, se conserva para no
   romper la trazabilidad y basta con no usarlo. */
IF EXISTS (SELECT 1 FROM sigcm.Unidad WHERE Codigo = 'UO-OGP')
   AND NOT EXISTS (SELECT 1 FROM sigcm.Expediente e
                    JOIN sigcm.Unidad u ON u.IdUnidad = e.IdUnidadOrigen
                   WHERE u.Codigo = 'UO-OGP')
BEGIN
    DELETE ur
      FROM sigcm.UsuarioRol ur
      JOIN sigcm.Unidad u ON u.IdUnidad = ur.IdUnidad
     WHERE u.Codigo = 'UO-OGP';

    DELETE FROM sigcm.Usuario WHERE Cuenta IN ('prueba.ogp.esp', 'prueba.ogp.jefe');
    DELETE FROM sigcm.Unidad  WHERE Codigo = 'UO-OGP';

    PRINT '  Retirado el perfil UO-OGP (elegido con el criterio equivocado).';
END
ELSE IF EXISTS (SELECT 1 FROM sigcm.Unidad WHERE Codigo = 'UO-OGP')
    PRINT '  [AVISO] UO-OGP tiene expedientes y se conserva. No usarlo: su centro esta en estado 6.';
GO

/* -------------------------------------------------------------------------- */
/* 2. Usuarios                                                                */
/* -------------------------------------------------------------------------- */

/*
  UNA CUENTA POR ROL, Y NO UNA CUENTA CON VARIOS ROLES.

  'prueba.abastecim' tenia asignados ABAST_COORDINADOR y ABAST_JEFE a la vez.
  Con eso el flujo nuevo no se puede probar: la firma del coordinador y la del
  jefe son dos pasos distintos del Anexo 3 y del Anexo 4, y si las pone la misma
  persona no se comprueba nada —ni siquiera se nota si el motor esta pidiendo el
  rol correcto, porque el actor los tiene todos—.

  Las cuentas viejas no se borran: se les retira la asignacion que ya no
  corresponde, mas abajo. Borrarlas romperia la auditoria de lo ya tramitado.
*/
DECLARE @Usuario TABLE (Cuenta varchar(120), Nombres varchar(120),
                        Apellidos varchar(120), Cargo varchar(180));
INSERT INTO @Usuario VALUES
  ('prueba.especialista', 'Ana',    'Quispe Rojas',    'Especialista del area usuaria'),
  ('prueba.coordinador',  'Pedro',  'Alvarez Nunez',   'Coordinador del area usuaria'),
  ('prueba.jefe',         'Carlos', 'Mendoza Diaz',    'Jefe del area usuaria'),
  ('prueba.oa',           'Lucia',  'Fernandez Paz',   'Analista de la Oficina de Administracion'),
  ('prueba.abast.esp',    'Sofia',  'Herrera Cordova', 'Especialista de Abastecimiento'),
  ('prueba.abastecim',    'Jorge',  'Ramos Salazar',   'Coordinador de Abastecimiento'),
  ('prueba.abast.jefe',   'Raul',   'Vega Tapia',      'Jefe de la Unidad de Abastecimiento'),
  ('prueba.oti.esp',      'Rosa',   'Chavez Untiveros','Especialista de la OTI'),
  ('prueba.oti.coord',    'Elena',  'Salas Bravo',     'Coordinadora de la OTI'),
  ('prueba.oti.jefe',     'Miguel', 'Arce Ponce',      'Jefe de la Oficina de Tecnologias de la Informacion'),

  /* Las tres areas usuarias reales que se agregaron para el Anexo 4 multiple.
     Cada una con su terna completa: sin coordinador no se puede recorrer la
     devolucion de observaciones, que baja por los tres escalones del area. */
  ('prueba.uds.esp',      'Diego',  'Palomino Rios',   'Especialista de la UDS'),
  ('prueba.uds.coord',    'Karina', 'Loayza Medina',   'Coordinadora de la UDS'),
  ('prueba.uds.jefe',     'Andres', 'Bustamante Leon', 'Jefe de la Unidad de Desarrollo de Sistemas'),
  ('prueba.us.esp',       'Paola',  'Ruiz Carrillo',   'Especialista de la Unidad de Soporte'),
  ('prueba.us.coord',     'Victor', 'Nunez Alfaro',    'Coordinador de la Unidad de Soporte'),
  ('prueba.us.jefe',      'Marina', 'Zegarra Pinto',   'Jefa de la Unidad de Soporte'),
  ('prueba.orh.esp',      'Cesar',  'Ibanez Torres',   'Especialista de la ORH'),
  ('prueba.orh.coord',    'Julia',  'Ampuero Vela',    'Coordinadora de la ORH'),
  ('prueba.orh.jefe',     'Fabian', 'Rojas Delgado',   'Jefe de la Oficina de Recursos Humanos');

/* El cargo se actualiza aunque la cuenta ya exista: 'prueba.abastecim' figuraba
   como Coordinador pero ejercia tambien de jefe, y ahora es solo lo primero. */
UPDATE d SET d.Cargo = s.Cargo
  FROM sigcm.Usuario AS d JOIN @Usuario AS s ON s.Cuenta = d.Cuenta;

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
/*
  Dos areas usuarias completas —UO-PRUEBA y UO-OTI— y no una sola: el Anexo 4
  multiple no se puede probar con una. Hacen falta al menos dos oficinas con sus
  propios Anexos 3 para que el especialista marque items de origenes distintos y
  se vea que cada uno vuelve a su area al final.

  Las cuentas AREA_COORDINADOR de area usuaria se conservan por compatibilidad
  de login, pero ya no tienen modulo CMN: el flujo AU es especialista <-> jefe.
*/
INSERT INTO @Asignacion VALUES
  ('prueba.especialista', 'AREA_ESPECIALISTA',  'UO-PRUEBA', 0),
  ('prueba.coordinador',  'AREA_COORDINADOR',   'UO-PRUEBA', 0),
  ('prueba.jefe',         'AREA_JEFE',          'UO-PRUEBA', 1),
  ('prueba.oa',           'OA',                 'UO-OA',     0),
  ('prueba.abast.esp',    'ABAST_ESPECIALISTA', 'UO-ABAST',  0),
  ('prueba.abastecim',    'ABAST_COORDINADOR',  'UO-ABAST',  0),
  ('prueba.abast.jefe',   'ABAST_JEFE',         'UO-ABAST',  1),
  ('prueba.oti.esp',      'AREA_ESPECIALISTA',  'UO-OTI',    0),
  ('prueba.oti.coord',    'AREA_COORDINADOR',   'UO-OTI',    0),
  ('prueba.oti.jefe',     'AREA_JEFE',          'UO-OTI',    1),
  ('prueba.uds.esp',      'AREA_ESPECIALISTA',  'UO-UDS',    0),
  ('prueba.uds.coord',    'AREA_COORDINADOR',   'UO-UDS',    0),
  ('prueba.uds.jefe',     'AREA_JEFE',          'UO-UDS',    1),
  ('prueba.us.esp',       'AREA_ESPECIALISTA',  'UO-US',     0),
  ('prueba.us.coord',     'AREA_COORDINADOR',   'UO-US',     0),
  ('prueba.us.jefe',      'AREA_JEFE',          'UO-US',     1),
  ('prueba.orh.esp',      'AREA_ESPECIALISTA',  'UO-ORH',    0),
  ('prueba.orh.coord',    'AREA_COORDINADOR',   'UO-ORH',    0),
  ('prueba.orh.jefe',     'AREA_JEFE',          'UO-ORH',    1);

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

/*
  Retira las asignaciones de prueba que ya no estan en la lista. Es lo que quita
  ABAST_JEFE de 'prueba.abastecim', que era la razon de que en la pantalla de
  ingreso local aparecieran dos perfiles de Abastecimiento y no tres: la misma
  cuenta ocupaba dos, y el especialista no existia.

  Solo toca cuentas 'prueba.%': las cuentas reales no las administra esta
  semilla.
*/
DELETE d
  FROM sigcm.UsuarioRol AS d
  JOIN sigcm.Usuario AS u ON u.IdUsuario = d.IdUsuario
 WHERE u.Cuenta LIKE 'prueba.%'
   AND NOT EXISTS (SELECT 1
                     FROM @Asignacion AS a
                     JOIN sigcm.Unidad AS n ON n.Codigo = a.CodigoUnidad
                    WHERE a.Cuenta = u.Cuenta
                      AND a.CodigoRol = d.CodigoRol
                      AND n.IdUnidad = d.IdUnidad);
GO

DECLARE @msg varchar(300) =
    'S900 aplicada: '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Unidad     WHERE Codigo LIKE 'UO-%'))      + ' unidades, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Usuario    WHERE Cuenta LIKE 'prueba.%'))  + ' usuarios, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.UsuarioRol)) + ' asignaciones de rol.';
PRINT @msg;
GO

