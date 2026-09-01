/*
===============================================================================
  SIGCM - Migracion V017 : Integracion de Orden de Servicio con SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Extiende el outbox para CREAR_ORDEN_SERVICIO (modulo Requerimiento / locacion)
  y agrega columnas de seguimiento en requerimiento.OrdenServicio.

  Requiere sinonimos hacia SIG_CUADRO_ADQUISICION, SIG_DETALLE_PEDIDO_CUADRO y
  SIG_CONTRATISTAS (C003 actualizado).
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Outbox: operaciones de requerimiento                                    */
/* -------------------------------------------------------------------------- */

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_integracion_Operacion_Solicitud')
    ALTER TABLE integracion.Operacion DROP CONSTRAINT FK_integracion_Operacion_Solicitud;
GO

ALTER TABLE integracion.Operacion ALTER COLUMN IdSolicitud uniqueidentifier NULL;
GO

ALTER TABLE integracion.Operacion
    ADD CONSTRAINT FK_integracion_Operacion_Solicitud
        FOREIGN KEY (IdSolicitud) REFERENCES cmn.Solicitud(IdSolicitud);
GO

IF COL_LENGTH('integracion.Operacion', 'IdRequerimiento') IS NULL
BEGIN
    ALTER TABLE integracion.Operacion
        ADD IdRequerimiento uniqueidentifier NULL
            CONSTRAINT FK_integracion_Operacion_Requerimiento
                REFERENCES requerimiento.Requerimiento(IdRequerimiento);
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_integracion_Operacion_Operacion')
    ALTER TABLE integracion.Operacion DROP CONSTRAINT CK_integracion_Operacion_Operacion;
GO

ALTER TABLE integracion.Operacion
    ADD CONSTRAINT CK_integracion_Operacion_Operacion
        CHECK (Operacion IN (
            'INCLUIR_ITEM','EXCLUIR_ITEM','MODIFICAR_CANTIDADES',
            'CONSOLIDAR_CMN','CREAR_ORDEN_SERVICIO'));
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_integracion_Operacion_Origen')
ALTER TABLE integracion.Operacion
    ADD CONSTRAINT CK_integracion_Operacion_Origen
        CHECK (
            (IdSolicitud IS NOT NULL AND IdRequerimiento IS NULL
             AND Operacion IN ('INCLUIR_ITEM','EXCLUIR_ITEM','MODIFICAR_CANTIDADES','CONSOLIDAR_CMN'))
            OR
            (IdSolicitud IS NULL AND IdRequerimiento IS NOT NULL
             AND Operacion = 'CREAR_ORDEN_SERVICIO')
        );
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_integracion_Operacion_Requerimiento'
               AND object_id = OBJECT_ID(N'integracion.Operacion'))
CREATE NONCLUSTERED INDEX IX_integracion_Operacion_Requerimiento
    ON integracion.Operacion(IdRequerimiento, Secuencia)
    WHERE IdRequerimiento IS NOT NULL;
GO

/* -------------------------------------------------------------------------- */
/* 2. Seguimiento de la O/S en el requerimiento                               */
/* -------------------------------------------------------------------------- */

IF COL_LENGTH('requerimiento.OrdenServicio', 'EstadoIntegracion') IS NULL
    ALTER TABLE requerimiento.OrdenServicio
        ADD EstadoIntegracion varchar(20) NULL;
GO

IF COL_LENGTH('requerimiento.OrdenServicio', 'SecCuadroSiga') IS NULL
    ALTER TABLE requerimiento.OrdenServicio
        ADD SecCuadroSiga bigint NULL;
GO

IF COL_LENGTH('requerimiento.OrdenServicio', 'ProveedorSiga') IS NULL
    ALTER TABLE requerimiento.OrdenServicio
        ADD ProveedorSiga int NULL;
GO

IF COL_LENGTH('requerimiento.OrdenServicio', 'ErrorIntegracion') IS NULL
    ALTER TABLE requerimiento.OrdenServicio
        ADD ErrorIntegracion nvarchar(500) NULL;
GO

IF COL_LENGTH('requerimiento.OrdenServicio', 'IdOperacionIntegracion') IS NULL
    ALTER TABLE requerimiento.OrdenServicio
        ADD IdOperacionIntegracion uniqueidentifier NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_req_Os_EstadoIntegracion')
ALTER TABLE requerimiento.OrdenServicio
    ADD CONSTRAINT CK_req_Os_EstadoIntegracion
        CHECK (EstadoIntegracion IS NULL OR EstadoIntegracion IN
            ('PENDIENTE','EN_PROCESO','COMPLETADO','SIMULADO','ERROR'));
GO

/* -------------------------------------------------------------------------- */
/* 3. Vista: cuadro de adquisicion de servicios elegible desde un pedido      */
/* -------------------------------------------------------------------------- */

CREATE OR ALTER VIEW siga.vwCuadroAdquisicionPedido
AS
SELECT DISTINCT
    AnoEje       = CONVERT(smallint, c.ANO_EJE),
    SecEjec      = CONVERT(int,      c.SEC_EJEC),
    TipoPedido   = CONVERT(char(1),     p.TIPO_PEDIDO)  COLLATE DATABASE_DEFAULT,
    NumeroPedido = CONVERT(varchar(6),  p.NRO_PEDIDO)   COLLATE DATABASE_DEFAULT,
    SecCuadro    = CONVERT(bigint,   c.SEC_CUADRO),
    TipoBien     = CONVERT(char(1),     c.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
    CentroCosto  = CONVERT(varchar(15), c.CENTRO_COSTO) COLLATE DATABASE_DEFAULT,
    EstadoCuadro = CONVERT(char(1),     c.ESTADO)       COLLATE DATABASE_DEFAULT
  FROM siga.SIG_CUADRO_ADQUISICION AS c
  JOIN siga.SIG_PEDIDOS AS p
    ON p.ANO_EJE     = c.ANO_EJE
   AND p.SEC_EJEC    = c.SEC_EJEC
   AND p.TIPO_BIEN   = c.TIPO_BIEN
   AND p.TIPO_PEDIDO = '2'
   AND p.NRO_PEDIDO  = RIGHT('000000' + CONVERT(varchar(6), c.NRO_REQUER), 6)
 WHERE c.TIPO_BIEN   = 'S'
   AND c.NRO_REQUER IS NOT NULL
   AND c.NRO_ORDEN IS NULL

UNION

SELECT DISTINCT
    AnoEje       = CONVERT(smallint, d.ANO_EJE),
    SecEjec      = CONVERT(int,      d.sec_ejec),
    TipoPedido   = CONVERT(char(1),     d.TIPO_PEDIDO)  COLLATE DATABASE_DEFAULT,
    NumeroPedido = CONVERT(varchar(6),  d.NRO_PEDIDO)   COLLATE DATABASE_DEFAULT,
    SecCuadro    = CONVERT(bigint,   c2.SEC_CUADRO),
    TipoBien     = CONVERT(char(1),     d.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
    CentroCosto  = CONVERT(varchar(15), c2.CENTRO_COSTO) COLLATE DATABASE_DEFAULT,
    EstadoCuadro = CONVERT(char(1),     c2.ESTADO)       COLLATE DATABASE_DEFAULT
  FROM siga.SIG_DETALLE_PEDIDOS AS d
  JOIN siga.SIG_CUADRO_ADQUISICION AS c2
    ON c2.ANO_EJE    = d.ANO_EJE
   AND c2.SEC_EJEC   = d.sec_ejec
   AND c2.TIPO_BIEN  = d.TIPO_BIEN
   AND c2.NRO_CUADRO = d.NRO_CUADRO
 WHERE d.TIPO_BIEN   = 'S'
   AND d.TIPO_PEDIDO = '2'
   AND d.NRO_CUADRO IS NOT NULL
   AND c2.NRO_ORDEN IS NULL

UNION

SELECT DISTINCT
    AnoEje       = CONVERT(smallint, lg.ANO_EJE),
    SecEjec      = CONVERT(int,      lg.SEC_EJEC),
    TipoPedido   = CONVERT(char(1),     lg.TIPO_PEDIDO)  COLLATE DATABASE_DEFAULT,
    NumeroPedido = CONVERT(varchar(6),  lg.NRO_PEDIDO)   COLLATE DATABASE_DEFAULT,
    SecCuadro    = CONVERT(bigint,   lg.SEC_CUADRO),
    TipoBien     = CONVERT(char(1),     lg.TIPO_BIEN)    COLLATE DATABASE_DEFAULT,
    CentroCosto  = CONVERT(varchar(15), c3.CENTRO_COSTO) COLLATE DATABASE_DEFAULT,
    EstadoCuadro = CONVERT(char(1),     c3.ESTADO)       COLLATE DATABASE_DEFAULT
  FROM siga.SIG_DETALLE_PEDIDO_CUADRO AS lg
  JOIN siga.SIG_CUADRO_ADQUISICION AS c3
    ON c3.ANO_EJE    = lg.ANO_EJE
   AND c3.SEC_EJEC   = lg.SEC_EJEC
   AND c3.TIPO_BIEN  = lg.TIPO_BIEN
   AND c3.SEC_CUADRO = lg.SEC_CUADRO
 WHERE lg.TIPO_BIEN = 'S'
   AND lg.NRO_PEDIDO IS NOT NULL
   AND c3.NRO_ORDEN IS NULL;
GO

PRINT 'V017 aplicada: integracion de orden de servicio con SIGA.';
GO
