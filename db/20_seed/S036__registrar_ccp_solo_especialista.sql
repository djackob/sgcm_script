/*
===============================================================================
  SIGCM - S036 : Registrar CCP solo Especialista de Abastecimiento
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  REQ_REGISTRAR_CCP («Registrar CCP y generar orden de servicio») queda solo
  para ABAST_ESPECIALISTA. Jefe, coordinador y secretaria de Abastecimiento
  no la ven en la bandeja.

  Idempotente. Va despues de S007, S019 y S034, que en instalaciones previas
  asignaban la transicion a esos roles.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_REGISTRAR_CCP'
   AND CodigoRol IN ('ABAST_COORDINADOR', 'ABAST_JEFE', 'ABAST_SECRETARIA');

IF NOT EXISTS (
    SELECT 1 FROM sigcm.TransicionRol
     WHERE CodigoTransicion = 'REQ_REGISTRAR_CCP'
       AND CodigoRol = 'ABAST_ESPECIALISTA'
)
    INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
    VALUES ('REQ_REGISTRAR_CCP', 'ABAST_ESPECIALISTA');

PRINT 'S036 aplicada: REQ_REGISTRAR_CCP solo ABAST_ESPECIALISTA.';
GO
