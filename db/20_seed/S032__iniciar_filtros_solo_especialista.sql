/*
===============================================================================
  SIGCM - S032 : Iniciar filtros solo Especialista de Abastecimiento
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  REQ_INICIAR_FILTROS queda solo para ABAST_ESPECIALISTA. El Coordinador no
  inicia los filtros de idoneidad.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_INICIAR_FILTROS'
   AND CodigoRol = 'ABAST_COORDINADOR';

IF NOT EXISTS (
    SELECT 1 FROM sigcm.TransicionRol
     WHERE CodigoTransicion = 'REQ_INICIAR_FILTROS'
       AND CodigoRol = 'ABAST_ESPECIALISTA'
)
    INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
    VALUES ('REQ_INICIAR_FILTROS', 'ABAST_ESPECIALISTA');

PRINT 'S032 aplicada: REQ_INICIAR_FILTROS solo ABAST_ESPECIALISTA.';
GO
