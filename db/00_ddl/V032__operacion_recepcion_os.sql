/*
===============================================================================
  SIGCM - Migracion V032 : REGISTRAR_RECEPCION_OS en la cola de integracion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  V006 fijo el vocabulario de integracion.Operacion cuando solo existian el CMN
  y la orden de servicio. El modulo de pagos agrega una operacion mas: la
  recepcion conforme de la orden, que es lo que significa en SIGA la firma del
  Acta de Conformidad (Anexo 11).

  La escribe db/15_siga/W004 llamando a usp_ext_registrar_recepcion_orden, y la
  encola pago.paEncolarRecepcionOrden (F014). Sin esto el encolado revienta con
  un 547 contra CK_integracion_Operacion_Operacion.

  Es la unica operacion de pagos: de los cinco hitos, los otros cuatro no
  escriben en SIGA. El porque esta en SIGA/integracion/FLUJO_PAGOS.md seccion 3.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_integracion_Operacion_Operacion')
    ALTER TABLE integracion.Operacion DROP CONSTRAINT CK_integracion_Operacion_Operacion;
GO

ALTER TABLE integracion.Operacion WITH CHECK
    ADD CONSTRAINT CK_integracion_Operacion_Operacion
    CHECK (Operacion IN ('INCLUIR_ITEM', 'EXCLUIR_ITEM', 'MODIFICAR_CANTIDADES',
                         'CONSOLIDAR_CMN', 'CREAR_CUADRO_ADQUISICION',
                         'CREAR_ORDEN_SERVICIO', 'REGISTRAR_RECEPCION_OS'));
GO

/* El segundo candado de V006 dice de que cuelga cada operacion: las del CMN de
   una solicitud, las del requerimiento de un requerimiento. La recepcion cuelga
   del requerimiento -es su orden la que se recibe- aunque la dispare un
   expediente de pago, que viaja en IdExpediente. */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_integracion_Operacion_Origen')
    ALTER TABLE integracion.Operacion DROP CONSTRAINT CK_integracion_Operacion_Origen;
GO

ALTER TABLE integracion.Operacion WITH CHECK
    ADD CONSTRAINT CK_integracion_Operacion_Origen
    CHECK (
        (IdSolicitud IS NOT NULL AND IdRequerimiento IS NULL
         AND Operacion IN ('INCLUIR_ITEM', 'EXCLUIR_ITEM', 'MODIFICAR_CANTIDADES', 'CONSOLIDAR_CMN'))
        OR
        (IdSolicitud IS NULL AND IdRequerimiento IS NOT NULL
         AND Operacion IN ('CREAR_CUADRO_ADQUISICION', 'CREAR_ORDEN_SERVICIO', 'REGISTRAR_RECEPCION_OS'))
    );
GO

PRINT 'V032 aplicada: la cola de integracion acepta REGISTRAR_RECEPCION_OS.';
GO
