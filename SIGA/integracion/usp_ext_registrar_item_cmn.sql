USE [SIGA_1750];
GO

/*
  Propuesta de integracion para registrar un item en el Cuadro Multianual
  de Necesidades (CMN) de SIGA, fase vigente 5.

  IMPORTANTE
  - El script se entrega para homologacion; no se instala automaticamente.
  - Registra una cabecera si no existe una combinacion equivalente y agrega
    un item con cantidades mensuales del anio base y tres anios posteriores.
  - El item queda en ESTADO='5' (CMN pendiente de consolidacion/aprobacion).
  - No cambia el item a ESTADO='6', no consolida y no modifica el techo.
  - SQL compatible con el nivel de compatibilidad 100 de SIGA_1750.

  Formato de @Periodos:
  <Periodos>
    <Periodo codigo="0" c01="1" c02="0" ... c12="0" />
    <Periodo codigo="1" c01="0" c02="0" ... c12="0" />
    <Periodo codigo="2" c01="0" c02="0" ... c12="0" />
    <Periodo codigo="3" c01="0" c02="0" ... c12="0" />
  </Periodos>

  codigo=0: anio @AnoEje
  codigo=1: @AnoEje + 1
  codigo=2: @AnoEje + 2
  codigo=3: @AnoEje + 3
*/

IF OBJECT_ID('dbo.usp_ext_registrar_item_cmn', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ext_registrar_item_cmn;
GO

CREATE PROCEDURE dbo.usp_ext_registrar_item_cmn
    @AnoEje          numeric(4,0),
    @SecEjec         numeric(6,0),
    @CentroCosto     varchar(15),
    @FaseCuadro      numeric(1,0) = 5,
    @Secuencia       numeric(10,0) = NULL OUTPUT,
    @TipoTarea       varchar(1),
    @NivelTarea      varchar(1),
    @CodigoTarea     numeric(10,0),
    @SecFunc         numeric(4,0),
    @SecFuncProp     numeric(4,0) = NULL,
    @Origen          varchar(1) = '1',
    @FuenteFinanc    varchar(2) = '00',
    @Clasificador    varchar(20),
    @TipoRecurso     varchar(2) = '1',
    @TipoPpto        numeric(1,0) = 1,
    @TipoUso         varchar(1) = 'C',
    @TipoBien        varchar(1),
    @GrupoBien       varchar(2),
    @ClaseBien       varchar(2),
    @FamiliaBien     varchar(4),
    @ItemBien        varchar(4),
    @UnidadMedida    numeric(3,0) = NULL,
    @PrecioUnit      numeric(16,6),
    @DescripcionServicio varchar(350) = NULL,
    @Periodos        xml,
    @Usuario         varchar(30),
    @Equipo          varchar(20) = NULL,
    @ItemSec         numeric(6,0) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @UnidadCatalogo numeric(3,0),
        @CategGasto varchar(1),
        @GrupoGasto varchar(1),
        @Techo0 numeric(15,2),
        @Techo1 numeric(15,2),
        @Techo2 numeric(15,2),
        @Techo3 numeric(15,2),
        @Usado0 numeric(15,2),
        @Usado1 numeric(15,2),
        @Usado2 numeric(15,2),
        @Usado3 numeric(15,2),
        @Cant0 numeric(14,2),
        @Cant1 numeric(14,2),
        @Cant2 numeric(14,2),
        @Cant3 numeric(14,2),
        @Monto0 numeric(14,2),
        @Monto1 numeric(14,2),
        @Monto2 numeric(14,2),
        @Monto3 numeric(14,2),
        @CabecerasCoincidentes int,
        @FilasTecho int,
        @ResultadoLock int,
        @RecursoLock nvarchar(255),
        @NuevaCabecera bit;

    DECLARE @P TABLE
    (
        Codigo tinyint NOT NULL PRIMARY KEY,
        C01 numeric(14,2) NOT NULL, C02 numeric(14,2) NOT NULL,
        C03 numeric(14,2) NOT NULL, C04 numeric(14,2) NOT NULL,
        C05 numeric(14,2) NOT NULL, C06 numeric(14,2) NOT NULL,
        C07 numeric(14,2) NOT NULL, C08 numeric(14,2) NOT NULL,
        C09 numeric(14,2) NOT NULL, C10 numeric(14,2) NOT NULL,
        C11 numeric(14,2) NOT NULL, C12 numeric(14,2) NOT NULL
    );

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
    BEGIN
        RAISERROR('El usuario de auditoria es obligatorio.', 16, 1);
        RETURN;
    END;

    IF @FaseCuadro <> 5
    BEGIN
        RAISERROR('Este procedimiento fue homologado solo para FASE_CUADRO=5.', 16, 1);
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

    INSERT INTO @P
    (
        Codigo,C01,C02,C03,C04,C05,C06,
        C07,C08,C09,C10,C11,C12
    )
    SELECT
        N.P.value('@codigo','tinyint'),
        COALESCE(N.P.value('@c01','numeric(14,2)'),0),
        COALESCE(N.P.value('@c02','numeric(14,2)'),0),
        COALESCE(N.P.value('@c03','numeric(14,2)'),0),
        COALESCE(N.P.value('@c04','numeric(14,2)'),0),
        COALESCE(N.P.value('@c05','numeric(14,2)'),0),
        COALESCE(N.P.value('@c06','numeric(14,2)'),0),
        COALESCE(N.P.value('@c07','numeric(14,2)'),0),
        COALESCE(N.P.value('@c08','numeric(14,2)'),0),
        COALESCE(N.P.value('@c09','numeric(14,2)'),0),
        COALESCE(N.P.value('@c10','numeric(14,2)'),0),
        COALESCE(N.P.value('@c11','numeric(14,2)'),0),
        COALESCE(N.P.value('@c12','numeric(14,2)'),0)
    FROM @Periodos.nodes('/Periodos/Periodo') AS N(P);

    IF (SELECT COUNT(*) FROM @P) <> 4
       OR EXISTS (SELECT 1 FROM @P WHERE Codigo NOT BETWEEN 0 AND 3)
       OR EXISTS
       (
           SELECT 1 FROM @P
           WHERE C01<0 OR C02<0 OR C03<0 OR C04<0 OR C05<0 OR C06<0
              OR C07<0 OR C08<0 OR C09<0 OR C10<0 OR C11<0 OR C12<0
       )
    BEGIN
        RAISERROR('El XML debe contener exactamente los periodos 0,1,2,3 y cantidades no negativas.', 16, 1);
        RETURN;
    END;

    SELECT @Cant0=C01+C02+C03+C04+C05+C06+C07+C08+C09+C10+C11+C12 FROM @P WHERE Codigo=0;
    SELECT @Cant1=C01+C02+C03+C04+C05+C06+C07+C08+C09+C10+C11+C12 FROM @P WHERE Codigo=1;
    SELECT @Cant2=C01+C02+C03+C04+C05+C06+C07+C08+C09+C10+C11+C12 FROM @P WHERE Codigo=2;
    SELECT @Cant3=C01+C02+C03+C04+C05+C06+C07+C08+C09+C10+C11+C12 FROM @P WHERE Codigo=3;

    SET @Monto0=ROUND(@Cant0*@PrecioUnit,2);
    SET @Monto1=ROUND(@Cant1*@PrecioUnit,2);
    SET @Monto2=ROUND(@Cant2*@PrecioUnit,2);
    SET @Monto3=ROUND(@Cant3*@PrecioUnit,2);

    IF COALESCE(@Cant0,0)+COALESCE(@Cant1,0)+COALESCE(@Cant2,0)+COALESCE(@Cant3,0) <= 0
    BEGIN
        RAISERROR('Debe existir al menos una cantidad mayor que cero.', 16, 1);
        RETURN;
    END;

    IF @Equipo IS NULL
        SET @Equipo=LEFT(COALESCE(HOST_NAME(),'SISTEMA_EXTERNO'),20);

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;

        SET @RecursoLock='SIGA_CMN_'+CONVERT(varchar(4),@AnoEje)+'_'+
                         CONVERT(varchar(6),@SecEjec)+'_'+@CentroCosto;

        EXEC @ResultadoLock=sys.sp_getapplock
             @Resource=@RecursoLock,
             @LockMode='Exclusive',
             @LockOwner='Transaction',
             @LockTimeout=15000;

        IF @ResultadoLock<0
            RAISERROR('No se pudo bloquear la numeracion del CMN.',16,1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SIG_CENTRO_COSTO WITH (HOLDLOCK)
            WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
              AND CENTRO_COSTO=@CentroCosto AND ESTADO='A'
        )
            RAISERROR('El centro de costo no existe o esta inactivo.',16,1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.META
            WHERE ano_eje=@AnoEje AND sec_ejec=@SecEjec AND sec_func=@SecFunc
        )
            RAISERROR('La meta SEC_FUNC no existe para el ejercicio y ejecutora.',16,1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.FUENTE_FINANC_EJEC
            WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
              AND ORIGEN=@Origen AND FUENTE_FINANC=@FuenteFinanc
              AND ESTADO='A'
        )
            RAISERROR('La fuente de financiamiento no existe o esta inactiva.',16,1);

        SELECT @UnidadCatalogo=UNIDAD_MEDIDA
        FROM dbo.CATALOGO_BIEN_SERV WITH (HOLDLOCK)
        WHERE SEC_EJEC=@SecEjec AND TIPO_BIEN=@TipoBien
          AND GRUPO_BIEN=@GrupoBien AND CLASE_BIEN=@ClaseBien
          AND FAMILIA_BIEN=@FamiliaBien AND ITEM_BIEN=@ItemBien
          AND ESTADO='A';

        IF @UnidadCatalogo IS NULL
            RAISERROR('El item no existe o esta inactivo en CATALOGO_BIEN_SERV.',16,1);

        IF @UnidadMedida IS NULL
            SET @UnidadMedida=@UnidadCatalogo;

        SELECT
            @FilasTecho=COUNT(*),
            @CategGasto=MAX(CATEG_GASTO),
            @GrupoGasto=MAX(GRUPO_GASTO),
            @Techo0=SUM(COALESCE(MNTO_APROB,0)),
            @Techo1=SUM(COALESCE(MNTO_ANNO_01,0)),
            @Techo2=SUM(COALESCE(MNTO_ANNO_02,0)),
            @Techo3=SUM(COALESCE(MNTO_ANNO_03,0))
        FROM dbo.SIG_TECHO_PRESUPUESTO WITH (UPDLOCK,HOLDLOCK)
        WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
          AND CENTRO_COSTO=@CentroCosto AND FASE_CUADRO=@FaseCuadro
          AND ORIGEN=@Origen AND FUENTE_FINANC=@FuenteFinanc
          AND sec_func=@SecFunc AND CLASIFICADOR=@Clasificador;

        IF COALESCE(@FilasTecho,0)=0
            RAISERROR('No existe techo presupuestal compatible con la cabecera CMN.',16,1);

        SET @NuevaCabecera=0;

        IF @Secuencia IS NULL
        BEGIN
            SELECT @CabecerasCoincidentes=COUNT(*), @Secuencia=MAX(SECUENCIA)
            FROM dbo.SIG_CUADRO_NECESIDAD WITH (UPDLOCK,HOLDLOCK)
            WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
              AND CENTRO_COSTO=@CentroCosto AND FASE_CUADRO=@FaseCuadro
              AND TIPO_TAREA=@TipoTarea AND NIVEL_TAREA=@NivelTarea
              AND CODIGO_TAREA=@CodigoTarea AND sec_func=@SecFunc
              AND ORIGEN=@Origen AND FUENTE_FINANC=@FuenteFinanc
              AND CLASIFICADOR=@Clasificador AND TIPO_RECURSO=@TipoRecurso
              AND TIPO_PPTO=@TipoPpto AND TIPO_USO=@TipoUso
              AND tipo_bien=@TipoBien;

            IF @CabecerasCoincidentes>1
                RAISERROR('Hay mas de una cabecera CMN equivalente; informe @Secuencia.',16,1);

            IF @CabecerasCoincidentes=0
            BEGIN
                SELECT @Secuencia=COALESCE(MAX(SECUENCIA),0)+1
                FROM dbo.SIG_CUADRO_NECESIDAD WITH (UPDLOCK,HOLDLOCK)
                WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
                  AND CENTRO_COSTO=@CentroCosto AND FASE_CUADRO=@FaseCuadro;
                SET @NuevaCabecera=1;
            END;
        END
        ELSE IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SIG_CUADRO_NECESIDAD WITH (UPDLOCK,HOLDLOCK)
            WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
              AND CENTRO_COSTO=@CentroCosto AND SECUENCIA=@Secuencia
              AND FASE_CUADRO=@FaseCuadro
        )
            RAISERROR('La @Secuencia informada no existe.',16,1);

        IF @NuevaCabecera=1
        BEGIN
            INSERT INTO dbo.SIG_CUADRO_NECESIDAD
            (
                ANO_EJE,SEC_EJEC,CENTRO_COSTO,SECUENCIA,FASE_CUADRO,
                TIPO_TAREA,NIVEL_TAREA,CODIGO_TAREA,SEC_FUNC_PROP,sec_func,
                ORIGEN,FUENTE_FINANC,CATEG_GASTO,GRUPO_GASTO,CLASIFICADOR,
                TIPO_RECURSO,TOTAL_APROB,MONTO_APROB,VALOR_IMP_APROB,
                TIPO_IMPUESTO,TASA_IMPTO,FLAG_GASTO,TIPO_PPTO,TIPO_USO,
                EQUIPO_REG,FECHA_REG,CUSER_ID,tipo_bien,
                TIPO_ORIGEN_EXTERNO,sec_establec,flag_origen_cab,
                MONTO_APROB_ANNO_01,MONTO_APROB_ANNO_02,MONTO_APROB_ANNO_03
            )
            VALUES
            (
                @AnoEje,@SecEjec,@CentroCosto,@Secuencia,@FaseCuadro,
                @TipoTarea,@NivelTarea,@CodigoTarea,@SecFuncProp,@SecFunc,
                @Origen,@FuenteFinanc,@CategGasto,@GrupoGasto,@Clasificador,
                @TipoRecurso,@Techo0,@Techo0,0,
                '0',0,'0',@TipoPpto,@TipoUso,
                @Equipo,GETDATE(),@Usuario,@TipoBien,
                '0',0,CONVERT(varchar(1),@FaseCuadro),
                @Techo1,@Techo2,@Techo3
            );
        END;

        IF EXISTS
        (
            SELECT 1 FROM dbo.SIG_CUADRO_NECESIDAD_DET WITH (HOLDLOCK)
            WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
              AND CENTRO_COSTO=@CentroCosto AND SECUENCIA=@Secuencia
              AND FASE_CUADRO=@FaseCuadro AND TIPO_BIEN=@TipoBien
              AND GRUPO_BIEN=@GrupoBien AND CLASE_BIEN=@ClaseBien
              AND FAMILIA_BIEN=@FamiliaBien AND ITEM_BIEN=@ItemBien
              AND ESTADO IN ('5','6')
        )
            RAISERROR('El item ya esta registrado en la cabecera CMN.',16,1);

        SELECT
            @Usado0=COALESCE(SUM(MNTO_TOTAL),0),
            @Usado1=COALESCE(SUM(MNTO_TOTAL_ANNO_01),0),
            @Usado2=COALESCE(SUM(MNTO_TOTAL_ANNO_02),0),
            @Usado3=COALESCE(SUM(MNTO_TOTAL_ANNO_03),0)
        FROM dbo.SIG_CUADRO_NECESIDAD_DET WITH (UPDLOCK,HOLDLOCK)
        WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
          AND CENTRO_COSTO=@CentroCosto AND FASE_CUADRO=@FaseCuadro
          AND ESTADO IN ('5','6')
          AND SECUENCIA IN
          (
              SELECT SECUENCIA FROM dbo.SIG_CUADRO_NECESIDAD
              WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
                AND CENTRO_COSTO=@CentroCosto AND FASE_CUADRO=@FaseCuadro
                AND ORIGEN=@Origen AND FUENTE_FINANC=@FuenteFinanc
                AND sec_func=@SecFunc AND CLASIFICADOR=@Clasificador
          );

        IF COALESCE(@Usado0,0)+@Monto0>COALESCE(@Techo0,0)
           OR COALESCE(@Usado1,0)+@Monto1>COALESCE(@Techo1,0)
           OR COALESCE(@Usado2,0)+@Monto2>COALESCE(@Techo2,0)
           OR COALESCE(@Usado3,0)+@Monto3>COALESCE(@Techo3,0)
            RAISERROR('El item excede el techo CMN de uno de los cuatro periodos.',16,1);

        SELECT @ItemSec=COALESCE(MAX(ITEM_SEC),0)+1
        FROM dbo.SIG_CUADRO_NECESIDAD_DET WITH (UPDLOCK,HOLDLOCK)
        WHERE ANO_EJE=@AnoEje AND SEC_EJEC=@SecEjec
          AND CENTRO_COSTO=@CentroCosto AND SECUENCIA=@Secuencia
          AND FASE_CUADRO=@FaseCuadro;

        INSERT INTO dbo.SIG_CUADRO_NECESIDAD_DET
        (
            ANO_EJE,SEC_EJEC,CENTRO_COSTO,SECUENCIA,FASE_CUADRO,ITEM_SEC,
            TIPO_BIEN,GRUPO_BIEN,CLASE_BIEN,FAMILIA_BIEN,ITEM_BIEN,
            DESCRIP_SERVICIO,UNIDAD_MEDIDA,PRECIO_UNIT,
            CANT_01,CANT_02,CANT_03,CANT_04,CANT_05,CANT_06,
            CANT_07,CANT_08,CANT_09,CANT_10,CANT_11,CANT_12,CANT_TOTAL,
            MNTO_01,MNTO_02,MNTO_03,MNTO_04,MNTO_05,MNTO_06,
            MNTO_07,MNTO_08,MNTO_09,MNTO_10,MNTO_11,MNTO_12,MNTO_TOTAL,
            ESTADO,FLAG_GASTO,FLAG_MODIF,EQUIPO_REG,CUSER_ID,FECHA_REG,
            tipo_origen_externo_det,flag_origen_det,ESTADO_ITEM_KIT,FLAG_PREVISION,
            CANT_01_ANNO_01,CANT_02_ANNO_01,CANT_03_ANNO_01,CANT_04_ANNO_01,
            CANT_05_ANNO_01,CANT_06_ANNO_01,CANT_07_ANNO_01,CANT_08_ANNO_01,
            CANT_09_ANNO_01,CANT_10_ANNO_01,CANT_11_ANNO_01,CANT_12_ANNO_01,CANT_TOTAL_ANNO_01,
            CANT_01_ANNO_02,CANT_02_ANNO_02,CANT_03_ANNO_02,CANT_04_ANNO_02,
            CANT_05_ANNO_02,CANT_06_ANNO_02,CANT_07_ANNO_02,CANT_08_ANNO_02,
            CANT_09_ANNO_02,CANT_10_ANNO_02,CANT_11_ANNO_02,CANT_12_ANNO_02,CANT_TOTAL_ANNO_02,
            CANT_01_ANNO_03,CANT_02_ANNO_03,CANT_03_ANNO_03,CANT_04_ANNO_03,
            CANT_05_ANNO_03,CANT_06_ANNO_03,CANT_07_ANNO_03,CANT_08_ANNO_03,
            CANT_09_ANNO_03,CANT_10_ANNO_03,CANT_11_ANNO_03,CANT_12_ANNO_03,CANT_TOTAL_ANNO_03,
            MNTO_01_ANNO_01,MNTO_02_ANNO_01,MNTO_03_ANNO_01,MNTO_04_ANNO_01,
            MNTO_05_ANNO_01,MNTO_06_ANNO_01,MNTO_07_ANNO_01,MNTO_08_ANNO_01,
            MNTO_09_ANNO_01,MNTO_10_ANNO_01,MNTO_11_ANNO_01,MNTO_12_ANNO_01,MNTO_TOTAL_ANNO_01,
            MNTO_01_ANNO_02,MNTO_02_ANNO_02,MNTO_03_ANNO_02,MNTO_04_ANNO_02,
            MNTO_05_ANNO_02,MNTO_06_ANNO_02,MNTO_07_ANNO_02,MNTO_08_ANNO_02,
            MNTO_09_ANNO_02,MNTO_10_ANNO_02,MNTO_11_ANNO_02,MNTO_12_ANNO_02,MNTO_TOTAL_ANNO_02,
            MNTO_01_ANNO_03,MNTO_02_ANNO_03,MNTO_03_ANNO_03,MNTO_04_ANNO_03,
            MNTO_05_ANNO_03,MNTO_06_ANNO_03,MNTO_07_ANNO_03,MNTO_08_ANNO_03,
            MNTO_09_ANNO_03,MNTO_10_ANNO_03,MNTO_11_ANNO_03,MNTO_12_ANNO_03,MNTO_TOTAL_ANNO_03,
            FLG_MNTO_01_ANNO,FLG_MNTO_02_ANNO,FLG_MNTO_03_ANNO,FLG_MNTO_04_ANNO,
            FLG_MNTO_05_ANNO,FLG_MNTO_06_ANNO,FLG_MNTO_07_ANNO,FLG_MNTO_08_ANNO,
            FLG_MNTO_09_ANNO,FLG_MNTO_10_ANNO,FLG_MNTO_11_ANNO,FLG_MNTO_12_ANNO,
            FLG_MNTO_01_ANNO_01,FLG_MNTO_02_ANNO_01,FLG_MNTO_03_ANNO_01,FLG_MNTO_04_ANNO_01,
            FLG_MNTO_05_ANNO_01,FLG_MNTO_06_ANNO_01,FLG_MNTO_07_ANNO_01,FLG_MNTO_08_ANNO_01,
            FLG_MNTO_09_ANNO_01,FLG_MNTO_10_ANNO_01,FLG_MNTO_11_ANNO_01,FLG_MNTO_12_ANNO_01,
            FLG_MNTO_01_ANNO_02,FLG_MNTO_02_ANNO_02,FLG_MNTO_03_ANNO_02,FLG_MNTO_04_ANNO_02,
            FLG_MNTO_05_ANNO_02,FLG_MNTO_06_ANNO_02,FLG_MNTO_07_ANNO_02,FLG_MNTO_08_ANNO_02,
            FLG_MNTO_09_ANNO_02,FLG_MNTO_10_ANNO_02,FLG_MNTO_11_ANNO_02,FLG_MNTO_12_ANNO_02,
            FLG_MNTO_01_ANNO_03,FLG_MNTO_02_ANNO_03,FLG_MNTO_03_ANNO_03,FLG_MNTO_04_ANNO_03,
            FLG_MNTO_05_ANNO_03,FLG_MNTO_06_ANNO_03,FLG_MNTO_07_ANNO_03,FLG_MNTO_08_ANNO_03,
            FLG_MNTO_09_ANNO_03,FLG_MNTO_10_ANNO_03,FLG_MNTO_11_ANNO_03,FLG_MNTO_12_ANNO_03
        )
        SELECT
            @AnoEje,@SecEjec,@CentroCosto,@Secuencia,@FaseCuadro,@ItemSec,
            @TipoBien,@GrupoBien,@ClaseBien,@FamiliaBien,@ItemBien,
            @DescripcionServicio,@UnidadMedida,@PrecioUnit,
            P0.C01,P0.C02,P0.C03,P0.C04,P0.C05,P0.C06,
            P0.C07,P0.C08,P0.C09,P0.C10,P0.C11,P0.C12,@Cant0,
            ROUND(P0.C01*@PrecioUnit,2),ROUND(P0.C02*@PrecioUnit,2),
            ROUND(P0.C03*@PrecioUnit,2),ROUND(P0.C04*@PrecioUnit,2),
            ROUND(P0.C05*@PrecioUnit,2),ROUND(P0.C06*@PrecioUnit,2),
            ROUND(P0.C07*@PrecioUnit,2),ROUND(P0.C08*@PrecioUnit,2),
            ROUND(P0.C09*@PrecioUnit,2),ROUND(P0.C10*@PrecioUnit,2),
            ROUND(P0.C11*@PrecioUnit,2),ROUND(P0.C12*@PrecioUnit,2),@Monto0,
            '5','0','0',@Equipo,@Usuario,GETDATE(),
            '0',CONVERT(varchar(1),@FaseCuadro),'A','0',
            P1.C01,P1.C02,P1.C03,P1.C04,P1.C05,P1.C06,
            P1.C07,P1.C08,P1.C09,P1.C10,P1.C11,P1.C12,@Cant1,
            P2.C01,P2.C02,P2.C03,P2.C04,P2.C05,P2.C06,
            P2.C07,P2.C08,P2.C09,P2.C10,P2.C11,P2.C12,@Cant2,
            P3.C01,P3.C02,P3.C03,P3.C04,P3.C05,P3.C06,
            P3.C07,P3.C08,P3.C09,P3.C10,P3.C11,P3.C12,@Cant3,
            ROUND(P1.C01*@PrecioUnit,2),ROUND(P1.C02*@PrecioUnit,2),
            ROUND(P1.C03*@PrecioUnit,2),ROUND(P1.C04*@PrecioUnit,2),
            ROUND(P1.C05*@PrecioUnit,2),ROUND(P1.C06*@PrecioUnit,2),
            ROUND(P1.C07*@PrecioUnit,2),ROUND(P1.C08*@PrecioUnit,2),
            ROUND(P1.C09*@PrecioUnit,2),ROUND(P1.C10*@PrecioUnit,2),
            ROUND(P1.C11*@PrecioUnit,2),ROUND(P1.C12*@PrecioUnit,2),@Monto1,
            ROUND(P2.C01*@PrecioUnit,2),ROUND(P2.C02*@PrecioUnit,2),
            ROUND(P2.C03*@PrecioUnit,2),ROUND(P2.C04*@PrecioUnit,2),
            ROUND(P2.C05*@PrecioUnit,2),ROUND(P2.C06*@PrecioUnit,2),
            ROUND(P2.C07*@PrecioUnit,2),ROUND(P2.C08*@PrecioUnit,2),
            ROUND(P2.C09*@PrecioUnit,2),ROUND(P2.C10*@PrecioUnit,2),
            ROUND(P2.C11*@PrecioUnit,2),ROUND(P2.C12*@PrecioUnit,2),@Monto2,
            ROUND(P3.C01*@PrecioUnit,2),ROUND(P3.C02*@PrecioUnit,2),
            ROUND(P3.C03*@PrecioUnit,2),ROUND(P3.C04*@PrecioUnit,2),
            ROUND(P3.C05*@PrecioUnit,2),ROUND(P3.C06*@PrecioUnit,2),
            ROUND(P3.C07*@PrecioUnit,2),ROUND(P3.C08*@PrecioUnit,2),
            ROUND(P3.C09*@PrecioUnit,2),ROUND(P3.C10*@PrecioUnit,2),
            ROUND(P3.C11*@PrecioUnit,2),ROUND(P3.C12*@PrecioUnit,2),@Monto3,
            '1','1','1','1','1','1','1','1','1','1','1','1',
            '1','1','1','1','1','1','1','1','1','1','1','1',
            '1','1','1','1','1','1','1','1','1','1','1','1',
            '1','1','1','1','1','1','1','1','1','1','1','1'
        FROM @P P0
        CROSS JOIN @P P1
        CROSS JOIN @P P2
        CROSS JOIN @P P3
        WHERE P0.Codigo=0 AND P1.Codigo=1 AND P2.Codigo=2 AND P3.Codigo=3;

        COMMIT TRANSACTION;

        SELECT
            @AnoEje AS ANO_EJE,
            @SecEjec AS SEC_EJEC,
            @CentroCosto AS CENTRO_COSTO,
            @Secuencia AS SECUENCIA,
            @FaseCuadro AS FASE_CUADRO,
            @ItemSec AS ITEM_SEC,
            '5' AS ESTADO,
            CASE WHEN @NuevaCabecera=1 THEN 'CABECERA_E_ITEM' ELSE 'ITEM' END AS REGISTRADO;
    END TRY
    BEGIN CATCH
        DECLARE @MensajeError nvarchar(4000), @SeveridadError int, @EstadoError int;
        SELECT @MensajeError=ERROR_MESSAGE(),
               @SeveridadError=ERROR_SEVERITY(),
               @EstadoError=ERROR_STATE();
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        RAISERROR(@MensajeError,@SeveridadError,@EstadoError);
        RETURN;
    END CATCH;
END;
GO

/*
-- EJEMPLO DE HOMOLOGACION. REEMPLAZAR LOS DATOS Y EJECUTAR CON ROLLBACK.
DECLARE @Secuencia numeric(10,0), @ItemSec numeric(6,0);
DECLARE @Periodos xml;

SET @Periodos='<Periodos>
  <Periodo codigo="0" c01="1" c02="0" c03="0" c04="0" c05="0" c06="0" c07="0" c08="0" c09="0" c10="0" c11="0" c12="0" />
  <Periodo codigo="1" c01="1" c02="0" c03="0" c04="0" c05="0" c06="0" c07="0" c08="0" c09="0" c10="0" c11="0" c12="0" />
  <Periodo codigo="2" c01="0" c02="0" c03="0" c04="0" c05="0" c06="0" c07="0" c08="0" c09="0" c10="0" c11="0" c12="0" />
  <Periodo codigo="3" c01="0" c02="0" c03="0" c04="0" c05="0" c06="0" c07="0" c08="0" c09="0" c10="0" c11="0" c12="0" />
</Periodos>';

BEGIN TRANSACTION;

EXEC dbo.usp_ext_registrar_item_cmn
     @AnoEje=2026,
     @SecEjec=1750,
     @CentroCosto='CENTRO_PRUEBA',
     @FaseCuadro=5,
     @Secuencia=@Secuencia OUTPUT,
     @TipoTarea='1',
     @NivelTarea='C',
     @CodigoTarea=999,
     @SecFunc=999,
     @Origen='1',
     @FuenteFinanc='00',
     @Clasificador='2.3. 1  1. 1  1',
     @TipoBien='B',
     @GrupoBien='09',
     @ClaseBien='11',
     @FamiliaBien='0007',
     @ItemBien='0041',
     @PrecioUnit=11.00,
     @Periodos=@Periodos,
     @Usuario='USUARIO_EXT',
     @Equipo='SERVICIO_WEB',
     @ItemSec=@ItemSec OUTPUT;

SELECT @Secuencia AS SECUENCIA, @ItemSec AS ITEM_SEC;
ROLLBACK TRANSACTION;
*/
