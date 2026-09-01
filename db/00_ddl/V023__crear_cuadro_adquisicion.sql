/*
===============================================================================
  SIGCM - V023 : Operacion CREAR_CUADRO_ADQUISICION
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Amplia el outbox para que el modulo Requerimiento pueda encolar la generacion
  del cuadro de adquisicion de servicios a partir del pedido SIGA, paso que
  ANIN no ejecuta por pantalla y que CREAR_ORDEN_SERVICIO necesita previo.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_integracion_Operacion_Operacion')
    ALTER TABLE integracion.Operacion DROP CONSTRAINT CK_integracion_Operacion_Operacion;
GO

ALTER TABLE integracion.Operacion
    ADD CONSTRAINT CK_integracion_Operacion_Operacion
        CHECK (Operacion IN (
            'INCLUIR_ITEM','EXCLUIR_ITEM','MODIFICAR_CANTIDADES',
            'CONSOLIDAR_CMN','CREAR_CUADRO_ADQUISICION','CREAR_ORDEN_SERVICIO'));
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_integracion_Operacion_Origen')
    ALTER TABLE integracion.Operacion DROP CONSTRAINT CK_integracion_Operacion_Origen;
GO

ALTER TABLE integracion.Operacion
    ADD CONSTRAINT CK_integracion_Operacion_Origen
        CHECK (
            (IdSolicitud IS NOT NULL AND IdRequerimiento IS NULL
             AND Operacion IN ('INCLUIR_ITEM','EXCLUIR_ITEM','MODIFICAR_CANTIDADES','CONSOLIDAR_CMN'))
            OR
            (IdSolicitud IS NULL AND IdRequerimiento IS NOT NULL
             AND Operacion IN ('CREAR_CUADRO_ADQUISICION','CREAR_ORDEN_SERVICIO'))
        );
GO

PRINT 'V023 aplicada: CREAR_CUADRO_ADQUISICION en el outbox.';
GO
