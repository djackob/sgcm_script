/*
===============================================================================
  SIGCM - Semilla S014 : Observar desde filtros de idoneidad
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Si un filtro obligatorio no cumple, el especialista de Abastecimiento
  devuelve el expediente al Area usuaria (REQ_OBSERVADO) con motivo.
  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sigcm.Transicion WHERE CodigoTransicion = 'REQ_OBSERVAR_FILTROS')
    INSERT INTO sigcm.Transicion
          (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
           NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
           EncolaIntegracion, OperacionIntegracion, GeneraObservacion)
    VALUES ('REQ_OBSERVAR_FILTROS', 'REQUERIMIENTO', 'REQ_FILTROS', 'REQ_OBSERVADO',
            'Devolver al Area usuaria / Observar', 1, 0, NULL, 0, NULL, 1);

UPDATE sigcm.Transicion
   SET CodigoEstadoOrigen  = 'REQ_FILTROS',
       CodigoEstadoDestino = 'REQ_OBSERVADO',
       NombreAccion        = 'Devolver al Area usuaria / Observar',
       RequiereComentario  = 1,
       GeneraObservacion   = 1,
       Activo              = 1
 WHERE CodigoTransicion = 'REQ_OBSERVAR_FILTROS';
GO

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT s.CodigoTransicion, s.CodigoRol
  FROM (VALUES
      ('REQ_OBSERVAR_FILTROS', 'ABAST_ESPECIALISTA'),
      ('REQ_OBSERVAR_FILTROS', 'ABAST_COORDINADOR')
  ) AS s(CodigoTransicion, CodigoRol)
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = s.CodigoTransicion
                      AND d.CodigoRol = s.CodigoRol);
GO

PRINT 'S014 aplicada: REQ_OBSERVAR_FILTROS desde idoneidad hacia el Area usuaria.';
GO
