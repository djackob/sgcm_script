:setvar bdSiga "SIGA_1750"
USE [$(bdSiga)];
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
                                     MOTIVO_SOLICITUD='0'. ESTADO NO se toca.
  4. SIG_SOLICITUD_GRUPO + _DET      cabecera de "Generacion de Aprobacion de
                                     Modificaciones al C.M.N." (menu 10032).
                                     Sin este asiento la solicitud queda
                                     aprobada pero NO aparece en esa pantalla.
                                     Varias solicitudes del mismo Anexo 4
                                     SIGCM (mismo @CodigoAnexo4) comparten un
                                     solo SEC_SOL_GRU.

  ---------------------------------------------------------------------------
  LO QUE ESTE PROCEDIMIENTO NO HACE, Y POR QUE
  ---------------------------------------------------------------------------
  NO escribe en SIG_CUADRO_MODIFICADO_CMN (FK de diez columnas contra el PAAC).
  Aprobacion y consolidacion PAAC no van uno a uno.

  ---------------------------------------------------------------------------
  IDEMPOTENCIA
  ---------------------------------------------------------------------------
  Si la solicitud ya esta en ESTADO='3' el procedimiento no falla: completa lo
  que falte (grupo/detalle incluidos) y devuelve el conteo en cero.

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
    /* Codigo del Anexo 4 SIGCM (ej. A4-2026-000003). Varias solicitudes del
       mismo paquete deben enviar el mismo valor para compartir SEC_SOL_GRU. */
    @CodigoAnexo4   varchar(40) = NULL,
    @ItemsAprobados int = NULL OUTPUT,
    @NroConsolid    numeric(5,0) = NULL OUTPUT,
    @SecSolGru      numeric(10,0) = NULL OUTPUT,
    /* Por defecto no devuelve filas: W001 lo invoca dentro de INSERT...EXEC. */
    @Detalle        bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @trnPropia bit = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

    DECLARE
        @Ahora         datetime,
        @ResultadoLock int,
        @RecursoLock   nvarchar(255),
        @EstadoSol     varchar(1),
        @SecDocEstado  numeric(10,0),
        @Consolidados  int,
        @ClaveGrupo    varchar(60),
        @MarcaGrupo    varchar(80),
        @GlosaGrupo    varchar(500),
        @SecDet        numeric(10,0),
        @GrupoNuevo    bit,
        @LockGrupo     int,
        @RecursoGrupo  nvarchar(255);

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

    SET @CodigoAnexo4 = NULLIF(LTRIM(RTRIM(@CodigoAnexo4)), '');
    IF @CodigoAnexo4 IS NULL
        SET @ClaveGrupo = 'SOL:' + @CentroCosto + ':' + CONVERT(varchar(20), @SecSolicitud);
    ELSE
        SET @ClaveGrupo = @CodigoAnexo4;

    SET @MarcaGrupo = '[SIGCM:' + @ClaveGrupo + ']';
    SET @RecursoGrupo = LEFT('SIGA_CMN_GRUPO_' + CONVERT(varchar(4),@AnoEje) + '_'
                      + CONVERT(varchar(6),@SecEjec) + '_' + @ClaveGrupo, 255);

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

        /* ---- 3. Cabecera de aprobacion (pantalla 10032) ----------------- */

        SET @GrupoNuevo = 0;
        SET @SecSolGru = NULL;

        EXEC @LockGrupo = sys.sp_getapplock
             @Resource = @RecursoGrupo,
             @LockMode = 'Exclusive',
             @LockOwner = 'Transaction',
             @LockTimeout = 15000;

        IF @LockGrupo < 0
            RAISERROR('No se pudo bloquear el grupo de aprobacion CMN.', 16, 1);

        SELECT TOP 1 @SecSolGru = g.SEC_SOL_GRU
          FROM dbo.SIG_SOLICITUD_GRUPO AS g WITH (UPDLOCK, HOLDLOCK)
         WHERE g.SEC_EJEC = @SecEjec
           AND g.ANNO_EJEC = @AnoEje
           AND CHARINDEX(@MarcaGrupo, g.GLOSA) > 0
         ORDER BY g.SEC_SOL_GRU DESC;

        IF @SecSolGru IS NULL
        BEGIN
            SELECT @SecSolGru = COALESCE(MAX(SEC_SOL_GRU), 0) + 1
              FROM dbo.SIG_SOLICITUD_GRUPO WITH (UPDLOCK, HOLDLOCK)
             WHERE SEC_EJEC = @SecEjec AND ANNO_EJEC = @AnoEje;

            SET @GlosaGrupo = LEFT(
                'SOLICITUD DE APROBACION DE ANEXO 04 N' + CHAR(176) + ' '
              + RIGHT('000000' + CONVERT(varchar(10), @SecSolGru), 6)
              + '-' + CONVERT(varchar(4), @AnoEje)
              + ' ' + @MarcaGrupo, 500);

            INSERT INTO dbo.SIG_SOLICITUD_GRUPO
                (SEC_EJEC, ANNO_EJEC, SEC_SOL_GRU, ESTADO, FECHA, REFERENCIA, GLOSA,
                 CUSER_ID, FECHA_REG, EQUIPO_REG)
            VALUES
                (@SecEjec, @AnoEje, @SecSolGru, '3', @Ahora,
                 'DIRECTIVA N' + CHAR(176) + ' 0007-2025-EF/54.01', @GlosaGrupo,
                 @Usuario, @Ahora, @Equipo);

            SET @GrupoNuevo = 1;
        END
        ELSE
        BEGIN
            UPDATE dbo.SIG_SOLICITUD_GRUPO
               SET ESTADO = '3',
                   CUSER_MOD = @Usuario,
                   FECHA_MOD = @Ahora,
                   EQUIPO_MOD = @Equipo
             WHERE SEC_EJEC = @SecEjec AND ANNO_EJEC = @AnoEje
               AND SEC_SOL_GRU = @SecSolGru
               AND ESTADO <> '3';
        END

        IF NOT EXISTS (
            SELECT 1
              FROM dbo.SIG_SOLICITUD_GRUPO_DET
             WHERE SEC_EJEC = @SecEjec AND ANNO_EJEC = @AnoEje
               AND SEC_SOL_GRU = @SecSolGru
               AND SOL_ANNO_EJEC = @AnoEje
               AND SOL_CC = @CentroCosto
               AND SEC_SOL_MOD = @SecSolicitud)
        BEGIN
            SELECT @SecDet = COALESCE(MAX(SEC_SOL_GRU_DET), 0) + 1
              FROM dbo.SIG_SOLICITUD_GRUPO_DET WITH (UPDLOCK, HOLDLOCK)
             WHERE SEC_EJEC = @SecEjec AND ANNO_EJEC = @AnoEje
               AND SEC_SOL_GRU = @SecSolGru;

            INSERT INTO dbo.SIG_SOLICITUD_GRUPO_DET
                (SEC_EJEC, ANNO_EJEC, SEC_SOL_GRU, SEC_SOL_GRU_DET,
                 SOL_ANNO_EJEC, SOL_CC, SEC_SOL_MOD)
            VALUES
                (@SecEjec, @AnoEje, @SecSolGru, @SecDet,
                 @AnoEje, @CentroCosto, @SecSolicitud);
        END

        /* ---- 4. Estado de la solicitud y movimientos -------------------
           Patron nativo SIGA (pantalla 10032):
           - Movimiento de la SOLICITUD: SEC_SOL_MOD lleno, SOL_GRU_* NULL.
           - Movimiento de la CABECERA del grupo: SEC_SOL_MOD NULL, SOL_GRU_* lleno.
           Mezclar ambos en la misma fila hace que el DataWindow falle con
           "Subquery returned more than 1 value" al abrir el grupo. */

        IF @EstadoSol = '2'
        BEGIN
            UPDATE dbo.SIG_SOLICITUD_MODIFICACION
               SET ESTADO = '3',
                   CUSER_MOD = @Usuario, FECHA_MOD = @Ahora, EQUIPO_MOD = @Equipo,
                   GLOSA_MODIF = LEFT(NULLIF(LTRIM(RTRIM(@Glosa)),''), 500)
             WHERE SEC_EJEC=@SecEjec AND ANNO_EJEC=@AnoEje
               AND CENTRO_COSTO=@CentroCosto AND SEC_SOL_MOD=@SecSolicitud;

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
        END

        /* Cabecera del grupo: un solo FLAG_ULT_MOV='1' con SEC_SOL_MOD NULL. */
        IF @GrupoNuevo = 1
           OR NOT EXISTS (
                SELECT 1
                  FROM dbo.SIG_DOCUMENTO_ESTADO
                 WHERE SEC_EJEC = @SecEjec AND ESTADO = '3'
                   AND SOL_GRU_ANNO_EJEC = @AnoEje AND SOL_GRU_SEC = @SecSolGru
                   AND SEC_SOL_MOD IS NULL AND FLAG_ULT_MOV = '1')
        BEGIN
            UPDATE dbo.SIG_DOCUMENTO_ESTADO
               SET FLAG_ULT_MOV = '0'
             WHERE SEC_EJEC = @SecEjec AND ESTADO = '3'
               AND SOL_GRU_ANNO_EJEC = @AnoEje AND SOL_GRU_SEC = @SecSolGru
               AND SEC_SOL_MOD IS NULL AND FLAG_ULT_MOV = '1';

            SELECT @SecDocEstado = COALESCE(MAX(SEC_DOC_EST),0) + 1
              FROM dbo.SIG_DOCUMENTO_ESTADO WITH (UPDLOCK, HOLDLOCK)
             WHERE SEC_EJEC=@SecEjec AND ESTADO='3';

            INSERT INTO dbo.SIG_DOCUMENTO_ESTADO
                (SEC_EJEC, SEC_DOC_EST, ESTADO, FLAG_ULT_MOV, FECHA, OBSERVACION,
                 CUSER_ID, FECHA_REG, EQUIPO_REG, SOL_ANNO_EJEC, SOL_CC, SEC_SOL_MOD,
                 SOL_GRU_ANNO_EJEC, SOL_GRU_SEC)
            VALUES
                (@SecEjec, @SecDocEstado, '3', '1', @Ahora, NULL,
                 @Usuario, @Ahora, @Equipo, NULL, NULL, NULL,
                 @AnoEje, @SecSolGru);
        END

        /* Limpieza: si alguna corrida anterior enlazo SOL_GRU en el movimiento
           de la solicitud, lo deshace (idempotente). */
        UPDATE dbo.SIG_DOCUMENTO_ESTADO
           SET SOL_GRU_ANNO_EJEC = NULL,
               SOL_GRU_SEC = NULL
         WHERE SEC_EJEC = @SecEjec AND ESTADO = '3'
           AND SOL_ANNO_EJEC = @AnoEje AND SOL_CC = @CentroCosto
           AND SEC_SOL_MOD = @SecSolicitud
           AND SOL_GRU_SEC IS NOT NULL;
        IF @trnPropia = 1 COMMIT TRANSACTION;

        IF @Detalle = 1
            SELECT @AnoEje         AS ANNO_EJEC,
                   @SecEjec        AS SEC_EJEC,
                   @CentroCosto    AS CENTRO_COSTO,
                   @SecSolicitud   AS SEC_SOL_MOD,
                   '3'             AS ESTADO_SOLICITUD,
                   @SecSolGru      AS SEC_SOL_GRU,
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

PRINT 'Instalado: dbo.usp_ext_aprobar_solicitud_cmn (con SIG_SOLICITUD_GRUPO).';
GO
