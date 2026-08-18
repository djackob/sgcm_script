/*
===============================================================================
  SIGCM - Semilla S002 : Plazos de la Directiva
  Motor  : SQL Server 2016 (compat 130) o superior
  Ambito : [DBSIGCM]

  Port de SIGCM/db/20_seed/S002__plazos_directiva.sql. Idempotente.

  Los plazos son DATOS. Una modificacion normativa debe resolverse con un
  UPDATE, no con un despliegue.

  Base: Directiva N.o 002-2026-ANIN y Directiva N.o 0007-2025-EF/54.01.
  Los plazos del modulo CMN estan marcados como PENDIENTE_CONFIRMACION en
  base_normativa: la Directiva fija plazos explicitos para el circuito de
  requerimientos, pero los del circuito de modificacion del CMN deben
  ratificarse con la Unidad de Abastecimiento antes de activarlos.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Reglas de plazo                                                         */
/* -------------------------------------------------------------------------- */

/* activo = 0 a proposito: el motor de plazos no debe empezar a vencer
   expedientes con valores que todavia no aprobo el area funcional. Se activan
   con un UPDATE cuando la ANIN los ratifique.

   Por eso el UPDATE de abajo NO toca la columna activo: si alguien ya los
   activo tras la ratificacion, reejecutar la semilla no debe apagarlos. */
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
  ('CMN_REVISION_OA',
   'Revision del Anexo 3 por la Oficina de Administracion',
   'CMN_EN_EVAL_OA', 2, 'HABIL', 0,
   'PENDIENTE_CONFIRMACION - analogia con revision de requerimiento'),

  ('CMN_REVISION_UA',
   'Revision del Anexo 3 por la Unidad de Abastecimiento',
   'CMN_EN_EVAL_UA', 2, 'HABIL', 0,
   'PENDIENTE_CONFIRMACION - analogia con revision de requerimiento'),

  ('CMN_SUBSANACION',
   'Subsanacion de observaciones por el area usuaria',
   'CMN_OBSERVADO', 2, 'HABIL', 1,
   'PENDIENTE_CONFIRMACION - analogia con subsanacion de requerimiento'),

  ('CMN_RECEPCION_A4',
   'Recepcion del Anexo 4 por el area usuaria',
   'CMN_A4_ENVIADO', 2, 'HABIL', 0,
   'PENDIENTE_CONFIRMACION');

UPDATE d
   SET d.Nombre = s.Nombre, d.CodigoEstadoInicio = s.CodigoEstadoInicio, d.Dias = s.Dias,
       d.TipoDia = s.TipoDia, d.Ampliable = s.Ampliable, d.BaseNormativa = s.BaseNormativa
  FROM sigcm.PlazoRegla AS d JOIN @Regla AS s ON s.CodigoRegla = d.CodigoRegla;

INSERT INTO sigcm.PlazoRegla
      (CodigoRegla, CodigoModulo, Nombre, CodigoEstadoInicio, Dias, TipoDia,
       Ampliable, BaseNormativa, Activo)
SELECT s.CodigoRegla, 'CMN', s.Nombre, s.CodigoEstadoInicio, s.Dias, s.TipoDia,
       s.Ampliable, s.BaseNormativa, 0
  FROM @Regla AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.PlazoRegla AS d WHERE d.CodigoRegla = s.CodigoRegla);
GO

/* -------------------------------------------------------------------------- */
/* 2. Dias no habiles 2026                                                    */
/* -------------------------------------------------------------------------- */

/* Feriados nacionales del Peru. Sabados y domingos se resuelven por calculo.
   Debe completarse cada anio antes de activar el motor de plazos. */
DECLARE @Feriado TABLE (Fecha date, Descripcion varchar(200));
INSERT INTO @Feriado VALUES
  ('2026-01-01', 'Anio Nuevo'),
  ('2026-04-02', 'Jueves Santo'),
  ('2026-04-03', 'Viernes Santo'),
  ('2026-05-01', 'Dia del Trabajo'),
  ('2026-06-07', 'Batalla de Arica y Dia de la Bandera'),
  ('2026-06-29', 'San Pedro y San Pablo'),
  ('2026-07-23', 'Dia de la Fuerza Aerea del Peru'),
  ('2026-07-28', 'Fiestas Patrias'),
  ('2026-07-29', 'Fiestas Patrias'),
  ('2026-08-06', 'Batalla de Junin'),
  ('2026-08-30', 'Santa Rosa de Lima'),
  ('2026-10-08', 'Combate de Angamos'),
  ('2026-11-01', 'Dia de Todos los Santos'),
  ('2026-12-08', 'Inmaculada Concepcion'),
  ('2026-12-09', 'Batalla de Ayacucho'),
  ('2026-12-25', 'Navidad');

UPDATE d SET d.Descripcion = s.Descripcion
  FROM sigcm.DiaNoHabil AS d JOIN @Feriado AS s ON s.Fecha = d.Fecha;

INSERT INTO sigcm.DiaNoHabil (Fecha, Descripcion)
SELECT s.Fecha, s.Descripcion
  FROM @Feriado AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.DiaNoHabil AS d WHERE d.Fecha = s.Fecha);
GO

DECLARE @msg varchar(200) =
    'S002 aplicada: '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.PlazoRegla))      + ' reglas de plazo (inactivas), '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.DiaNoHabil)) + ' dias no habiles.';
PRINT @msg;
GO
