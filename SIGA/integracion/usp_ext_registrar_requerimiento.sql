USE [SIGA_1750];
GO

/*
===============================================================================
  usp_ext_registrar_requerimiento
  Registro de un requerimiento (pedido) de SIGA a partir de items del Cuadro
  Multianual de Necesidades ya vigentes.

  IMPORTANTE
  - Se entrega para homologacion; no se instala automaticamente.
  - Deja el requerimiento en ESTADO='0' (registrado). NO aprueba, no genera
    orden, no toca presupuesto ni SIAF.
  - SQL compatible con el nivel de compatibilidad 100 de SIGA_1750: sin JSON,
    sin funciones posteriores a 2008. La entrada de items viaja como XML.

  -----------------------------------------------------------------------------
  QUE ES UN REQUERIMIENTO EN SIGA, SEGUN LOS DATOS DE SIGA_1750
  -----------------------------------------------------------------------------
  Cabecera : SIG_PEDIDOS         con TIPO_PEDIDO='2'
  Detalle  : SIG_DETALLE_PEDIDOS
  Enlace al CMN: las columnas CENTRO_COSTO, SEC_CUADRO, SEC_ITEM, ANNO_PROG y
  SEC_CUA_MOD_SAL del detalle, que apuntan a SIG_CUADRO_MODIFICADO_DET.

  En el ejercicio 2026 de la ejecutora 1750 ese enlace esta al 100 %:
      TIPO_PEDIDO='2', TIPO_BIEN='S' -> 6855 lineas, 6855 con enlace al CMN
      TIPO_PEDIDO='2', TIPO_BIEN='B' ->  423 lineas,  423 con enlace al CMN
      TIPO_PEDIDO='1'                -> 3101 lineas,    0 con enlace (almacen)
  Por eso un requerimiento generado desde el SIGCM siempre nace de un item del
  CMN: sin SEC_CUA_MOD_SAL no hay requerimiento valido.

  -----------------------------------------------------------------------------
  QUE ITEM DEL CMN SE PUEDE PEDIR
  -----------------------------------------------------------------------------
  La regla no es inventada: es la del propio cliente SIGA, extraida del SQL
  embebido en sig_aba_dawi21_te.pbd (la ventana que elige items para el pedido):

      SIG_CUADRO_MODIFICADO_DET.MOTIVO_SOLICITUD IN ('0','3')
      SIG_CUADRO_MODIFICADO_DET.ESTADO NOT IN ('E','ET','IC')
      AND EXISTS (SELECT 1 FROM SIG_CUADRO_MODIFICADO_SALDO
                   WHERE ... SEC_CUA_MOD_SAL = SIG_CUADRO_MODIFICADO_DET.SEC_CUA_MOD_SAL
                     AND (CANT_TOTAL - CANT_TOTAL_CMN) > 0)

  De ahi salen las tres validaciones del procedimiento:
    1. El item no puede estar excluido (E), excluido por transferencia (ET) ni
       anulado (IC).
    2. El item no puede tener una solicitud de modificacion abierta: solo pasan
       MOTIVO_SOLICITUD '0' (estable) y '3' (modificacion de cantidades).
       Un item recien incluido queda en MOTIVO_SOLICITUD='1' y NO es pedible
       hasta que la solicitud se aprueba y SIGA lo devuelve a '0'.
    3. El saldo disponible es CANT_TOTAL - CANT_TOTAL_CMN, y tiene que alcanzar.

  -----------------------------------------------------------------------------
  COMO SE CONSUME EL SALDO
  -----------------------------------------------------------------------------
  SIG_CUADRO_MODIFICADO_SALDO lleva tres cubetas por mes y un total de cada una:
      CANT_xx      cantidad programada en el CMN
      CANT_xx_CMN  cantidad ya comprometida por requerimientos
      CANT_xx_SC   cantidad "sin cuadro"
  El cliente SIGA acumula con  CANT_xx_CMN = CANT_xx_CMN + n  (sig_aba_wind30).

  Dos invariantes verificadas sobre las 28 904 filas de saldo del 2026, sin una
  sola excepcion:
      CANT_TOTAL     = suma de los doce CANT_xx
      CANT_TOTAL_CMN = suma de los doce CANT_xx_CMN
  Este procedimiento las conserva.

  El mes que se consume NO es el mes del pedido. En los datos reales, un pedido
  de julio descuenta de mayo y junio: SIGA llena los meses programados desde el
  primero con saldo. Aqui se reproduce ese reparto codicioso de enero a
  diciembre. Si tras diciembre queda un resto -por meses ya sobregirados, cosa
  que ocurre en cerca del 1 % de los saldos del 2026- el resto se carga a
  diciembre, de modo que los dos totales sigan cuadrando.

  El limite duro es el total, no el mes: SIGA tampoco valida mes a mes.

  -----------------------------------------------------------------------------
  VALORES POR DEFECTO, TOMADOS DE LOS 7 278 DETALLES REALES DEL 2026
  -----------------------------------------------------------------------------
      ESTADO (cabecera) = '0'    registrado; '1' es aprobado
      ESTADO_PED        = '0'    sigue al estado de la cabecera
      ESTADO_ATEND      = '0'
      ESTADO_CONFOR     = '0'
      ESTADO_COMPRA     = '0'
      ESTADO_PROG       = '1'
      FLAG_CAJA         = '0'
      CANT_APROBADA     = 0      SIGA no la llena al registrar
      CANT_ATENDIDA     = 0
      VALOR_TOTAL       = 0      7278 de 7278 detalles reales lo tienen en cero
      INDICADOR_PEDIDO  = '0'
      PROCEDENCIA       = 'M'
      tipo_recurso      = '1'
      ANNO_PROG         = ANO_EJE   7278 de 7278

  ORIGEN y FUENTE_FINANC quedan nulos en la cabecera, igual que en los datos
  reales: el rubro efectivo vive en el item del CMN.

  -----------------------------------------------------------------------------
  FORMATO DE @Items
  -----------------------------------------------------------------------------
  <Items>
    <Item secCuadro="1" secItem="3228" cantidad="15000" justificacion="..." />
    <Item secCuadro="1" secItem="3301" cantidad="12" />
  </Items>

  secCuadro y secItem identifican el item dentro de SIG_CUADRO_MODIFICADO_DET
  del centro de costo y ejercicio indicados. El resto (catalogo, unidad de
  medida, precio, clasificador, meta y tarea) NO se recibe: se lee del CMN, que
  es la unica fuente que no puede contradecirse a si misma.
===============================================================================
*/

/*
  El procedimiento usa metodos del tipo XML (@Items.nodes). SQL Server exige
  QUOTED_IDENTIFIER ON en el momento de CREAR el procedimiento, no al
  ejecutarlo: la opcion queda grabada con el objeto. sqlcmd abre la sesion con
  QUOTED_IDENTIFIER OFF, asi que sin estas dos lineas el procedimiento se crea
  igual pero falla en ejecucion con el error 1934.
*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.usp_ext_registrar_requerimiento', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ext_registrar_requerimiento;
GO

CREATE PROCEDURE dbo.usp_ext_registrar_requerimiento
    @AnoEje          numeric(4,0),
    @SecEjec         numeric(6,0),
    @CentroCosto     varchar(15),
    @TipoBien        varchar(1),
    @Empleado        varchar(15),
    @NombreEmpleado  varchar(80)  = NULL,
    @MotivoPedido    varchar(max),
    @TipoPpto        numeric(1,0) = 1,
    @TipoUso         varchar(1)   = 'C',
    @MesPedido       char(2)      = NULL,
    @Moneda          varchar(6)   = 'S/.',
    @FechaPedido     datetime     = NULL,
    @Usuario         varchar(30),
    @Equipo          varchar(20)  = NULL,
    @Items           xml,
    @TipoPedido      char(1)      = '2',
    @NroPedido       varchar(6)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @Ahora           datetime,
        @ResultadoLock   int,
        @RecursoLock     nvarchar(255),
        @Correlativo     int,
        @Lineas          int,
        @SecFunc         numeric(4,0),
        @TipoTarea       char(1),
        @NivelTarea      char(1),
        @CodigoTarea     numeric(10,0),
        @Malos           int,
        @Mensaje         nvarchar(400);

    /* ---- Items tal como llegan ------------------------------------------ */
    DECLARE @I TABLE
    (
        Secuencia     int            NOT NULL IDENTITY(1,1) PRIMARY KEY,
        SecCuadro     numeric(10,0)  NOT NULL,
        SecItem       numeric(10,0)  NOT NULL,
        Cantidad      numeric(20,6)  NOT NULL,
        Justificacion varchar(250)       NULL
    );

    /* ---- Items ya resueltos contra el CMN ------------------------------- */
    DECLARE @R TABLE
    (
        Secuencia      int            NOT NULL PRIMARY KEY,
        SecCuadro      numeric(10,0)  NOT NULL,
        SecItem        numeric(10,0)  NOT NULL,
        SecCuaModSal   numeric(10,0)  NOT NULL,
        GrupoBien      varchar(2)     NOT NULL,
        ClaseBien      varchar(2)     NOT NULL,
        FamiliaBien    varchar(4)     NOT NULL,
        ItemBien       varchar(4)     NOT NULL,
        UnidadMedida   numeric(3,0)       NULL,
        PrecioUnit     numeric(16,6)  NOT NULL,
        Clasificador   varchar(20)    NOT NULL,
        IdClasificador char(7)            NULL,
        Cantidad       numeric(20,6)  NOT NULL,
        Justificacion  varchar(250)       NULL
    );

    /* ---- Consumo agregado por fila de saldo ----------------------------- */
    /* Un mismo SEC_CUA_MOD_SAL puede servir a mas de una fila de detalle del
       CMN (32 876 filas de detalle contra 28 904 saldos distintos en 2026),
       asi que el saldo se valida y se descuenta agregado, no linea a linea. */
    DECLARE @C TABLE
    (
        SecCuaModSal numeric(10,0) NOT NULL PRIMARY KEY,
        Requerido    numeric(20,6) NOT NULL
    );

    /* ---- Saldo desplegado mes a mes ------------------------------------- */
    DECLARE @SaldoMes TABLE
    (
        SecCuaModSal numeric(10,0) NOT NULL,
        Mes          tinyint       NOT NULL,
        Programado   numeric(20,6) NOT NULL,
        Comprometido numeric(20,6) NOT NULL,
        PRIMARY KEY (SecCuaModSal, Mes)
    );

    /* ---- Reparto del consumo por mes ------------------------------------ */
    DECLARE @Alloc TABLE
    (
        SecCuaModSal numeric(10,0) NOT NULL,
        Mes          tinyint       NOT NULL,
        Cantidad     numeric(20,6) NOT NULL,
        PRIMARY KEY (SecCuaModSal, Mes)
    );

    /* =================================================================== */
    /* 1. Validacion de la entrada, antes de abrir transaccion             */
    /* =================================================================== */

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
    BEGIN
        RAISERROR('El usuario de auditoria es obligatorio.', 16, 1);
        RETURN;
    END;

    IF @TipoPedido <> '2'
    BEGIN
        RAISERROR('Este procedimiento fue homologado solo para TIPO_PEDIDO=2 (requerimiento).', 16, 1);
        RETURN;
    END;

    IF @TipoBien NOT IN ('B', 'S')
    BEGIN
        RAISERROR('TIPO_BIEN debe ser B (bienes) o S (servicios).', 16, 1);
        RETURN;
    END;

    IF NULLIF(LTRIM(RTRIM(@Empleado)), '') IS NULL
    BEGIN
        RAISERROR('El empleado solicitante es obligatorio.', 16, 1);
        RETURN;
    END;

    IF @Items IS NULL
    BEGIN
        RAISERROR('El XML de items es obligatorio.', 16, 1);
        RETURN;
    END;

    SET @Ahora = GETDATE();

    IF @FechaPedido IS NULL SET @FechaPedido = @Ahora;
    IF @Equipo IS NULL SET @Equipo = LEFT(COALESCE(HOST_NAME(), 'SISTEMA_EXTERNO'), 20);
    IF @MesPedido IS NULL SET @MesPedido = RIGHT('0' + CONVERT(varchar(2), MONTH(@FechaPedido)), 2);
    IF NULLIF(LTRIM(RTRIM(@Moneda)), '') IS NULL SET @Moneda = 'S/.';

    INSERT INTO @I (SecCuadro, SecItem, Cantidad, Justificacion)
    SELECT N.It.value('@secCuadro', 'numeric(10,0)'),
           N.It.value('@secItem',   'numeric(10,0)'),
           N.It.value('@cantidad',  'numeric(20,6)'),
           LEFT(N.It.value('@justificacion', 'varchar(250)'), 250)
    FROM @Items.nodes('/Items/Item') AS N(It)
    ORDER BY N.It.value('@secCuadro', 'numeric(10,0)'),
             N.It.value('@secItem',   'numeric(10,0)');

    SELECT @Lineas = COUNT(*) FROM @I;

    IF COALESCE(@Lineas, 0) = 0
    BEGIN
        RAISERROR('El requerimiento debe tener al menos un item.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM @I WHERE Cantidad IS NULL OR Cantidad <= 0)
    BEGIN
        RAISERROR('Todas las cantidades solicitadas deben ser mayores que cero.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM @I GROUP BY SecCuadro, SecItem HAVING COUNT(*) > 1)
    BEGIN
        RAISERROR('El mismo item del CMN aparece mas de una vez en el requerimiento.', 16, 1);
        RETURN;
    END;

    /* =================================================================== */
    /* 2. Registro                                                          */
    /* =================================================================== */

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;

        /* La numeracion de pedidos es por ejercicio, ejecutora, tipo de bien
           y tipo de pedido. Se comprueba en 2026/1750: la serie S/2 llega a
           7662 mientras la serie B/2 llega a 109, o sea no se comparten. */
        SET @RecursoLock = 'SIGA_PED_' + CONVERT(varchar(4), @AnoEje) + '_'
                         + CONVERT(varchar(6), @SecEjec) + '_'
                         + @TipoBien + '_' + @TipoPedido;

        EXEC @ResultadoLock = sys.sp_getapplock
             @Resource     = @RecursoLock,
             @LockMode     = 'Exclusive',
             @LockOwner    = 'Transaction',
             @LockTimeout  = 15000;

        IF @ResultadoLock < 0
            RAISERROR('No se pudo bloquear la numeracion de requerimientos.', 16, 1);

        /* ---- 2.1 Maestros de la cabecera -------------------------------- */

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SIG_CENTRO_COSTO WITH (HOLDLOCK)
             WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
               AND CENTRO_COSTO = @CentroCosto AND ESTADO = 'A'
        )
            RAISERROR('El centro de costo no existe o esta inactivo.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SIG_CUADRO_MODIFICADO WITH (HOLDLOCK)
             WHERE SEC_EJEC = @SecEjec AND ANNO_EJEC = @AnoEje
               AND CENTRO_COSTO = @CentroCosto
        )
            RAISERROR('El centro de costo no tiene cuadro modificado en el ejercicio.', 16, 1);

        /* ---- 2.2 Resolucion de cada item contra el CMN ------------------- */
        /*
           Se toma UPDLOCK sobre el detalle del CMN: entre la lectura del saldo
           y su descuento no puede colarse otro requerimiento.
           ANNO_PROG = ANO_EJE porque asi esta el 100 % de los 7 278 detalles
           reales del 2026: un requerimiento consume la programacion del anio
           en curso, no la de los anios 2 a 4 del multianual.
        */
        INSERT INTO @R
        (
            Secuencia, SecCuadro, SecItem, SecCuaModSal,
            GrupoBien, ClaseBien, FamiliaBien, ItemBien,
            UnidadMedida, PrecioUnit, Clasificador, IdClasificador,
            Cantidad, Justificacion
        )
        SELECT i.Secuencia, i.SecCuadro, i.SecItem, d.SEC_CUA_MOD_SAL,
               d.GRUPO_BIEN, d.CLASE_BIEN, d.FAMILIA_BIEN, d.ITEM_BIEN,
               d.UNIDAD_MEDIDA, d.PRECIO_UNIT, d.CLASIFICADOR, cg.ID_CLASIFICADOR,
               i.Cantidad, i.Justificacion
          FROM @I AS i
          JOIN dbo.SIG_CUADRO_MODIFICADO_DET AS d WITH (UPDLOCK, HOLDLOCK)
            ON d.SEC_EJEC     = @SecEjec
           AND d.ANNO_EJEC    = @AnoEje
           AND d.CENTRO_COSTO = @CentroCosto
           AND d.SEC_CUADRO   = i.SecCuadro
           AND d.SEC_ITEM     = i.SecItem
           AND d.ANNO_PROG    = @AnoEje
          LEFT JOIN dbo.SIG_CLASIFICADOR_GASTO AS cg
            ON cg.ANO_EJE = @AnoEje AND cg.CLASIFICADOR = d.CLASIFICADOR;

        IF (SELECT COUNT(*) FROM @R) <> @Lineas
            RAISERROR('Algun item no existe en el cuadro modificado del centro de costo para el ejercicio.', 16, 1);

        /* El tipo de bien del pedido y el del catalogo tienen que coincidir:
           un requerimiento de servicios no puede arrastrar un bien. */
        SELECT @Malos = COUNT(*)
          FROM @R AS r
          JOIN dbo.SIG_CUADRO_MODIFICADO_DET AS d
            ON d.SEC_EJEC = @SecEjec AND d.ANNO_EJEC = @AnoEje
           AND d.CENTRO_COSTO = @CentroCosto AND d.SEC_CUADRO = r.SecCuadro
           AND d.SEC_ITEM = r.SecItem AND d.ANNO_PROG = @AnoEje
         WHERE d.TIPO_BIEN <> @TipoBien;

        IF COALESCE(@Malos, 0) > 0
            RAISERROR('Hay items cuyo TIPO_BIEN no corresponde al del requerimiento.', 16, 1);

        /* Regla del propio cliente SIGA (sig_aba_dawi21_te.pbd). */
        SELECT @Malos = COUNT(*)
          FROM @R AS r
          JOIN dbo.SIG_CUADRO_MODIFICADO_DET AS d
            ON d.SEC_EJEC = @SecEjec AND d.ANNO_EJEC = @AnoEje
           AND d.CENTRO_COSTO = @CentroCosto AND d.SEC_CUADRO = r.SecCuadro
           AND d.SEC_ITEM = r.SecItem AND d.ANNO_PROG = @AnoEje
         WHERE d.ESTADO IN ('E', 'ET', 'IC');

        IF COALESCE(@Malos, 0) > 0
            RAISERROR('Hay items excluidos o anulados en el CMN; no se pueden requerir.', 16, 1);

        SELECT @Malos = COUNT(*)
          FROM @R AS r
          JOIN dbo.SIG_CUADRO_MODIFICADO_DET AS d
            ON d.SEC_EJEC = @SecEjec AND d.ANNO_EJEC = @AnoEje
           AND d.CENTRO_COSTO = @CentroCosto AND d.SEC_CUADRO = r.SecCuadro
           AND d.SEC_ITEM = r.SecItem AND d.ANNO_PROG = @AnoEje
         WHERE d.MOTIVO_SOLICITUD NOT IN ('0', '3');

        IF COALESCE(@Malos, 0) > 0
            RAISERROR('Hay items con una solicitud de modificacion pendiente; hay que esperar su aprobacion.', 16, 1);

        IF EXISTS (SELECT 1 FROM @R WHERE IdClasificador IS NULL)
            RAISERROR('Algun clasificador del CMN no existe en SIG_CLASIFICADOR_GASTO del ejercicio.', 16, 1);

        IF EXISTS (SELECT 1 FROM @R WHERE UnidadMedida IS NULL)
            RAISERROR('Algun item del CMN no tiene unidad de medida.', 16, 1);

        /* ---- 2.3 Meta y tarea: se heredan del CMN, no se reciben --------- */
        /*
           La cabecera del pedido lleva una sola meta y una sola tarea. Si los
           items del CMN no coinciden entre si, el requerimiento no es
           representable y hay que partirlo. Mejor rechazarlo aqui que grabar
           una cabecera que miente sobre su propio detalle.
        */
        SELECT @SecFunc     = MIN(d.SEC_FUNC),
               @TipoTarea   = MIN(d.TIPO_TAREA),
               @NivelTarea  = MIN(d.NIVEL_TAREA),
               @CodigoTarea = MIN(d.CODIGO_TAREA),
               @Malos       = COUNT(DISTINCT CONVERT(varchar(60),
                                d.SEC_FUNC) + '|' + d.TIPO_TAREA + '|'
                              + d.NIVEL_TAREA + '|' + CONVERT(varchar(20), d.CODIGO_TAREA))
          FROM @R AS r
          JOIN dbo.SIG_CUADRO_MODIFICADO_DET AS d
            ON d.SEC_EJEC = @SecEjec AND d.ANNO_EJEC = @AnoEje
           AND d.CENTRO_COSTO = @CentroCosto AND d.SEC_CUADRO = r.SecCuadro
           AND d.SEC_ITEM = r.SecItem AND d.ANNO_PROG = @AnoEje;

        IF COALESCE(@Malos, 0) <> 1
            RAISERROR('Los items pertenecen a metas o tareas distintas; hay que emitir un requerimiento por cada una.', 16, 1);

        /* ---- 2.4 Saldo disponible --------------------------------------- */

        INSERT INTO @C (SecCuaModSal, Requerido)
        SELECT SecCuaModSal, SUM(Cantidad) FROM @R GROUP BY SecCuaModSal;

        SELECT @Malos = COUNT(*)
          FROM @C AS c
          LEFT JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO AS s WITH (UPDLOCK, HOLDLOCK)
            ON s.SEC_EJEC = @SecEjec AND s.ANNO_EJEC = @AnoEje
           AND s.SEC_CUA_MOD_SAL = c.SecCuaModSal
         WHERE s.SEC_CUA_MOD_SAL IS NULL
            OR (s.CANT_TOTAL - s.CANT_TOTAL_CMN) < c.Requerido;

        IF COALESCE(@Malos, 0) > 0
            RAISERROR('La cantidad solicitada supera el saldo disponible del CMN en algun item.', 16, 1);

        /* ---- 2.5 Reparto del consumo mes a mes -------------------------- */

        INSERT INTO @SaldoMes (SecCuaModSal, Mes, Programado, Comprometido)
        SELECT c.SecCuaModSal,  1, s.CANT_01, s.CANT_01_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal,  2, s.CANT_02, s.CANT_02_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal,  3, s.CANT_03, s.CANT_03_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal,  4, s.CANT_04, s.CANT_04_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal,  5, s.CANT_05, s.CANT_05_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal,  6, s.CANT_06, s.CANT_06_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal,  7, s.CANT_07, s.CANT_07_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal,  8, s.CANT_08, s.CANT_08_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal,  9, s.CANT_09, s.CANT_09_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal, 10, s.CANT_10, s.CANT_10_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal, 11, s.CANT_11, s.CANT_11_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal
        UNION ALL SELECT c.SecCuaModSal, 12, s.CANT_12, s.CANT_12_CMN FROM @C c JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s ON s.SEC_EJEC=@SecEjec AND s.ANNO_EJEC=@AnoEje AND s.SEC_CUA_MOD_SAL=c.SecCuaModSal;

        DECLARE @sal numeric(10,0), @pend numeric(20,6), @mes tinyint,
                @disp numeric(20,6), @toma numeric(20,6);

        DECLARE curSaldo CURSOR LOCAL FAST_FORWARD FOR
            SELECT SecCuaModSal, Requerido FROM @C ORDER BY SecCuaModSal;

        OPEN curSaldo;
        FETCH NEXT FROM curSaldo INTO @sal, @pend;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @mes = 1;

            WHILE @mes <= 12 AND @pend > 0
            BEGIN
                SELECT @disp = Programado - Comprometido
                  FROM @SaldoMes WHERE SecCuaModSal = @sal AND Mes = @mes;

                IF @disp > 0
                BEGIN
                    SET @toma = CASE WHEN @pend < @disp THEN @pend ELSE @disp END;

                    INSERT INTO @Alloc (SecCuaModSal, Mes, Cantidad)
                    VALUES (@sal, @mes, @toma);

                    SET @pend = @pend - @toma;
                END;

                SET @mes = @mes + 1;
            END;

            /* Resto por meses ya sobregirados: se carga a diciembre para que
               CANT_TOTAL_CMN siga siendo la suma de los doce meses. */
            IF @pend > 0
            BEGIN
                UPDATE @Alloc SET Cantidad = Cantidad + @pend
                 WHERE SecCuaModSal = @sal AND Mes = 12;

                IF @@ROWCOUNT = 0
                    INSERT INTO @Alloc (SecCuaModSal, Mes, Cantidad)
                    VALUES (@sal, 12, @pend);
            END;

            FETCH NEXT FROM curSaldo INTO @sal, @pend;
        END;

        CLOSE curSaldo;
        DEALLOCATE curSaldo;

        /* ---- 2.6 Correlativo del pedido --------------------------------- */

        SELECT @Correlativo = COALESCE(MAX(CONVERT(int, NRO_PEDIDO)), 0) + 1
          FROM dbo.SIG_PEDIDOS WITH (UPDLOCK, HOLDLOCK)
         WHERE ANO_EJE = @AnoEje AND SEC_EJEC = @SecEjec
           AND TIPO_BIEN = @TipoBien AND TIPO_PEDIDO = @TipoPedido;

        IF @Correlativo > 999999
            RAISERROR('Se agoto la numeracion de requerimientos del ejercicio.', 16, 1);

        SET @NroPedido = RIGHT('000000' + CONVERT(varchar(6), @Correlativo), 6);

        /* ---- 2.7 Cabecera ----------------------------------------------- */

        INSERT INTO dbo.SIG_PEDIDOS
        (
            ANO_EJE, SEC_EJEC, TIPO_BIEN, TIPO_PEDIDO, NRO_PEDIDO,
            CENTRO_COSTO, FECHA_PEDIDO, MOTIVO_PEDIDO, EMPLEADO, NOMBRE_EMPLEADO,
            TIPO_PPTO, sec_func, TIPO_TAREA, NIVEL_TAREA, CODIGO_TAREA,
            ESTADO, TIPO_USO, MES_PEDIDO, INDICADOR_PEDIDO, MONEDA,
            tipo_recurso, PROCEDENCIA,
            CUSER_ID, FECHA_REG, EQUIPO_REG
        )
        VALUES
        (
            @AnoEje, @SecEjec, @TipoBien, @TipoPedido, @NroPedido,
            @CentroCosto, @FechaPedido, @MotivoPedido, @Empleado, @NombreEmpleado,
            @TipoPpto, @SecFunc, @TipoTarea, @NivelTarea, @CodigoTarea,
            '0', @TipoUso, @MesPedido, '0', @Moneda,
            '1', 'M',
            @Usuario, @Ahora, @Equipo
        );

        /* ---- 2.8 Detalle ------------------------------------------------ */

        INSERT INTO dbo.SIG_DETALLE_PEDIDOS
        (
            ANO_EJE, sec_ejec, TIPO_BIEN, TIPO_PEDIDO, NRO_PEDIDO, SECUENCIA,
            GRUPO_BIEN, CLASE_BIEN, FAMILIA_BIEN, ITEM_BIEN, UNIDAD_MEDIDA,
            CANT_SOLICITADA, CANT_APROBADA, CANT_ATENDIDA,
            PRECIO_UNIT, VALOR_TOTAL,
            ESTADO_PED, ESTADO_ATEND, ESTADO_CONFOR, ESTADO_COMPRA, ESTADO_PROG,
            CLASIFICADOR, ID_CLASIFICADOR, FLAG_CAJA, JUSTIFICACION,
            CENTRO_COSTO, SEC_CUADRO, SEC_ITEM, ANNO_PROG, SEC_CUA_MOD_SAL,
            CUSER_ID, EQUIPO_REG, FECHA_REG
        )
        SELECT @AnoEje, @SecEjec, @TipoBien, @TipoPedido, @NroPedido, r.Secuencia,
               r.GrupoBien, r.ClaseBien, r.FamiliaBien, r.ItemBien, r.UnidadMedida,
               r.Cantidad, 0, 0,
               r.PrecioUnit, 0,
               '0', '0', '0', '0', '1',
               r.Clasificador, r.IdClasificador, '0', r.Justificacion,
               @CentroCosto, r.SecCuadro, r.SecItem, @AnoEje, r.SecCuaModSal,
               @Usuario, @Equipo, @Ahora
          FROM @R AS r
         ORDER BY r.Secuencia;

        /* ---- 2.9 Compromiso del saldo del CMN --------------------------- */

        UPDATE s
           SET CANT_01_CMN = s.CANT_01_CMN + COALESCE(a01.Cantidad, 0),
               CANT_02_CMN = s.CANT_02_CMN + COALESCE(a02.Cantidad, 0),
               CANT_03_CMN = s.CANT_03_CMN + COALESCE(a03.Cantidad, 0),
               CANT_04_CMN = s.CANT_04_CMN + COALESCE(a04.Cantidad, 0),
               CANT_05_CMN = s.CANT_05_CMN + COALESCE(a05.Cantidad, 0),
               CANT_06_CMN = s.CANT_06_CMN + COALESCE(a06.Cantidad, 0),
               CANT_07_CMN = s.CANT_07_CMN + COALESCE(a07.Cantidad, 0),
               CANT_08_CMN = s.CANT_08_CMN + COALESCE(a08.Cantidad, 0),
               CANT_09_CMN = s.CANT_09_CMN + COALESCE(a09.Cantidad, 0),
               CANT_10_CMN = s.CANT_10_CMN + COALESCE(a10.Cantidad, 0),
               CANT_11_CMN = s.CANT_11_CMN + COALESCE(a11.Cantidad, 0),
               CANT_12_CMN = s.CANT_12_CMN + COALESCE(a12.Cantidad, 0),
               CANT_TOTAL_CMN = s.CANT_TOTAL_CMN + c.Requerido
          FROM dbo.SIG_CUADRO_MODIFICADO_SALDO AS s
          JOIN @C AS c
            ON s.SEC_EJEC = @SecEjec AND s.ANNO_EJEC = @AnoEje
           AND s.SEC_CUA_MOD_SAL = c.SecCuaModSal
          LEFT JOIN @Alloc a01 ON a01.SecCuaModSal = c.SecCuaModSal AND a01.Mes =  1
          LEFT JOIN @Alloc a02 ON a02.SecCuaModSal = c.SecCuaModSal AND a02.Mes =  2
          LEFT JOIN @Alloc a03 ON a03.SecCuaModSal = c.SecCuaModSal AND a03.Mes =  3
          LEFT JOIN @Alloc a04 ON a04.SecCuaModSal = c.SecCuaModSal AND a04.Mes =  4
          LEFT JOIN @Alloc a05 ON a05.SecCuaModSal = c.SecCuaModSal AND a05.Mes =  5
          LEFT JOIN @Alloc a06 ON a06.SecCuaModSal = c.SecCuaModSal AND a06.Mes =  6
          LEFT JOIN @Alloc a07 ON a07.SecCuaModSal = c.SecCuaModSal AND a07.Mes =  7
          LEFT JOIN @Alloc a08 ON a08.SecCuaModSal = c.SecCuaModSal AND a08.Mes =  8
          LEFT JOIN @Alloc a09 ON a09.SecCuaModSal = c.SecCuaModSal AND a09.Mes =  9
          LEFT JOIN @Alloc a10 ON a10.SecCuaModSal = c.SecCuaModSal AND a10.Mes = 10
          LEFT JOIN @Alloc a11 ON a11.SecCuaModSal = c.SecCuaModSal AND a11.Mes = 11
          LEFT JOIN @Alloc a12 ON a12.SecCuaModSal = c.SecCuaModSal AND a12.Mes = 12;

        /* ---- 2.10 Comprobacion de las dos invariantes ------------------- */
        /* Si el descuento rompio la igualdad total = suma de meses, algo se
           calculo mal y es preferible no dejar rastro. */

        IF EXISTS
        (
            SELECT 1
              FROM dbo.SIG_CUADRO_MODIFICADO_SALDO AS s
              JOIN @C AS c
                ON s.SEC_EJEC = @SecEjec AND s.ANNO_EJEC = @AnoEje
               AND s.SEC_CUA_MOD_SAL = c.SecCuaModSal
             WHERE s.CANT_TOTAL_CMN <>
                   s.CANT_01_CMN + s.CANT_02_CMN + s.CANT_03_CMN + s.CANT_04_CMN
                 + s.CANT_05_CMN + s.CANT_06_CMN + s.CANT_07_CMN + s.CANT_08_CMN
                 + s.CANT_09_CMN + s.CANT_10_CMN + s.CANT_11_CMN + s.CANT_12_CMN
        )
            RAISERROR('El descuento rompio la igualdad CANT_TOTAL_CMN = suma de los doce meses.', 16, 1);

        IF EXISTS
        (
            SELECT 1
              FROM dbo.SIG_CUADRO_MODIFICADO_SALDO AS s
              JOIN @C AS c
                ON s.SEC_EJEC = @SecEjec AND s.ANNO_EJEC = @AnoEje
               AND s.SEC_CUA_MOD_SAL = c.SecCuaModSal
             WHERE s.CANT_TOTAL_CMN > s.CANT_TOTAL
        )
            RAISERROR('El descuento dejo el consumo por encima de lo programado.', 16, 1);

        COMMIT TRANSACTION;

        SELECT @AnoEje      AS ANO_EJE,
               @SecEjec     AS SEC_EJEC,
               @TipoBien    AS TIPO_BIEN,
               @TipoPedido  AS TIPO_PEDIDO,
               @NroPedido   AS NRO_PEDIDO,
               @CentroCosto AS CENTRO_COSTO,
               @SecFunc     AS SEC_FUNC,
               '0'          AS ESTADO,
               @Lineas      AS ITEMS,
               'REGISTRADO' AS RESULTADO;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'curSaldo') >= 0
        BEGIN
            CLOSE curSaldo;
            DEALLOCATE curSaldo;
        END;

        DECLARE @MensajeError nvarchar(4000), @SeveridadError int, @EstadoError int;
        SELECT @MensajeError  = ERROR_MESSAGE(),
               @SeveridadError = ERROR_SEVERITY(),
               @EstadoError    = ERROR_STATE();
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        RAISERROR(@MensajeError, @SeveridadError, @EstadoError);
        RETURN;
    END CATCH;
END;
GO

/*
-- EJEMPLO DE HOMOLOGACION. REEMPLAZAR LOS DATOS Y EJECUTAR CON ROLLBACK.
--
-- Para elegir un item real y pedible, primero:
--
--   SELECT TOP 10 d.SEC_CUADRO, d.SEC_ITEM, d.GRUPO_BIEN, d.CLASE_BIEN,
--          d.FAMILIA_BIEN, d.ITEM_BIEN, d.PRECIO_UNIT,
--          saldo = s.CANT_TOTAL - s.CANT_TOTAL_CMN
--     FROM dbo.SIG_CUADRO_MODIFICADO_DET d
--     JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO s
--       ON s.SEC_EJEC = d.SEC_EJEC AND s.ANNO_EJEC = d.ANNO_EJEC
--      AND s.SEC_CUA_MOD_SAL = d.SEC_CUA_MOD_SAL
--    WHERE d.SEC_EJEC = 1750 AND d.ANNO_EJEC = 2026
--      AND d.CENTRO_COSTO = '01.02.02' AND d.ANNO_PROG = 2026
--      AND d.TIPO_BIEN = 'S'
--      AND d.ESTADO NOT IN ('E','ET','IC')
--      AND d.MOTIVO_SOLICITUD IN ('0','3')
--      AND (s.CANT_TOTAL - s.CANT_TOTAL_CMN) > 0
--    ORDER BY saldo DESC;

DECLARE @NroPedido varchar(6);
DECLARE @Items xml;

SET @Items = '<Items>
  <Item secCuadro="1" secItem="3228" cantidad="100" justificacion="PRUEBA DE HOMOLOGACION" />
</Items>';

BEGIN TRANSACTION;

EXEC dbo.usp_ext_registrar_requerimiento
     @AnoEje       = 2026,
     @SecEjec      = 1750,
     @CentroCosto  = '01.02.02',
     @TipoBien     = 'S',
     @Empleado     = '43066891',
     @MotivoPedido = 'REQUERIMIENTO GENERADO DESDE EL SIGCM',
     @Usuario      = 'USUARIO_EXT',
     @Equipo       = 'SERVICIO_WEB',
     @Items        = @Items,
     @NroPedido    = @NroPedido OUTPUT;

SELECT @NroPedido AS NRO_PEDIDO;

ROLLBACK TRANSACTION;
*/
