/*
===============================================================================
  SIGCM - S016 : Indagacion de mercado (locacion, invitacion uno a uno)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Tras la No Objecion / conformidad DEC el expediente de locacion entra a
  REQ_INDAGACION_MERCADO. Desde ahi el locador tiene 3 dias habiles para
  devolver Anexo 6 y Anexo 7; recien entonces se inician los filtros.
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
  ('REQ_INDAGACION_MERCADO', 'Indagacion de mercado (invitacion al locador)', 85, 0, 0, 'ABAST_ESPECIALISTA');

UPDATE d
   SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.EsInicial = s.EsInicial,
       d.EsFinal = s.EsFinal, d.RolResponsable = s.RolResponsable
  FROM sigcm.Estado AS d JOIN @Estado AS s ON s.CodigoEstado = d.CodigoEstado;

INSERT INTO sigcm.Estado (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
SELECT s.CodigoEstado, 'REQUERIMIENTO', s.Nombre, s.Orden, s.EsInicial, s.EsFinal, s.RolResponsable
  FROM @Estado AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Estado AS d WHERE d.CodigoEstado = s.CodigoEstado);

UPDATE sigcm.Estado
   SET Nombre = 'Filtros de idoneidad'
 WHERE CodigoEstado = 'REQ_FILTROS'
   AND Nombre LIKE N'%indagacion%';
GO

DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200),
                        NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('REQ_PAQUETE_INTEGRIDAD', 'Instructivo anticorrupcion y Politica de Integridad ANIN', 'INT', 0);

UPDATE d SET d.Nombre = s.Nombre, d.NumeracionVisible = s.NumeracionVisible,
             d.AdmiteConsolidado = s.AdmiteConsolidado
  FROM sigcm.TipoDocumento AS d
  JOIN @TipoDoc AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento;

INSERT INTO sigcm.TipoDocumento (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
SELECT s.CodigoTipoDocumento, 'REQUERIMIENTO', s.Nombre, s.NumeracionVisible, s.AdmiteConsolidado
  FROM @TipoDoc AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento AS d
                    WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento);
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
  ('REQ_INICIAR_INDAGACION', 'REQ_CONFORME', 'REQ_INDAGACION_MERCADO',
   'Iniciar indagacion de mercado e invitar al locador', 0, 0, NULL, 0, NULL, 0),

  ('REQ_INICIAR_FILTROS', 'REQ_INDAGACION_MERCADO', 'REQ_FILTROS',
   'Iniciar filtros de idoneidad', 0, 0, 'REQ_COTIZACION_ANEXO6', 0, NULL, 0);

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
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion AS d WHERE d.CodigoTransicion = s.CodigoTransicion);
GO

DECLARE @TrRol TABLE (CodigoTransicion varchar(70), CodigoRol varchar(40));
INSERT INTO @TrRol VALUES
  ('REQ_INICIAR_INDAGACION','ABAST_ESPECIALISTA'),
  ('REQ_INICIAR_INDAGACION','ABAST_COORDINADOR'),
  ('REQ_INICIAR_FILTROS','ABAST_ESPECIALISTA'),
  ('REQ_INICIAR_FILTROS','ABAST_COORDINADOR');

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM @TrRol AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion AND d.CodigoRol = s.CodigoRol);
GO

DECLARE @Regla TABLE (
    CodigoRegla        varchar(60),
    Nombre             varchar(200),
    CodigoEstadoInicio varchar(60),
    Dias               int,
    TipoDia            varchar(10),
    Ampliable          bit,
    BaseNormativa      varchar(200)
);
INSERT INTO @Regla VALUES
  ('REQ_RESPUESTA_LOCADOR',
   'Respuesta del locador: Anexo 6 y Anexo 7 firmados',
   'REQ_INDAGACION_MERCADO', 3, 'HABIL', 0,
   'ERF locacion <= 8 UIT - 3 dias habiles');

UPDATE d
   SET d.Nombre = s.Nombre, d.CodigoEstadoInicio = s.CodigoEstadoInicio, d.Dias = s.Dias,
       d.TipoDia = s.TipoDia, d.Ampliable = s.Ampliable, d.BaseNormativa = s.BaseNormativa,
       d.Activo = 1
  FROM sigcm.PlazoRegla AS d JOIN @Regla AS s ON s.CodigoRegla = d.CodigoRegla;

INSERT INTO sigcm.PlazoRegla
      (CodigoRegla, CodigoModulo, Nombre, CodigoEstadoInicio, Dias, TipoDia,
       Ampliable, BaseNormativa, Activo)
SELECT s.CodigoRegla, 'REQUERIMIENTO', s.Nombre, s.CodigoEstadoInicio, s.Dias, s.TipoDia,
       s.Ampliable, s.BaseNormativa, 1
  FROM @Regla AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.PlazoRegla AS d WHERE d.CodigoRegla = s.CodigoRegla);
GO

PRINT 'S016 aplicada: indagacion de mercado (invitacion uno a uno).';
GO
