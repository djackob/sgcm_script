/*
===============================================================================
  SIGCM - S005 : Jerarquia de filtros de idoneidad y solicitud CCP
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El especialista completa los filtros y deriva al coordinador; el coordinador
  al jefe. Solo el jefe de Abastecimiento envia el expediente a OPP (entre jefes).
  OPP y Administracion no tienen jerarquia interna modelada: el rol OPP/OA actua
  como contraparte de jefe en los tramites cruzados.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Estado TABLE (CodigoEstado varchar(60), Nombre varchar(150), Orden int,
                       EsInicial bit, EsFinal bit, RolResponsable varchar(40) NULL);
INSERT INTO @Estado VALUES
  ('REQ_FILTROS_COORD', 'Filtros de idoneidad - revision del coordinador', 91, 0, 0, 'ABAST_COORDINADOR'),
  ('REQ_FILTROS_JEFE',  'Filtros de idoneidad - aprobacion del jefe',     92, 0, 0, 'ABAST_JEFE');

UPDATE d
   SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'REQUERIMIENTO', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);
GO

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
  ('REQ_ENVIAR_FILTROS_COORD', 'REQ_FILTROS', 'REQ_FILTROS_COORD',
   'Enviar filtros al coordinador', 0, 0, NULL, 0, NULL, 0),

  ('REQ_ENVIAR_FILTROS_JEFE', 'REQ_FILTROS_COORD', 'REQ_FILTROS_JEFE',
   'Enviar filtros al jefe', 0, 0, NULL, 0, NULL, 0),

  ('REQ_DEVOLVER_FILTROS_COORD', 'REQ_FILTROS_COORD', 'REQ_FILTROS',
   'Devolver al especialista', 1, 0, NULL, 0, NULL, 0),

  ('REQ_DEVOLVER_FILTROS_JEFE', 'REQ_FILTROS_JEFE', 'REQ_FILTROS_COORD',
   'Devolver al coordinador', 1, 0, NULL, 0, NULL, 0),

  ('REQ_CONFIRMAR_FILTROS', 'REQ_FILTROS_JEFE', 'REQ_CCP_SOLICITADO',
   'Confirmar idoneidad y solicitar CCP', 0, 0, NULL, 0, NULL, 0);

UPDATE d
   SET d.CodigoEstadoOrigen = s.CodigoEstadoOrigen,
       d.CodigoEstadoDestino = s.CodigoEstadoDestino,
       d.NombreAccion = s.NombreAccion,
       d.RequiereComentario = s.RequiereComentario,
       d.RequiereFirma = s.RequiereFirma,
       d.DocumentoRequerido = s.DocumentoRequerido,
       d.EncolaIntegracion = s.EncolaIntegracion,
       d.OperacionIntegracion = s.OperacionIntegracion,
       d.GeneraObservacion = s.GeneraObservacion
  FROM sigcm.Transicion AS d JOIN @Tr AS s ON s.CodigoTransicion = d.CodigoTransicion;

INSERT INTO sigcm.Transicion
      (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
       NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
       EncolaIntegracion, OperacionIntegracion, GeneraObservacion)
SELECT s.CodigoTransicion, 'REQUERIMIENTO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_CONFIRMAR_FILTROS'
   AND CodigoRol IN ('ABAST_ESPECIALISTA', 'ABAST_COORDINADOR');
GO

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('REQ_ENVIAR_FILTROS_COORD', 'ABAST_ESPECIALISTA'),
  ('REQ_ENVIAR_FILTROS_JEFE', 'ABAST_COORDINADOR'),
  ('REQ_DEVOLVER_FILTROS_COORD', 'ABAST_COORDINADOR'),
  ('REQ_DEVOLVER_FILTROS_JEFE', 'ABAST_JEFE'),
  ('REQ_CONFIRMAR_FILTROS', 'ABAST_JEFE');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

PRINT 'S005 aplicada: jerarquia de filtros especialista -> coordinador -> jefe -> OPP.';
GO
