/*
===============================================================================
  SIGCM - S049 : Informe tecnico / visto bueno previo a la conformidad
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Si el Anexo 3 (8.1) declaro perfiles, el entregable presentado no entra
  directo al especialista del area que emite la conformidad. Pasa primero por
  esos perfiles, en el orden grabado. El ultimo otorga y deja el expediente
  en PAG_ENTREGABLE_PRESENTADO, en el area usuaria de origen.

  PAG_PRESENTAR_RUTA no se ofrece en bandeja: lo dispara
  pago.paPresentarEntregable cuando la ruta tiene pasos. El proveedor sigue
  viendo "Presentar entregable y RHE".

  El rol responsable del estado PAG_PEND_VISTO_BUENO queda nulo: cada paso
  trae su propio perfil. Quien puede pulsar el boton lo resuelve la bandeja
  contra pago.RutaInformePrevio, no contra Estado.RolResponsable.

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
  ('PAG_PEND_VISTO_BUENO', 'Informe tecnico / visto bueno previo', 15, 0, 0, NULL);

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
  ('PAG_PRESENTAR_RUTA', 'PAG_PENDIENTE', 'PAG_PEND_VISTO_BUENO',
   'Presentar entregable y RHE', 0, 0, NULL, 0, NULL, 0),

  ('PAG_OTORGAR_VB_SIGUIENTE', 'PAG_PEND_VISTO_BUENO', 'PAG_PEND_VISTO_BUENO',
   'Otorgar informe tecnico / visto bueno', 0, 0, NULL, 0, NULL, 0),

  ('PAG_OTORGAR_VB_AU', 'PAG_PEND_VISTO_BUENO', 'PAG_ENTREGABLE_PRESENTADO',
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
SELECT 'PAG_PRESENTAR_RUTA', 'PROVEEDOR'
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol
                    WHERE CodigoTransicion = 'PAG_PRESENTAR_RUTA' AND CodigoRol = 'PROVEEDOR');

/* Cualquier perfil institucional puede ser un paso del 8.1. La bandeja solo
   muestra el boton a la unidad y el perfil del paso pendiente. */
INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT t.CodigoTransicion, r.CodigoRol
  FROM (VALUES ('PAG_OTORGAR_VB_SIGUIENTE'), ('PAG_OTORGAR_VB_AU')) AS t(CodigoTransicion)
  CROSS JOIN sigcm.Rol AS r
 WHERE r.Activo = 1
   AND r.EsTecnico = 0
   AND r.CodigoRol NOT IN ('PROVEEDOR', 'ADMIN_SISTEMA')
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
   AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS tr
                WHERE tr.CodigoRol = r.CodigoRol
                  AND tr.CodigoTransicion IN ('PAG_OTORGAR_VB_SIGUIENTE', 'PAG_OTORGAR_VB_AU'))
   AND NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS d
                    WHERE d.CodigoRol = r.CodigoRol AND d.CodigoModulo = 'PAGO');

UPDATE sigcm.RolModulo
   SET Activo = 1
 WHERE CodigoModulo = 'PAGO'
   AND CodigoRol IN (
        SELECT tr.CodigoRol FROM sigcm.TransicionRol AS tr
         WHERE tr.CodigoTransicion IN ('PAG_OTORGAR_VB_SIGUIENTE', 'PAG_OTORGAR_VB_AU'));
GO
