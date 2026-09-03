/*
===============================================================================
  SIGCM - Semilla S005 : Mapeo de perfiles del SSO y arbol de derivacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Puebla las dos tablas de mantenimiento que crea V016. Es CONFIGURACION, no
  dato capturado: se despliega con la serie y se edita cuando el SSO agrega un
  perfil o cuando el negocio cambia un escalon del flujo.

  Idempotente: actualiza lo que existe y agrega lo que falta. No borra, porque
  una fila agregada a mano en desarrollo puede ser justamente lo que se esta
  probando.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Traduccion cod_perfil del SSO -> CodigoRol del SIGCM                     */
/* -------------------------------------------------------------------------- */

/*
  Los 15 perfiles que el SSO declara hoy para el sistema 73 (SGCM-I), medidos
  contra login.vw_login_usuario_perfil_sistema_sgcm el 2026-08-27.

  Los ocho primeros son los que el flujo CMN necesita para funcionar completo.
  Los seis siguientes son roles que existen en el SIGCM pero todavia no
  participan del flujo vigente; se mapean igual, para que esas personas entren y
  vean su menu en vez de rebotar en la puerta.

  PE019 EXTERNO NO SE MAPEA, a proposito. Es un consultor externo en el centro de
  costo de OTI: darle un rol del flujo por descarte seria inventarle una
  autorizacion. F008 lo reporta en Descartes cada vez que sincroniza, que es
  exactamente la visibilidad que corresponde. Si el negocio decide que debe
  entrar, es una fila.

  NOTA SOBRE EL AREA USUARIA. El SSO distingue oficina de unidad -PE079 JEFE
  OFICINA y PE091 JEFE DE UNIDAD- porque asi esta su organigrama. Para el flujo
  CMN la distincion no existe: las dos son area usuaria y firman el mismo Anexo
  3. Por eso dos cod_perfil caen en el mismo CodigoRol; la tabla lo admite
  porque su clave es el codigo del SSO.
*/
DECLARE @Perfil TABLE (CodigoPerfilSso varchar(20), NombreSso varchar(150),
                       CodigoRol varchar(40), Observacion nvarchar(400));
INSERT INTO @Perfil VALUES
  /* --- Los ocho del flujo CMN --------------------------------------------- */
  ('PE091', 'JEFE DE UNIDAD',       'AREA_JEFE',          N'Area usuaria. Firma el Anexo 3 y remite a OA.'),
  ('PE079', 'JEFE OFICINA',         'AREA_JEFE',          N'Area usuaria a nivel de oficina. Mismo papel que PE091 en el flujo.'),
  ('PE092', 'ESPECIALISTA UNIDAD',  'AREA_ESPECIALISTA',  N'Area usuaria. Registra el Anexo 3 y subsana observaciones.'),
  ('PE080', 'ESPECIALISTA OFICINA', 'AREA_ESPECIALISTA',  N'Area usuaria a nivel de oficina. Mismo papel que PE092.'),
  ('PE099', 'COORDINADOR OFICINA',  'AREA_COORDINADOR',   N'Area usuaria a nivel de oficina. Completa el par PE079/PE080. Requerimiento pasa por este escalon.'),
  ('PE081', 'JEFE OA',              'OA',                 N'Oficina de Administracion. Revisa, observa o deriva a Abastecimiento.'),
  ('PE082', 'JEFE UA',              'ABAST_JEFE',         N'Abastecimiento. Ultima firma del Anexo 3 y del Anexo 4.'),
  ('PE083', 'COORDINADOR UA',       'ABAST_COORDINADOR',  N'Abastecimiento. Deriva al especialista y firma en segundo lugar.'),
  ('PE084', 'ESPECIALISTA UA',      'ABAST_ESPECIALISTA', N'Abastecimiento. Evalua el Anexo 3 y genera el Anexo 4.'),
  /* --- Roles fuera del flujo CMN vigente ---------------------------------- */
  ('PE085', 'JEFE OP',              'OPP',                N'Planeamiento y Presupuesto. Sin participacion en el flujo CMN.'),
  ('PE086', 'ESPECIALISTA OP',      'OPP',                N'Planeamiento y Presupuesto. Sin participacion en el flujo CMN.'),
  ('PE087', 'JEFE UC',              'CONTABILIDAD',       N'Control previo y devengado. Modulo de Pago.'),
  ('PE088', 'ESPECIALISTA UC',      'CONTABILIDAD',       N'Control previo y devengado. Modulo de Pago.'),
  ('PE089', 'JEFE UT',              'TESORERIA',          N'Giro y pago. Modulo de Pago.'),
  ('PE090', 'ESPECIALISTA UT',      'TESORERIA',          N'Giro y pago. Modulo de Pago.');

UPDATE d
   SET d.NombreSso = s.NombreSso, d.CodigoRol = s.CodigoRol, d.Observacion = s.Observacion
  FROM sigcm.PerfilSso AS d
  JOIN @Perfil AS s ON s.CodigoPerfilSso = d.CodigoPerfilSso;

INSERT INTO sigcm.PerfilSso (CodigoPerfilSso, NombreSso, CodigoRol, Observacion)
SELECT s.CodigoPerfilSso, s.NombreSso, s.CodigoRol, s.Observacion
  FROM @Perfil AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.PerfilSso AS d
                    WHERE d.CodigoPerfilSso = s.CodigoPerfilSso);
GO

/* -------------------------------------------------------------------------- */
/* 2. Arbol de derivacion                                                     */
/* -------------------------------------------------------------------------- */

/*
  Una fila por arista. Leidas juntas dicen la regla que pidio el negocio:

  CMN
    El area usuaria NO PASA POR EL COORDINADOR. No hay que apagar nada ni poner
    una condicion: la fila AREA_JEFE -> AREA_COORDINADOR simplemente no existe
    para este modulo. El jefe deriva a su especialista y punto.
    Abastecimiento si tiene los tres escalones, y su jefe puede ir al
    coordinador o saltar directo al especialista.

  REQUERIMIENTO
    Pasa por los tres en las dos areas. La misma tabla, dos filas mas.

  EL SALTO DIRECTO ES UNA ARISTA MAS, con Orden 2. No es una excepcion en el
  codigo: es un destino valido que la pantalla ofrece despues del natural. Que
  el jefe pueda saltarse al coordinador cuando el asunto es urgente lo pidio el
  negocio y asi queda dicho como dato.

  ALCANCE MISMA_UNIDAD en todas: el arbol es interno al area. El jefe de
  Abastecimiento deriva a SU coordinador, y el jefe de una unidad usuaria a SU
  especialista. Los pases ENTRE areas -area usuaria a OA, OA a Abastecimiento-
  no son derivaciones jerarquicas y los sigue resolviendo el enrutamiento por
  rol de la maquina de estados (F004), que no cambia.
*/
DECLARE @Arista TABLE (CodigoModulo varchar(30), CodigoRolOrigen varchar(40),
                       CodigoRolDestino varchar(40), Alcance varchar(20),
                       Orden int, Descripcion nvarchar(400));
INSERT INTO @Arista VALUES
  /* --- CMN: area usuaria, sin coordinador --------------------------------- */
  ('CMN', 'AREA_JEFE',         'AREA_ESPECIALISTA',  'MISMA_UNIDAD', 1,
   N'En CMN el area usuaria no pasa por el coordinador: el jefe deriva directo al especialista.'),
  /* --- CMN: Abastecimiento, los tres escalones ---------------------------- */
  ('CMN', 'ABAST_JEFE',        'ABAST_COORDINADOR',  'MISMA_UNIDAD', 1,
   N'Camino natural: el jefe de Abastecimiento deriva a su coordinador.'),
  ('CMN', 'ABAST_JEFE',        'ABAST_ESPECIALISTA', 'MISMA_UNIDAD', 2,
   N'Salto directo: el jefe puede derivar al especialista sin pasar por el coordinador.'),
  ('CMN', 'ABAST_COORDINADOR', 'ABAST_ESPECIALISTA', 'MISMA_UNIDAD', 1,
   N'El coordinador reparte entre los especialistas de su unidad.'),
  /* --- REQUERIMIENTO: los tres escalones en las dos areas ----------------- */
  ('REQUERIMIENTO', 'AREA_JEFE',         'AREA_COORDINADOR',   'MISMA_UNIDAD', 1,
   N'En Requerimiento el area usuaria si pasa por el coordinador.'),
  ('REQUERIMIENTO', 'AREA_JEFE',         'AREA_ESPECIALISTA',  'MISMA_UNIDAD', 2,
   N'Salto directo del jefe al especialista, tambien en Requerimiento.'),
  ('REQUERIMIENTO', 'AREA_COORDINADOR',  'AREA_ESPECIALISTA',  'MISMA_UNIDAD', 1,
   N'El coordinador del area usuaria reparte entre sus especialistas.'),
  ('REQUERIMIENTO', 'ABAST_JEFE',        'ABAST_COORDINADOR',  'MISMA_UNIDAD', 1,
   N'Camino natural en Abastecimiento.'),
  ('REQUERIMIENTO', 'ABAST_JEFE',        'ABAST_ESPECIALISTA', 'MISMA_UNIDAD', 2,
   N'Salto directo en Abastecimiento.'),
  ('REQUERIMIENTO', 'ABAST_COORDINADOR', 'ABAST_ESPECIALISTA', 'MISMA_UNIDAD', 1,
   N'El coordinador reparte entre los especialistas de su unidad.');

UPDATE d
   SET d.Alcance = s.Alcance, d.Orden = s.Orden, d.Descripcion = s.Descripcion
  FROM sigcm.RolDerivacion AS d
  JOIN @Arista AS s ON s.CodigoModulo     = d.CodigoModulo
                   AND s.CodigoRolOrigen  = d.CodigoRolOrigen
                   AND s.CodigoRolDestino = d.CodigoRolDestino;

INSERT INTO sigcm.RolDerivacion
      (CodigoModulo, CodigoRolOrigen, CodigoRolDestino, Alcance, Orden, Descripcion)
SELECT s.CodigoModulo, s.CodigoRolOrigen, s.CodigoRolDestino, s.Alcance, s.Orden, s.Descripcion
  FROM @Arista AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.RolDerivacion AS d
                    WHERE d.CodigoModulo     = s.CodigoModulo
                      AND d.CodigoRolOrigen  = s.CodigoRolOrigen
                      AND d.CodigoRolDestino = s.CodigoRolDestino);
GO

/* -------------------------------------------------------------------------- */
/* 3. Curaduria de las unidades que sincroniza el SSO                         */
/* -------------------------------------------------------------------------- */

/*
  Las areas que TRAMITAN el CMN en vez de originarlo. F008 da de alta cada
  unidad con EsAreaUsuaria = 1 salvo que su centro de costo figure aqui.

  ES UNA TABLA Y NO UN UPDATE DE ESTA SEMILLA, y la diferencia no es de estilo:
  cuando S005 corre, las unidades TODAVIA NO EXISTEN. Las crea la primera
  sincronizacion con el SSO, que ocurre despues. Un UPDATE aqui no encontraria
  ninguna fila que corregir y Abastecimiento quedaria marcado como area usuaria
  -que es exactamente lo que paso la primera vez que se probo esto-.

  Siendo tabla, la regla se aplica cuando la unidad nace, en el orden que sea.
*/
DECLARE @Tramitadora TABLE (CentroCosto varchar(15), Motivo nvarchar(300));
INSERT INTO @Tramitadora VALUES
  ('01.07.03.01', N'Unidad de Abastecimiento: tramita el CMN, no lo origina.'),
  ('01.07.03.04', N'Oficina de Administracion: revisa y deriva.');

UPDATE d SET d.Motivo = s.Motivo, d.Activo = 1
  FROM sigcm.UnidadTramitadora AS d
  JOIN @Tramitadora AS s ON s.CentroCosto = d.CentroCosto;

INSERT INTO sigcm.UnidadTramitadora (CentroCosto, Motivo)
SELECT s.CentroCosto, s.Motivo
  FROM @Tramitadora AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.UnidadTramitadora AS d
                    WHERE d.CentroCosto = s.CentroCosto);

/* Y se aplica tambien a lo que ya exista, para que una base instalada antes de
   este script no se quede con la marca equivocada. */
UPDATE n
   SET n.EsAreaUsuaria = 0
  FROM sigcm.Unidad AS n
  JOIN sigcm.UnidadTramitadora AS t ON t.CentroCosto = n.CentroCostoSiga AND t.Activo = 1
 WHERE n.EsAreaUsuaria <> 0;
GO

DECLARE @msg varchar(300) =
    'S005 aplicada: '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.PerfilSso))    + ' perfiles del SSO mapeados, '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.RolDerivacion))+ ' aristas de derivacion.';
PRINT @msg;
GO
