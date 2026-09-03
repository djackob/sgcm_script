/*
===============================================================================
  SIGCM - Semilla S012 : PE099 Coordinador de area usuaria
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  El SSO crea PE099 COORDINADOR OFICINA (sso/S02). Sin esta fila el padron
  lo descarta y Evelyn no entra como AREA_COORDINADOR.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF EXISTS (SELECT 1 FROM sigcm.PerfilSso WHERE CodigoPerfilSso = 'PE099')
    UPDATE sigcm.PerfilSso
       SET NombreSso   = 'COORDINADOR OFICINA',
           CodigoRol   = 'AREA_COORDINADOR',
           Observacion = N'Area usuaria a nivel de oficina. Completa el par PE079/PE080. Requerimiento pasa por este escalon.'
     WHERE CodigoPerfilSso = 'PE099';
ELSE
    INSERT INTO sigcm.PerfilSso (CodigoPerfilSso, NombreSso, CodigoRol, Observacion)
    VALUES ('PE099', 'COORDINADOR OFICINA', 'AREA_COORDINADOR',
            N'Area usuaria a nivel de oficina. Completa el par PE079/PE080. Requerimiento pasa por este escalon.');

PRINT 'S012 aplicada: PE099 COORDINADOR OFICINA -> AREA_COORDINADOR.';
GO
