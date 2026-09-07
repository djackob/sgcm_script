USE [SIGA_1750];
GO

/*
  Marca la recepcion conforme de una orden de servicio.

  Es el aterrizaje del Hito 2 del modulo de pagos del SGCM: cuando el Jefe del
  area usuaria firma el Acta de Conformidad (Anexo 11), el servicio quedo
  recibido, y eso en SIGA se anota en la propia orden.

  POR QUE ESTAS DOS COLUMNAS Y NO OTRAS
  Se reviso SIGA_1750 entera buscando donde vive la conformidad de un servicio:
    - SIG_DEVENGADO tiene 1 fila en toda la base (2024): el ANIN no devenga aqui.
    - SIG_TES_INTERFASE_CAB esta vacia: el giro tampoco.
    - SIG_DEVENGADO_PENALIDAD_OTROS y SIG_CONTRATO_PENALIDAD_OTROS, vacias.
    - Ninguna tabla SIG_ORDEN_* tiene columna de conformidad.
  Lo unico que el ANIN si usa es FLAG_RECEPCION / FECHA_RECEPCION de la orden:
  82 de las 3 803 ordenes de servicio del 2026 estan en 'S' con su fecha. Ese es
  el par que escribe este procedimiento, y no se toca nada mas.

  Idempotente: si la orden ya esta recibida devuelve 0 sin escribir. No mueve
  ESTADO ni ESTADO_SIAF: aprobar y comprometer es de Logistica, no del SGCM.

  Se entrega para homologacion, igual que el resto de usp_ext_*: lo aplica
  instalar.ps1 sobre la base SIGA que ya existe.
*/
IF OBJECT_ID('dbo.usp_ext_registrar_recepcion_orden', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ext_registrar_recepcion_orden;
GO

CREATE PROCEDURE dbo.usp_ext_registrar_recepcion_orden
    @AnoEje         numeric(4,0),
    @SecEjec        numeric(6,0),
    @NroOrden       numeric(7,0),
    @Usuario        varchar(30),
    @FechaRecepcion datetime = NULL,
    @Equipo         varchar(20) = NULL,
    @Aplicados      int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Aplicados = 0;

    DECLARE @TipoBien varchar(1) = 'S',
            @Estado   varchar(1),
            @Flag     varchar(1);

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
    BEGIN
        RAISERROR('El usuario de auditoria es obligatorio.', 16, 1);
        RETURN;
    END;

    IF @Equipo IS NULL
        SET @Equipo = LEFT(COALESCE(HOST_NAME(), 'EXTERNO'), 20);

    IF @FechaRecepcion IS NULL
        SET @FechaRecepcion = GETDATE();

    SELECT @Estado = o.ESTADO,
           @Flag   = o.FLAG_RECEPCION
      FROM dbo.SIG_ORDEN_ADQUISICION AS o
     WHERE o.ANO_EJE = @AnoEje AND o.SEC_EJEC = @SecEjec
       AND o.TIPO_BIEN = @TipoBien AND o.NRO_ORDEN = @NroOrden;

    IF @Estado IS NULL
    BEGIN
        RAISERROR('No existe la orden de servicio indicada.', 16, 1);
        RETURN;
    END;

    /* '4' es anulada. Recibir una orden anulada no significa nada. */
    IF @Estado <> '1'
    BEGIN
        RAISERROR('La orden no esta emitida (ESTADO=%s): no se puede registrar la recepcion.', 16, 1, @Estado);
        RETURN;
    END;

    IF @Flag = 'S'
        RETURN;   /* ya recibida: idempotente */

    UPDATE dbo.SIG_ORDEN_ADQUISICION
       SET FLAG_RECEPCION  = 'S',
           FECHA_RECEPCION = @FechaRecepcion,
           FECHA_MOD       = GETDATE(),
           CUSER_MOD       = @Usuario,
           EQUIPO_MOD      = @Equipo
     WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
       AND TIPO_BIEN = @TipoBien AND NRO_ORDEN = @NroOrden
       AND ISNULL(FLAG_RECEPCION, 'N') <> 'S';

    SET @Aplicados = @@ROWCOUNT;
END
GO

PRINT 'usp_ext_registrar_recepcion_orden instalado.';
GO
