/*
===============================================================================
  SIGCM - F014 : Los hitos de pagos que SI tienen contraparte en SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51870-51889

  F012 dejo cinco hitos en pago.HitoSincronizacion, todos como bitacora: sus
  mensajes decian "stub" y "pendiente de usp_ext homologado". Revisado SIGA
  tabla por tabla, resulta que solo tres de los cinco tienen donde aterrizar:

    Hito 1  Activa O/S    SIGA -> SGCM   SIG_ORDEN_ADQUISICION.ESTADO/ESTADO_SIAF
    Hito 2  Conformidad   SGCM -> SIGA   FLAG_RECEPCION / FECHA_RECEPCION
    Hito 3  Penalidades   -              NO existe destino en SIGA
    Hito 4  Devengado     SIGA -> SGCM   EXP_SIAF / NRO_CERTIFICA
    Hito 5  Pago cerrado  -              NO existe destino en SIGA

  Los hitos 3 y 5 no se implementan porque no hay donde: SIG_DEVENGADO tiene
  1 fila en toda la base (2024), SIG_TES_INTERFASE_CAB esta vacia,
  SIG_*_PENALIDAD_OTROS estan vacias y FECHA_CANCEL no se usa en ninguna de las
  3 803 ordenes de servicio del 2026. El ANIN devenga y gira en SIAF, no en
  SIGA. Inventar un destino seria escribir en columnas que nadie lee.

  Este archivo cubre los hitos 1 y 4, que son LECTURA. El 2 es escritura y vive
  en db/15_siga/W004 + SIGA/integracion/usp_ext_registrar_recepcion_orden.sql.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. pago.paAnotarHito : upsert de la bitacora                               */
/* ========================================================================== */

/* paRegistrarHito (F012) inserta siempre, que es lo correcto para un hito que
   ocurre una vez. La sincronizacion se repite cada vez que alguien abre el
   expediente, asi que necesita reemplazar la lectura anterior en vez de
   apilarla. */
CREATE OR ALTER PROCEDURE pago.paAnotarHito
    @IdExpedientePago uniqueidentifier,
    @NumeroHito       tinyint,
    @NombreHito       varchar(80),
    @Direccion        varchar(20),
    @TablaSiga        varchar(120),
    @Payload          nvarchar(max),
    @Estado           varchar(20),
    @Mensaje          nvarchar(400)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE pago.HitoSincronizacion
       SET NombreHito = @NombreHito,
           Direccion  = @Direccion,
           TablaSiga  = @TablaSiga,
           Payload    = @Payload,
           Estado     = @Estado,
           Mensaje    = @Mensaje,
           FechaHito  = GETDATE()
     WHERE IdExpedientePago = @IdExpedientePago
       AND NumeroHito       = @NumeroHito;

    IF @@ROWCOUNT = 0
        INSERT INTO pago.HitoSincronizacion
            (IdExpedientePago, NumeroHito, NombreHito, Direccion, TablaSiga,
             Payload, Estado, Mensaje)
        VALUES
            (@IdExpedientePago, @NumeroHito, @NombreHito, @Direccion, @TablaSiga,
             @Payload, @Estado, @Mensaje);
END
GO

/* ========================================================================== */
/* 2. pago.paSincronizarOrdenSiga : hitos 1 y 4, de SIGA hacia el SGCM        */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paSincronizarOrdenSiga
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* La vista recorre SIG_ORDEN_ADQUISICION, que es de SIGA y se mueve. Misma
       doctrina que paListarMaestroSiga: si esta bloqueada, se rinde rapido en
       vez de colgar el clic del usuario. */
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51870, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120),
                @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier,
                @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50),
                @CorrelacionId uniqueidentifier;

        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdExpediente uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));

        IF @IdExpediente IS NULL
            THROW 51871, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @IdPago uniqueidentifier, @IdReq uniqueidentifier,
                @NumeroOrden varchar(40), @AnoEje smallint, @SecEjec int,
                @EstadoIntegracion varchar(20);

        /* AnoEje y SecEjec salen del pedido SIGA que dio origen al
           requerimiento, que es la misma pareja con la que W002 creo la orden.
           Si el requerimiento no tiene pedido -expediente sembrado-, se cae al
           ejercicio del requerimiento y a la ejecutora del ANIN. */
        SELECT @IdPago = p.IdExpedientePago,
               @IdReq  = p.IdRequerimiento,
               @NumeroOrden = o.NumeroOrden,
               @EstadoIntegracion = o.EstadoIntegracion,
               @AnoEje = COALESCE(ped.AnoEje, r.AnoEje),
               @SecEjec = ISNULL(ped.SecEjec, 1750)
          FROM pago.ExpedientePago AS p
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = p.IdRequerimiento
          LEFT JOIN requerimiento.OrdenServicio AS o
                 ON o.IdRequerimiento = p.IdRequerimiento AND o.Activo = 1
          OUTER APPLY (
              SELECT TOP 1 rp.AnoEje, rp.SecEjec
                FROM requerimiento.RequerimientoPedido AS rp
               WHERE rp.IdRequerimiento = p.IdRequerimiento AND rp.Activo = 1
               ORDER BY rp.FechaCreacionAuditoria
          ) AS ped
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 51872, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        /* El numero de orden del SGCM es el que devolvio SIGA al crearla (W002).
           Un expediente sembrado o simulado no tiene contraparte: se dice, no se
           inventa. */
        DECLARE @NroSiga varchar(20) =
            CASE WHEN @NumeroOrden LIKE '%[^0-9]%' THEN NULL
                 ELSE CONVERT(varchar(20), TRY_CONVERT(bigint, @NumeroOrden)) END;

        DECLARE @Estado char(1), @EstadoSiaf char(1), @Aprobada bit,
                @ExpSiaf varchar(20), @NroCertifica bigint,
                @FlagRecepcion char(1), @FechaRecepcion date, @TieneInterfase bit;

        IF @NroSiga IS NOT NULL
            SELECT @Estado = v.Estado, @EstadoSiaf = v.EstadoSiaf, @Aprobada = v.Aprobada,
                   @ExpSiaf = v.ExpedienteSiaf, @NroCertifica = v.NroCertifica,
                   @FlagRecepcion = v.FlagRecepcion, @FechaRecepcion = v.FechaRecepcion,
                   @TieneInterfase = v.TieneInterfase
              FROM siga.vwOrdenServicioSiga AS v
             WHERE v.AnoEje = @AnoEje AND v.SecEjec = @SecEjec
               AND v.TipoBien = 'S' AND v.NumeroOrden = @NroSiga;

        DECLARE @Payload nvarchar(max) = (
            SELECT NumeroOrden = @NumeroOrden, AnoEje = @AnoEje, SecEjec = @SecEjec,
                   Estado = @Estado, EstadoSiaf = @EstadoSiaf,
                   ExpedienteSiaf = @ExpSiaf, NroCertifica = @NroCertifica,
                   FlagRecepcion = @FlagRecepcion, TieneInterfase = @TieneInterfase
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        /* ---- Hito 1: la orden existe y esta aprobada y comprometida ------- */
        DECLARE @EstadoHito1 varchar(20), @MsgHito1 nvarchar(400);

        IF @Estado IS NULL
        BEGIN
            SET @EstadoHito1 = CASE WHEN @EstadoIntegracion = 'SIMULADO' THEN 'SIMULADO' ELSE 'PENDIENTE' END;
            SET @MsgHito1 = CASE
                WHEN @EstadoIntegracion = 'SIMULADO'
                    THEN N'Expediente sembrado: la orden no existe en SIGA y no hay nada que leer.'
                ELSE N'La orden ' + ISNULL(@NumeroOrden, N'(sin numero)')
                     + N' no se encontro en SIGA. Revise que W002 la haya creado.' END;
        END
        ELSE IF @Aprobada = 1
        BEGIN
            SET @EstadoHito1 = 'REGISTRADO';
            SET @MsgHito1 = N'Orden emitida y comprometida en SIAF. El expediente de pago puede avanzar.';
        END
        ELSE
        BEGIN
            SET @EstadoHito1 = 'PENDIENTE';
            SET @MsgHito1 = CASE
                WHEN @Estado = '4' THEN N'La orden esta ANULADA en SIGA. No corresponde continuar el pago.'
                WHEN @Estado = '0' THEN N'La orden sigue PENDIENTE en SIGA: falta que Logistica la apruebe.'
                WHEN @EstadoSiaf <> '2' THEN N'La orden esta emitida pero SIN COMPROMISO SIAF en SIGA.'
                ELSE N'La orden no esta en condicion de continuar (estado ' + @Estado + N').' END;
        END

        EXEC pago.paAnotarHito @IdPago, 1, 'Activa O/S', 'SIGA_A_SGCM',
             'SIG_ORDEN_ADQUISICION', @Payload, @EstadoHito1, @MsgHito1;

        /* ---- Hito 4: el expediente SIAF lo tiene SIGA, no lo tecleamos ---- */
        IF @ExpSiaf IS NOT NULL AND @ExpSiaf <> ''
            EXEC pago.paAnotarHito @IdPago, 4, 'Devengado', 'SIGA_A_SGCM',
                 'SIG_ORDEN_ADQUISICION', @Payload, 'REGISTRADO',
                 N'Expediente SIAF leido de SIGA. Contabilidad ya no tiene que teclearlo.';

        SELECT @resultado = (
            SELECT 1 AS estado,
                   EnSiga         = CONVERT(bit, CASE WHEN @Estado IS NULL THEN 0 ELSE 1 END),
                   NumeroOrden    = @NumeroOrden,
                   EstadoOrden    = @Estado,
                   EstadoSiaf     = @EstadoSiaf,
                   Aprobada       = ISNULL(@Aprobada, CONVERT(bit, 0)),
                   ExpedienteSiaf = @ExpSiaf,
                   NroCertifica   = @NroCertifica,
                   FlagRecepcion  = @FlagRecepcion,
                   FechaRecepcion = @FechaRecepcion,
                   mensaje        = @MsgHito1
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 3. pago.paEncolarRecepcionOrden : hito 2, del SGCM hacia SIGA              */
/* ========================================================================== */

/* La firma del Acta de Conformidad (Anexo 11) significa que el servicio quedo
   recibido. En SIGA eso se anota en la propia orden. No se escribe aqui: se
   encola, y W004 lo drena, porque SIGA puede no responder y la conformidad no
   puede quedarse esperando a que responda.

   Lo llama pago.paMarcarConformidadFirmada, en el punto donde antes anotaba el
   hito 2 como stub. */
CREATE OR ALTER PROCEDURE pago.paEncolarRecepcionOrden
    @IdExpedientePago uniqueidentifier,
    @Cuenta           varchar(120),
    @Equipo           varchar(50)   = NULL,
    @Programa         varchar(50)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdExpediente uniqueidentifier, @IdReq uniqueidentifier,
            @NumeroOrden varchar(40), @AnoEje smallint, @SecEjec int,
            @FechaConformidad datetime;

    SELECT @IdExpediente = p.IdExpediente,
           @IdReq        = p.IdRequerimiento,
           @NumeroOrden  = o.NumeroOrden,
           @FechaConformidad = ISNULL(p.FechaConformidadTecnica, GETDATE()),
           @AnoEje       = COALESCE(ped.AnoEje, r.AnoEje),
           @SecEjec      = ISNULL(ped.SecEjec, 1750)
      FROM pago.ExpedientePago AS p
      JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = p.IdRequerimiento
      LEFT JOIN requerimiento.OrdenServicio AS o
             ON o.IdRequerimiento = p.IdRequerimiento AND o.Activo = 1
      OUTER APPLY (
          SELECT TOP 1 rp.AnoEje, rp.SecEjec
            FROM requerimiento.RequerimientoPedido AS rp
           WHERE rp.IdRequerimiento = p.IdRequerimiento AND rp.Activo = 1
           ORDER BY rp.FechaCreacionAuditoria
      ) AS ped
     WHERE p.IdExpedientePago = @IdExpedientePago AND p.Activo = 1;

    DECLARE @NroSiga bigint =
        CASE WHEN @NumeroOrden LIKE '%[^0-9]%' THEN NULL
             ELSE TRY_CONVERT(bigint, @NumeroOrden) END;

    DECLARE @Payload nvarchar(max) = (
        SELECT AnoEje = @AnoEje, SecEjec = @SecEjec, NroOrden = @NroSiga,
               FechaRecepcion = CONVERT(varchar(19), @FechaConformidad, 126)
          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    /* Sin numero de SIGA no hay orden que recibir: pasa con los expedientes
       sembrados (S909) y con cualquier O/S que no llego a escribirse alla. Se
       anota y no se encola una operacion que nacio condenada. */
    IF @NroSiga IS NULL
    BEGIN
        EXEC pago.paAnotarHito @IdExpedientePago, 2, 'Conformidad', 'SGCM_A_SIGA',
             'SIG_ORDEN_ADQUISICION', @Payload, 'SIMULADO',
             N'La orden no existe en SIGA: la conformidad queda solo en el SGCM.';
        RETURN;
    END

    DECLARE @Clave varchar(200) =
        CONCAT('pago:', CONVERT(varchar(36), @IdExpedientePago), ':RECEPCION_OS');

    IF NOT EXISTS (SELECT 1 FROM integracion.Operacion WHERE IdempotenciaKey = @Clave)
        INSERT INTO integracion.Operacion
              (IdempotenciaKey, IdExpediente, IdRequerimiento, Operacion,
               Procedimiento, Secuencia, Estado, RequestJson,
               UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES (@Clave, @IdExpediente, @IdReq, 'REGISTRAR_RECEPCION_OS',
                'siga.usp_ext_registrar_recepcion_orden', 1, 'PENDIENTE', @Payload,
                @Cuenta, @Equipo, @Programa);

    EXEC pago.paAnotarHito @IdExpedientePago, 2, 'Conformidad', 'SGCM_A_SIGA',
         'SIG_ORDEN_ADQUISICION', @Payload, 'PENDIENTE',
         N'Recepcion encolada hacia SIGA. La escribe W004 al drenar.';
END
GO

PRINT 'F014 aplicada: paAnotarHito, paSincronizarOrdenSiga (1 y 4) y paEncolarRecepcionOrden (2).';
GO
