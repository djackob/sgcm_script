USE [SIGA_1750];
GO

/*
===============================================================================
  usp_ext_aprobar_solicitud_cmn
  Aprobacion y consolidacion de una solicitud de modificacion del CMN.
  Es el efecto en SIGA de la firma del Anexo 4.

  ---------------------------------------------------------------------------
  POR QUE ESTE PROCEDIMIENTO Y NO OTRO
  ---------------------------------------------------------------------------
  El Anexo 3 abre la solicitud: el item queda escrito pero con
  MOTIVO_SOLICITUD distinto de '0', y en ese estado SIGA NO lo deja usar. El
  filtro del selector de items de un requerimiento
  (sig_aba_dawi21_te.pbd) exige:

      MOTIVO_SOLICITUD IN ('0','3')  AND  ESTADO NOT IN ('E','ET','IC')

  Mientras la solicitud siga abierta, la inclusion existe pero no sirve. Lo que
  la habilita es la aprobacion, y eso es lo que hace este procedimiento.

  ---------------------------------------------------------------------------
  QUE ESCRIBE
  ---------------------------------------------------------------------------
  1. SIG_SOLICITUD_MODIFICACION      ESTADO '2' (enviada) -> '3' (aprobada).
  2. SIG_DOCUMENTO_ESTADO            nuevo movimiento con ESTADO='3'.
  3. SIG_CUADRO_MODIFICADO_DET       FLAG_MODIFICADO='0', FLAG_SOLICITUD='0',
                                     MOTIVO_SOLICITUD='0'. ESTADO NO se toca:
                                     lo incluido sigue en 'I' y lo excluido en
                                     'E'. Es lo que hace el cliente SIGA, tal
                                     como aparece en sig_aba_wind30.pbd:

         update SIG_CUADRO_MODIFICADO_DET
            SET FLAG_MODIFICADO='0', FLAG_SOLICITUD='0', MOTIVO_SOLICITUD='0',
                CUSER_MOD=..., FECHA_MOD=..., EQUIPO_MOD=...
          WHERE EXISTS (SELECT 1 FROM SIG_SOLICITUD_MODIFICACION_DET ...)

  Ese tercer paso es el que HABILITA el item: al dejar MOTIVO_SOLICITUD en '0'
  el item pasa el filtro del selector de requerimientos y recien entonces se
  puede pedir.

  ---------------------------------------------------------------------------
  LO QUE ESTE PROCEDIMIENTO NO HACE, Y POR QUE
  ---------------------------------------------------------------------------
  NO escribe en SIG_CUADRO_MODIFICADO_CMN.

  La primera version lo intentaba, porque a simple vista esa tabla parece un
  asiento simple: once columnas, y en una muestra por SEC_CUA_MOD_SAL casi todas
  parecian constantes. Al ejecutarlo, SIGA lo rechazo:

      The INSERT statement conflicted with the FOREIGN KEY constraint
      "FK_SIG_CUA_MOD_CMN_02" ... table "dbo.SIG_PAAC_CENTRO_COSTO"

  SIG_CUADRO_MODIFICADO_CMN tiene una clave foranea de DIEZ columnas
  (ANNO_EJEC, SEC_EJEC, TIPO_CONSOLID, NRO_CONSOLID, TIPO_GENERACION, TIPO_BIEN,
  SEC_CONSOLID, SEC_RESUMEN, SEC_META, SEC_CTRO_COSTO) contra
  SIG_PAAC_CENTRO_COSTO. Es decir: una fila de consolidacion solo puede existir
  si el nodo correspondiente del PAAC ya existe. Y SEC_META no es constante: en
  las filas reales de 01.06.03 toma valores 11, 16, 19, 20...

  Consolidar el CMN es, en SIGA, generar el arbol del PAAC: SIG_PAAC_CONSOLIDADO
  (13 779 filas), SIG_PAAC_METAS (43 077), SIG_PAAC_CENTRO_COSTO (43 181),
  SIG_PAAC_ITEM (26 117) y su numeracion propia. Es un proceso por lotes que
  Abastecimiento corre dentro de SIGA sobre muchas solicitudes a la vez, no el
  efecto de firmar un documento.

  Los datos lo confirman: de las 5 837 inclusiones ya aprobadas del 2026, solo
  4 406 estan consolidadas. Aprobacion y consolidacion no van uno a uno.

  Por eso la firma del Anexo 4 llega hasta la aprobacion, que es lo que el
  SIGCM puede garantizar y lo que el area usuaria necesita para poder pedir. La
  generacion del PAAC queda donde estaba: en SIGA.

  ---------------------------------------------------------------------------
  IDEMPOTENCIA
  ---------------------------------------------------------------------------
  Si la solicitud ya esta en ESTADO='3' el procedimiento no falla: completa lo
  que falte y devuelve el conteo en cero. W001 puede reintentar sin duplicar.

  SQL compatible con el nivel de compatibilidad 100 de SIGA_1750.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.usp_ext_aprobar_solicitud_cmn', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ext_aprobar_solicitud_cmn;
GO

CREATE PROCEDURE dbo.usp_ext_aprobar_solicitud_cmn
    @AnoEje         numeric(4,0),
    @SecEjec        numeric(6,0),
    @CentroCosto    varchar(15),
    @SecSolicitud   numeric(10,0),
    @Usuario        varchar(30),
    @Equipo         varchar(20) = NULL,
    @Glosa          varchar(500) = NULL,
    @ItemsAprobados int = NULL OUTPUT,
    @NroConsolid    numeric(5,0) = NULL OUTPUT,
    /* Ver la nota de usp_ext_incluir_item_cmn: por defecto no devuelve filas,
       porque W001 lo invoca dentro de un INSERT ... EXEC y un conjunto de
       resultados inesperado rompe la insercion y el contrato del backend. */
    @Detalle        bit = 0
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
        @Ahora         datetime,
        @ResultadoLock int,
        @RecursoLock   nvarchar(255),
        @EstadoSol     varchar(1),
        @SecDocEstado  numeric(10,0),
        @Consolidados  int,
        @Msg           nvarchar(400);

    /* Saldos alcanzados por la solicitud, con su tipo de bien. */
    DECLARE @S TABLE
    (
        SecCuaModSal numeric(10,0) NOT NULL PRIMARY KEY,
        TipoBien     varchar(1)    NOT NULL,
        NroConsolid  numeric(5,0)      NULL
    );

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
    BEGIN
        RAISERROR('El usuario de auditoria es obligatorio.', 16, 1);
        RETURN;
    END;

    IF @SecSolicitud IS NULL
    BEGIN
        RAISERROR('SecSolicitud es obligatorio.', 16, 1);
        RETURN;
    END;

    SET @Ahora = GETDATE();
    IF @Equipo IS NULL SET @Equipo = LEFT(COALESCE(HOST_NAME(),'SISTEMA_EXTERNO'), 20);

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        IF @trnPropia = 1 BEGIN TRANSACTION;
        SET @RecursoLock = 'SIGA_CMN_APROBAR_' + CONVERT(varchar(4),@AnoEje) + '_'
                         + CONVERT(varchar(6),@SecEjec) + '_' + @CentroCosto + '_'
                         + CONVERT(varchar(20),@SecSolicitud);

        EXEC @ResultadoLock = sys.sp_getapplock
             @Resource=@RecursoLock, @LockMode='Exclusive',
             @LockOwner='Transaction', @LockTimeout=15000;

        IF @ResultadoLock < 0
            RAISERROR('No se pudo bloquear la solicitud de modificacion.', 16, 1);

        SELECT @EstadoSol = ESTADO
          FROM dbo.SIG_SOLICITUD_MODIFICACION WITH (UPDLOCK, HOLDLOCK)
         WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
           AND CENTRO_COSTO=@CentroCosto AND SEC_SOL_MOD=@SecSolicitud;

        IF @EstadoSol IS NULL
            RAISERROR('La solicitud de modificacion no existe.', 16, 1);

        IF @EstadoSol NOT IN ('2', '3')
            RAISERROR('Solo se puede aprobar una solicitud enviada (estado 2).', 16, 1);

        /* ---- Saldos que cubre la solicitud ----------------------------- */

        INSERT INTO @S (SecCuaModSal, TipoBien)
        SELECT DISTINCT d.SEC_CUA_MOD_SAL, d.TIPO_BIEN
          FROM dbo.SIG_SOLICITUD_MODIFICACION_DET AS sd
          JOIN dbo.SIG_CUADRO_MODIFICADO_DET AS d WITH (UPDLOCK, HOLDLOCK)
            ON d.SEC_EJEC=sd.SEC_EJEC AND d.ANNO_EJEC=sd.ANNO_EJEC
           AND d.CENTRO_COSTO=sd.CENTRO_COSTO AND d.SEC_CUADRO=sd.SEC_CUADRO
           AND d.SEC_ITEM=sd.SEC_ITEM AND d.ANNO_PROG=sd.ANNO_PROG
         WHERE sd.SEC_EJEC=@SecEjec AND sd.ANNO_EJEC=@AnoEje
           AND sd.CENTRO_COSTO=@CentroCosto AND sd.SEC_SOL_MOD=@SecSolicitud;

        IF (SELECT COUNT(*) FROM @S) = 0
            RAISERROR('La solicitud no tiene items en el cuadro modificado.', 16, 1);

        /* ---- 1. Cerrar los flags de la solicitud ----------------------- */
        /* ESTADO no se toca: la inclusion sigue en I y la exclusion en E. */

        UPDATE d
           SET d.FLAG_MODIFICADO  = '0',
               d.FLAG_SOLICITUD   = '0',
               d.MOTIVO_SOLICITUD = '0',
               d.CUSER_MOD = @Usuario, d.FECHA_MOD = @Ahora, d.EQUIPO_MOD = @Equipo
          FROM dbo.SIG_CUADRO_MODIFICADO_DET AS d
         WHERE d.SEC_EJEC=@SecEjec AND d.ANNO_EJEC=@AnoEje
           AND d.CENTRO_COSTO=@CentroCosto
           AND d.MOTIVO_SOLICITUD <> '0'
           AND EXISTS (SELECT 1 FROM dbo.SIG_SOLICITUD_MODIFICACION_DET AS sd
                        WHERE sd.SEC_EJEC=d.SEC_EJEC AND sd.ANNO_EJEC=d.ANNO_EJEC
                          AND sd.CENTRO_COSTO=d.CENTRO_COSTO
                          AND sd.SEC_SOL_MOD=@SecSolicitud
                          AND sd.SEC_CUADRO=d.SEC_CUADRO AND sd.SEC_ITEM=d.SEC_ITEM
                          AND sd.ANNO_PROG=d.ANNO_PROG);

        SET @ItemsAprobados = @@ROWCOUNT;

        /* ---- 2. Consolidacion: se informa, no se escribe ---------------- */
        /* Ver la cabecera. La fila de SIG_CUADRO_MODIFICADO_CMN depende del
           arbol del PAAC por una FK de diez columnas; generarla desde fuera
           exigiria inventar la numeracion del PAAC. Aqui solo se cuenta cuantos
           de los saldos alcanzados YA estaban consolidados, para que el SIGCM
           pueda mostrar si el area usuaria todavia espera la consolidacion. */

        SELECT @Consolidados = COUNT(*)
          FROM @S AS s
          JOIN dbo.SIG_CUADRO_MODIFICADO_CMN AS c
            ON c.SEC_EJEC=@SecEjec AND c.ANNO_EJEC=@AnoEje
           AND c.SEC_CUA_MOD_SAL=s.SecCuaModSal;

        SELECT @NroConsolid = MIN(c.NRO_CONSOLID)
          FROM @S AS s
          JOIN dbo.SIG_CUADRO_MODIFICADO_CMN AS c
            ON c.SEC_EJEC=@SecEjec AND c.ANNO_EJEC=@AnoEje
           AND c.SEC_CUA_MOD_SAL=s.SecCuaModSal;

        /* ---- 3. Estado de la solicitud y su movimiento ----------------- */

        IF @EstadoSol = '2'
        BEGIN
            UPDATE dbo.SIG_SOLICITUD_MODIFICACION
               SET ESTADO = '3',
                   CUSER_MOD = @Usuario, FECHA_MOD = @Ahora, EQUIPO_MOD = @Equipo,
                   GLOSA_MODIF = LEFT(NULLIF(LTRIM(RTRIM(@Glosa)),''), 500)
             WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
               AND CENTRO_COSTO=@CentroCosto AND SEC_SOL_MOD=@SecSolicitud;

            /* FLAG_ULT_MOV marca el ultimo movimiento DE CADA ESTADO, no el de
               la solicitud: en los datos reales conviven un '2' y un '3' con la
               marca en 1. Por eso solo se apaga la de otro '3' anterior. */
            UPDATE dbo.SIG_DOCUMENTO_ESTADO
               SET FLAG_ULT_MOV = '0'
             WHERE SEC_EJEC=@SecEjec AND ESTADO='3' AND SOL_ANNO_EJEC=@AnoEje
               AND SOL_CC=@CentroCosto AND SEC_SOL_MOD=@SecSolicitud
               AND FLAG_ULT_MOV='1';

            SELECT @SecDocEstado = COALESCE(MAX(SEC_DOC_EST),0) + 1
              FROM dbo.SIG_DOCUMENTO_ESTADO WITH (UPDLOCK, HOLDLOCK)
             WHERE SEC_EJEC=@SecEjec AND ESTADO='3';

            INSERT INTO dbo.SIG_DOCUMENTO_ESTADO
                (SEC_EJEC, SEC_DOC_EST, ESTADO, FLAG_ULT_MOV, FECHA, OBSERVACION,
                 CUSER_ID, FECHA_REG, EQUIPO_REG, SOL_ANNO_EJEC, SOL_CC, SEC_SOL_MOD,
                 SOL_GRU_ANNO_EJEC, SOL_GRU_SEC)
            VALUES
                (@SecEjec, @SecDocEstado, '3', '1', @Ahora, NULL,
                 @Usuario, @Ahora, @Equipo, @AnoEje, @CentroCosto, @SecSolicitud,
                 NULL, NULL);
        END;

        IF @trnPropia = 1 COMMIT TRANSACTION;

        IF @Detalle = 1
            SELECT @AnoEje         AS ANNO_EJEC,
                   @SecEjec        AS SEC_EJEC,
                   @CentroCosto    AS CENTRO_COSTO,
                   @SecSolicitud   AS SEC_SOL_MOD,
                   '3'             AS ESTADO_SOLICITUD,
                   @ItemsAprobados AS FILAS_APROBADAS,
                   @Consolidados   AS SALDOS_YA_CONSOLIDADOS,
                   @NroConsolid    AS NRO_CONSOLID,
                   'APROBADO'      AS RESULTADO;
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

PRINT 'Instalado: dbo.usp_ext_aprobar_solicitud_cmn';
GO



