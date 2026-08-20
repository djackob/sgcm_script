USE [SIGA_1750];
GO

/*
  usp_ext_excluir_item_cmn
  Exclusion de un item del Cuadro Multianual de Necesidades (ruta de MODIFICACION).

  ORIGEN DE ESTE ARCHIVO
  ----------------------
  El procedimiento fue instalado en SIGA_1750 el 2026-08-19 sin dejar el fuente
  en disco. Este archivo lo recupera desde sys.sql_modules y le aplica UNA
  correccion, marcada abajo. La version instalada hoy en la base NO incluye la
  correccion: hay que reinstalarla con este archivo.

  CORRECCION APLICADA
  -------------------
  SIG_CUADRO_MODIFICADO_DET_ORI.TIPO pasa de '2' a '1'.

  Evidencia: en SIGA_1750, sobre 2024/2025/2026, el cliente SIGA solo escribe
  TIPO='1' (snapshot de una solicitud de modificacion: 1368 + 1560 + 1280 filas)
  y TIPO='3' (transferencias). TIPO='2' aparece unicamente en las 4 filas que
  dejo la prueba de esta integracion. Con TIPO='2' la pantalla de Demanda
  Adicional no encuentra el snapshot y no puede mostrar la cantidad anterior
  ni calcular la diferencia de la exclusion.

  QUE HACE, EN ORDEN
  ------------------
  1. Bloquea el item y la numeracion de solicitudes del centro de costo.
  2. Exige las cuatro filas multianuales (ANNO_PROG = ano .. ano+3).
  3. Guarda el snapshot en SIG_CUADRO_MODIFICADO_DET_ORI (TIPO='1').
  4. Crea o reutiliza SIG_SOLICITUD_MODIFICACION en ESTADO='2' (enviada) y su
     detalle con MOTIVO='2'.
  5. Registra el movimiento en SIG_DOCUMENTO_ESTADO (ESTADO='2', ultimo mov.).
  6. Pone el item en ESTADO='E', FLAG_MODIFICADO='1', MOTIVO_SOLICITUD='2' y
     cantidades e importes en cero.

  Coincide con el UPDATE del cliente SIGA extraido de sig_aba_wind30.pbd:
      update SIG_CUADRO_MODIFICADO_DET
         set ESTADO='E', FLAG_MODIFICADO='1', MOTIVO_SOLICITUD='2', CANT_01=...

  QUE NO HACE, A PROPOSITO
  ------------------------
  - No aprueba la solicitud. La aprobacion (ESTADO='3') es del flujo oficial.
  - No toca SIG_CUADRO_MODIFICADO_SALDO. El cliente SIGA tampoco lo exige: de
    las 896 filas realmente excluidas en 2026, 577 quedaron con saldo en cero y
    319 con saldo residual. El item deja de ser consumible por el filtro de la
    pantalla de requerimiento, no por el saldo:
        ESTADO NOT IN ('E','ET','IC') AND MOTIVO_SOLICITUD IN ('0','3')
  - No consolida el CMN.
*/

/*
  Se fija QUOTED_IDENTIFIER ON por coherencia con el resto de los
  procedimientos de integracion: la opcion queda grabada con el objeto y
  sqlcmd abre la sesion con la opcion en OFF.
*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.usp_ext_excluir_item_cmn', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ext_excluir_item_cmn;
GO

CREATE PROCEDURE dbo.usp_ext_excluir_item_cmn
    @AnoEje          numeric(4,0),
    @SecEjec         numeric(6,0),
    @CentroCosto     varchar(15),
    @SecCuadro       numeric(10,0),
    @SecItem         numeric(10,0),
    @TipoBien        varchar(1),
    @GrupoBien       varchar(2),
    @ClaseBien       varchar(2),
    @FamiliaBien     varchar(4),
    @ItemBien        varchar(4),
    @Usuario         varchar(30),
    @Equipo          varchar(20) = NULL,
    @Glosa           varchar(500) = NULL,
    @FilasActualizadas int = NULL OUTPUT,
    @SecSolicitud    numeric(10,0) = NULL OUTPUT,
    /* Ver la nota de usp_ext_incluir_item_cmn: por defecto no devuelve filas,
       porque W001 lo invoca dentro de un INSERT ... EXEC. */
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


    DECLARE @ResultadoLock int,
            @RecursoLock nvarchar(255),
            @Filas int,
            @Anios int,
            @YaExcluidas int,
            @Elegibles int,
            @SecDocEstado numeric(10,0),
            @Ahora datetime;

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
    BEGIN
        RAISERROR('El usuario de auditoria es obligatorio.',16,1);
        RETURN;
    END;

    IF @SecCuadro IS NULL OR @SecItem IS NULL
    BEGIN
        RAISERROR('SecCuadro y SecItem son obligatorios para una exclusion.',16,1);
        RETURN;
    END;

    IF @Equipo IS NULL
        SET @Equipo=LEFT(COALESCE(HOST_NAME(),'SISTEMA_EXTERNO'),20);

    SET @Ahora=GETDATE();
    SET @Glosa=LEFT(COALESCE(NULLIF(LTRIM(RTRIM(@Glosa)),''),
        'EXCLUSION REGISTRADA DESDE SIGCM'),500);

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        IF @trnPropia = 1 BEGIN TRANSACTION;
        SET @RecursoLock='SIGA_CMN_EXCLUIR_'+CONVERT(varchar(4),@AnoEje)+'_'+
                         CONVERT(varchar(6),@SecEjec)+'_'+@CentroCosto+'_'+
                         CONVERT(varchar(20),@SecCuadro)+'_'+CONVERT(varchar(20),@SecItem);

        EXEC @ResultadoLock=sys.sp_getapplock
             @Resource=@RecursoLock,
             @LockMode='Exclusive',
             @LockOwner='Transaction',
             @LockTimeout=15000;

        IF @ResultadoLock<0
            RAISERROR('No se pudo bloquear el item del CMN para excluirlo.',16,1);

        /* La numeracion de solicitudes se obtiene por centro de costo. El
           bloqueo de aplicacion evita colisiones con otros consumidores del
           procedimiento; UPDLOCK/HOLDLOCK protege la lectura del maximo. */
        SET @RecursoLock='SIGA_SOL_MOD_'+CONVERT(varchar(6),@SecEjec)+'_'+
                         CONVERT(varchar(4),@AnoEje)+'_'+@CentroCosto;

        EXEC @ResultadoLock=sys.sp_getapplock
             @Resource=@RecursoLock,
             @LockMode='Exclusive',
             @LockOwner='Transaction',
             @LockTimeout=15000;

        IF @ResultadoLock<0
            RAISERROR('No se pudo reservar la numeracion de la solicitud SIGA.',16,1);

        IF NOT EXISTS
        (
            SELECT 1
              FROM dbo.SIG_CUADRO_MODIFICADO WITH (UPDLOCK,HOLDLOCK)
             WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
               AND CENTRO_COSTO=@CentroCosto AND SEC_CUADRO=@SecCuadro
        )
            RAISERROR('La cabecera del cuadro modificado no existe.',16,1);

        SELECT @Filas=COUNT(*),
               @Anios=COUNT(DISTINCT ANNO_PROG),
               @YaExcluidas=SUM(CASE WHEN ESTADO='E' AND FLAG_MODIFICADO='1'
                                           AND FLAG_SOLICITUD='0' AND MOTIVO_SOLICITUD='2'
                                           AND CANT_TOTAL=0 AND MNTO_TOTAL=0
                                      THEN 1 ELSE 0 END),
               @Elegibles=SUM(CASE WHEN ESTADO IN ('C','I')
                                         AND FLAG_MODIFICADO='0' AND FLAG_SOLICITUD='0'
                                         AND MOTIVO_SOLICITUD='0'
                                    THEN 1 ELSE 0 END)
          FROM dbo.SIG_CUADRO_MODIFICADO_DET WITH (UPDLOCK,HOLDLOCK)
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
           AND CENTRO_COSTO=@CentroCosto AND SEC_CUADRO=@SecCuadro
           AND SEC_ITEM=@SecItem AND ANNO_PROG BETWEEN @AnoEje AND @AnoEje+3;

        IF COALESCE(@Filas,0)<>4 OR COALESCE(@Anios,0)<>4
            RAISERROR('El item no tiene las cuatro filas multianuales esperadas.',16,1);

        IF EXISTS
        (
            SELECT 1
              FROM dbo.SIG_CUADRO_MODIFICADO_DET WITH (HOLDLOCK)
             WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
               AND CENTRO_COSTO=@CentroCosto AND SEC_CUADRO=@SecCuadro
               AND SEC_ITEM=@SecItem AND ANNO_PROG BETWEEN @AnoEje AND @AnoEje+3
               AND (TIPO_BIEN<>@TipoBien OR GRUPO_BIEN<>@GrupoBien
                    OR CLASE_BIEN<>@ClaseBien OR FAMILIA_BIEN<>@FamiliaBien
                    OR ITEM_BIEN<>@ItemBien)
        )
            RAISERROR('La referencia no corresponde al item indicado en la solicitud.',16,1);

        IF COALESCE(@YaExcluidas,0)<>4 AND COALESCE(@Elegibles,0)<>4
            RAISERROR('El item ya fue modificado, no esta activo o no es elegible para exclusion.',16,1);

        IF COALESCE(@YaExcluidas,0)<>4 AND NOT EXISTS
        (
            SELECT 1
              FROM dbo.SIG_CUADRO_MODIFICADO_DET WITH (HOLDLOCK)
             WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
               AND CENTRO_COSTO=@CentroCosto AND SEC_CUADRO=@SecCuadro
               AND SEC_ITEM=@SecItem AND ANNO_PROG BETWEEN @AnoEje AND @AnoEje+3
               AND CANT_TOTAL>0
        )
            RAISERROR('El item no tiene cantidades vigentes para excluir.',16,1);

        /* El cliente SIGA ejecuta esta copia antes de poner el item en E.
           La pantalla de Demanda Adicional usa estas filas para mostrar la
           cantidad anterior y calcular la diferencia de la exclusion. */
        INSERT INTO dbo.SIG_CUADRO_MODIFICADO_DET_ORI
            (SEC_EJEC,ANNO_EJEC,CENTRO_COSTO,SEC_CUADRO,SEC_ITEM,ANNO_PROG,TIPO,
             FLG_MNTO_01_INI,FLG_MNTO_02_INI,FLG_MNTO_03_INI,FLG_MNTO_04_INI,
             FLG_MNTO_05_INI,FLG_MNTO_06_INI,FLG_MNTO_07_INI,FLG_MNTO_08_INI,
             FLG_MNTO_09_INI,FLG_MNTO_10_INI,FLG_MNTO_11_INI,FLG_MNTO_12_INI,
             CANT_01_INI,CANT_02_INI,CANT_03_INI,CANT_04_INI,CANT_05_INI,CANT_06_INI,
             CANT_07_INI,CANT_08_INI,CANT_09_INI,CANT_10_INI,CANT_11_INI,CANT_12_INI,
             CANT_TOTAL_INI)
        SELECT d.SEC_EJEC,d.ANNO_EJEC,d.CENTRO_COSTO,d.SEC_CUADRO,d.SEC_ITEM,d.ANNO_PROG,'1',
               CASE WHEN x.C01<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C02<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C03<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C04<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C05<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C06<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C07<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C08<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C09<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C10<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C11<>0 THEN '1' ELSE '0' END,
               CASE WHEN x.C12<>0 THEN '1' ELSE '0' END,
               x.C01,x.C02,x.C03,x.C04,x.C05,x.C06,
               x.C07,x.C08,x.C09,x.C10,x.C11,x.C12,
               x.C01+x.C02+x.C03+x.C04+x.C05+x.C06+
               x.C07+x.C08+x.C09+x.C10+x.C11+x.C12
          FROM dbo.SIG_CUADRO_MODIFICADO_DET AS d
          LEFT JOIN dbo.SIG_CUADRO_MODIFICADO_SALDO AS s
            ON s.SEC_EJEC=d.SEC_EJEC AND s.ANNO_EJEC=d.ANNO_EJEC
           AND s.SEC_CUA_MOD_SAL=d.SEC_CUA_MOD_SAL
         CROSS APPLY
         (
             SELECT
               C01=CASE WHEN @YaExcluidas=4 THEN s.CANT_01+s.CANT_01_SC+s.CANT_01_CMN ELSE d.CANT_01 END,
               C02=CASE WHEN @YaExcluidas=4 THEN s.CANT_02+s.CANT_02_SC+s.CANT_02_CMN ELSE d.CANT_02 END,
               C03=CASE WHEN @YaExcluidas=4 THEN s.CANT_03+s.CANT_03_SC+s.CANT_03_CMN ELSE d.CANT_03 END,
               C04=CASE WHEN @YaExcluidas=4 THEN s.CANT_04+s.CANT_04_SC+s.CANT_04_CMN ELSE d.CANT_04 END,
               C05=CASE WHEN @YaExcluidas=4 THEN s.CANT_05+s.CANT_05_SC+s.CANT_05_CMN ELSE d.CANT_05 END,
               C06=CASE WHEN @YaExcluidas=4 THEN s.CANT_06+s.CANT_06_SC+s.CANT_06_CMN ELSE d.CANT_06 END,
               C07=CASE WHEN @YaExcluidas=4 THEN s.CANT_07+s.CANT_07_SC+s.CANT_07_CMN ELSE d.CANT_07 END,
               C08=CASE WHEN @YaExcluidas=4 THEN s.CANT_08+s.CANT_08_SC+s.CANT_08_CMN ELSE d.CANT_08 END,
               C09=CASE WHEN @YaExcluidas=4 THEN s.CANT_09+s.CANT_09_SC+s.CANT_09_CMN ELSE d.CANT_09 END,
               C10=CASE WHEN @YaExcluidas=4 THEN s.CANT_10+s.CANT_10_SC+s.CANT_10_CMN ELSE d.CANT_10 END,
               C11=CASE WHEN @YaExcluidas=4 THEN s.CANT_11+s.CANT_11_SC+s.CANT_11_CMN ELSE d.CANT_11 END,
               C12=CASE WHEN @YaExcluidas=4 THEN s.CANT_12+s.CANT_12_SC+s.CANT_12_CMN ELSE d.CANT_12 END
         ) AS x
         WHERE d.SEC_EJEC=@SecEjec AND d.ANNO_EJEC=@AnoEje
           AND d.CENTRO_COSTO=@CentroCosto AND d.SEC_CUADRO=@SecCuadro
           AND d.SEC_ITEM=@SecItem AND d.ANNO_PROG BETWEEN @AnoEje AND @AnoEje+3
           AND NOT EXISTS
               (SELECT 1 FROM dbo.SIG_CUADRO_MODIFICADO_DET_ORI AS o
                 WHERE o.SEC_EJEC=d.SEC_EJEC AND o.ANNO_EJEC=d.ANNO_EJEC
                   AND o.CENTRO_COSTO=d.CENTRO_COSTO AND o.SEC_CUADRO=d.SEC_CUADRO
                   AND o.SEC_ITEM=d.SEC_ITEM AND o.ANNO_PROG=d.ANNO_PROG AND o.TIPO='1');

        /* Una exclusiÃ³n validada en SIGCM equivale a una solicitud enviada
           (estado 2) en SIGA. La aprobaciÃ³n/grupo del Anexo 4 es otra etapa. */
        SELECT TOP 1 @SecSolicitud=md.SEC_SOL_MOD
          FROM dbo.SIG_SOLICITUD_MODIFICACION_DET AS md WITH (UPDLOCK,HOLDLOCK)
          JOIN dbo.SIG_SOLICITUD_MODIFICACION AS sm WITH (UPDLOCK,HOLDLOCK)
            ON sm.SEC_EJEC=md.SEC_EJEC AND sm.ANNO_EJEC=md.ANNO_EJEC
           AND sm.CENTRO_COSTO=md.CENTRO_COSTO AND sm.SEC_SOL_MOD=md.SEC_SOL_MOD
         WHERE md.SEC_EJEC=@SecEjec AND md.ANNO_EJEC=@AnoEje
           AND md.CENTRO_COSTO=@CentroCosto AND md.SEC_CUADRO=@SecCuadro
           AND md.SEC_ITEM=@SecItem AND md.MOTIVO='2' AND sm.ESTADO IN ('1','2','3')
         GROUP BY md.SEC_SOL_MOD
        HAVING COUNT(*)=4 AND COUNT(DISTINCT md.ANNO_PROG)=4
         ORDER BY md.SEC_SOL_MOD DESC;

        IF @SecSolicitud IS NULL
        BEGIN
            SELECT @SecSolicitud=COALESCE(MAX(SEC_SOL_MOD),0)+1
              FROM dbo.SIG_SOLICITUD_MODIFICACION WITH (UPDLOCK,HOLDLOCK)
             WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
               AND CENTRO_COSTO=@CentroCosto;

            INSERT INTO dbo.SIG_SOLICITUD_MODIFICACION
                (SEC_EJEC,ANNO_EJEC,CENTRO_COSTO,SEC_SOL_MOD,ESTADO,FECHA,GLOSA,
                 CUSER_ID,FECHA_REG,EQUIPO_REG,CUSER_MOD,FECHA_MOD,EQUIPO_MOD,GLOSA_MODIF)
            VALUES
                (@SecEjec,@AnoEje,@CentroCosto,@SecSolicitud,'2',@Ahora,@Glosa,
                 @Usuario,@Ahora,@Equipo,NULL,NULL,NULL,NULL);
        END;

        /* Versiones iniciales de la integracion usaron GLOSA_MODIF como marca
           tecnica. El cliente SIGA muestra ese campo, por eso se limpia. */
        UPDATE dbo.SIG_SOLICITUD_MODIFICACION
           SET GLOSA_MODIF=NULL
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
           AND CENTRO_COSTO=@CentroCosto AND SEC_SOL_MOD=@SecSolicitud
           AND GLOSA_MODIF LIKE 'SIGCM:%';

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SIG_SOLICITUD_MODIFICACION_DET
             WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
               AND CENTRO_COSTO=@CentroCosto AND SEC_SOL_MOD=@SecSolicitud
        )
        BEGIN
            INSERT INTO dbo.SIG_SOLICITUD_MODIFICACION_DET
                (SEC_EJEC,ANNO_EJEC,CENTRO_COSTO,SEC_SOL_MOD,SEC_SOL_MOD_DET,
                 SEC_CUADRO,SEC_ITEM,ANNO_PROG,MOTIVO,PRECIO_UNIT,
                 CANT_01,CANT_02,CANT_03,CANT_04,CANT_05,CANT_06,
                 CANT_07,CANT_08,CANT_09,CANT_10,CANT_11,CANT_12,
                 FLAG_MNTO_INI,CANT_01_INI,CANT_02_INI,CANT_03_INI,CANT_04_INI,
                 CANT_05_INI,CANT_06_INI,CANT_07_INI,CANT_08_INI,CANT_09_INI,
                 CANT_10_INI,CANT_11_INI,CANT_12_INI,CUSER_ID,FECHA_REG,EQUIPO_REG)
            SELECT @SecEjec,@AnoEje,@CentroCosto,@SecSolicitud,
                   ROW_NUMBER() OVER (ORDER BY o.ANNO_PROG),@SecCuadro,@SecItem,o.ANNO_PROG,
                   '2',d.PRECIO_UNIT,
                   0,0,0,0,0,0,0,0,0,0,0,0,
                   o.FLG_MNTO_01_INI+o.FLG_MNTO_02_INI+o.FLG_MNTO_03_INI+
                   o.FLG_MNTO_04_INI+o.FLG_MNTO_05_INI+o.FLG_MNTO_06_INI+
                   o.FLG_MNTO_07_INI+o.FLG_MNTO_08_INI+o.FLG_MNTO_09_INI+
                   o.FLG_MNTO_10_INI+o.FLG_MNTO_11_INI+o.FLG_MNTO_12_INI,
                   o.CANT_01_INI,o.CANT_02_INI,o.CANT_03_INI,o.CANT_04_INI,
                   o.CANT_05_INI,o.CANT_06_INI,o.CANT_07_INI,o.CANT_08_INI,
                   o.CANT_09_INI,o.CANT_10_INI,o.CANT_11_INI,o.CANT_12_INI,
                   @Usuario,@Ahora,@Equipo
              FROM dbo.SIG_CUADRO_MODIFICADO_DET_ORI AS o
              JOIN dbo.SIG_CUADRO_MODIFICADO_DET AS d
                ON d.SEC_EJEC=o.SEC_EJEC AND d.ANNO_EJEC=o.ANNO_EJEC
               AND d.CENTRO_COSTO=o.CENTRO_COSTO AND d.SEC_CUADRO=o.SEC_CUADRO
               AND d.SEC_ITEM=o.SEC_ITEM AND d.ANNO_PROG=o.ANNO_PROG
             WHERE o.SEC_EJEC=@SecEjec AND o.ANNO_EJEC=@AnoEje
               AND o.CENTRO_COSTO=@CentroCosto AND o.SEC_CUADRO=@SecCuadro
               AND o.SEC_ITEM=@SecItem AND o.TIPO='1';
        END;

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SIG_DOCUMENTO_ESTADO
             WHERE SEC_EJEC=@SecEjec AND ESTADO='2'
               AND SOL_ANNO_EJEC=@AnoEje AND SOL_CC=@CentroCosto
               AND SEC_SOL_MOD=@SecSolicitud
        )
        BEGIN
            SELECT @SecDocEstado=COALESCE(MAX(SEC_DOC_EST),0)+1
              FROM dbo.SIG_DOCUMENTO_ESTADO WITH (UPDLOCK,HOLDLOCK)
             WHERE SEC_EJEC=@SecEjec AND ESTADO='2';

            INSERT INTO dbo.SIG_DOCUMENTO_ESTADO
                (SEC_EJEC,SEC_DOC_EST,ESTADO,FLAG_ULT_MOV,FECHA,OBSERVACION,
                 CUSER_ID,FECHA_REG,EQUIPO_REG,SOL_ANNO_EJEC,SOL_CC,SEC_SOL_MOD,
                 SOL_GRU_ANNO_EJEC,SOL_GRU_SEC)
            VALUES
                (@SecEjec,@SecDocEstado,'2','1',@Ahora,NULL,@Usuario,@Ahora,@Equipo,
                 @AnoEje,@CentroCosto,@SecSolicitud,NULL,NULL);
        END;

        IF COALESCE(@YaExcluidas,0)<>4
        UPDATE dbo.SIG_CUADRO_MODIFICADO_DET
           SET ESTADO='E',
               FLAG_MODIFICADO='1',
               FLAG_SOLICITUD='0',
               MOTIVO_SOLICITUD='2',
               FLG_MNTO_01='0',FLG_MNTO_02='0',FLG_MNTO_03='0',FLG_MNTO_04='0',
               FLG_MNTO_05='0',FLG_MNTO_06='0',FLG_MNTO_07='0',FLG_MNTO_08='0',
               FLG_MNTO_09='0',FLG_MNTO_10='0',FLG_MNTO_11='0',FLG_MNTO_12='0',
               CANT_01=0,CANT_02=0,CANT_03=0,CANT_04=0,CANT_05=0,CANT_06=0,
               CANT_07=0,CANT_08=0,CANT_09=0,CANT_10=0,CANT_11=0,CANT_12=0,
               CANT_TOTAL=0,
               MNTO_01=0,MNTO_02=0,MNTO_03=0,MNTO_04=0,MNTO_05=0,MNTO_06=0,
               MNTO_07=0,MNTO_08=0,MNTO_09=0,MNTO_10=0,MNTO_11=0,MNTO_12=0,
               MNTO_TOTAL=0,
               CUSER_MOD=@Usuario,FECHA_MOD=GETDATE(),EQUIPO_MOD=@Equipo
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
           AND CENTRO_COSTO=@CentroCosto AND SEC_CUADRO=@SecCuadro
           AND SEC_ITEM=@SecItem AND ANNO_PROG BETWEEN @AnoEje AND @AnoEje+3;

        SET @FilasActualizadas=CASE WHEN @YaExcluidas=4 THEN 0 ELSE @@ROWCOUNT END;

        UPDATE dbo.SIG_CUADRO_MODIFICADO
           SET CUSER_MOD=@Usuario,FECHA_MOD=GETDATE(),EQUIPO_MOD=@Equipo
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
           AND CENTRO_COSTO=@CentroCosto AND SEC_CUADRO=@SecCuadro;

        IF @trnPropia = 1 COMMIT TRANSACTION;

        IF @Detalle = 1
        SELECT @AnoEje AS ANNO_EJEC,@SecEjec AS SEC_EJEC,
               @CentroCosto AS CENTRO_COSTO,@SecCuadro AS SEC_CUADRO,
               @SecItem AS SEC_ITEM,@SecSolicitud AS SEC_SOL_MOD,'E' AS ESTADO,
               @FilasActualizadas AS FILAS_ACTUALIZADAS,'EXCLUIDO' AS RESULTADO;
    END TRY
    BEGIN CATCH
        DECLARE @MensajeError nvarchar(4000),@SeveridadError int,@EstadoError int;
        SELECT @MensajeError=ERROR_MESSAGE(),@SeveridadError=ERROR_SEVERITY(),
               @EstadoError=ERROR_STATE();
        IF @trnPropia = 1 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
        RAISERROR(@MensajeError,@SeveridadError,@EstadoError);
        RETURN;
    END CATCH;
END;
GO




