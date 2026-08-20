USE [SIGA_1750];
GO

/*
===============================================================================
  usp_ext_incluir_item_cmn
  Inclusion de un item en el Cuadro Multianual de Necesidades, por la ruta de
  MODIFICACION (SIG_CUADRO_MODIFICADO), que es la vigente durante el ejercicio.

  POR QUE EXISTE
  --------------
  usp_ext_registrar_item_cmn escribe en SIG_CUADRO_NECESIDAD, o sea en la ruta
  de FORMULACION. En la ejecutora 1750 esa ruta se cerro el 2026-01-07: desde el
  8 de enero todo el movimiento del cuadro ocurre en SIG_CUADRO_MODIFICADO.
  Un item incluido por la ruta de formulacion no aparece en la pantalla que el
  area usuaria usa hoy ni puede ser consumido por un requerimiento.

  Este procedimiento reemplaza a aquel para la operacion INCLUIR_ITEM y deja la
  inclusion simetrica con usp_ext_excluir_item_cmn: las dos escriben en el mismo
  cuadro y las dos abren una solicitud de modificacion.

  ---------------------------------------------------------------------------
  QUE ESCRIBE, EN ORDEN
  ---------------------------------------------------------------------------
  1. SIG_CUADRO_MODIFICADO         cabecera del cuadro del centro, si no existe.
  2. SIG_CUADRO_MODIFICADO_SALDO   cuatro filas, una por anio programado.
  3. SIG_CUADRO_MODIFICADO_DET     cuatro filas, una por ANNO_PROG.
  4. SIG_CUADRO_MODIFICADO_DET_ORI cuatro filas TIPO='1' con la foto previa,
                                   que para un item nuevo es todo en cero.
  5. SIG_SOLICITUD_MODIFICACION    el expediente, ESTADO='2' (enviada).
  6. SIG_SOLICITUD_MODIFICACION_DET una fila por anio, MOTIVO='1'.
  7. SIG_DOCUMENTO_ESTADO          el movimiento del documento.

  El item queda en ESTADO='I', PROCEDENCIA='N', FLAG_MODIFICADO='1',
  FLAG_SOLICITUD='0', MOTIVO_SOLICITUD='1'. Es exactamente la combinacion que
  tienen los 82 items realmente incluidos y aun no aprobados del 2026, y la que
  distingue una inclusion pendiente (I/N/1/0/1) de una ya aprobada (I/N/0/0/0).

  MIENTRAS MOTIVO_SOLICITUD SEA '1' EL ITEM NO ES PEDIBLE. El selector de items
  de un requerimiento exige MOTIVO_SOLICITUD IN ('0','3'). Recien lo habilita la
  aprobacion, que hace usp_ext_aprobar_solicitud_cmn (Anexo 4).

  ---------------------------------------------------------------------------
  EL TECHO PRESUPUESTAL
  ---------------------------------------------------------------------------
  Se comprueba contra SIG_TECHO_PRESUPUESTO de la fase 5, agregado por
  CENTRO_COSTO + SEC_FUNC + CLASIFICADOR + ORIGEN + FUENTE_FINANC, y se compara
  con lo ya comprometido en SIG_CUADRO_MODIFICADO_DET para esa misma clave,
  ignorando lo excluido (ESTADO NOT IN 'E','ET','IC'). Los cuatro anios se
  validan por separado.

  Es el limite real: un area usuaria sin techo libre no puede incluir nada, y el
  procedimiento lo dice con el monto disponible en el mensaje de error.

  ---------------------------------------------------------------------------
  FORMATO DE @Periodos  (el mismo que usa W001 al pivotar los 48 periodos)
  ---------------------------------------------------------------------------
  <Periodos>
    <Periodo codigo="0" c01="1" c02="0" ... c12="0" />
    <Periodo codigo="1" ... />
    <Periodo codigo="2" ... />
    <Periodo codigo="3" ... />
  </Periodos>

  codigo 0 = @AnoEje, 1 = +1, 2 = +2, 3 = +3.

  SQL compatible con el nivel de compatibilidad 100 de SIGA_1750.
===============================================================================
*/

/*
  El procedimiento usa metodos del tipo XML (@Periodos.nodes). SQL Server exige
  QUOTED_IDENTIFIER ON al CREAR el procedimiento; la opcion queda grabada con el
  objeto y sqlcmd abre la sesion con la opcion en OFF.
*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.usp_ext_incluir_item_cmn', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ext_incluir_item_cmn;
GO

CREATE PROCEDURE dbo.usp_ext_incluir_item_cmn
    @AnoEje          numeric(4,0),
    @SecEjec         numeric(6,0),
    @CentroCosto     varchar(15),
    @TipoTarea       varchar(1),
    @NivelTarea      varchar(1),
    @CodigoTarea     numeric(10,0),
    @SecFunc         numeric(4,0),
    @Origen          varchar(1)  = '1',
    @FuenteFinanc    varchar(2)  = '00',
    @Clasificador    varchar(20),
    @TipoUso         varchar(1)  = 'C',
    @TipoBien        varchar(1),
    @GrupoBien       varchar(2),
    @ClaseBien       varchar(2),
    @FamiliaBien     varchar(4),
    @ItemBien        varchar(4),
    @UnidadMedida    numeric(3,0) = NULL,
    @PrecioUnit      numeric(16,6),
    @Periodos        xml,
    @Usuario         varchar(30),
    @Equipo          varchar(20)   = NULL,
    @Glosa           varchar(500)  = NULL,
    @SecCuadro       numeric(10,0) = NULL OUTPUT,
    @SecItem         numeric(10,0) = NULL OUTPUT,
    @SecSolicitud    numeric(10,0) = NULL OUTPUT,
    /*
      Por defecto el procedimiento NO devuelve filas: todo lo que hay que saber
      sale por los parametros OUTPUT.

      No es un detalle de estilo. El SIGCM llama a este procedimiento desde
      W001 dentro de un INSERT ... EXEC, y ese patron exige que el
      procedimiento llamado devuelva un unico conjunto de resultados con la
      forma esperada por el destino. Si aqui se cuela un SELECT de diez
      columnas, la insercion falla y la operacion se queda colgada en la cola.
      Lo mismo rompe el contrato del backend, que lee una sola columna de texto.

      @Detalle = 1 activa el SELECT y sirve para la homologacion manual.
    */
    @Detalle         bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*
      TRANSACCION PROPIA O AJENA.

      Este procedimiento puede ser llamado de dos formas: suelto, y desde W001
      dentro de un INSERT ... EXEC, que abre una transaccion implicita. En el
      segundo caso @@TRANCOUNT ya vale 1 al entrar.

      Un ROLLBACK TRANSACTION no deshace solo lo propio: deshace TODO, incluida
      la transaccion del llamador, y lo deja con una transaccion inutilizable.
      El sintoma es "Transaction count after EXECUTE indicates a mismatching
      number of BEGIN and COMMIT statements".

      Por eso solo se abre y se cierra la transaccion cuando es propia. Si es
      ajena, el error se propaga y decide el llamador, que es quien la abrio.
      La atomicidad no se pierde: la transaccion del llamador cubre todo.
    */
    DECLARE @trnPropia bit = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;


    DECLARE
        @Ahora          datetime,
        @ResultadoLock  int,
        @RecursoLock    nvarchar(255),
        @UnidadCatalogo numeric(3,0),
        @SecCuaModSalBase numeric(10,0),
        @SecDocEstado   numeric(10,0),
        @FilasTecho     int,
        @Techo0 numeric(20,2), @Techo1 numeric(20,2),
        @Techo2 numeric(20,2), @Techo3 numeric(20,2),
        @Usado0 numeric(20,2), @Usado1 numeric(20,2),
        @Usado2 numeric(20,2), @Usado3 numeric(20,2),
        @Msg nvarchar(400);

    /* Periodos normalizados: una fila por anio con sus doce meses. */
    DECLARE @P TABLE
    (
        Codigo tinyint NOT NULL PRIMARY KEY,
        AnnoProg numeric(4,0) NOT NULL,
        C01 numeric(20,2) NOT NULL, C02 numeric(20,2) NOT NULL,
        C03 numeric(20,2) NOT NULL, C04 numeric(20,2) NOT NULL,
        C05 numeric(20,2) NOT NULL, C06 numeric(20,2) NOT NULL,
        C07 numeric(20,2) NOT NULL, C08 numeric(20,2) NOT NULL,
        C09 numeric(20,2) NOT NULL, C10 numeric(20,2) NOT NULL,
        C11 numeric(20,2) NOT NULL, C12 numeric(20,2) NOT NULL,
        CTotal numeric(20,2) NOT NULL,
        SecSaldo numeric(10,0) NULL
    );

    /* ------------------------------------------------------------------ */
    /* 1. Validacion de la entrada                                        */
    /* ------------------------------------------------------------------ */

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
    BEGIN
        RAISERROR('El usuario de auditoria es obligatorio.', 16, 1);
        RETURN;
    END;

    IF @TipoBien NOT IN ('B', 'S', 'O')
    BEGIN
        RAISERROR('TIPO_BIEN debe ser B, S u O.', 16, 1);
        RETURN;
    END;

    IF @PrecioUnit IS NULL OR @PrecioUnit <= 0
    BEGIN
        RAISERROR('El precio unitario debe ser mayor que cero.', 16, 1);
        RETURN;
    END;

    IF @Periodos IS NULL
    BEGIN
        RAISERROR('El XML de periodos es obligatorio.', 16, 1);
        RETURN;
    END;

    INSERT INTO @P (Codigo, AnnoProg, C01,C02,C03,C04,C05,C06,C07,C08,C09,C10,C11,C12, CTotal)
    SELECT c.codigo, @AnoEje + c.codigo,
           c.c01,c.c02,c.c03,c.c04,c.c05,c.c06,c.c07,c.c08,c.c09,c.c10,c.c11,c.c12,
           c.c01+c.c02+c.c03+c.c04+c.c05+c.c06+c.c07+c.c08+c.c09+c.c10+c.c11+c.c12
      FROM (
        SELECT codigo = N.P.value('@codigo','tinyint'),
               c01 = COALESCE(N.P.value('@c01','numeric(20,2)'),0),
               c02 = COALESCE(N.P.value('@c02','numeric(20,2)'),0),
               c03 = COALESCE(N.P.value('@c03','numeric(20,2)'),0),
               c04 = COALESCE(N.P.value('@c04','numeric(20,2)'),0),
               c05 = COALESCE(N.P.value('@c05','numeric(20,2)'),0),
               c06 = COALESCE(N.P.value('@c06','numeric(20,2)'),0),
               c07 = COALESCE(N.P.value('@c07','numeric(20,2)'),0),
               c08 = COALESCE(N.P.value('@c08','numeric(20,2)'),0),
               c09 = COALESCE(N.P.value('@c09','numeric(20,2)'),0),
               c10 = COALESCE(N.P.value('@c10','numeric(20,2)'),0),
               c11 = COALESCE(N.P.value('@c11','numeric(20,2)'),0),
               c12 = COALESCE(N.P.value('@c12','numeric(20,2)'),0)
          FROM @Periodos.nodes('/Periodos/Periodo') AS N(P)
      ) AS c;

    IF (SELECT COUNT(*) FROM @P) <> 4
       OR EXISTS (SELECT 1 FROM @P WHERE Codigo NOT BETWEEN 0 AND 3)
       OR EXISTS (SELECT 1 FROM @P
                   WHERE C01<0 OR C02<0 OR C03<0 OR C04<0 OR C05<0 OR C06<0
                      OR C07<0 OR C08<0 OR C09<0 OR C10<0 OR C11<0 OR C12<0)
    BEGIN
        RAISERROR('El XML debe traer exactamente los periodos 0,1,2,3 y cantidades no negativas.', 16, 1);
        RETURN;
    END;

    IF (SELECT SUM(CTotal) FROM @P) <= 0
    BEGIN
        RAISERROR('Debe existir al menos una cantidad mayor que cero.', 16, 1);
        RETURN;
    END;

    SET @Ahora = GETDATE();
    IF @Equipo IS NULL SET @Equipo = LEFT(COALESCE(HOST_NAME(),'SISTEMA_EXTERNO'), 20);
    SET @Glosa = LEFT(COALESCE(NULLIF(LTRIM(RTRIM(@Glosa)),''),
                 'INCLUSION CMN INTEGRADA DESDE SIGCM'), 500);

    /* ------------------------------------------------------------------ */
    /* 2. Registro                                                        */
    /* ------------------------------------------------------------------ */

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        IF @trnPropia = 1 BEGIN TRANSACTION;
        SET @RecursoLock = 'SIGA_CMN_INCLUIR_' + CONVERT(varchar(4),@AnoEje) + '_'
                         + CONVERT(varchar(6),@SecEjec) + '_' + @CentroCosto;

        EXEC @ResultadoLock = sys.sp_getapplock
             @Resource=@RecursoLock, @LockMode='Exclusive',
             @LockOwner='Transaction', @LockTimeout=15000;

        IF @ResultadoLock < 0
            RAISERROR('No se pudo bloquear el cuadro del centro de costo.', 16, 1);

        /* La numeracion de saldos es por ejercicio y ejecutora, o sea global:
           se bloquea aparte para no serializar todos los centros entre si mas
           de lo imprescindible. */
        SET @RecursoLock = 'SIGA_CMN_SALDO_' + CONVERT(varchar(4),@AnoEje) + '_'
                         + CONVERT(varchar(6),@SecEjec);

        EXEC @ResultadoLock = sys.sp_getapplock
             @Resource=@RecursoLock, @LockMode='Exclusive',
             @LockOwner='Transaction', @LockTimeout=15000;

        IF @ResultadoLock < 0
            RAISERROR('No se pudo reservar la numeracion de saldos del CMN.', 16, 1);

        /* ---- 2.1 Maestros ---------------------------------------------- */

        IF NOT EXISTS (SELECT 1 FROM dbo.SIG_CENTRO_COSTO WITH (HOLDLOCK)
                        WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
                          AND CENTRO_COSTO=@CentroCosto AND ESTADO='A')
            RAISERROR('El centro de costo no existe o esta inactivo.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM dbo.META
                        WHERE ano_eje=@AnoEje AND sec_ejec=@SecEjec AND sec_func=@SecFunc)
            RAISERROR('La meta SEC_FUNC no existe para el ejercicio y la ejecutora.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM dbo.FUENTE_FINANC_EJEC
                        WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
                          AND ORIGEN=@Origen AND FUENTE_FINANC=@FuenteFinanc AND ESTADO='A')
            RAISERROR('La fuente de financiamiento no existe o esta inactiva.', 16, 1);

        SELECT @UnidadCatalogo = UNIDAD_MEDIDA
          FROM dbo.CATALOGO_BIEN_SERV WITH (HOLDLOCK)
         WHERE SEC_EJEC=@SecEjec AND TIPO_BIEN=@TipoBien AND GRUPO_BIEN=@GrupoBien
           AND CLASE_BIEN=@ClaseBien AND FAMILIA_BIEN=@FamiliaBien
           AND ITEM_BIEN=@ItemBien AND ESTADO='A';

        IF @UnidadCatalogo IS NULL
            RAISERROR('El item no existe o esta inactivo en CATALOGO_BIEN_SERV.', 16, 1);

        IF @UnidadMedida IS NULL SET @UnidadMedida = @UnidadCatalogo;

        /* ---- 2.2 Techo presupuestal ------------------------------------ */

        SELECT @FilasTecho = COUNT(*),
               @Techo0 = SUM(COALESCE(MNTO_APROB,0)),
               @Techo1 = SUM(COALESCE(MNTO_ANNO_01,0)),
               @Techo2 = SUM(COALESCE(MNTO_ANNO_02,0)),
               @Techo3 = SUM(COALESCE(MNTO_ANNO_03,0))
          FROM dbo.SIG_TECHO_PRESUPUESTO WITH (UPDLOCK, HOLDLOCK)
         WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec AND CENTRO_COSTO=@CentroCosto
           AND FASE_CUADRO=5 AND ORIGEN=@Origen AND FUENTE_FINANC=@FuenteFinanc
           AND sec_func=@SecFunc AND CLASIFICADOR=@Clasificador;

        IF COALESCE(@FilasTecho,0) = 0
            RAISERROR('No existe techo presupuestal para ese centro, meta, fuente y clasificador.', 16, 1);

        SELECT @Usado0 = SUM(CASE WHEN ANNO_PROG=@AnoEje   THEN MNTO_TOTAL ELSE 0 END),
               @Usado1 = SUM(CASE WHEN ANNO_PROG=@AnoEje+1 THEN MNTO_TOTAL ELSE 0 END),
               @Usado2 = SUM(CASE WHEN ANNO_PROG=@AnoEje+2 THEN MNTO_TOTAL ELSE 0 END),
               @Usado3 = SUM(CASE WHEN ANNO_PROG=@AnoEje+3 THEN MNTO_TOTAL ELSE 0 END)
          FROM dbo.SIG_CUADRO_MODIFICADO_DET WITH (UPDLOCK, HOLDLOCK)
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje AND CENTRO_COSTO=@CentroCosto
           AND sec_func=@SecFunc AND CLASIFICADOR=@Clasificador
           AND ORIGEN=@Origen AND FUENTE_FINANC=@FuenteFinanc
           AND ESTADO NOT IN ('E','ET','IC');

        /*
          SOLO SE VALIDA UN ANIO SI LA INCLUSION LE AGREGA MONTO.

          En SIGA hay techos ya sobregirados de antes: OTI, meta 15, tiene el
          techo de los anios 1 a 3 en cero y un item del cuadro con 1.00 en el
          anio 1. Si se valida un anio al que la inclusion no le pone nada, ese
          sobregiro preexistente bloquea cualquier alta, incluso una que solo
          toca el anio base. Y no seria culpa de quien incluye.

          La regla correcta es: esta inclusion no puede EMPEORAR el techo de un
          anio. Si le suma cero, no lo empeora.
        */

        DECLARE @Nuevo0 numeric(20,2) = (SELECT ROUND(CTotal*@PrecioUnit,2) FROM @P WHERE Codigo=0),
                @Nuevo1 numeric(20,2) = (SELECT ROUND(CTotal*@PrecioUnit,2) FROM @P WHERE Codigo=1),
                @Nuevo2 numeric(20,2) = (SELECT ROUND(CTotal*@PrecioUnit,2) FROM @P WHERE Codigo=2),
                @Nuevo3 numeric(20,2) = (SELECT ROUND(CTotal*@PrecioUnit,2) FROM @P WHERE Codigo=3);

        IF @Nuevo0 > 0 AND COALESCE(@Usado0,0) + @Nuevo0 > COALESCE(@Techo0,0)
        BEGIN
            SET @Msg = N'La inclusion excede el techo del anio base. Disponible: '
                     + CONVERT(varchar(30), COALESCE(@Techo0,0) - COALESCE(@Usado0,0))
                     + N', solicitado: ' + CONVERT(varchar(30), @Nuevo0) + N'.';
            RAISERROR(@Msg, 16, 1);
        END;

        IF @Nuevo1 > 0 AND COALESCE(@Usado1,0) + @Nuevo1 > COALESCE(@Techo1,0)
        BEGIN
            SET @Msg = N'La inclusion excede el techo del anio 1. Disponible: '
                     + CONVERT(varchar(30), COALESCE(@Techo1,0) - COALESCE(@Usado1,0))
                     + N', solicitado: ' + CONVERT(varchar(30), @Nuevo1) + N'.';
            RAISERROR(@Msg, 16, 1);
        END;

        IF @Nuevo2 > 0 AND COALESCE(@Usado2,0) + @Nuevo2 > COALESCE(@Techo2,0)
        BEGIN
            SET @Msg = N'La inclusion excede el techo del anio 2. Disponible: '
                     + CONVERT(varchar(30), COALESCE(@Techo2,0) - COALESCE(@Usado2,0))
                     + N', solicitado: ' + CONVERT(varchar(30), @Nuevo2) + N'.';
            RAISERROR(@Msg, 16, 1);
        END;

        IF @Nuevo3 > 0 AND COALESCE(@Usado3,0) + @Nuevo3 > COALESCE(@Techo3,0)
        BEGIN
            SET @Msg = N'La inclusion excede el techo del anio 3. Disponible: '
                     + CONVERT(varchar(30), COALESCE(@Techo3,0) - COALESCE(@Usado3,0))
                     + N', solicitado: ' + CONVERT(varchar(30), @Nuevo3) + N'.';
            RAISERROR(@Msg, 16, 1);
        END;

        /* ---- 2.3 Cabecera del cuadro modificado ------------------------ */

        SELECT @SecCuadro = MAX(SEC_CUADRO)
          FROM dbo.SIG_CUADRO_MODIFICADO WITH (UPDLOCK, HOLDLOCK)
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje AND CENTRO_COSTO=@CentroCosto;

        IF @SecCuadro IS NULL
        BEGIN
            SET @SecCuadro = 1;
            INSERT INTO dbo.SIG_CUADRO_MODIFICADO
                (SEC_EJEC, ANNO_EJEC, CENTRO_COSTO, SEC_CUADRO,
                 CUSER_ID, FECHA_REG, EQUIPO_REG)
            VALUES
                (@SecEjec, @AnoEje, @CentroCosto, @SecCuadro,
                 @Usuario, @Ahora, @Equipo);
        END;

        /* ---- 2.4 Correlativos ------------------------------------------ */

        SELECT @SecItem = COALESCE(MAX(SEC_ITEM),0) + 1
          FROM dbo.SIG_CUADRO_MODIFICADO_DET WITH (UPDLOCK, HOLDLOCK)
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
           AND CENTRO_COSTO=@CentroCosto AND SEC_CUADRO=@SecCuadro;

        SELECT @SecCuaModSalBase = COALESCE(MAX(SEC_CUA_MOD_SAL),0)
          FROM dbo.SIG_CUADRO_MODIFICADO_SALDO WITH (UPDLOCK, HOLDLOCK)
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje;

        /* Cuatro saldos consecutivos, uno por anio, igual que hace SIGA. */
        UPDATE @P SET SecSaldo = @SecCuaModSalBase + Codigo + 1;

        /* ---- 2.5 Saldos ------------------------------------------------ */
        /* CANT_xx lleva lo programado; _SC y _CMN nacen en cero porque nada se
           ha consumido todavia. CANT_TOTAL_ORI queda en cero: el item es nuevo,
           no viene de un cuadro anterior. */

        INSERT INTO dbo.SIG_CUADRO_MODIFICADO_SALDO
            (SEC_EJEC, ANNO_EJEC, SEC_CUA_MOD_SAL,
             CANT_01,CANT_01_SC,CANT_01_CMN, CANT_02,CANT_02_SC,CANT_02_CMN,
             CANT_03,CANT_03_SC,CANT_03_CMN, CANT_04,CANT_04_SC,CANT_04_CMN,
             CANT_05,CANT_05_SC,CANT_05_CMN, CANT_06,CANT_06_SC,CANT_06_CMN,
             CANT_07,CANT_07_SC,CANT_07_CMN, CANT_08,CANT_08_SC,CANT_08_CMN,
             CANT_09,CANT_09_SC,CANT_09_CMN, CANT_10,CANT_10_SC,CANT_10_CMN,
             CANT_11,CANT_11_SC,CANT_11_CMN, CANT_12,CANT_12_SC,CANT_12_CMN,
             CANT_TOTAL_ORI, CANT_TOTAL, CANT_TOTAL_SC, CANT_TOTAL_CMN)
        SELECT @SecEjec, @AnoEje, p.SecSaldo,
               p.C01,0,0, p.C02,0,0, p.C03,0,0, p.C04,0,0,
               p.C05,0,0, p.C06,0,0, p.C07,0,0, p.C08,0,0,
               p.C09,0,0, p.C10,0,0, p.C11,0,0, p.C12,0,0,
               0, p.CTotal, 0, 0
          FROM @P AS p ORDER BY p.Codigo;

        /* ---- 2.6 Detalle ----------------------------------------------- */
        /* I/N/1/0/1 es la combinacion de una inclusion pendiente de aprobar.
           FLG_MNTO_xx en '0': es lo que tienen las inclusiones reales del 2026,
           incluso en los meses con cantidad. */

        INSERT INTO dbo.SIG_CUADRO_MODIFICADO_DET
            (SEC_EJEC, ANNO_EJEC, CENTRO_COSTO, SEC_CUADRO, SEC_ITEM, ANNO_PROG,
             ESTADO, PROCEDENCIA, FLAG_MODIFICADO, FLAG_SOLICITUD, MOTIVO_SOLICITUD,
             FLAG_GASTO, PORC_GASTO, PRECIO_REF,
             ORIGEN, FUENTE_FINANC, SEC_FUNC, TIPO_TAREA, NIVEL_TAREA, CODIGO_TAREA,
             CLASIFICADOR, TIPO_BIEN, GRUPO_BIEN, CLASE_BIEN, FAMILIA_BIEN, ITEM_BIEN,
             UNIDAD_MEDIDA, TIPO_USO, PRECIO_UNIT, SEC_CUA_MOD_SAL,
             FLG_MNTO_01,FLG_MNTO_02,FLG_MNTO_03,FLG_MNTO_04,FLG_MNTO_05,FLG_MNTO_06,
             FLG_MNTO_07,FLG_MNTO_08,FLG_MNTO_09,FLG_MNTO_10,FLG_MNTO_11,FLG_MNTO_12,
             CANT_01,CANT_02,CANT_03,CANT_04,CANT_05,CANT_06,
             CANT_07,CANT_08,CANT_09,CANT_10,CANT_11,CANT_12,CANT_TOTAL,
             MNTO_01,MNTO_02,MNTO_03,MNTO_04,MNTO_05,MNTO_06,
             MNTO_07,MNTO_08,MNTO_09,MNTO_10,MNTO_11,MNTO_12,MNTO_TOTAL,
             CUSER_ID, FECHA_REG, EQUIPO_REG)
        SELECT @SecEjec, @AnoEje, @CentroCosto, @SecCuadro, @SecItem, p.AnnoProg,
               'I', 'N', '1', '0', '1',
               '0', 0, 0,
               @Origen, @FuenteFinanc, @SecFunc, @TipoTarea, @NivelTarea, @CodigoTarea,
               @Clasificador, @TipoBien, @GrupoBien, @ClaseBien, @FamiliaBien, @ItemBien,
               @UnidadMedida, @TipoUso, @PrecioUnit, p.SecSaldo,
               '0','0','0','0','0','0','0','0','0','0','0','0',
               p.C01,p.C02,p.C03,p.C04,p.C05,p.C06,
               p.C07,p.C08,p.C09,p.C10,p.C11,p.C12,p.CTotal,
               ROUND(p.C01*@PrecioUnit,2), ROUND(p.C02*@PrecioUnit,2),
               ROUND(p.C03*@PrecioUnit,2), ROUND(p.C04*@PrecioUnit,2),
               ROUND(p.C05*@PrecioUnit,2), ROUND(p.C06*@PrecioUnit,2),
               ROUND(p.C07*@PrecioUnit,2), ROUND(p.C08*@PrecioUnit,2),
               ROUND(p.C09*@PrecioUnit,2), ROUND(p.C10*@PrecioUnit,2),
               ROUND(p.C11*@PrecioUnit,2), ROUND(p.C12*@PrecioUnit,2),
               ROUND(p.CTotal*@PrecioUnit,2),
               @Usuario, @Ahora, @Equipo
          FROM @P AS p ORDER BY p.Codigo;

        /* ---- 2.7 Foto previa ------------------------------------------- */
        /* Para un item nuevo la foto previa es todo en cero: es lo que tienen
           las inclusiones reales, y es lo que permite a la pantalla de Demanda
           Adicional mostrar la diferencia como alta completa. */

        INSERT INTO dbo.SIG_CUADRO_MODIFICADO_DET_ORI
            (SEC_EJEC, ANNO_EJEC, CENTRO_COSTO, SEC_CUADRO, SEC_ITEM, ANNO_PROG, TIPO,
             FLG_MNTO_01_INI,FLG_MNTO_02_INI,FLG_MNTO_03_INI,FLG_MNTO_04_INI,
             FLG_MNTO_05_INI,FLG_MNTO_06_INI,FLG_MNTO_07_INI,FLG_MNTO_08_INI,
             FLG_MNTO_09_INI,FLG_MNTO_10_INI,FLG_MNTO_11_INI,FLG_MNTO_12_INI,
             CANT_01_INI,CANT_02_INI,CANT_03_INI,CANT_04_INI,CANT_05_INI,CANT_06_INI,
             CANT_07_INI,CANT_08_INI,CANT_09_INI,CANT_10_INI,CANT_11_INI,CANT_12_INI,
             CANT_TOTAL_INI)
        SELECT @SecEjec, @AnoEje, @CentroCosto, @SecCuadro, @SecItem, p.AnnoProg, '1',
               '0','0','0','0','0','0','0','0','0','0','0','0',
               0,0,0,0,0,0,0,0,0,0,0,0,0
          FROM @P AS p ORDER BY p.Codigo;

        /* ---- 2.8 Solicitud de modificacion ----------------------------- */

        SET @RecursoLock = 'SIGA_SOL_MOD_' + CONVERT(varchar(6),@SecEjec) + '_'
                         + CONVERT(varchar(4),@AnoEje) + '_' + @CentroCosto;

        EXEC @ResultadoLock = sys.sp_getapplock
             @Resource=@RecursoLock, @LockMode='Exclusive',
             @LockOwner='Transaction', @LockTimeout=15000;

        IF @ResultadoLock < 0
            RAISERROR('No se pudo reservar la numeracion de la solicitud SIGA.', 16, 1);

        SELECT @SecSolicitud = COALESCE(MAX(SEC_SOL_MOD),0) + 1
          FROM dbo.SIG_SOLICITUD_MODIFICACION WITH (UPDLOCK, HOLDLOCK)
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje AND CENTRO_COSTO=@CentroCosto;

        INSERT INTO dbo.SIG_SOLICITUD_MODIFICACION
            (SEC_EJEC, ANNO_EJEC, CENTRO_COSTO, SEC_SOL_MOD, ESTADO, FECHA, GLOSA,
             CUSER_ID, FECHA_REG, EQUIPO_REG, CUSER_MOD, FECHA_MOD, EQUIPO_MOD, GLOSA_MODIF)
        VALUES
            (@SecEjec, @AnoEje, @CentroCosto, @SecSolicitud, '2', @Ahora, @Glosa,
             @Usuario, @Ahora, @Equipo, NULL, NULL, NULL, NULL);

        INSERT INTO dbo.SIG_SOLICITUD_MODIFICACION_DET
            (SEC_EJEC, ANNO_EJEC, CENTRO_COSTO, SEC_SOL_MOD, SEC_SOL_MOD_DET,
             SEC_CUADRO, SEC_ITEM, ANNO_PROG, MOTIVO, PRECIO_UNIT,
             CANT_01,CANT_02,CANT_03,CANT_04,CANT_05,CANT_06,
             CANT_07,CANT_08,CANT_09,CANT_10,CANT_11,CANT_12,
             FLAG_MNTO_INI,
             CANT_01_INI,CANT_02_INI,CANT_03_INI,CANT_04_INI,CANT_05_INI,CANT_06_INI,
             CANT_07_INI,CANT_08_INI,CANT_09_INI,CANT_10_INI,CANT_11_INI,CANT_12_INI,
             CUSER_ID, FECHA_REG, EQUIPO_REG)
        SELECT @SecEjec, @AnoEje, @CentroCosto, @SecSolicitud,
               ROW_NUMBER() OVER (ORDER BY p.Codigo),
               @SecCuadro, @SecItem, p.AnnoProg, '1', @PrecioUnit,
               p.C01,p.C02,p.C03,p.C04,p.C05,p.C06,
               p.C07,p.C08,p.C09,p.C10,p.C11,p.C12,
               0,
               0,0,0,0,0,0,0,0,0,0,0,0,
               @Usuario, @Ahora, @Equipo
          FROM @P AS p;

        /* ---- 2.9 Movimiento del documento ------------------------------ */
        /* SEC_DOC_EST se numera por ejecutora y estado: la PK es
           (SEC_EJEC, SEC_DOC_EST, ESTADO). */

        SELECT @SecDocEstado = COALESCE(MAX(SEC_DOC_EST),0) + 1
          FROM dbo.SIG_DOCUMENTO_ESTADO WITH (UPDLOCK, HOLDLOCK)
         WHERE SEC_EJEC=@SecEjec AND ESTADO='2';

        INSERT INTO dbo.SIG_DOCUMENTO_ESTADO
            (SEC_EJEC, SEC_DOC_EST, ESTADO, FLAG_ULT_MOV, FECHA, OBSERVACION,
             CUSER_ID, FECHA_REG, EQUIPO_REG, SOL_ANNO_EJEC, SOL_CC, SEC_SOL_MOD,
             SOL_GRU_ANNO_EJEC, SOL_GRU_SEC)
        VALUES
            (@SecEjec, @SecDocEstado, '2', '1', @Ahora, NULL,
             @Usuario, @Ahora, @Equipo, @AnoEje, @CentroCosto, @SecSolicitud,
             NULL, NULL);

        UPDATE dbo.SIG_CUADRO_MODIFICADO
           SET CUSER_MOD=@Usuario, FECHA_MOD=@Ahora, EQUIPO_MOD=@Equipo
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
           AND CENTRO_COSTO=@CentroCosto AND SEC_CUADRO=@SecCuadro;

        IF @trnPropia = 1 COMMIT TRANSACTION;

        IF @Detalle = 1
            SELECT @AnoEje       AS ANNO_EJEC,
                   @SecEjec      AS SEC_EJEC,
                   @CentroCosto  AS CENTRO_COSTO,
                   @SecCuadro    AS SEC_CUADRO,
                   @SecItem      AS SEC_ITEM,
                   @SecSolicitud AS SEC_SOL_MOD,
                   'I'           AS ESTADO,
                   '1'           AS MOTIVO_SOLICITUD,
                   (SELECT MIN(SecSaldo) FROM @P) AS SEC_CUA_MOD_SAL_BASE,
                   'INCLUIDO'    AS RESULTADO;
    END TRY
    BEGIN CATCH
        DECLARE @MensajeError nvarchar(4000), @SeveridadError int, @EstadoError int;
        SELECT @MensajeError=ERROR_MESSAGE(), @SeveridadError=ERROR_SEVERITY(),
               @EstadoError=ERROR_STATE();
        IF @trnPropia = 1 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
        RAISERROR(@MensajeError, @SeveridadError, @EstadoError);
        RETURN;
    END CATCH;
END;
GO

PRINT 'Instalado: dbo.usp_ext_incluir_item_cmn';
GO


