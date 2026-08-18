USE [SIGA_1750];
GO

/*
  Procedimiento propuesto para registrar una Orden de Servicio pendiente
  a partir de un Cuadro de Adquisicion ya existente en SIGA.

  Alcance:
    - Marca el cuadro como atendido (ESTADO = '2') y asigna NRO_ORDEN.
    - Inserta cabecera, secuencia inicial, items y distribucion presupuestal.
    - Deja la orden pendiente: ESTADO = '0', ESTADO_SIAF = '0'.
    - NO certifica, NO compromete y NO inserta SIG_ORDEN_INTERFASE.

  Recomendacion: desplegar primero en una copia de homologacion y ejecutar
  el bloque de prueba con ROLLBACK incluido al final de este archivo.
*/
IF OBJECT_ID('dbo.usp_ext_crear_orden_servicio_desde_cuadro', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ext_crear_orden_servicio_desde_cuadro;
GO

CREATE PROCEDURE dbo.usp_ext_crear_orden_servicio_desde_cuadro
    @AnoEje                 numeric(4,0),
    @SecEjec                numeric(6,0),
    @SecCuadro              numeric(6,0),
    @Proveedor              numeric(5,0),
    @FechaOrden             datetime,
    @Usuario                varchar(30),
    @Equipo                 varchar(20) = NULL,
    @MesCalend              char(2) = NULL,
    @TipoProveedor          varchar(1) = NULL,
    @DocumentoReferencia    varchar(100) = NULL,
    @Concepto               varchar(350) = NULL,
    @PlazoEntrega           numeric(4,0) = NULL,
    @CondicionPago          varchar(80) = NULL,
    @IncluyeIgv             varchar(1) = 'N',
    @TasaImpuesto           numeric(9,2) = 18.00,
    @SubtotalMoneda         numeric(16,2) = NULL,
    @TotalIgvMoneda         numeric(14,2) = NULL,
    @SubtotalSoles          numeric(16,2) = NULL,
    @TotalIgvSoles          numeric(14,2) = NULL,
    @Especificaciones       varchar(max) = NULL,
    @NroOrden               numeric(7,0) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @TipoBien           varchar(1) = 'S',
        @TipoPpto           numeric(2,0),
        @TipoUso            varchar(1),
        @NroEncargo         numeric(6,0),
        @SecEjec2           numeric(6,0),
        @Moneda             varchar(6),
        @TipoCambio         numeric(10,6),
        @TipoProceso        varchar(4),
        @TipoOperacion      varchar(2),
        @TipoCompra         varchar(1),
        @ModalCompra        varchar(2),
        @TipoOrganismo      varchar(2),
        @FlagTesoro         char(1),
        @TipoEntidad        char(1),
        @IdProceso          varchar(8),
        @IdContrato         varchar(8),
        @FlagPsa            varchar(1),
        @ModalidadJustifica varchar(250),
        @TipoAfectacion     varchar(1),
        @TotalMoneda        numeric(16,2),
        @TotalSoles         numeric(16,2),
        @ResultadoLock      int,
        @RecursoLock        nvarchar(255);

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
    BEGIN
        RAISERROR('El usuario de auditoria es obligatorio.', 16, 1);
        RETURN;
    END;

    IF @FechaOrden IS NULL
    BEGIN
        RAISERROR('La fecha de la orden es obligatoria.', 16, 1);
        RETURN;
    END;

    SET @MesCalend = COALESCE(NULLIF(@MesCalend, ''),
                             RIGHT('0' + CONVERT(varchar(2), MONTH(@FechaOrden)), 2));

    IF @MesCalend LIKE '%[^0-9]%'
       OR CONVERT(int, @MesCalend) NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('El mes calendario debe estar entre 01 y 12.', 16, 1);
        RETURN;
    END;

    IF @Equipo IS NULL
        SET @Equipo = LEFT(COALESCE(HOST_NAME(), 'EXTERNO'), 20);

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;

        /* Los triggers de SIGA toman de esta tabla temporal la auditoria. */
        CREATE TABLE #SIG_SESION
        (
            CUSER_ID  varchar(30) NOT NULL,
            EQUIPO_REG varchar(20) NULL
        );

        INSERT INTO #SIG_SESION(CUSER_ID, EQUIPO_REG)
        VALUES (@Usuario, @Equipo);

        SET @RecursoLock = 'SIGA_OS_' + CONVERT(varchar(4), @AnoEje)
                         + '_' + CONVERT(varchar(6), @SecEjec);

        EXEC @ResultadoLock = sys.sp_getapplock
             @Resource = @RecursoLock,
             @LockMode = 'Exclusive',
             @LockOwner = 'Transaction',
             @LockTimeout = 15000;

        IF @ResultadoLock < 0
            RAISERROR('No se pudo reservar la numeracion de Orden de Servicio.', 16, 1);

        SELECT
            @TipoPpto           = C.TIPO_PPTO,
            @TipoUso            = C.TIPO_USO,
            @NroEncargo         = C.NRO_ENCARGO,
            @SecEjec2           = C.SEC_EJEC2,
            @Moneda             = C.MONEDA,
            @TipoCambio         = COALESCE(C.TIPO_CAMBIO, 1),
            @TipoProceso        = C.TIPO_PROCESO,
            @TipoOperacion      = C.TIPO_OPERACION,
            @TipoCompra         = C.TIPO_COMPRA,
            @ModalCompra        = C.MODAL_COMPRA,
            @TipoProveedor      = COALESCE(@TipoProveedor, C.TIPO_PROVEEDOR),
            @TipoOrganismo      = C.TIPO_ORGANISMO,
            @FlagTesoro         = C.FLAG_TESORO,
            @TipoEntidad        = C.TIPO_ENTIDAD,
            @IdProceso          = C.ID_PROCESO,
            @IdContrato         = C.ID_CONTRATO,
            @FlagPsa            = C.FLAG_PSA,
            @ModalidadJustifica = C.MODALIDAD_JUSTIFICA,
            @TipoAfectacion     = C.TIPO_AFECTACION
        FROM dbo.SIG_CUADRO_ADQUISICION AS C WITH (UPDLOCK, HOLDLOCK)
        WHERE C.ANO_EJE    = @AnoEje
          AND C.SEC_EJEC   = @SecEjec
          AND C.TIPO_BIEN  = @TipoBien
          AND C.SEC_CUADRO = @SecCuadro
          AND C.NRO_ORDEN IS NULL;

        IF @TipoPpto IS NULL
            RAISERROR('El cuadro no existe, no es de servicios o ya tiene una orden.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.SIG_CONTRATISTAS
            WHERE PROVEEDOR = @Proveedor
              AND COALESCE(ESTADO, 'A') <> 'I'
        )
            RAISERROR('El proveedor no existe o esta inactivo.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.SIG_DETALLE_BSERV_CUADRO
            WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
              AND TIPO_BIEN = @TipoBien AND SEC_CUADRO = @SecCuadro
        )
            RAISERROR('El cuadro no contiene servicios aprobados.', 16, 1);

        IF EXISTS
        (
            SELECT 1
            FROM dbo.SIG_DETALLE_METAS_CUADRO M
            WHERE M.ANO_EJE = @AnoEje AND M.SEC_EJEC = @SecEjec
              AND M.TIPO_BIEN = @TipoBien AND M.SEC_CUADRO = @SecCuadro
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.SIG_DETALLE_BSERV_CUADRO D
                  WHERE D.ANO_EJE = M.ANO_EJE AND D.SEC_EJEC = M.SEC_EJEC
                    AND D.TIPO_BIEN = M.TIPO_BIEN AND D.SEC_CUADRO = M.SEC_CUADRO
                    AND D.SECUENCIA = M.SECUENCIA
              )
        )
            RAISERROR('Hay metas del cuadro sin un item de servicio correspondiente.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.SIG_DETALLE_METAS_CUADRO
            WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
              AND TIPO_BIEN = @TipoBien AND SEC_CUADRO = @SecCuadro
        )
            RAISERROR('El cuadro no tiene distribucion presupuestal.', 16, 1);

        SELECT
            @TotalMoneda = SUM(COALESCE(VALOR_MONEDA, 0)),
            @TotalSoles  = SUM(COALESCE(VALOR_SOLES, 0))
        FROM dbo.SIG_DETALLE_BSERV_CUADRO
        WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
          AND TIPO_BIEN = @TipoBien AND SEC_CUADRO = @SecCuadro;

        SET @SubtotalMoneda = COALESCE(@SubtotalMoneda, @TotalMoneda);
        SET @TotalIgvMoneda = COALESCE(@TotalIgvMoneda, 0);
        SET @SubtotalSoles  = COALESCE(@SubtotalSoles, @TotalSoles);
        SET @TotalIgvSoles  = COALESCE(@TotalIgvSoles, 0);

        SELECT @NroOrden = COALESCE(MAX(NRO_ORDEN), 0) + 1
        FROM dbo.SIG_ORDEN_ADQUISICION WITH (UPDLOCK, HOLDLOCK)
        WHERE ANO_EJE = @AnoEje
          AND SEC_EJEC = @SecEjec
          AND TIPO_BIEN = @TipoBien;

        /* El cuadro queda enlazado a la nueva orden. Sus triggers mantienen seguimiento. */
        UPDATE dbo.SIG_CUADRO_ADQUISICION
           SET ESTADO     = '2',
               NRO_ORDEN  = @NroOrden,
               CUSER_MOD  = @Usuario,
               EQUIPO_MOD = @Equipo
         WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
           AND TIPO_BIEN = @TipoBien AND SEC_CUADRO = @SecCuadro;

        INSERT INTO dbo.SIG_ORDEN_ADQUISICION
        (
            ANO_EJE, SEC_EJEC, NRO_ORDEN, TIPO_BIEN, TIPO_PPTO,
            TIPO_USO, NRO_ENCARGO, SEC_EJEC2, ANO_CUADRO, SEC_CUADRO,
            TIPO_PROVEEDOR, PROVEEDOR, MES_CALEND, FECHA_ORDEN,
            PLAZO_ENTREGA, CONDICION_PAGO, DOCUM_REFERENCIA,
            MONEDA, TIPO_CAMBIO, CONCEPTO, INCL_IGV, TASA_IMPTO,
            SUBTOTAL_MONEDA, TOTAL_IGV_MONEDA, TOTAL_FACT_MONEDA,
            SUBTOTAL_SOLES, TOTAL_IGV_SOLES, TOTAL_FACT_SOLES,
            ESTADO, ESTADO_SIAF, TIPO_PROCESO, TIPO_OPERACION,
            TIPO_COMPRA, MODAL_COMPRA, CUSER_ID, EQUIPO_REG,
            FLAG_RECEPCION, TIPO_ORGANISMO, FLAG_TESORO, TIPO_ENTIDAD,
            ID_PROCESO, ID_CONTRATO, FLAG_PSA, MODALIDAD_JUSTIFICA,
            TIPO_AFECTACION
        )
        VALUES
        (
            @AnoEje, @SecEjec, @NroOrden, @TipoBien, @TipoPpto,
            @TipoUso, @NroEncargo, @SecEjec2, @AnoEje, @SecCuadro,
            @TipoProveedor, @Proveedor, @MesCalend, @FechaOrden,
            @PlazoEntrega, @CondicionPago, @DocumentoReferencia,
            @Moneda, @TipoCambio, @Concepto, @IncluyeIgv, @TasaImpuesto,
            @SubtotalMoneda, @TotalIgvMoneda, @TotalMoneda,
            @SubtotalSoles, @TotalIgvSoles, @TotalSoles,
            '0', '0', @TipoProceso, @TipoOperacion,
            @TipoCompra, @ModalCompra, @Usuario, @Equipo,
            'N', @TipoOrganismo, @FlagTesoro, @TipoEntidad,
            @IdProceso, @IdContrato, COALESCE(@FlagPsa, 'N'),
            @ModalidadJustifica, @TipoAfectacion
        );

        INSERT INTO dbo.SIG_ORDEN_SECUENCIA
        (
            ANO_EJE, SEC_EJEC, NRO_ORDEN, TIPO_BIEN, TIPO_PPTO,
            SEC_ORDEN, ANO_SECUENCIA, MES_SECUENCIA, TIPO_CAMBIO,
            FASE_ORDEN, ESTADO_FASE, FECHA_ESTADO, FECHA_REG,
            CUSER_ID, EQUIPO_REG, FLAG_COMPROMETIDO
        )
        VALUES
        (
            @AnoEje, @SecEjec, @NroOrden, @TipoBien, @TipoPpto,
            1, @AnoEje, @MesCalend, @TipoCambio,
            'C', '0', GETDATE(), GETDATE(),
            @Usuario, @Equipo, 'N'
        );

        INSERT INTO dbo.SIG_ORDEN_ITEM
        (
            ANO_EJE, SEC_EJEC, NRO_ORDEN, TIPO_BIEN, TIPO_PPTO,
            SEC_ORDEN, SEC_ITEM, GRUPO_BIEN, CLASE_BIEN,
            FAMILIA_BIEN, ITEM_BIEN, CANT_ITEM, UNIDAD_MEDIDA,
            PREC_UNIT_MONEDA, PREC_TOT_MONEDA, PREC_TOT_SOLES,
            FECHA_REG, CUSER_ID, EQUIPO_REG, ESPECIFICACIONES,
            FLAG_EXO_IMPTO
        )
        SELECT
            @AnoEje, @SecEjec, @NroOrden, @TipoBien, @TipoPpto,
            1, CONVERT(numeric(4,0), D.SECUENCIA), D.GRUPO_BIEN,
            D.CLASE_BIEN, D.FAMILIA_BIEN, D.ITEM_BIEN,
            D.CANT_APROBADA, D.UNIDAD_MEDIDA, D.PRECIO_UNIT,
            D.VALOR_MONEDA, D.VALOR_SOLES,
            GETDATE(), @Usuario, @Equipo, @Especificaciones,
            CASE WHEN COALESCE(D.VALOR_IMPTO, 0) = 0 THEN ' ' ELSE 'N' END
        FROM dbo.SIG_DETALLE_BSERV_CUADRO D
        WHERE D.ANO_EJE = @AnoEje AND D.SEC_EJEC = @SecEjec
          AND D.TIPO_BIEN = @TipoBien AND D.SEC_CUADRO = @SecCuadro;

        ;WITH ItemPpto AS
        (
            SELECT
                M.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY M.SECUENCIA
                    ORDER BY M.ORIGEN, M.FUENTE_FINANC, M.SEC_FUNC,
                             M.CLASIFICADOR, M.OPERACION
                ) AS SEC_ITEM_PPTO_NUEVA
            FROM dbo.SIG_DETALLE_METAS_CUADRO M
            WHERE M.ANO_EJE = @AnoEje AND M.SEC_EJEC = @SecEjec
              AND M.TIPO_BIEN = @TipoBien AND M.SEC_CUADRO = @SecCuadro
        )
        INSERT INTO dbo.SIG_ORDEN_ITEM_PPTO
        (
            ANO_EJE, SEC_EJEC, NRO_ORDEN, TIPO_BIEN, TIPO_PPTO,
            SEC_ORDEN, SEC_ITEM, SEC_ITEM_PPTO, ORIGEN, FUENTE_FINANC,
            TIPO_RECURSO, TIPO_PAGO, TIPO_COMPROMISO, SEC_FUNC,
            OPERACION, CLASIFICADOR, TIPO_DESTINO, MODAL_DESTINO,
            FLAG_DESTINO, CANT_ARTICULO, VALOR_MONEDA, VALOR_SOLES,
            MNTO_MONEDA, MNTO_SOLES, TIPO_IMPTO, FTE_FTO_IMPTO,
            TASA_IMPTO, VALOR_IMPTO_MONEDA, VALOR_IMPTO_SOLES,
            FECHA_REG, CUSER_ID, EQUIPO_REG, EXPEDIENTE,
            SEC_FUNC_ENCARGO, TIPO_PAGO_IMPTO, TIPO_RECURSO_IMPTO,
            TIPO_COMPROMISO_IMPTO, TIPO_USO, ID_CLASIFICADOR
        )
        SELECT
            @AnoEje, @SecEjec, @NroOrden, @TipoBien, @TipoPpto,
            1, CONVERT(numeric(4,0), M.SECUENCIA),
            CONVERT(numeric(3,0), M.SEC_ITEM_PPTO_NUEVA),
            M.ORIGEN, M.FUENTE_FINANC, M.TIPO_RECURSO,
            M.TIPO_PAGO, M.TIPO_COMPROMISO, M.SEC_FUNC,
            M.OPERACION, M.CLASIFICADOR, M.TIPO_DESTINO,
            M.MODAL_DESTINO, M.FLAG_DESTINO, M.CANT_APROBADA,
            M.VALOR_MONEDA, M.VALOR_SOLES, M.MNTO_MONEDA,
            M.MNTO_SOLES, M.TIPO_IMPUESTO, M.FTE_FTO_IMPTO,
            M.TASA_IMPTO, M.VALOR_IMPTO_MON, M.VALOR_IMPTO_SOL,
            GETDATE(), @Usuario, @Equipo, M.EXPEDIENTE,
            M.SEC_FUNC_ENCARGO, M.TIPO_PAGO_IMPTO,
            M.TIPO_RECURSO_IMPTO, M.TIPO_COMPROMISO_IMPTO,
            M.TIPO_USO, M.ID_CLASIFICADOR
        FROM ItemPpto M;

        ;WITH PptoAgrupado AS
        (
            SELECT
                M.ORIGEN, M.FUENTE_FINANC, M.SEC_FUNC,
                M.TIPO_RECURSO, M.TIPO_PAGO, M.TIPO_COMPROMISO,
                M.OPERACION, M.CLASIFICADOR, M.TIPO_DESTINO,
                M.MODAL_DESTINO, M.EXPEDIENTE, M.SEC_FUNC_ENCARGO,
                M.CICLO, M.FASE, M.SECUENCIA_EXPEDIENTE,
                M.CORRELATIVO, M.ID_CLASIFICADOR,
                SUM(COALESCE(M.VALOR_MONEDA, 0)) AS VALOR_MONEDA,
                SUM(COALESCE(M.VALOR_SOLES, 0)) AS VALOR_SOLES,
                SUM(COALESCE(M.MNTO_MONEDA, 0)) AS MNTO_MONEDA,
                SUM(COALESCE(M.MNTO_SOLES, 0)) AS MNTO_SOLES
            FROM dbo.SIG_DETALLE_METAS_CUADRO M
            WHERE M.ANO_EJE = @AnoEje AND M.SEC_EJEC = @SecEjec
              AND M.TIPO_BIEN = @TipoBien AND M.SEC_CUADRO = @SecCuadro
            GROUP BY
                M.ORIGEN, M.FUENTE_FINANC, M.SEC_FUNC,
                M.TIPO_RECURSO, M.TIPO_PAGO, M.TIPO_COMPROMISO,
                M.OPERACION, M.CLASIFICADOR, M.TIPO_DESTINO,
                M.MODAL_DESTINO, M.EXPEDIENTE, M.SEC_FUNC_ENCARGO,
                M.CICLO, M.FASE, M.SECUENCIA_EXPEDIENTE,
                M.CORRELATIVO, M.ID_CLASIFICADOR
        ), PptoNumerado AS
        (
            SELECT *, ROW_NUMBER() OVER
            (
                ORDER BY ORIGEN, FUENTE_FINANC, SEC_FUNC,
                         CLASIFICADOR, OPERACION
            ) AS SEC_PPTO_NUEVA
            FROM PptoAgrupado
        )
        INSERT INTO dbo.SIG_ORDEN_PRESUPUESTO
        (
            ANO_EJE, SEC_EJEC, NRO_ORDEN, TIPO_BIEN, TIPO_PPTO,
            SEC_ORDEN, SEC_PPTO, ORIGEN, FUENTE_FINANC, SEC_FUNC,
            TIPO_RECURSO, TIPO_PAGO, TIPO_COMPROMISO, MES_CALE,
            OPERACION, CLASIFICADOR, TIPO_DESTINO, MODAL_DESTINO,
            VALOR_MONEDA, VALOR_SOLES, MNTO_MONEDA, MNTO_SOLES,
            EXPEDIENTE, SEC_FUNC_ENCARGO, CICLO, FASE,
            SECUENCIA_EXPEDIENTE, CORRELATIVO, ID_CLASIFICADOR
        )
        SELECT
            @AnoEje, @SecEjec, @NroOrden, @TipoBien, @TipoPpto,
            1, CONVERT(numeric(3,0), P.SEC_PPTO_NUEVA),
            P.ORIGEN, P.FUENTE_FINANC, P.SEC_FUNC,
            P.TIPO_RECURSO, P.TIPO_PAGO, P.TIPO_COMPROMISO,
            @MesCalend, P.OPERACION, P.CLASIFICADOR,
            P.TIPO_DESTINO, P.MODAL_DESTINO,
            P.VALOR_MONEDA, P.VALOR_SOLES,
            P.MNTO_MONEDA, P.MNTO_SOLES,
            P.EXPEDIENTE, P.SEC_FUNC_ENCARGO, P.CICLO, P.FASE,
            P.SECUENCIA_EXPEDIENTE, P.CORRELATIVO, P.ID_CLASIFICADOR
        FROM PptoNumerado P;

        COMMIT TRANSACTION;

        SELECT
            @AnoEje AS ANO_EJE,
            @SecEjec AS SEC_EJEC,
            @NroOrden AS NRO_ORDEN,
            @TipoBien AS TIPO_BIEN,
            @TipoPpto AS TIPO_PPTO,
            @SecCuadro AS SEC_CUADRO,
            'PENDIENTE' AS RESULTADO;
    END TRY
    BEGIN CATCH
        DECLARE
            @MensajeError nvarchar(4000),
            @SeveridadError int,
            @EstadoError int;

        SELECT
            @MensajeError = ERROR_MESSAGE(),
            @SeveridadError = ERROR_SEVERITY(),
            @EstadoError = ERROR_STATE();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        RAISERROR(@MensajeError, @SeveridadError, @EstadoError);
        RETURN;
    END CATCH;
END;
GO

/*
-- PRUEBA DE HOMOLOGACION SIN PERSISTIR DATOS
DECLARE @Orden numeric(7,0);

BEGIN TRANSACTION;

EXEC dbo.usp_ext_crear_orden_servicio_desde_cuadro
     @AnoEje = 2026,
     @SecEjec = 1750,
     @SecCuadro = 999999,        -- Reemplazar por un cuadro de prueba elegible
     @Proveedor = 99999,         -- Reemplazar por un proveedor de prueba
     @FechaOrden = '2026-08-10',
     @Usuario = 'USUARIO_EXT',
     @Equipo = 'SISTEMA_EXTERNO',
     @Concepto = 'PRUEBA DE INTEGRACION',
     @NroOrden = @Orden OUTPUT;

SELECT @Orden AS NRO_ORDEN_GENERADO;

-- Validar las seis tablas antes de finalizar la prueba.
SELECT * FROM dbo.SIG_ORDEN_ADQUISICION
 WHERE ANO_EJE=2026 AND SEC_EJEC=1750 AND NRO_ORDEN=@Orden AND TIPO_BIEN='S';
SELECT * FROM dbo.SIG_ORDEN_SECUENCIA
 WHERE ANO_EJE=2026 AND SEC_EJEC=1750 AND NRO_ORDEN=@Orden AND TIPO_BIEN='S';
SELECT * FROM dbo.SIG_ORDEN_ITEM
 WHERE ANO_EJE=2026 AND SEC_EJEC=1750 AND NRO_ORDEN=@Orden AND TIPO_BIEN='S';
SELECT * FROM dbo.SIG_ORDEN_ITEM_PPTO
 WHERE ANO_EJE=2026 AND SEC_EJEC=1750 AND NRO_ORDEN=@Orden AND TIPO_BIEN='S';
SELECT * FROM dbo.SIG_ORDEN_PRESUPUESTO
 WHERE ANO_EJE=2026 AND SEC_EJEC=1750 AND NRO_ORDEN=@Orden AND TIPO_BIEN='S';
SELECT * FROM dbo.SIG_CUADRO_ADQUISICION
 WHERE ANO_EJE=2026 AND SEC_EJEC=1750 AND TIPO_BIEN='S' AND SEC_CUADRO=999999;

ROLLBACK TRANSACTION;
*/
