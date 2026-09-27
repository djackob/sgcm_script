/*
===============================================================================
  SIGCM - S050 : Anexo 5 sin firma del especialista, CV del locador
                 y filtros de idoneidad en el especialista de Abastecimiento
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El Anexo 5 lo firma solo el jefe del area usuaria.
  La cotizacion del locador adjunta el CV (REQ_CV_LOCADOR).
  El especialista de Abastecimiento confirma la idoneidad y solicita la CCP.
  Ya no deriva esos documentos al coordinador ni al jefe.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DELETE FROM sigcm.TipoDocumentoFirma
 WHERE CodigoTipoDocumento = 'REQ_PROPUESTA_LOCACION'
   AND CodigoRol = 'AREA_ESPECIALISTA';
GO

DECLARE @TipoDoc TABLE (
    CodigoTipoDocumento varchar(60),
    Nombre varchar(200),
    NumeracionVisible varchar(10),
    AdmiteConsolidado bit
);
INSERT INTO @TipoDoc VALUES
  ('REQ_CV_LOCADOR', 'CV del locador', 'CV', 0);

UPDATE d
   SET d.Nombre = s.Nombre
  FROM sigcm.TipoDocumento AS d
  JOIN @TipoDoc AS s ON s.CodigoTipoDocumento = d.CodigoTipoDocumento;

INSERT INTO sigcm.TipoDocumento
      (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
SELECT s.CodigoTipoDocumento, 'REQUERIMIENTO', s.Nombre, s.NumeracionVisible, s.AdmiteConsolidado
  FROM @TipoDoc AS s
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.TipoDocumento AS d
        WHERE d.CodigoTipoDocumento = s.CodigoTipoDocumento);
GO

UPDATE sigcm.Transicion
   SET CodigoEstadoOrigen = 'REQ_FILTROS',
       NombreAccion = 'Confirmar idoneidad y solicitar CCP',
       Activo = 1
 WHERE CodigoTransicion = 'REQ_CONFIRMAR_FILTROS';
GO

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT 'REQ_CONFIRMAR_FILTROS', 'ABAST_ESPECIALISTA'
 WHERE NOT EXISTS (
       SELECT 1 FROM sigcm.TransicionRol
        WHERE CodigoTransicion = 'REQ_CONFIRMAR_FILTROS'
          AND CodigoRol = 'ABAST_ESPECIALISTA');
GO

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion IN (
       'REQ_ENVIAR_FILTROS_COORD',
       'REQ_ENVIAR_FILTROS_JEFE',
       'REQ_DEVOLVER_FILTROS_COORD',
       'REQ_DEVOLVER_FILTROS_JEFE');
GO

/* Expedientes que ya estaban en revision del coordinador o del jefe
   vuelven al especialista, que ahora cierra la idoneidad. */
UPDATE sigcm.Expediente
   SET CodigoEstado = 'REQ_FILTROS'
 WHERE CodigoEstado IN ('REQ_FILTROS_COORD', 'REQ_FILTROS_JEFE')
   AND Anulado = 0
   AND Activo = 1;
GO

IF COL_LENGTH('requerimiento.FiltroIdoneidad', 'GeneradoDocumentoEvidencia') IS NOT NULL
   AND (SELECT c.max_length
          FROM sys.columns AS c
          JOIN sys.objects AS o ON o.object_id = c.object_id
          JOIN sys.schemas AS s ON s.schema_id = o.schema_id
         WHERE s.name = 'requerimiento' AND o.name = 'FiltroIdoneidad'
           AND c.name = 'GeneradoDocumentoEvidencia') <> -1
BEGIN
    ALTER TABLE requerimiento.FiltroIdoneidad
        ALTER COLUMN GeneradoDocumentoEvidencia nvarchar(max) NULL;
    ALTER TABLE requerimiento.FiltroIdoneidad
        ALTER COLUMN NombreDocumentoEvidencia nvarchar(max) NULL;
END
GO

PRINT 'S050 aplicada: Anexo 5 lo firma el jefe; CV del locador; idoneidad en el especialista de Abastecimiento.';
GO
