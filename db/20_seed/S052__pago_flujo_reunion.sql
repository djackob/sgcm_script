/*
===============================================================================
  SIGCM - S052 : Flujo de pagos segun la reunion del 27-09-2026
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  1. RECEPCION EN EL AREA USUARIA SIN AUTODISTRIBUCION
     El entregable presentado (o con el ultimo visto bueno otorgado) llega a
     PAG_RECIBIDO_AU, a cargo del Jefe o la Secretaria del area. Ellos lo
     asignan a un especialista con PAG_ASIGNAR_ESPECIALISTA, que exige
     IdResponsableDestino (validado contra sigcm.RolDerivacion, modulo PAGO).

  2. LA OBSERVACION DEL AREA USUARIA PASA POR ABASTECIMIENTO
     PAG_OBSERVAR_AU ya no va al proveedor: deja el expediente en
     PAG_OBS_AU_ABAST, a cargo del especialista de Abastecimiento, que
     notifica formalmente al proveedor con PAG_NOTIFICAR_OBS_PROVEEDOR. El
     plazo de subsanacion corre desde esa notificacion.

  3. Codigo del expediente de pago: (nro.pago-OS/OC)_(nro O/S u O/C)_(nro
     entregable). Se recodifican los expedientes ya abiertos.

  4. Vencimientos del cronograma que caen en dia inhabil se trasladan al
     siguiente dia habil (solo los que siguen pendientes de presentacion).

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Estados                                                                 */
/* -------------------------------------------------------------------------- */

DECLARE @Estado TABLE (CodigoEstado varchar(60), Nombre varchar(150), Orden int,
                       EsInicial bit, EsFinal bit, RolResponsable varchar(40) NULL);
INSERT INTO @Estado VALUES
  ('PAG_RECIBIDO_AU',  'Recibido en el Area usuaria - por asignar especialista', 17, 0, 0, 'AREA_JEFE'),
  ('PAG_OBS_AU_ABAST', 'Observado por el Area usuaria - Abastecimiento notifica al proveedor', 22, 0, 0, 'ABAST_ESPECIALISTA');

UPDATE d
   SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable, d.Activo = 1
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'PAGO', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);

UPDATE sigcm.Estado
   SET Nombre = 'Observado - notificado al proveedor para subsanar'
 WHERE CodigoEstado = 'PAG_OBSERVADO_AU';
GO

/* -------------------------------------------------------------------------- */
/* 2. Transiciones                                                            */
/* -------------------------------------------------------------------------- */

DECLARE @Tr TABLE (
    CodigoTransicion     varchar(70),
    CodigoEstadoOrigen   varchar(60),
    CodigoEstadoDestino  varchar(60),
    NombreAccion         varchar(150),
    RequiereComentario   bit,
    RequiereFirma        bit,
    DocumentoRequerido   varchar(60) NULL,
    EncolaIntegracion    bit,
    OperacionIntegracion varchar(30) NULL,
    GeneraObservacion    bit
);
INSERT INTO @Tr VALUES
  ('PAG_PRESENTAR', 'PAG_PENDIENTE', 'PAG_RECIBIDO_AU',
   'Presentar entregable y RHE', 0, 0, NULL, 0, NULL, 0),

  ('PAG_ASIGNAR_ESPECIALISTA', 'PAG_RECIBIDO_AU', 'PAG_ENTREGABLE_PRESENTADO',
   'Asignar a especialista', 0, 0, NULL, 0, NULL, 0),

  ('PAG_OBSERVAR_AU', 'PAG_ENTREGABLE_PRESENTADO', 'PAG_OBS_AU_ABAST',
   'Observar y enviar a Abastecimiento', 1, 0, NULL, 0, NULL, 0),

  ('PAG_NOTIFICAR_OBS_PROVEEDOR', 'PAG_OBS_AU_ABAST', 'PAG_OBSERVADO_AU',
   'Notificar observacion al proveedor', 0, 0, NULL, 0, NULL, 0);

IF EXISTS (SELECT 1 FROM sigcm.Transicion WHERE CodigoTransicion = 'PAG_OTORGAR_VB_AU')
    INSERT INTO @Tr VALUES
      ('PAG_OTORGAR_VB_AU', 'PAG_PEND_VISTO_BUENO', 'PAG_RECIBIDO_AU',
       'Otorgar informe tecnico / visto bueno', 0, 0, NULL, 0, NULL, 0);

UPDATE d
   SET d.CodigoEstadoOrigen = s.CodigoEstadoOrigen,
       d.CodigoEstadoDestino = s.CodigoEstadoDestino,
       d.NombreAccion = s.NombreAccion,
       d.RequiereComentario = s.RequiereComentario,
       d.RequiereFirma = s.RequiereFirma,
       d.DocumentoRequerido = s.DocumentoRequerido,
       d.EncolaIntegracion = s.EncolaIntegracion,
       d.OperacionIntegracion = s.OperacionIntegracion,
       d.GeneraObservacion = s.GeneraObservacion,
       d.Activo = 1
  FROM sigcm.Transicion AS d JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion
      (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
       NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
       EncolaIntegracion, OperacionIntegracion, GeneraObservacion)
SELECT s.CodigoTransicion, 'PAGO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT v.CodigoTransicion, v.CodigoRol
  FROM (VALUES ('PAG_ASIGNAR_ESPECIALISTA',    'AREA_JEFE'),
               ('PAG_ASIGNAR_ESPECIALISTA',    'AREA_SECRETARIA'),
               ('PAG_NOTIFICAR_OBS_PROVEEDOR', 'ABAST_ESPECIALISTA'),
               ('PAG_NOTIFICAR_OBS_PROVEEDOR', 'ABAST_COORDINADOR')) AS v(CodigoTransicion, CodigoRol)
 WHERE EXISTS (SELECT 1 FROM sigcm.Rol AS r WHERE r.CodigoRol = v.CodigoRol)
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = v.CodigoTransicion AND d.CodigoRol = v.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 3. Derivacion: jefe y secretaria del area asignan al especialista          */
/* -------------------------------------------------------------------------- */

DECLARE @Arista TABLE (CodigoModulo varchar(30), CodigoRolOrigen varchar(40),
                       CodigoRolDestino varchar(40), Alcance varchar(20), Orden int,
                       Descripcion nvarchar(300));
INSERT INTO @Arista VALUES
  ('PAGO', 'AREA_JEFE',       'AREA_ESPECIALISTA', 'MISMA_UNIDAD', 1,
   N'El jefe del area asigna el entregable recibido a un especialista.'),
  ('PAGO', 'AREA_SECRETARIA', 'AREA_ESPECIALISTA', 'MISMA_UNIDAD', 1,
   N'La secretaria del area asigna el entregable recibido a un especialista.');

UPDATE d
   SET d.Alcance = s.Alcance, d.Orden = s.Orden, d.Descripcion = s.Descripcion, d.Activo = 1
  FROM sigcm.RolDerivacion AS d
  JOIN @Arista AS s ON s.CodigoModulo = d.CodigoModulo
                   AND s.CodigoRolOrigen = d.CodigoRolOrigen
                   AND s.CodigoRolDestino = d.CodigoRolDestino;

INSERT INTO sigcm.RolDerivacion
      (CodigoModulo, CodigoRolOrigen, CodigoRolDestino, Alcance, Orden, Descripcion, Activo)
SELECT s.CodigoModulo, s.CodigoRolOrigen, s.CodigoRolDestino, s.Alcance, s.Orden, s.Descripcion, 1
  FROM @Arista AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.RolDerivacion AS d
                    WHERE d.CodigoModulo = s.CodigoModulo
                      AND d.CodigoRolOrigen = s.CodigoRolOrigen
                      AND d.CodigoRolDestino = s.CodigoRolDestino);
GO

/* -------------------------------------------------------------------------- */
/* 4. Tipo de orden y recodificacion de expedientes ya abiertos               */
/* -------------------------------------------------------------------------- */

UPDATE p
   SET p.TipoOrden = CASE WHEN r.CodigoTipoContratacion LIKE '%BIEN%' THEN 'OC' ELSE 'OS' END
  FROM pago.ExpedientePago AS p
  JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = p.IdRequerimiento;

UPDATE e
   SET e.Codigo = pago.fnCodigoExpedientePago(e.Codigo, p.TipoOrden, p.NumeroOrdenSiga, p.NumeroEntregable)
  FROM sigcm.Expediente AS e
  JOIN pago.ExpedientePago AS p ON p.IdExpediente = e.IdExpediente
 WHERE e.Codigo LIKE 'PAG-%'
   AND NULLIF(p.NumeroOrdenSiga, '') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sigcm.Expediente AS x
                    WHERE x.Codigo = pago.fnCodigoExpedientePago(e.Codigo, p.TipoOrden, p.NumeroOrdenSiga, p.NumeroEntregable));
GO

/* -------------------------------------------------------------------------- */
/* 5. Vencimientos pendientes en dia inhabil -> siguiente dia habil           */
/* -------------------------------------------------------------------------- */

UPDATE p
   SET p.FechaLimiteCronograma = sigcm.fnSiguienteDiaHabil(p.FechaLimiteCronograma)
  FROM pago.ExpedientePago AS p
  JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
 WHERE p.Activo = 1
   AND p.FechaLimiteCronograma IS NOT NULL
   AND e.CodigoEstado = 'PAG_PENDIENTE'
   AND sigcm.fnEsDiaHabil(p.FechaLimiteCronograma) = 0;
GO

PRINT 'S052 aplicada: recepcion AU con asignacion, observacion via Abastecimiento, codigo O/S y dias habiles.';
GO
