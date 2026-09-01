/*
===============================================================================
  SIGCM - S006 : OPP y Administracion — interaccion solo a nivel jefe
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  En OPP y OA no se modela (por ahora) la jerarquia interna coord/esp.
  Los tramites cruzados entre unidades se resuelven entre jefes:
    - Abastecimiento (jefe) -> OPP (rol unico, jefe de la oficina)
    - Area usuaria (jefe) -> OA (rol unico)
    - OA -> Abastecimiento (jefe)

  La emision de la CCP la registra solo OPP, no Abastecimiento.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'REQ_REGISTRAR_CCP'
   AND CodigoRol = 'ABAST_ESPECIALISTA';
GO

UPDATE sigcm.Estado
   SET Nombre = 'Solicitado a CCP (OPP)'
 WHERE CodigoEstado = 'REQ_CCP_SOLICITADO'
   AND CodigoModulo = 'REQUERIMIENTO';
GO

PRINT 'S006 aplicada: CCP solo OPP; OA/OPP sin jerarquia interna (solo jefes).';
GO
