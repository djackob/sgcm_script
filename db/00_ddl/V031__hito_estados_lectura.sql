/*
===============================================================================
  SIGCM - Migracion V031 : Estados de pago.HitoSincronizacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  V027 creo la bitacora de hitos cuando todos eran STUB: la unica pregunta que
  tenia sentido era si el hito se habia anotado (REGISTRADO), si era un stub o
  si algo habia fallado (ERROR).

  Desde que los hitos 1 y 4 leen SIGA de verdad (F014), la lectura tiene dos
  desenlaces mas que no son ni un error ni un stub:

    PENDIENTE  la orden existe en SIGA pero todavia no esta aprobada o
               comprometida; el expediente de pago no deberia avanzar.
    SIMULADO   el expediente se sembro (S909) y no hay contraparte en SIGA que
               leer. Es un dato de la prueba, no una falla.

  Sin esto la sincronizacion revienta con un 547 contra CK_pago_Hito_Est.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_pago_Hito_Est')
    ALTER TABLE pago.HitoSincronizacion DROP CONSTRAINT CK_pago_Hito_Est;
GO

ALTER TABLE pago.HitoSincronizacion WITH CHECK
    ADD CONSTRAINT CK_pago_Hito_Est
    CHECK (Estado IN ('REGISTRADO', 'STUB', 'ERROR', 'PENDIENTE', 'SIMULADO'));
GO

PRINT 'V031 aplicada: CK_pago_Hito_Est acepta PENDIENTE y SIMULADO.';
GO
