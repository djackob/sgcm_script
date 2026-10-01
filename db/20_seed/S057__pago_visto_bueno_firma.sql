/*
===============================================================================
  SIGCM - S057 : Visto bueno previo a la firma del Acta (Anexo 11)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Si el Anexo 3 (8.1) declaro perfiles, el jefe del area usuaria no firma el
  Acta ni envia a Administracion hasta que cada persona derivada otorgo su
  conformidad, una por una (pago.VistoBuenoFirma, V043).

    PAG_DERIVAR_VB_FIRMA   Jefe o Secretaria AU eligen a la persona de cada
                           fila y derivan. Lo ejecuta pago.paDerivarVistoBuenoFirma.
    PAG_OTORGAR_VB_FIRMA   El ultimo paso devuelve el acta al jefe. Los pasos
                           intermedios solo cambian de unidad y persona
                           (pago.paResponderVistoBuenoFirma).
    PAG_OBSERVAR_VB_FIRMA  Cualquier paso devuelve el acta al jefe con
                           observaciones y cierra la ronda.

  El rol responsable del estado queda nulo: el paso pendiente trae su persona.
  Quien ve el boton lo resuelve pago.fnAccionVistoBuenoFirma.

  Idempotente.
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
  ('PAG_VB_PREVIO_FIRMA', 'Visto bueno previo a la firma del Acta', 31, 0, 0, NULL);

UPDATE d
   SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable, d.Activo = 1
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'PAGO', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
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
  ('PAG_DERIVAR_VB_FIRMA', 'PAG_CONFORMIDAD_PEND_FIRMA', 'PAG_VB_PREVIO_FIRMA',
   'Derivar para visto bueno previo a la firma', 0, 0, NULL, 0, NULL, 0),
  ('PAG_OTORGAR_VB_FIRMA', 'PAG_VB_PREVIO_FIRMA', 'PAG_CONFORMIDAD_PEND_FIRMA',
   'Otorgar conformidad / visto bueno', 0, 0, NULL, 0, NULL, 0),
  ('PAG_OBSERVAR_VB_FIRMA', 'PAG_VB_PREVIO_FIRMA', 'PAG_CONFORMIDAD_PEND_FIRMA',
   'Devolver al Jefe del area usuaria con observaciones', 1, 0, NULL, 0, NULL, 0);

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
  FROM (VALUES ('PAG_DERIVAR_VB_FIRMA', 'AREA_JEFE'),
               ('PAG_DERIVAR_VB_FIRMA', 'AREA_SECRETARIA')) AS v(CodigoTransicion, CodigoRol)
 WHERE EXISTS (SELECT 1 FROM sigcm.Rol AS r WHERE r.CodigoRol = v.CodigoRol)
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = v.CodigoTransicion AND d.CodigoRol = v.CodigoRol);

/* Responde la persona elegida, con el perfil con el que haya ingresado. */
INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT t.CodigoTransicion, r.CodigoRol
  FROM (VALUES ('PAG_OTORGAR_VB_FIRMA'), ('PAG_OBSERVAR_VB_FIRMA')) AS t(CodigoTransicion)
  CROSS JOIN sigcm.Rol AS r
 WHERE r.Activo = 1
   AND (r.EsTecnico = 0 OR r.CodigoRol = 'ADMIN_SISTEMA')
   AND r.CodigoRol <> 'PROVEEDOR'
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = t.CodigoTransicion
                      AND d.CodigoRol = r.CodigoRol);
GO

INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT r.CodigoRol, 'PAGO'
  FROM sigcm.Rol AS r
 WHERE r.Activo = 1
   AND r.EsTecnico = 0
   AND r.CodigoRol NOT IN ('PROVEEDOR', 'ADMIN_SISTEMA')
   AND NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS d
                    WHERE d.CodigoRol = r.CodigoRol AND d.CodigoModulo = 'PAGO');

UPDATE sigcm.RolModulo
   SET Activo = 1
 WHERE CodigoModulo = 'PAGO'
   AND CodigoRol IN (SELECT tr.CodigoRol FROM sigcm.TransicionRol AS tr
                      WHERE tr.CodigoTransicion = 'PAG_OTORGAR_VB_FIRMA');
GO

PRINT 'S057 aplicada: visto bueno previo a la firma del Acta (Anexo 11).';
GO
