/*
  Base    : DBSIGCM
  Esquema : cmn
  Objeto  : cmn.paRegistrarSolicitud
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 1. cmn.paRegistrarSolicitud                                               */
/* ========================================================================== */

CREATE   PROCEDURE cmn.paRegistrarSolicitud
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    /* Se leen los maestros de SIGA para validar: aplican las tres medidas de
       convivencia. En la copia local no cambian nada; en produccion evitan que
       una validacion nuestra frene a un escritor de SIGA. */
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF sigcm.fnEsJson(@parametro) <> 1
            RAISERROR('JSON incorrecto.', 16, 1);

        /* ---- Actor ---------------------------------------------------- */
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

        /* ---- Cabecera ------------------------------------------------- */
        DECLARE @AnoEje smallint, @SecEjec int, @CentroCosto varchar(15),
                @TipoOperacion varchar(20), @Sustento nvarchar(max),
                @DatosAdicionales nvarchar(max);

        SET @AnoEje           = CONVERT(smallint, sigcm.fnJsonEntero(@parametro, 'Solicitud.AnoEje'));
        SET @SecEjec          = sigcm.fnJsonEntero(@parametro, 'Solicitud.SecEjec');
        SET @CentroCosto      = sigcm.fnJsonTexto(@parametro, 'Solicitud.CentroCosto');
        SET @TipoOperacion    = ISNULL(sigcm.fnJsonTexto(@parametro, 'Solicitud.TipoOperacion'), 'MODIFICACION');
        SET @Sustento         = sigcm.fnJsonTexto(@parametro, 'Solicitud.Sustento');
        /* Objeto anidado: fnJsonTexto devuelve el token {...} tal cual. */
        SET @DatosAdicionales = sigcm.fnJsonTexto(@parametro, 'Solicitud.DatosAdicionales');

        IF @AnoEje IS NULL OR @SecEjec IS NULL
            RAISERROR('VALIDACION_PAYLOAD: Solicitud.AnoEje y Solicitud.SecEjec son obligatorios.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@CentroCosto)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta Solicitud.CentroCosto.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@Sustento)), '') IS NULL
            RAISERROR('VALIDACION_SUSTENTO: el sustento de la solicitud es obligatorio.', 16, 1);
        IF @TipoOperacion <> 'MODIFICACION'
            RAISERROR('VALIDACION_PAYLOAD: la v1 solo habilita TipoOperacion = MODIFICACION (ADR-002).', 16, 1);
        IF sigcm.fnEsJson(ISNULL(@DatosAdicionales, N'{}')) <> 1
            SET @DatosAdicionales = N'{}';
        SET @DatosAdicionales = ISNULL(@DatosAdicionales, N'{}');

        /* El area usuaria solo puede registrar sobre SU centro de costo. Sin
           esto, cualquier especialista podria modificar el cuadro de otra area. */
        IF @CentroCostoActor IS NULL OR @CentroCostoActor <> @CentroCosto
        BEGIN
            DECLARE @errCentro nvarchar(400);
            SET @errCentro = 'NO_AUTORIZADO: la unidad del actor esta asociada al centro de costo '
                + ISNULL(@CentroCostoActor, '(ninguno)') + ' y la solicitud es para ' + ISNULL(@CentroCosto, '') + '.';
            RAISERROR(@errCentro, 16, 1);
        END

        /* El centro de costo debe existir y estar activo en SIGA. */
        IF NOT EXISTS (SELECT 1 FROM siga.vwCentroCosto
                        WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                          AND CentroCosto = @CentroCosto AND Activo = 1)
        BEGIN
            DECLARE @errCC nvarchar(400);
            SET @errCC = 'MAESTRO_CENTRO_COSTO: el centro de costo ' + ISNULL(@CentroCosto, '')
                + ' no existe o no esta activo en SIGA para ' + ISNULL(CONVERT(varchar(10), @AnoEje), '') + '.';
            RAISERROR(@errCC, 16, 1);
        END

        /* ---- Items a tabla temporal ----------------------------------- */
        /* Las columnas de texto llevan COLLATE DATABASE_DEFAULT porque las
           tablas #temporales heredan la intercalacion de tempdb, no la de esta
           base. Sin esto, compararlas con las vistas de SIGA falla con el
           error 468 en cuanto las intercalaciones difieran. */
        CREATE TABLE #Item (
            Orden               int NOT NULL PRIMARY KEY,
            TipoMovimiento      varchar(15)   COLLATE DATABASE_DEFAULT NOT NULL,
            TipoTarea           char(1)       COLLATE DATABASE_DEFAULT NULL,
            NivelTarea          char(1)       COLLATE DATABASE_DEFAULT NULL,
            CodigoTarea         bigint        NULL,
            SecFunc             int           NULL,
            SecFuncProp         int           NULL,
            Origen              varchar(1)    COLLATE DATABASE_DEFAULT NULL,
            FuenteFinanc        varchar(2)    COLLATE DATABASE_DEFAULT NULL,
            Clasificador        varchar(20)   COLLATE DATABASE_DEFAULT NULL,
            TipoRecurso         varchar(2)    COLLATE DATABASE_DEFAULT NULL,
            TipoPpto            smallint      NULL,
            TipoUso             varchar(1)    COLLATE DATABASE_DEFAULT NULL,
            TipoBien            char(1)       COLLATE DATABASE_DEFAULT NULL,
            GrupoBien           varchar(2)    COLLATE DATABASE_DEFAULT NULL,
            ClaseBien           varchar(2)    COLLATE DATABASE_DEFAULT NULL,
            FamiliaBien         varchar(4)    COLLATE DATABASE_DEFAULT NULL,
            ItemBien            varchar(4)    COLLATE DATABASE_DEFAULT NULL,
            DescripcionServicio varchar(350)  COLLATE DATABASE_DEFAULT NULL,
            PrecioUnitario      decimal(16,6) NULL,
            RefSecCuadro        bigint        NULL,
            RefSecItem          bigint        NULL,
            UnidadMedida        int           NULL,
            IdSolicitudItem     uniqueidentifier NULL,
            Periodos            nvarchar(max) COLLATE DATABASE_DEFAULT NULL
        );

        INSERT INTO #Item (Orden, TipoMovimiento, TipoTarea, NivelTarea, CodigoTarea,
                           SecFunc, SecFuncProp, Origen, FuenteFinanc, Clasificador,
                           TipoRecurso, TipoPpto, TipoUso, TipoBien, GrupoBien, ClaseBien,
                           FamiliaBien, ItemBien, DescripcionServicio, PrecioUnitario,
                           RefSecCuadro, RefSecItem, Periodos)
        SELECT a.Orden,
               j.TipoMovimiento, j.TipoTarea, j.NivelTarea,
               CONVERT(bigint, NULLIF(j.CodigoTarea, N'')),
               sigcm.fnJsonEntero(a.Valor, 'SecFunc'),
               sigcm.fnJsonEntero(a.Valor, 'SecFuncProp'),
               ISNULL(j.Origen, '1'), ISNULL(j.FuenteFinanc, '00'), j.Clasificador,
               ISNULL(j.TipoRecurso, '1'),
               ISNULL(CONVERT(smallint, sigcm.fnJsonEntero(a.Valor, 'TipoPpto')), 1),
               ISNULL(j.TipoUso, 'C'),
               j.TipoBien, j.GrupoBien, j.ClaseBien, j.FamiliaBien, j.ItemBien,
               j.DescripcionServicio,
               CONVERT(decimal(16,6), NULLIF(j.PrecioUnitario, N'')),
               CONVERT(bigint, NULLIF(j.RefSecCuadro, N'')),
               CONVERT(bigint, NULLIF(j.RefSecItem, N'')),
               j.Periodos
        FROM sigcm.fnJsonArray(@parametro, 'Items') AS a
        CROSS APPLY (
            SELECT
                TipoMovimiento      = sigcm.fnJsonTexto(a.Valor, 'TipoMovimiento'),
                TipoTarea           = sigcm.fnJsonTexto(a.Valor, 'TipoTarea'),
                NivelTarea          = sigcm.fnJsonTexto(a.Valor, 'NivelTarea'),
                CodigoTarea         = sigcm.fnJsonTexto(a.Valor, 'CodigoTarea'),
                Origen              = sigcm.fnJsonTexto(a.Valor, 'Origen'),
                FuenteFinanc        = sigcm.fnJsonTexto(a.Valor, 'FuenteFinanc'),
                Clasificador        = sigcm.fnJsonTexto(a.Valor, 'Clasificador'),
                TipoRecurso         = sigcm.fnJsonTexto(a.Valor, 'TipoRecurso'),
                TipoUso             = sigcm.fnJsonTexto(a.Valor, 'TipoUso'),
                TipoBien            = sigcm.fnJsonTexto(a.Valor, 'TipoBien'),
                GrupoBien           = sigcm.fnJsonTexto(a.Valor, 'GrupoBien'),
                ClaseBien           = sigcm.fnJsonTexto(a.Valor, 'ClaseBien'),
                FamiliaBien         = sigcm.fnJsonTexto(a.Valor, 'FamiliaBien'),
                ItemBien            = sigcm.fnJsonTexto(a.Valor, 'ItemBien'),
                DescripcionServicio = sigcm.fnJsonTexto(a.Valor, 'DescripcionServicio'),
                PrecioUnitario      = sigcm.fnJsonTexto(a.Valor, 'PrecioUnitario'),
                RefSecCuadro        = sigcm.fnJsonTexto(a.Valor, 'RefSecCuadro'),
                RefSecItem          = sigcm.fnJsonTexto(a.Valor, 'RefSecItem'),
                Periodos            = sigcm.fnJsonToken(a.Valor, 'Periodos')
        ) AS j;

        IF NOT EXISTS (SELECT 1 FROM #Item)
            RAISERROR('VALIDACION_ITEMS: la solicitud debe tener al menos un item.', 16, 1);

        /* ---- Validaciones por item ------------------------------------ */
        DECLARE @Orden int, @errItem nvarchar(400);

        SELECT TOP 1 @Orden = Orden FROM #Item
         WHERE TipoMovimiento NOT IN ('INCLUSION','EXCLUSION','MODIFICACION') OR TipoMovimiento IS NULL;
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = 'VALIDACION_ITEMS: el item ' + CONVERT(varchar(20), @Orden)
                + ' tiene un TipoMovimiento invalido. Valores: INCLUSION, EXCLUSION, MODIFICACION.';
            RAISERROR(@errItem, 16, 1);
        END

        SET @Orden = NULL;
        SELECT TOP 1 @Orden = Orden FROM #Item WHERE PrecioUnitario IS NULL OR PrecioUnitario <= 0;
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = 'VALIDACION_PRECIO: el item ' + CONVERT(varchar(20), @Orden)
                + ' necesita un precio unitario mayor que cero.';
            RAISERROR(@errItem, 16, 1);
        END

        /* Excluir o modificar exige senialar cual item del cuadro vigente se
           toca. Sin la referencia, SIGA no sabria sobre que fila operar. */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = Orden FROM #Item
         WHERE TipoMovimiento <> 'INCLUSION' AND (RefSecCuadro IS NULL OR RefSecItem IS NULL);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = 'VALIDACION_REFERENCIA: el item ' + CONVERT(varchar(20), @Orden)
                + ' es una ' + ISNULL((SELECT TipoMovimiento FROM #Item WHERE Orden = @Orden), '')
                + ' y debe indicar RefSecCuadro y RefSecItem del cuadro vigente.';
            RAISERROR(@errItem, 16, 1);
        END

        /* La referencia debe existir de verdad en el cuadro vigente de SIGA. */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = i.Orden
          FROM #Item AS i
         WHERE i.TipoMovimiento <> 'INCLUSION'
           AND NOT EXISTS (SELECT 1 FROM siga.vwCuadroVigenteItem AS c
                            WHERE c.AnoEje = @AnoEje AND c.SecEjec = @SecEjec
                              AND c.CentroCosto = @CentroCosto
                              AND c.SecCuadro = i.RefSecCuadro AND c.SecItem = i.RefSecItem);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = 'MAESTRO_CUADRO: el item ' + CONVERT(varchar(20), @Orden)
                + ' referencia un item que no existe en el cuadro vigente de SIGA para ese centro de costo.';
            RAISERROR(@errItem, 16, 1);
        END

        /* Catalogo. La unidad de medida se toma de SIGA, no de lo que mande el
           cliente: es dato del catalogo y no del formulario. */
        UPDATE i
           SET i.UnidadMedida = c.UnidadMedida
          FROM #Item AS i
          JOIN siga.vwCatalogoItem AS c
            ON  c.SecEjec     = @SecEjec
            AND c.TipoBien    = i.TipoBien
            AND c.GrupoBien   = i.GrupoBien
            AND c.ClaseBien   = i.ClaseBien
            AND c.FamiliaBien = i.FamiliaBien
            AND c.ItemBien    = i.ItemBien
            AND c.Activo      = 1;

        SET @Orden = NULL;
        SELECT TOP 1 @Orden = Orden FROM #Item WHERE UnidadMedida IS NULL;
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = 'MAESTRO_CATALOGO: el item ' + CONVERT(varchar(20), @Orden) + ' ('
                + ISNULL((SELECT sigcm.fnCodigoItemSiga(TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien)
                            FROM #Item WHERE Orden = @Orden), '')
                + ') no existe o no esta activo en el catalogo de SIGA.';
            RAISERROR(@errItem, 16, 1);
        END

        /* Meta */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = i.Orden
          FROM #Item AS i
         WHERE NOT EXISTS (SELECT 1 FROM siga.vwMeta AS m
                            WHERE m.AnoEje = @AnoEje AND m.SecEjec = @SecEjec
                              AND m.SecFunc = i.SecFunc AND m.Activo = 1);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = 'MAESTRO_META: el item ' + CONVERT(varchar(20), @Orden) + ' referencia la meta '
                + ISNULL(CONVERT(varchar(20), (SELECT SecFunc FROM #Item WHERE Orden = @Orden)), '')
                + ', que no existe o no esta activa en SIGA.';
            RAISERROR(@errItem, 16, 1);
        END

        /* Fuente de financiamiento */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = i.Orden
          FROM #Item AS i
         WHERE NOT EXISTS (SELECT 1 FROM siga.vwFuenteFinanc AS f
                            WHERE f.AnoEje = @AnoEje AND f.SecEjec = @SecEjec
                              AND f.Origen = i.Origen AND f.FuenteFinanc = i.FuenteFinanc);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = 'MAESTRO_FUENTE: el item ' + CONVERT(varchar(20), @Orden)
                + ' referencia una fuente de financiamiento que no existe en SIGA.';
            RAISERROR(@errItem, 16, 1);
        END

        /* Tarea, que en SIGA vive por centro de costo */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = i.Orden
          FROM #Item AS i
         WHERE NOT EXISTS (SELECT 1 FROM siga.vwTarea AS t
                            WHERE t.AnoEje = @AnoEje AND t.SecEjec = @SecEjec
                              AND t.CentroCosto = @CentroCosto
                              AND t.TipoTarea = i.TipoTarea AND t.NivelTarea = i.NivelTarea
                              AND t.CodigoTarea = i.CodigoTarea AND t.Activo = 1);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = 'MAESTRO_TAREA: el item ' + CONVERT(varchar(20), @Orden)
                + ' referencia una tarea que no existe o no esta activa para el centro de costo '
                + ISNULL(@CentroCosto, '') + '.';
            RAISERROR(@errItem, 16, 1);
        END

        /* ---- Periodos a tabla temporal -------------------------------- */
        CREATE TABLE #Periodo (
            Orden     int NOT NULL,
            AnoOffset smallint NOT NULL,
            Mes       smallint NOT NULL,
            Cantidad  decimal(18,2) NOT NULL,
            PRIMARY KEY (Orden, AnoOffset, Mes)
        );

        INSERT INTO #Periodo (Orden, AnoOffset, Mes, Cantidad)
        SELECT i.Orden, q.AnoOffset, q.Mes, SUM(ISNULL(q.Cantidad, 0))
          FROM #Item AS i
         CROSS APPLY sigcm.fnJsonArray(ISNULL(i.Periodos, N'[]'), N'') AS p
         CROSS APPLY (
            SELECT
                AnoOffset = CONVERT(smallint, sigcm.fnJsonEntero(p.Valor, 'AnoOffset')),
                Mes       = CONVERT(smallint, sigcm.fnJsonEntero(p.Valor, 'Mes')),
                Cantidad  = CONVERT(decimal(18,2), NULLIF(sigcm.fnJsonTexto(p.Valor, 'Cantidad'), N''))
         ) AS q
         WHERE q.AnoOffset BETWEEN 0 AND 3
           AND q.Mes BETWEEN 1 AND 12
         GROUP BY i.Orden, q.AnoOffset, q.Mes;

        /* Un item sin ninguna cantidad no es una solicitud, es una linea vacia. */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = i.Orden
          FROM #Item AS i
         WHERE NOT EXISTS (SELECT 1 FROM #Periodo AS p WHERE p.Orden = i.Orden AND p.Cantidad > 0);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = 'VALIDACION_PERIODOS: el item ' + CONVERT(varchar(20), @Orden)
                + ' no tiene ninguna cantidad mayor que cero en los 48 periodos.';
            RAISERROR(@errItem, 16, 1);
        END

        /* ---- Escritura ------------------------------------------------ */
        DECLARE @CodigoEstadoInicial varchar(60);
        SELECT @CodigoEstadoInicial = CodigoEstado
          FROM sigcm.Estado
         WHERE CodigoModulo = 'CMN' AND EsInicial = 1 AND Activo = 1;

        IF @CodigoEstadoInicial IS NULL
            RAISERROR('CONFLICTO_CONFIGURACION: el modulo CMN no tiene estado inicial. Falta ejecutar S001.', 16, 1);

        DECLARE @Codigo varchar(40);
        EXEC sigcm.paSiguienteCodigo 'CMN', @AnoEje, N'cmn.SeqSolicitud', @Codigo OUTPUT;

        DECLARE @Ahora datetime = GETDATE();
        DECLARE @IdExpediente uniqueidentifier;
        DECLARE @IdSolicitud  uniqueidentifier;

        BEGIN TRANSACTION;

        INSERT INTO sigcm.Expediente
            (Codigo, CodigoModulo, AnoEje, IdUnidadOrigen, CodigoEstado,
             IdUnidadActual, IdResponsableActual, Version,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@Codigo, 'CMN', @AnoEje, @IdUnidad, @CodigoEstadoInicial,
             @IdUnidad, @IdUsuario, 1,
             @Cuenta, @Ahora, @Equipo, @Programa);

        SELECT @IdExpediente = IdExpediente FROM sigcm.Expediente WHERE Codigo = @Codigo;

        INSERT INTO cmn.Solicitud
            (IdExpediente, Codigo, AnoEje, SecEjec, CentroCosto, TipoOperacion,
             Sustento, IdResponsable, DatosAdicionales,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExpediente, @Codigo, @AnoEje, @SecEjec, @CentroCosto, @TipoOperacion,
             @Sustento, @IdUsuario, @DatosAdicionales,
             @Cuenta, @Ahora, @Equipo, @Programa);

        SELECT @IdSolicitud = IdSolicitud FROM cmn.Solicitud WHERE IdExpediente = @IdExpediente;

        /* Los identificadores se capturan con OUTPUT porque NEWSEQUENTIALID es un
           DEFAULT y no hay SCOPE_IDENTITY para uniqueidentifier. */
        DECLARE @ItemNuevo TABLE (IdSolicitudItem uniqueidentifier, Orden int);

        INSERT INTO cmn.SolicitudItem
            (IdSolicitud, Orden, TipoMovimiento, TipoTarea, NivelTarea, CodigoTarea,
             SecFunc, SecFuncProp, Origen, FuenteFinanc, Clasificador, TipoRecurso,
             TipoPpto, TipoUso, TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien,
             DescripcionServicio, UnidadMedida, PrecioUnitario, RefSecCuadro, RefSecItem,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        OUTPUT inserted.IdSolicitudItem, inserted.Orden INTO @ItemNuevo
        SELECT @IdSolicitud, i.Orden, i.TipoMovimiento, i.TipoTarea, i.NivelTarea, i.CodigoTarea,
               i.SecFunc, i.SecFuncProp, i.Origen, i.FuenteFinanc, i.Clasificador, i.TipoRecurso,
               i.TipoPpto, i.TipoUso, i.TipoBien, i.GrupoBien, i.ClaseBien, i.FamiliaBien, i.ItemBien,
               i.DescripcionServicio, i.UnidadMedida, i.PrecioUnitario, i.RefSecCuadro, i.RefSecItem,
               @Cuenta, @Ahora, @Equipo, @Programa
          FROM #Item AS i;

        UPDATE i SET i.IdSolicitudItem = n.IdSolicitudItem
          FROM #Item AS i JOIN @ItemNuevo AS n ON n.Orden = i.Orden;

        /* Materializacion de los 48 periodos. dbo.Numero sustituye a
           generate_series(0,3) x generate_series(1,12) de PostgreSQL. */
        INSERT INTO cmn.SolicitudItemPeriodo (IdSolicitudItem, AnoOffset, Mes, Cantidad, Monto)
        SELECT i.IdSolicitudItem,
               a.n, m.n,
               ISNULL(p.Cantidad, 0),
               ROUND(ISNULL(p.Cantidad, 0) * i.PrecioUnitario, 2)
          FROM #Item AS i
         CROSS JOIN (SELECT n FROM dbo.Numero WHERE n BETWEEN 0 AND 3)  AS a
         CROSS JOIN (SELECT n FROM dbo.Numero WHERE n BETWEEN 1 AND 12) AS m
          LEFT JOIN #Periodo AS p
                 ON p.Orden = i.Orden AND p.AnoOffset = a.n AND p.Mes = m.n;

        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
             Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExpediente, NULL, @CodigoEstadoInicial, NULL,
             'Registro inicial del Anexo 3', @IdUsuario, @CodigoRol, @IdUnidad,
             N'{"Codigo":' + sigcm.fnJsonValorTexto(@Codigo)
               + N',"CentroCosto":' + sigcm.fnJsonValorTexto(@CentroCosto) + N'}',
             @Cuenta, @Equipo, @Programa);

        COMMIT TRANSACTION;

        DECLARE @Items int = (SELECT COUNT(*) FROM #Item);

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = 'CMN',
             @Entidad = 'cmn.Solicitud', @IdEntidad = @IdSolicitud, @Accion = 'REGISTRAR',
             @Resultado = 'OK', @IdActor = @IdUsuario, @ActorCuenta = @Cuenta,
             @ActorRol = @CodigoRol, @IdActorUnidad = @IdUnidad,
             @OrigenIp = @Ip, @Equipo = @Equipo, @Programa = @Programa,
             @DatosDespues = NULL, @Metadata = NULL;

        SET @resultado = N'{"estado":1'
            + N',"IdSolicitud":'  + sigcm.fnJsonValorTexto(CONVERT(varchar(36), @IdSolicitud))
            + N',"IdExpediente":' + sigcm.fnJsonValorTexto(CONVERT(varchar(36), @IdExpediente))
            + N',"Codigo":'       + sigcm.fnJsonValorTexto(@Codigo)
            + N',"CodigoEstado":' + sigcm.fnJsonValorTexto(@CodigoEstadoInicial)
            + N',"Version":1'
            + N',"Items":'        + CONVERT(nvarchar(20), @Items)
            + N',"Periodos":'     + CONVERT(nvarchar(20), @Items * 48)
            + N',"mensaje":'      + sigcm.fnJsonValorTexto(N'Se realizo el registro satisfactoriamente.')
            + N'}';

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N'}';
        SELECT @resultado;
    END CATCH
END
GO
