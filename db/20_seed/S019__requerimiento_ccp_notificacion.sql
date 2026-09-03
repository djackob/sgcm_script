/*
===============================================================================
  SIGCM - S019 : Las dos transiciones que cierran el flujo de requerimiento
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  REQ_CCP_SOLICITADO y REQ_OS_EMITIDA eran estados sin salida: S004, S006 y S007
  actualizaban REQ_REGISTRAR_CCP y le repartian roles, y F008 ejecutaba
  REQ_NOTIFICAR_OS en su linea 1024, pero ninguna semilla creaba las dos filas
  de sigcm.Transicion. El efecto era que paRegistrarCcp grababa la CCP sin mover
  el expediente, y notificar la orden reventaba con CONFLICTO_TRANSICION.

  Ninguna de las dos encola hacia SIGA: el cuadro lo encola REQ_GENERAR_CUADRO y
  la orden REQ_EMITIR_OS. La notificacion es el correo al locador, que arma
  paPrepararNotificacionOrden y envia el controlador.

  Va despues de S006 y S007 -que borran roles de REQ_REGISTRAR_CCP- porque el
  instalador ordena por nombre: aqui se deja el reparto definitivo.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
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
  ('REQ_REGISTRAR_CCP', 'REQ_CCP_SOLICITADO', 'REQ_CCP_CARGADA',
   'Registrar CCP y generar orden de servicio', 0, 0, NULL, 0, NULL, 0),

  ('REQ_NOTIFICAR_OS', 'REQ_OS_EMITIDA', 'REQ_NOTIFICADO',
   'Notificar orden de servicio', 0, 0, NULL, 0, NULL, 0);

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
SELECT s.CodigoTransicion, 'REQUERIMIENTO', s.CodigoEstadoOrigen, s.CodigoEstadoDestino,
       s.NombreAccion, s.RequiereComentario, s.RequiereFirma, s.DocumentoRequerido,
       s.EncolaIntegracion, s.OperacionIntegracion, s.GeneraObservacion
  FROM @Tr AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

/* La CCP la carga la DEC (S007 saco a OPP); la notificacion la hace quien emitio
   la orden. */
DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('REQ_REGISTRAR_CCP', 'ABAST_ESPECIALISTA'),
  ('REQ_REGISTRAR_CCP', 'ABAST_COORDINADOR'),
  ('REQ_REGISTRAR_CCP', 'ABAST_JEFE'),
  ('REQ_NOTIFICAR_OS',  'ABAST_ESPECIALISTA'),
  ('REQ_NOTIFICAR_OS',  'ABAST_COORDINADOR');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion
                      AND d.CodigoRol = s.CodigoRol);
GO

PRINT 'S019 aplicada: REQ_REGISTRAR_CCP y REQ_NOTIFICAR_OS creadas con sus roles.';
GO
