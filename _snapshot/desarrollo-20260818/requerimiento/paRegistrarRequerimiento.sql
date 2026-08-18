/*
  Base    : DBSIGCM
  Esquema : requerimiento
  Objeto  : requerimiento.paRegistrarRequerimiento
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 1. requerimiento.paRegistrarRequerimiento                                 */
/* ========================================================================== */

CREATE   PROCEDURE requerimiento.paRegistrarRequerimiento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    /* Se leen maestros de SIGA para validar los items: aplican las tres medidas
       de convivencia. */
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
                @Denominacion varchar(500), @CodigoTipoContratacion varchar(20),
                @CodigoDec varchar(20), @CondicionCmn varchar(20),
                @IdSolicitudCmn uniqueidentifier,
                @GeneradoDocumentoCmn nvarchar(1000), @NombreDocumentoCmn nvarchar(1000),
                @Monto decimal(18,2), @PlazoDias int, @FechaInicioPrevisto date,
                @Ate varchar(200), @RucSugerido varchar(11),
                @TieneDisponibilidad bit,
                @GeneradoDocumentoDisp nvarchar(1000), @NombreDocumentoDisp nvarchar(1000),
                @Sustento nvarchar(max), @DatosAdicionales nvarchar(max);

        DECLARE @MontoTxt nvarchar(40), @TdTxt nvarchar(20);

        SET @AnoEje                 = CONVERT(smallint, sigcm.fnJsonEntero(@parametro, 'Requerimiento.AnoEje'));
        SET @SecEjec                = sigcm.fnJsonEntero(@parametro, 'Requerimiento.SecEjec');
        SET @CentroCosto            = sigcm.fnJsonTexto(@parametro, 'Requerimiento.CentroCosto');
        SET @Denominacion           = sigcm.fnJsonTexto(@parametro, 'Requerimiento.Denominacion');
        SET @CodigoTipoContratacion = sigcm.fnJsonTexto(@parametro, 'Requerimiento.CodigoTipoContratacion');
        SET @CodigoDec              = ISNULL(sigcm.fnJsonTexto(@parametro, 'Requerimiento.CodigoDec'), 'ABASTECIMIENTO');
        SET @CondicionCmn           = sigcm.fnJsonTexto(@parametro, 'Requerimiento.CondicionCmn');
        SET @IdSolicitudCmn         = sigcm.fnTryGuid(sigcm.fnJsonTexto(@parametro, 'Requerimiento.IdSolicitudCmn'));
        SET @GeneradoDocumentoCmn   = sigcm.fnJsonTexto(@parametro, 'Requerimiento.GeneradoDocumentoCmn');
        SET @NombreDocumentoCmn     = sigcm.fnJsonTexto(@parametro, 'Requerimiento.NombreDocumentoCmn');
        SET @MontoTxt               = sigcm.fnJsonTexto(@parametro, 'Requerimiento.Monto');
        SET @Monto                  = CASE WHEN @MontoTxt IS NOT NULL AND ISNUMERIC(@MontoTxt) = 1
                                           THEN CONVERT(decimal(18,2), @MontoTxt) END;
        SET @PlazoDias              = sigcm.fnJsonEntero(@parametro, 'Requerimiento.PlazoDias');
        SET @FechaInicioPrevisto    = sigcm.fnTryFecha(sigcm.fnJsonTexto(@parametro, 'Requerimiento.FechaInicioPrevisto'));
        SET @Ate                    = sigcm.fnJsonTexto(@parametro, 'Requerimiento.Ate');
        SET @RucSugerido            = sigcm.fnJsonTexto(@parametro, 'Requerimiento.RucSugerido');
        SET @TdTxt                  = LOWER(ISNULL(sigcm.fnJsonTexto(@parametro, 'Requerimiento.TieneDisponibilidad'), N''));
        SET @TieneDisponibilidad    = CASE WHEN @TdTxt IN (N'1', N'true') THEN 1 ELSE 0 END;
        SET @GeneradoDocumentoDisp  = sigcm.fnJsonTexto(@parametro, 'Requerimiento.GeneradoDocumentoDisponibilidad');
        SET @NombreDocumentoDisp    = sigcm.fnJsonTexto(@parametro, 'Requerimiento.NombreDocumentoDisponibilidad');
        SET @Sustento               = sigcm.fnJsonTexto(@parametro, 'Requerimiento.Sustento');
        SET @DatosAdicionales       = sigcm.fnJsonTexto(@parametro, 'Requerimiento.DatosAdicionales');

        /* ---- Validaciones de cabecera --------------------------------- */
        IF @AnoEje IS NULL OR @SecEjec IS NULL
            RAISERROR('VALIDACION_PAYLOAD: Requerimiento.AnoEje y Requerimiento.SecEjec son obligatorios.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@CentroCosto)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta Requerimiento.CentroCosto.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@Denominacion)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: la denominacion del requerimiento es obligatoria.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@Sustento)), '') IS NULL
            RAISERROR('VALIDACION_SUSTENTO: el sustento del requerimiento es obligatorio.', 16, 1);
        IF @PlazoDias IS NULL OR @PlazoDias <= 0
            RAISERROR('VALIDACION_PLAZO: el plazo de ejecucion debe ser mayor que cero.', 16, 1);

        IF @CodigoDec NOT IN ('ABASTECIMIENTO','DAI')
            RAISERROR('VALIDACION_PAYLOAD: CodigoDec debe ser ABASTECIMIENTO o DAI.', 16, 1);
        IF @CondicionCmn NOT IN ('INCLUIDO','NO_INCLUIDO')
            RAISERROR('VALIDACION_PAYLOAD: CondicionCmn debe ser INCLUIDO o NO_INCLUIDO.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM sigcm.TipoContratacion
                        WHERE CodigoTipoContratacion = @CodigoTipoContratacion AND Activo = 1)
        BEGIN
            DECLARE @errTipo nvarchar(400);
            SET @errTipo = 'VALIDACION_PAYLOAD: el tipo de contratacion ' + ISNULL(@CodigoTipoContratacion, '(vacio)')
                + ' no existe. Validos: '
                + ISNULL(STUFF((
                    SELECT ', ' + CodigoTipoContratacion
                      FROM sigcm.TipoContratacion
                     WHERE Activo = 1
                       FOR XML PATH(''), TYPE
                ).value('.', 'nvarchar(max)'), 1, 2, ''), '') + '.';
            RAISERROR(@errTipo, 16, 1);
        END

        IF sigcm.fnEsJson(ISNULL(@DatosAdicionales, N'{}')) <> 1 SET @DatosAdicionales = N'{}';
        SET @DatosAdicionales = ISNULL(@DatosAdicionales, N'{}');

        /* El area usuaria solo registra sobre SU centro de costo. */
        IF @CentroCostoActor IS NULL OR @CentroCostoActor <> @CentroCosto
        BEGIN
            DECLARE @errCentro nvarchar(400);
            SET @errCentro = 'NO_AUTORIZADO: la unidad del actor esta asociada al centro de costo '
                + ISNULL(@CentroCostoActor, '(ninguno)') + ' y el requerimiento es para ' + ISNULL(@CentroCosto, '') + '.';
            RAISERROR(@errCentro, 16, 1);
        END

        IF NOT EXISTS (SELECT 1 FROM siga.vwCentroCosto
                        WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                          AND CentroCosto = @CentroCosto AND Activo = 1)
        BEGIN
            DECLARE @errCC nvarchar(400);
            SET @errCC = 'MAESTRO_CENTRO_COSTO: el centro de costo ' + ISNULL(@CentroCosto, '')
                + ' no existe o no esta activo en SIGA para ' + ISNULL(CONVERT(varchar(10), @AnoEje), '') + '.';
            RAISERROR(@errCC, 16, 1);
        END

        /* ---- REQ-06: el tope de ocho UIT ------------------------------ */
        DECLARE @MontoTope decimal(18,2), @ValorUit decimal(18,2);

        SELECT @MontoTope = MontoTope, @ValorUit = ValorUit
          FROM requerimiento.ParametroAnio
         WHERE AnoEje = @AnoEje AND Activo = 1;

        IF @MontoTope IS NULL
        BEGIN
            DECLARE @errParam nvarchar(400);
            SET @errParam = 'CONFLICTO_CONFIGURACION: no hay parametros para el anio ' + ISNULL(CONVERT(varchar(10), @AnoEje), '')
                + '. Falta sembrar requerimiento.ParametroAnio con la UIT vigente.';
            RAISERROR(@errParam, 16, 1);
        END

        IF @Monto IS NULL OR @Monto <= 0
            RAISERROR('VALIDACION_MONTO: el monto del requerimiento debe ser mayor que cero.', 16, 1);

        IF @Monto > @MontoTope
        BEGIN
            DECLARE @errTope nvarchar(500);
            SET @errTope = 'VALIDACION_MONTO: el monto S/ ' + CONVERT(varchar(30), @Monto)
                + ' supera el tope de ocho UIT para ' + ISNULL(CONVERT(varchar(10), @AnoEje), '') + ', que es S/ '
                + CONVERT(varchar(30), @MontoTope) + ' (UIT S/ ' + CONVERT(varchar(30), @ValorUit)
                + '). Una contratacion mayor no se tramita por esta via.';
            RAISERROR(@errTope, 16, 1);
        END

        /* ---- REQ-03 y REQ-04: la condicion frente al CMN -------------- */
        IF @CondicionCmn = 'INCLUIDO'
        BEGIN
            IF NULLIF(LTRIM(RTRIM(@GeneradoDocumentoCmn)), '') IS NULL
                RAISERROR('VALIDACION_CMN: la necesidad esta incluida en el CMN y debe adjuntarse el Anexo 1 firmado.', 16, 1);
        END
        ELSE
        BEGIN
            /* No incluida: o se apoya en una modificacion del CMN finalizada, o
               se adjunta el Anexo 4 firmado. Una de las dos, no ninguna. */
            IF @IdSolicitudCmn IS NULL AND NULLIF(LTRIM(RTRIM(@GeneradoDocumentoCmn)), '') IS NULL
                RAISERROR('VALIDACION_CMN: la necesidad no esta incluida en el CMN. Seleccione la modificacion aprobada o adjunte el Anexo 4 firmado.', 16, 1);

            IF @IdSolicitudCmn IS NOT NULL
            BEGIN
                DECLARE @EstadoCmn varchar(60);

                SELECT @EstadoCmn = e.CodigoEstado
                  FROM cmn.Solicitud AS s
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
                 WHERE s.IdSolicitud = @IdSolicitudCmn AND s.Activo = 1 AND e.Anulado = 0;

                IF @EstadoCmn IS NULL
                    RAISERROR('NO_ENCONTRADO: la modificacion del CMN indicada no existe o esta anulada.', 16, 1);

                /* REQ-04 exige un Anexo 4 FINALIZADO: una modificacion que
                   todavia esta en tramite no habilita nada. */
                IF @EstadoCmn <> 'CMN_FINALIZADO'
                BEGIN
                    DECLARE @errCmn nvarchar(500);
                    SET @errCmn = 'CONFLICTO_CMN: la modificacion del CMN esta en estado ' + ISNULL(@EstadoCmn, '')
                        + ' y solo habilita el requerimiento cuando el Anexo 4 ha sido recepcionado.';
                    RAISERROR(@errCmn, 16, 1);
                END
            END
        END

        /* ---- REQ-05: evidencia de la disponibilidad ------------------- */
        IF @TieneDisponibilidad = 1
           AND NULLIF(LTRIM(RTRIM(@GeneradoDocumentoDisp)), '') IS NULL
            RAISERROR('VALIDACION_PRESUPUESTO: se declaro disponibilidad presupuestal y debe adjuntarse la evidencia del saldo o de la habilitacion.', 16, 1);

        /* ---- PLZ-01: diez dias habiles de antelacion ------------------ */
        IF @FechaInicioPrevisto IS NOT NULL
        BEGIN
            DECLARE @Minima date = sigcm.fnSumarDiasHabiles(CONVERT(date, GETDATE()), 10);

            IF @FechaInicioPrevisto < @Minima
            BEGIN
                DECLARE @errPlazo nvarchar(500);
                SET @errPlazo = 'VALIDACION_PLAZO: el requerimiento debe presentarse al menos 10 dias habiles antes del inicio previsto. '
                    + 'La fecha mas proxima posible es ' + CONVERT(varchar(10), @Minima, 103) + '.';
                RAISERROR(@errPlazo, 16, 1);
            END
        END

        /* ---- Pedidos SIGA --------------------------------------------- */
        CREATE TABLE #Pedido (
            Orden        int NOT NULL PRIMARY KEY,
            AnoEje       smallint    NULL,
            SecEjec      int         NULL,
            NumeroPedido varchar(20) COLLATE DATABASE_DEFAULT NULL,
            SecPedido    bigint      NULL,
            FechaPedido  date        NULL,
            CentroCosto  varchar(15) COLLATE DATABASE_DEFAULT NULL,
            SecFunc      int         NULL,
            Origen       varchar(1)  COLLATE DATABASE_DEFAULT NULL,
            FuenteFinanc varchar(2)  COLLATE DATABASE_DEFAULT NULL,
            Clasificador varchar(20) COLLATE DATABASE_DEFAULT NULL,
            IdPedidoNuevo uniqueidentifier NULL
        );

        INSERT INTO #Pedido (Orden, AnoEje, SecEjec, NumeroPedido, SecPedido,
                             FechaPedido, CentroCosto, SecFunc, Origen, FuenteFinanc, Clasificador)
        SELECT a.Orden,
               ISNULL(CONVERT(smallint, sigcm.fnJsonEntero(a.Valor, 'AnoEje')), @AnoEje),
               ISNULL(sigcm.fnJsonEntero(a.Valor, 'SecEjec'), @SecEjec),
               sigcm.fnJsonTexto(a.Valor, 'NumeroPedido'),
               CASE WHEN ISNUMERIC(sigcm.fnJsonTexto(a.Valor, 'SecPedido')) = 1
                    THEN CONVERT(bigint, sigcm.fnJsonTexto(a.Valor, 'SecPedido')) END,
               sigcm.fnTryFecha(sigcm.fnJsonTexto(a.Valor, 'FechaPedido')),
               ISNULL(sigcm.fnJsonTexto(a.Valor, 'CentroCosto'), @CentroCosto),
               sigcm.fnJsonEntero(a.Valor, 'SecFunc'),
               sigcm.fnJsonTexto(a.Valor, 'Origen'),
               sigcm.fnJsonTexto(a.Valor, 'FuenteFinanc'),
               sigcm.fnJsonTexto(a.Valor, 'Clasificador')
          FROM sigcm.fnJsonArray(@parametro, 'Pedidos') AS a;

        /* REQ-01: uno o mas pedidos SIGA. Sin pedido no hay necesidad
           registrada en SIGA a la cual referirse. */
        IF NOT EXISTS (SELECT 1 FROM #Pedido)
            RAISERROR('VALIDACION_PEDIDOS: el requerimiento debe vincular al menos un pedido SIGA.', 16, 1);

        DECLARE @OrdenMal int;

        SELECT TOP 1 @OrdenMal = Orden FROM #Pedido
         WHERE NULLIF(LTRIM(RTRIM(NumeroPedido)), '') IS NULL;
        IF @OrdenMal IS NOT NULL
        BEGIN
            DECLARE @errPed nvarchar(300);
            SET @errPed = 'VALIDACION_PEDIDOS: el pedido ' + CONVERT(varchar(20), @OrdenMal) + ' no tiene numero.';
            RAISERROR(@errPed, 16, 1);
        END

        /* NOTA: aqui deberia validarse el pedido contra SIGA. No existe todavia
           una vista de pedidos (ver V009), asi que los pedidos se guardan con
           Verificado = 0. Cuando exista siga.vwPedido, esta es la validacion que
           falta y el unico lugar donde hay que agregarla. */

        /* ---- Items ---------------------------------------------------- */
        CREATE TABLE #Item (
            Orden               int NOT NULL PRIMARY KEY,
            OrdenPedido         int NULL,
            TipoBien            char(1)      COLLATE DATABASE_DEFAULT NULL,
            GrupoBien           varchar(2)   COLLATE DATABASE_DEFAULT NULL,
            ClaseBien           varchar(2)   COLLATE DATABASE_DEFAULT NULL,
            FamiliaBien         varchar(4)   COLLATE DATABASE_DEFAULT NULL,
            ItemBien            varchar(4)   COLLATE DATABASE_DEFAULT NULL,
            DescripcionServicio varchar(350) COLLATE DATABASE_DEFAULT NULL,
            UnidadMedida        int           NULL,
            Cantidad            decimal(18,2) NULL,
            PrecioUnitario      decimal(16,6) NULL
        );

        INSERT INTO #Item (Orden, OrdenPedido, TipoBien, GrupoBien, ClaseBien,
                           FamiliaBien, ItemBien, DescripcionServicio, Cantidad, PrecioUnitario)
        SELECT a.Orden,
               sigcm.fnJsonEntero(a.Valor, 'OrdenPedido'),
               sigcm.fnJsonTexto(a.Valor, 'TipoBien'),
               sigcm.fnJsonTexto(a.Valor, 'GrupoBien'),
               sigcm.fnJsonTexto(a.Valor, 'ClaseBien'),
               sigcm.fnJsonTexto(a.Valor, 'FamiliaBien'),
               sigcm.fnJsonTexto(a.Valor, 'ItemBien'),
               sigcm.fnJsonTexto(a.Valor, 'DescripcionServicio'),
               CASE WHEN ISNUMERIC(sigcm.fnJsonTexto(a.Valor, 'Cantidad')) = 1
                    THEN CONVERT(decimal(18,2), sigcm.fnJsonTexto(a.Valor, 'Cantidad')) END,
               CASE WHEN ISNUMERIC(sigcm.fnJsonTexto(a.Valor, 'PrecioUnitario')) = 1
                    THEN CONVERT(decimal(16,6), sigcm.fnJsonTexto(a.Valor, 'PrecioUnitario')) END
          FROM sigcm.fnJsonArray(@parametro, 'Items') AS a;

        IF NOT EXISTS (SELECT 1 FROM #Item)
            RAISERROR('VALIDACION_ITEMS: el requerimiento debe tener al menos un item.', 16, 1);

        SET @OrdenMal = NULL;
        SELECT TOP 1 @OrdenMal = Orden FROM #Item
         WHERE Cantidad IS NULL OR Cantidad <= 0 OR PrecioUnitario IS NULL OR PrecioUnitario <= 0;
        IF @OrdenMal IS NOT NULL
        BEGIN
            DECLARE @errItem nvarchar(300);
            SET @errItem = 'VALIDACION_ITEMS: el item ' + CONVERT(varchar(20), @OrdenMal)
                + ' necesita cantidad y precio unitario mayores que cero.';
            RAISERROR(@errItem, 16, 1);
        END

        /* Un item es del catalogo o es un servicio descrito; nunca ninguno. */
        SET @OrdenMal = NULL;
        SELECT TOP 1 @OrdenMal = Orden FROM #Item
         WHERE ItemBien IS NULL AND NULLIF(LTRIM(RTRIM(DescripcionServicio)), '') IS NULL;
        IF @OrdenMal IS NOT NULL
        BEGIN
            SET @errItem = 'VALIDACION_ITEMS: el item ' + CONVERT(varchar(20), @OrdenMal)
                + ' debe elegirse del catalogo de SIGA o describirse como servicio.';
            RAISERROR(@errItem, 16, 1);
        END

        /* La unidad de medida se toma del catalogo, no del formulario. */
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

        SET @OrdenMal = NULL;
        SELECT TOP 1 @OrdenMal = Orden FROM #Item
         WHERE ItemBien IS NOT NULL AND UnidadMedida IS NULL;
        IF @OrdenMal IS NOT NULL
        BEGIN
            SET @errItem = 'MAESTRO_CATALOGO: el item ' + CONVERT(varchar(20), @OrdenMal) + ' ('
                + ISNULL((SELECT sigcm.fnCodigoItemSiga(TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien)
                            FROM #Item WHERE Orden = @OrdenMal), '')
                + ') no existe o no esta activo en el catalogo de SIGA.';
            RAISERROR(@errItem, 16, 1);
        END

        /* ---- Coherencia del monto ------------------------------------- */
        DECLARE @MontoItems decimal(18,2) =
            (SELECT SUM(ROUND(Cantidad * PrecioUnitario, 2)) FROM #Item);

        IF ABS(@MontoItems - @Monto) > 0.01
        BEGIN
            DECLARE @errMonto nvarchar(500);
            SET @errMonto = 'VALIDACION_MONTO: el monto declarado S/ ' + CONVERT(varchar(30), @Monto)
                + ' no coincide con la suma de los items S/ ' + CONVERT(varchar(30), @MontoItems) + '.';
            RAISERROR(@errMonto, 16, 1);
        END

        /* ---- Escritura ------------------------------------------------ */
        DECLARE @CodigoEstadoInicial varchar(60);
        SELECT @CodigoEstadoInicial = CodigoEstado
          FROM sigcm.Estado
         WHERE CodigoModulo = 'REQUERIMIENTO' AND EsInicial = 1 AND Activo = 1;

        IF @CodigoEstadoInicial IS NULL
            RAISERROR('CONFLICTO_CONFIGURACION: el modulo REQUERIMIENTO no tiene estado inicial. Falta ejecutar S003.', 16, 1);

        DECLARE @Codigo varchar(40);
        EXEC sigcm.paSiguienteCodigo 'REQ', @AnoEje, N'requerimiento.SeqRequerimiento', @Codigo OUTPUT;

        DECLARE @Ahora datetime = GETDATE();
        DECLARE @IdExpediente uniqueidentifier, @IdRequerimiento uniqueidentifier;
        DECLARE @Metadata nvarchar(max);

        BEGIN TRANSACTION;

        INSERT INTO sigcm.Expediente
            (Codigo, CodigoModulo, CodigoTipoContratacion, AnoEje, IdUnidadOrigen,
             CodigoEstado, IdUnidadActual, IdResponsableActual, Version,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@Codigo, 'REQUERIMIENTO', @CodigoTipoContratacion, @AnoEje, @IdUnidad,
             @CodigoEstadoInicial, @IdUnidad, @IdUsuario, 1,
             @Cuenta, @Ahora, @Equipo, @Programa);

        SELECT @IdExpediente = IdExpediente FROM sigcm.Expediente WHERE Codigo = @Codigo;

        INSERT INTO requerimiento.Requerimiento
            (IdExpediente, Codigo, AnoEje, SecEjec, CentroCosto, Denominacion,
             CodigoTipoContratacion, CodigoDec, CondicionCmn, IdSolicitudCmn,
             GeneradoDocumentoCmn, NombreDocumentoCmn, Monto, PlazoDias,
             FechaInicioPrevisto, Ate, RucSugerido, TieneDisponibilidad,
             GeneradoDocumentoDisponibilidad, NombreDocumentoDisponibilidad,
             Sustento, IdResponsable, DatosAdicionales,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExpediente, @Codigo, @AnoEje, @SecEjec, @CentroCosto, @Denominacion,
             @CodigoTipoContratacion, @CodigoDec, @CondicionCmn, @IdSolicitudCmn,
             @GeneradoDocumentoCmn, @NombreDocumentoCmn, @Monto, @PlazoDias,
             @FechaInicioPrevisto, @Ate, @RucSugerido, @TieneDisponibilidad,
             @GeneradoDocumentoDisp, @NombreDocumentoDisp,
             @Sustento, @IdUsuario, @DatosAdicionales,
             @Cuenta, @Ahora, @Equipo, @Programa);

        SELECT @IdRequerimiento = IdRequerimiento
          FROM requerimiento.Requerimiento WHERE IdExpediente = @IdExpediente;

        /* Los pedidos primero: los items pueden referenciarlos por su orden. */
        DECLARE @PedidoNuevo TABLE (IdRequerimientoPedido uniqueidentifier, NumeroPedido varchar(20));

        INSERT INTO requerimiento.RequerimientoPedido
            (IdRequerimiento, AnoEje, SecEjec, NumeroPedido, SecPedido, FechaPedido,
             CentroCosto, SecFunc, Origen, FuenteFinanc, Clasificador, Verificado,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        OUTPUT inserted.IdRequerimientoPedido, inserted.NumeroPedido INTO @PedidoNuevo
        SELECT @IdRequerimiento, p.AnoEje, p.SecEjec, p.NumeroPedido, p.SecPedido, p.FechaPedido,
               p.CentroCosto, p.SecFunc, p.Origen, p.FuenteFinanc, p.Clasificador, 0,
               @Cuenta, @Ahora, @Equipo, @Programa
          FROM #Pedido AS p;

        UPDATE p SET p.IdPedidoNuevo = n.IdRequerimientoPedido
          FROM #Pedido AS p JOIN @PedidoNuevo AS n ON n.NumeroPedido = p.NumeroPedido;

        INSERT INTO requerimiento.RequerimientoItem
            (IdRequerimiento, IdRequerimientoPedido, Orden, TipoBien, GrupoBien,
             ClaseBien, FamiliaBien, ItemBien, DescripcionServicio, UnidadMedida,
             Cantidad, PrecioUnitario,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT @IdRequerimiento, p.IdPedidoNuevo, i.Orden, i.TipoBien, i.GrupoBien,
               i.ClaseBien, i.FamiliaBien, i.ItemBien, i.DescripcionServicio, i.UnidadMedida,
               i.Cantidad, i.PrecioUnitario,
               @Cuenta, @Ahora, @Equipo, @Programa
          FROM #Item AS i
          LEFT JOIN #Pedido AS p ON p.Orden = i.OrdenPedido;

        SET @Metadata = N'{"Codigo":' + sigcm.fnJsonValorTexto(@Codigo)
            + N',"CentroCosto":' + sigcm.fnJsonValorTexto(@CentroCosto)
            + N',"TipoContratacion":' + sigcm.fnJsonValorTexto(@CodigoTipoContratacion)
            + N',"Dec":' + sigcm.fnJsonValorTexto(@CodigoDec)
            + N'}';

        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
             Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExpediente, NULL, @CodigoEstadoInicial, NULL,
             'Registro inicial del requerimiento', @IdUsuario, @CodigoRol, @IdUnidad,
             @Metadata,
             @Cuenta, @Equipo, @Programa);

        COMMIT TRANSACTION;

        DECLARE @Items int = (SELECT COUNT(*) FROM #Item);
        DECLARE @Pedidos int = (SELECT COUNT(*) FROM #Pedido);

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = 'REQUERIMIENTO',
             @Entidad = 'requerimiento.Requerimiento', @IdEntidad = @IdRequerimiento,
             @Accion = 'REGISTRAR', @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta, @ActorRol = @CodigoRol,
             @IdActorUnidad = @IdUnidad, @OrigenIp = @Ip, @Equipo = @Equipo,
             @Programa = @Programa;

        SET @resultado = N'{"estado":1'
            + N',"IdRequerimiento":' + sigcm.fnJsonValorTexto(CONVERT(nvarchar(36), @IdRequerimiento))
            + N',"IdExpediente":'    + sigcm.fnJsonValorTexto(CONVERT(nvarchar(36), @IdExpediente))
            + N',"Codigo":'          + sigcm.fnJsonValorTexto(@Codigo)
            + N',"CodigoEstado":'    + sigcm.fnJsonValorTexto(@CodigoEstadoInicial)
            + N',"Version":1'
            + N',"Items":'           + CONVERT(nvarchar(20), @Items)
            + N',"Pedidos":'         + CONVERT(nvarchar(20), @Pedidos)
            + N',"Monto":'           + CONVERT(nvarchar(40), @Monto)
            + N',"MontoTope":'       + CONVERT(nvarchar(40), @MontoTope)
            + N',"mensaje":'         + sigcm.fnJsonValorTexto(N'Se realizo el registro satisfactoriamente.')
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
