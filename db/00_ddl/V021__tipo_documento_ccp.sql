/*
===============================================================================
  SIGCM - V021 : Tipos de documento CCP (memo UP y prevision)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Corrige VALIDACION_TIPO_DOCUMENTO para REQ_MEMO_UP_CCP y REQ_PREVISION_PRESUP.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200),
                        NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('REQ_MEMO_UP_CCP',      'Memorando de respuesta de la Unidad de Presupuesto', 'MEMO UP', 0),
  ('REQ_PREVISION_PRESUP', 'Prevision presupuestal aprobada por OPP',            'PREV.',   0);

UPDATE d SET d.Nombre = s.Nombre, d.NumeracionVisible = s.NumeracionVisible,
             d.AdmiteConsolidado = s.AdmiteConsolidado, d.Activo = 1
  FROM sigcm.TipoDocumento AS d
  JOIN @TipoDoc AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento;

INSERT INTO sigcm.TipoDocumento (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
SELECT s.CodigoTipoDocumento, 'REQUERIMIENTO', s.Nombre, s.NumeracionVisible, s.AdmiteConsolidado
  FROM @TipoDoc AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento AS d
                    WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento);
GO

PRINT 'V021 aplicada: REQ_MEMO_UP_CCP y REQ_PREVISION_PRESUP en REQUERIMIENTO.';
GO
