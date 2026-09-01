USE [SIGA_1750];
GO

/*
  Autoriza un pedido de requerimiento de servicios (TIPO_PEDIDO=2) y genera
  su cuadro de adquisicion pendiente de orden.

  En ANIN 26.01.00 no hay pantalla que haga este puente: Pedidos Consolidados
  exige FLAG_PEDIDO=1 (cero filas en 2026) y Cuadro de Adquisicion no ofrece
  Alta al perfil logistico de consulta. SGCM llama este procedimiento.

  Idempotente: si ya existe cuadro de servicios para NRO_REQUER sin NRO_ORDEN,
  devuelve ese SEC_CUADRO. Si el cuadro ya tiene orden, falla.

  La cabecera, el item y la meta se clonan de un cuadro real de la ejecutora
  para no dejar columnas fuera del patron de SIGA; luego se sobrescriben los
  valores del pedido.
*/
IF OBJECT_ID('dbo.usp_ext_crear_cuadro_adquisicion_desde_pedido', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ext_crear_cuadro_adquisicion_desde_pedido;
GO

CREATE PROCEDURE dbo.usp_ext_crear_cuadro_adquisicion_desde_pedido
    @AnoEje     numeric(4,0),
    @SecEjec    numeric(6,0),
    @NroPedido  varchar(6),
    @Usuario    varchar(30),
    @Equipo     varchar(20) = NULL,
    @SecCuadro  numeric(6,0) OUTPUT,
    @NroCuadro  numeric(6,0) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @TipoBien      varchar(1)    = 'S',
        @TipoPedido    char(1)       = '2',
        @NroRequer     numeric(10,0),
        @SecCuadroRef  numeric(6,0),
        @CentroCosto   varchar(15),
        @Empleado      varchar(15),
        @Descripcion   varchar(250),
        @FechaPedido   datetime,
        @MesPedido     char(2),
        @TipoPpto      numeric(1,0),
        @TipoUso       varchar(1),
        @Moneda        varchar(6),
        @SecFunc       numeric(4,0),
        @ActProy       varchar(7),
        @TipoRecurso   varchar(2),
        @OrigenFto     varchar(1),
        @FuenteFto     varchar(2),
        @Secuencia     numeric(4,0),
        @GrupoBien     varchar(2),
        @ClaseBien     varchar(2),
        @FamiliaBien   varchar(4),
        @ItemBien      varchar(4),
        @UnidadMedida  numeric(3,0),
        @Cantidad      numeric(20,6),
        @PrecioUnit    numeric(16,6),
        @Clasificador  varchar(20),
        @IdClasific    varchar(15),
        @ValorTotal    numeric(20,2),
        @Funcion       varchar(2),
        @Programa      varchar(3),
        @CategGasto    numeric(1,0),
        @GrupoGasto    numeric(1,0),
        @ResultadoLock int,
        @RecursoLock   nvarchar(255),
        @NroOrdenEx    numeric(7,0);

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
    BEGIN
        RAISERROR('El usuario de auditoria es obligatorio.', 16, 1);
        RETURN;
    END;

    SET @NroPedido = RIGHT('000000' + LTRIM(RTRIM(@NroPedido)), 6);
    IF @NroPedido LIKE '%[^0-9]%' OR NULLIF(@NroPedido, '') IS NULL
    BEGIN
        RAISERROR('El numero de pedido no es numerico.', 16, 1);
        RETURN;
    END;
    SET @NroRequer = CONVERT(numeric(10,0), @NroPedido);

    IF @Equipo IS NULL
        SET @Equipo = LEFT(COALESCE(HOST_NAME(), 'EXTERNO'), 20);

    SELECT @SecCuadro = C.SEC_CUADRO,
           @NroCuadro = C.NRO_CUADRO,
           @NroOrdenEx = C.NRO_ORDEN
      FROM dbo.SIG_CUADRO_ADQUISICION AS C
     WHERE C.ANO_EJE = @AnoEje AND C.SEC_EJEC = @SecEjec
       AND C.TIPO_BIEN = @TipoBien AND C.NRO_REQUER = @NroRequer;

    IF @SecCuadro IS NOT NULL
    BEGIN
        IF @NroOrdenEx IS NOT NULL
        BEGIN
            RAISERROR('El cuadro del pedido ya tiene una orden de servicio.', 16, 1);
            RETURN;
        END;
        RETURN;
    END;

    SELECT @CentroCosto = p.CENTRO_COSTO,
           @Empleado    = p.EMPLEADO,
           @Descripcion = LEFT(LTRIM(RTRIM(CONVERT(varchar(400), p.MOTIVO_PEDIDO))), 250),
           @FechaPedido = p.FECHA_PEDIDO,
           @MesPedido   = COALESCE(NULLIF(p.MES_PEDIDO, ''),
                                   RIGHT('0' + CONVERT(varchar(2), MONTH(p.FECHA_PEDIDO)), 2)),
           @TipoPpto    = p.TIPO_PPTO,
           @TipoUso     = COALESCE(p.TIPO_USO, 'C'),
           @Moneda      = COALESCE(p.MONEDA, 'S/.'),
           @SecFunc     = p.sec_func,
           @ActProy     = p.ACT_PROY,
           @TipoRecurso = COALESCE(p.tipo_recurso, '1'),
           @OrigenFto   = COALESCE(p.origen_fto, '1'),
           @FuenteFto   = COALESCE(p.fuente_fto, '00')
      FROM dbo.SIG_PEDIDOS AS p
     WHERE p.ANO_EJE = @AnoEje AND p.SEC_EJEC = @SecEjec
       AND p.NRO_PEDIDO = @NroPedido AND p.TIPO_PEDIDO = @TipoPedido
       AND p.TIPO_BIEN = @TipoBien;

    IF @CentroCosto IS NULL
    BEGIN
        RAISERROR('No existe el pedido de servicio indicado.', 16, 1);
        RETURN;
    END;

    SELECT TOP 1
           @Secuencia    = d.SECUENCIA,
           @GrupoBien    = d.GRUPO_BIEN,
           @ClaseBien    = d.CLASE_BIEN,
           @FamiliaBien  = d.FAMILIA_BIEN,
           @ItemBien     = d.ITEM_BIEN,
           @UnidadMedida = d.UNIDAD_MEDIDA,
           @Cantidad     = d.CANT_SOLICITADA,
           @PrecioUnit   = COALESCE(NULLIF(d.PRECIO_UNIT, 0), 1),
           @Clasificador = d.CLASIFICADOR,
           @IdClasific   = d.ID_CLASIFICADOR
      FROM dbo.SIG_DETALLE_PEDIDOS AS d
     WHERE d.ANO_EJE = @AnoEje AND d.sec_ejec = @SecEjec
       AND d.NRO_PEDIDO = @NroPedido AND d.TIPO_PEDIDO = @TipoPedido
       AND d.TIPO_BIEN = @TipoBien
     ORDER BY d.SECUENCIA;

    IF @Secuencia IS NULL
    BEGIN
        RAISERROR('El pedido no tiene detalle.', 16, 1);
        RETURN;
    END;

    SET @ValorTotal = CONVERT(numeric(20,2), @Cantidad * @PrecioUnit);

    SELECT TOP 1 @SecCuadroRef = C.SEC_CUADRO
      FROM dbo.SIG_CUADRO_ADQUISICION AS C
     WHERE C.ANO_EJE = @AnoEje AND C.SEC_EJEC = @SecEjec AND C.TIPO_BIEN = @TipoBien
       AND EXISTS (SELECT 1 FROM dbo.SIG_DETALLE_BSERV_CUADRO AS I
                    WHERE I.ANO_EJE = C.ANO_EJE AND I.SEC_EJEC = C.SEC_EJEC
                      AND I.TIPO_BIEN = C.TIPO_BIEN AND I.SEC_CUADRO = C.SEC_CUADRO)
       AND EXISTS (SELECT 1 FROM dbo.SIG_DETALLE_METAS_CUADRO AS M
                    WHERE M.ANO_EJE = C.ANO_EJE AND M.sec_ejec = C.SEC_EJEC
                      AND M.TIPO_BIEN = C.TIPO_BIEN AND M.SEC_CUADRO = C.SEC_CUADRO)
     ORDER BY CASE WHEN C.SEC_CUADRO = 83 THEN 0 ELSE 1 END,
              CASE WHEN C.TIPO_PROCESO = '14' THEN 0 ELSE 1 END,
              C.SEC_CUADRO;

    IF @SecCuadroRef IS NULL
    BEGIN
        RAISERROR('No hay un cuadro de servicios de referencia en la ejecutora.', 16, 1);
        RETURN;
    END;

    SELECT TOP 1
           @Funcion    = m.FUNCION,
           @Programa   = m.PROGRAMA,
           @CategGasto = m.CATEG_GASTO,
           @GrupoGasto = m.GRUPO_GASTO
      FROM dbo.SIG_DETALLE_METAS_CUADRO AS m
     WHERE m.ANO_EJE = @AnoEje AND m.sec_ejec = @SecEjec
       AND m.sec_func = @SecFunc AND m.FUNCION IS NOT NULL
     ORDER BY m.SEC_CUADRO DESC;

    IF @Funcion IS NULL
        SELECT TOP 1
               @Funcion    = m.FUNCION,
               @Programa   = m.PROGRAMA,
               @CategGasto = m.CATEG_GASTO,
               @GrupoGasto = m.GRUPO_GASTO
          FROM dbo.SIG_DETALLE_METAS_CUADRO AS m
         WHERE m.ANO_EJE = @AnoEje AND m.sec_ejec = @SecEjec
           AND m.TIPO_BIEN = @TipoBien AND m.SEC_CUADRO = @SecCuadroRef
         ORDER BY m.SECUENCIA, m.SEC_META;

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;

        CREATE TABLE #SIG_SESION
        (
            CUSER_ID   varchar(30) NOT NULL,
            EQUIPO_REG varchar(20) NULL
        );
        INSERT INTO #SIG_SESION(CUSER_ID, EQUIPO_REG) VALUES (@Usuario, @Equipo);

        SET @RecursoLock = 'SIGA_CUADRO_' + CONVERT(varchar(4), @AnoEje)
                         + '_' + CONVERT(varchar(6), @SecEjec);

        EXEC @ResultadoLock = sys.sp_getapplock
             @Resource = @RecursoLock,
             @LockMode = 'Exclusive',
             @LockOwner = 'Transaction',
             @LockTimeout = 15000;

        IF @ResultadoLock < 0
            RAISERROR('No se pudo reservar la numeracion del cuadro de adquisicion.', 16, 1);

        SELECT @SecCuadro = C.SEC_CUADRO, @NroCuadro = C.NRO_CUADRO, @NroOrdenEx = C.NRO_ORDEN
          FROM dbo.SIG_CUADRO_ADQUISICION AS C WITH (UPDLOCK, HOLDLOCK)
         WHERE C.ANO_EJE = @AnoEje AND C.SEC_EJEC = @SecEjec
           AND C.TIPO_BIEN = @TipoBien AND C.NRO_REQUER = @NroRequer;

        IF @SecCuadro IS NOT NULL
        BEGIN
            IF @NroOrdenEx IS NOT NULL
                RAISERROR('El cuadro del pedido ya tiene una orden de servicio.', 16, 1);
            COMMIT TRANSACTION;
            RETURN;
        END;

        SELECT @SecCuadro = COALESCE(MAX(SEC_CUADRO), 0) + 1
          FROM dbo.SIG_CUADRO_ADQUISICION WITH (UPDLOCK, HOLDLOCK)
         WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec AND TIPO_BIEN = @TipoBien;

        SELECT @NroCuadro = COALESCE(MAX(NRO_CUADRO), 0) + 1
          FROM dbo.SIG_CUADRO_ADQUISICION
         WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec AND TIPO_BIEN = @TipoBien;

        SELECT TOP 1 * INTO #cab
          FROM dbo.SIG_CUADRO_ADQUISICION
         WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
           AND TIPO_BIEN = @TipoBien AND SEC_CUADRO = @SecCuadroRef;

        UPDATE #cab
           SET SEC_CUADRO       = @SecCuadro,
               NRO_CUADRO       = @NroCuadro,
               ANO_REQUER       = @AnoEje,
               NRO_REQUER       = @NroRequer,
               CENTRO_COSTO     = @CentroCosto,
               EMPLEADO         = @Empleado,
               DESCRIPCION      = @Descripcion,
               TIPO_PPTO        = @TipoPpto,
               TIPO_USO         = @TipoUso,
               MONEDA           = @Moneda,
               VALOR_TOTAL      = @ValorTotal,
               ESTADO           = '1',
               NRO_ORDEN        = NULL,
               PROVEEDOR        = NULL,
               NRO_CONS_PAAC    = NULL,
               FECHA_CUADRO     = @FechaPedido,
               FECHA_AUTORIZ    = @FechaPedido,
               FECHA_NRO_CUADRO = @FechaPedido,
               FECHA_COMPRA     = @FechaPedido,
               fecha_pedido     = @FechaPedido,
               MES_CALEND       = @MesPedido,
               FECHA_REG        = GETDATE(),
               CUSER_ID         = @Usuario,
               EQUIPO_REG       = @Equipo,
               FECHA_MOD        = NULL,
               CUSER_MOD        = NULL,
               EQUIPO_MOD       = NULL;

        INSERT INTO dbo.SIG_CUADRO_ADQUISICION SELECT * FROM #cab;

        SELECT TOP 1 * INTO #item
          FROM dbo.SIG_DETALLE_BSERV_CUADRO
         WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
           AND TIPO_BIEN = @TipoBien AND SEC_CUADRO = @SecCuadroRef
         ORDER BY SECUENCIA;

        UPDATE #item
           SET SEC_CUADRO      = @SecCuadro,
               SECUENCIA       = 1,
               GRUPO_BIEN      = @GrupoBien,
               CLASE_BIEN      = @ClaseBien,
               FAMILIA_BIEN    = @FamiliaBien,
               ITEM_BIEN       = @ItemBien,
               UNIDAD_MEDIDA   = @UnidadMedida,
               CANT_SOLICITADA = @Cantidad,
               CANT_APROBADA   = @Cantidad,
               PRECIO_UNIT     = @PrecioUnit,
               VALOR_MONEDA    = @ValorTotal,
               VALOR_SOLES     = @ValorTotal,
               VALOR_IMPTO     = 0,
               nro_pedido      = @NroPedido,
               sec_item_pedido = @Secuencia,
               tipo_pedido     = @TipoPedido,
               NRO_CONS_PAAC   = NULL,
               FECHA_REG       = GETDATE(),
               CUSER_ID        = @Usuario,
               EQUIPO_REG      = @Equipo;

        INSERT INTO dbo.SIG_DETALLE_BSERV_CUADRO SELECT * FROM #item;

        SELECT TOP 1 * INTO #meta
          FROM dbo.SIG_DETALLE_METAS_CUADRO
         WHERE ANO_EJE = @AnoEje AND sec_ejec = @SecEjec
           AND TIPO_BIEN = @TipoBien AND SEC_CUADRO = @SecCuadroRef
         ORDER BY SECUENCIA, SEC_META;

        UPDATE #meta
           SET SEC_CUADRO      = @SecCuadro,
               SECUENCIA       = 1,
               SEC_META        = 1,
               sec_func        = @SecFunc,
               FUNCION         = @Funcion,
               PROGRAMA        = @Programa,
               ACT_PROY        = @ActProy,
               ORIGEN          = @OrigenFto,
               FUENTE_FINANC   = @FuenteFto,
               TIPO_RECURSO    = @TipoRecurso,
               CATEG_GASTO     = @CategGasto,
               GRUPO_GASTO     = @GrupoGasto,
               CLASIFICADOR    = @Clasificador,
               ID_CLASIFICADOR = @IdClasific,
               CANT_SOLICITADA = @Cantidad,
               CANT_APROBADA   = @Cantidad,
               MNTO_MONEDA     = @ValorTotal,
               MNTO_SOLES      = @ValorTotal,
               VALOR_MONEDA    = @ValorTotal,
               VALOR_SOLES     = @ValorTotal,
               TIPO_USO        = @TipoUso,
               TIPO_USO_ORIG   = @TipoUso,
               FECHA_REG       = GETDATE(),
               CUSER_ID        = @Usuario,
               EQUIPO_REG      = @Equipo;

        INSERT INTO dbo.SIG_DETALLE_METAS_CUADRO SELECT * FROM #meta;

        UPDATE dbo.SIG_DETALLE_PEDIDOS
           SET CANT_APROBADA = @Cantidad,
               ESTADO_COMPRA = '1',
               NRO_CUADRO    = @NroCuadro,
               FECHA_CUADRO  = @FechaPedido,
               FECHA_APROB   = @FechaPedido
         WHERE ANO_EJE = @AnoEje AND sec_ejec = @SecEjec
           AND NRO_PEDIDO = @NroPedido AND TIPO_PEDIDO = @TipoPedido
           AND TIPO_BIEN = @TipoBien;

        UPDATE dbo.SIG_PEDIDOS
           SET FECHA_APROB = @FechaPedido
         WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
           AND NRO_PEDIDO = @NroPedido AND TIPO_PEDIDO = @TipoPedido
           AND TIPO_BIEN = @TipoBien;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        DECLARE @msg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR('%s', 16, 1, @msg);
        RETURN;
    END CATCH
END
GO
