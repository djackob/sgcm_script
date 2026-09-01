/*
===============================================================================
  SIGCM - Semilla S006 : El salto directo del jefe al especialista, en CMN
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  QUE PIDIO EL NEGOCIO
  --------------------
  "El jefe puede derivar el expediente a un coordinador o directamente a un
  especialista."

  Hasta ahora el flujo CMN no lo permitia: desde CMN_EN_ABAST_JEFE la unica
  salida era CMN_ABAST_JEFE_DERIVAR, que lleva al coordinador y a ningun otro
  sitio. Lo mismo en la ruta de observacion del area usuaria, donde
  CMN_OBS_AU_JEFE_DERIVAR obliga a pasar por el coordinador antes de que el
  especialista pueda subsanar.

  ESTO SON DOS FILAS, NO CODIGO
  Los estados destino YA EXISTEN -CMN_EN_ABAST_ESP y CMN_OBSERVADO- y a ellos ya
  se llega por el camino largo. Agregar el corto es declarar dos transiciones
  mas, que es el corolario que gobierna el proyecto: agregar un escalon a un
  flujo es agregar filas (CONTEXTO.md, seccion 3).

  EL CAMINO LARGO NO SE RETIRA
  Las dos rutas quedan disponibles y el jefe elige. Es la lectura literal de lo
  que pidio el negocio -"a un coordinador O directamente a un especialista"-, y
  ademas retirar el escalon del coordinador seria una decision distinta, que
  afecta a expedientes en curso y que nadie pidio todavia.

  En sigcm.RolDerivacion (S005) el salto ya figuraba como arista con Orden 2. Sin
  estas transiciones era un destino que el arbol declaraba y la maquina de
  estados no podia cumplir: la pantalla no lo ofrecia porque
  paListarDestinatarioDerivacion filtra por el rol del estado destino, asi que no
  hubo inconsistencia visible, solo una capacidad que faltaba.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Las dos transiciones                                                    */
/* -------------------------------------------------------------------------- */

DECLARE @Tr TABLE (
    CodigoTransicion     varchar(70),
    CodigoEstadoOrigen   varchar(60),
    CodigoEstadoDestino  varchar(60),
    NombreAccion         varchar(180),
    RequiereComentario   bit,
    RequiereFirma        bit,
    DocumentoRequerido   varchar(60) NULL,
    EncolaIntegracion    bit,
    OperacionIntegracion varchar(30) NULL,
    GeneraObservacion    bit,
    RolFirmaRequerida    varchar(40) NULL
);

INSERT INTO @Tr VALUES
  /* Abastecimiento: el jefe se salta a su coordinador. */
  ('CMN_ABAST_JEFE_DERIVAR_ESP', 'CMN_EN_ABAST_JEFE', 'CMN_EN_ABAST_ESP',
   'Derivar directamente al Especialista de Abastecimiento', 0, 0, NULL, 0, NULL, 0, NULL),

  /* Area usuaria, ruta de observacion: el jefe manda a subsanar sin pasar por
     el coordinador. Es el caso que el negocio describio como "en CMN no pasa
     por el coordinador del area usuaria". */
  ('CMN_OBS_AU_JEFE_DERIVAR_ESP', 'CMN_OBS_AU_JEFE', 'CMN_OBSERVADO',
   'Derivar directamente al Especialista para subsanar', 0, 0, NULL, 0, NULL, 0, NULL);

UPDATE d
   SET d.CodigoEstadoOrigen   = s.CodigoEstadoOrigen,
       d.CodigoEstadoDestino  = s.CodigoEstadoDestino,
       d.NombreAccion         = s.NombreAccion,
       d.RequiereComentario   = s.RequiereComentario,
       d.RequiereFirma        = s.RequiereFirma,
       d.DocumentoRequerido   = s.DocumentoRequerido,
       d.EncolaIntegracion    = s.EncolaIntegracion,
       d.OperacionIntegracion = s.OperacionIntegracion,
       d.GeneraObservacion    = s.GeneraObservacion,
       d.RolFirmaRequerida    = s.RolFirmaRequerida,
       d.Activo               = 1
  FROM sigcm.Transicion AS d
  JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion
      (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
       NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
       EncolaIntegracion, OperacionIntegracion, GeneraObservacion, RolFirmaRequerida)
SELECT s.CodigoTransicion, 'CMN', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion, s.RolFirmaRequerida
  FROM @Tr AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion)
   /* Los estados destino tienen que existir. Si S001 cambiara y alguno
      desapareciera, es mejor no insertar que dejar una FK colgando. */
   AND EXISTS (SELECT 1 FROM sigcm.Estado AS e WHERE e.CodigoEstado = s.CodigoEstadoOrigen)
   AND EXISTS (SELECT 1 FROM sigcm.Estado AS e WHERE e.CodigoEstado = s.CodigoEstadoDestino);
GO

/* -------------------------------------------------------------------------- */
/* 2. Quien puede ejecutarlas                                                 */
/* -------------------------------------------------------------------------- */

/*
  Solo el jefe. El salto es una prerrogativa suya -decidir que este expediente no
  necesita el escalon intermedio-, no una via alternativa abierta a cualquiera.

  Ojo con S001: su limpieza final borra de sigcm.TransicionRol las filas
  'CMN[_]%' que no esten en SU semilla. Por eso este script se aplica DESPUES de
  S001 -el instalador ordena por nombre y S006 > S001- y por eso hay que
  reaplicarlo si alguna vez se corre S001 solo.
*/
DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('CMN_ABAST_JEFE_DERIVAR_ESP',  'ABAST_JEFE'),
  ('CMN_OBS_AU_JEFE_DERIVAR_ESP', 'AREA_JEFE');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE EXISTS (SELECT 1 FROM sigcm.Transicion AS t WHERE t.CodigoTransicion = s.CodigoTransicion)
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

DECLARE @msg varchar(300) =
    'S006 aplicada: '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.Transicion
                           WHERE CodigoTransicion LIKE 'CMN[_]%[_]DERIVAR[_]ESP'))
  + ' transiciones de derivacion directa vigentes.';
PRINT @msg;
GO
