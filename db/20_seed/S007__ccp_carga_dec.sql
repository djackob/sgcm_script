/*
===============================================================================
  SIGCM - S007 : Carga de CCP por DEC (asistente Abastecimiento)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Cuando la UP remite la CCP aprobada, la DEC registra la certificacion y
  desbloquea la emision de la orden de servicio.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

UPDATE sigcm.Estado
   SET Nombre = 'Solicitado a CCP (pendiente de carga DEC)',
       RolResponsable = 'ABAST_ESPECIALISTA'
 WHERE CodigoEstado = 'REQ_CCP_SOLICITADO'
   AND CodigoModulo = 'REQUERIMIENTO';
GO

UPDATE sigcm.Transicion
   SET NombreAccion = 'Registrar CCP y generar orden de servicio'
 WHERE CodigoTransicion = 'REQ_REGISTRAR_CCP'
   AND CodigoModulo = 'REQUERIMIENTO';
GO

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_REGISTRAR_CCP'
   AND CodigoRol = 'OPP';
GO

/* Mismo candado que en S004: REQ_REGISTRAR_CCP no la define ninguna semilla,
   asi que sin el EXISTS esta linea corta la instalacion con un 547 en toda base
   que no arrastre la fila de antes. */
INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT v.CodigoTransicion, v.CodigoRol
  FROM (VALUES
    ('REQ_REGISTRAR_CCP', 'ABAST_ESPECIALISTA'),
    ('REQ_REGISTRAR_CCP', 'ABAST_COORDINADOR'),
    ('REQ_REGISTRAR_CCP', 'ABAST_JEFE')
  ) AS v(CodigoTransicion, CodigoRol)
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.TransicionRol AS d
        WHERE d.CodigoTransicion = v.CodigoTransicion
          AND d.CodigoRol = v.CodigoRol)
   AND EXISTS (
       SELECT 1 FROM sigcm.Transicion AS t
        WHERE t.CodigoTransicion = v.CodigoTransicion);
GO

DECLARE @TipoDoc TABLE (CodigoTipoDocumento varchar(60), Nombre varchar(200),
                        NumeracionVisible varchar(60), AdmiteConsolidado bit);
INSERT INTO @TipoDoc VALUES
  ('REQ_MEMO_UP_CCP',      'Memorando de respuesta de la Unidad de Presupuesto', 'MEMO UP', 0),
  ('REQ_PREVISION_PRESUP', 'Prevision presupuestal aprobada por OPP',            'PREV.',   0);

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

PRINT 'S007 aplicada: carga CCP por DEC; tipos memo UP y prevision.';
GO
