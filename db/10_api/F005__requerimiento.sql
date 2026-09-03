/*
===============================================================================
  SIGCM - F005 : Modulo Requerimiento a Notificacion - registro y consulta
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51400-51499

  Cubre las reglas REQ-01 a REQ-14 de Analisis/reglas-negocio-mockup.md y la
  validacion de ocho UIT de locacion (monto mensual x entregables). Las acciones
  del flujo (derivar, firmar, remitir, observar, declarar conforme) NO estan
  aqui: son transiciones y las ejecuta sigcm.paEjecutarTransicion con S003/S004.
  Filtros, CCP y orden: F008 (requiere V016).

  ---------------------------------------------------------------------------
  SOBRE DE ENTRADA de requerimiento.paRegistrarRequerimiento
  ---------------------------------------------------------------------------
  {
    "Actor": { ... },
    "Requerimiento": {
      "AnoEje":2026, "SecEjec":1750, "CentroCosto":"01.01",
      "Denominacion":"...",
      "CodigoTipoContratacion":"BIEN",
      "CodigoDec":"ABASTECIMIENTO",
      "CondicionCmn":"INCLUIDO",
      "IdSolicitudCmn":null,
      "GeneradoDocumentoCmn":"http://.../anexo1.pdf",
      "NombreDocumentoCmn":"Anexo 1 firmado.pdf",
      "Monto":12000.00, "PlazoDias":30,
      "FechaInicioPrevisto":"2026-09-30",
      "Ate":null, "RucSugerido":null,
      "TieneDisponibilidad":true,
      "GeneradoDocumentoDisponibilidad":"...", "NombreDocumentoDisponibilidad":"...",
      "Sustento":"...", "DatosAdicionales":{ }
    },
    "Pedidos": [ { "AnoEje":2026, "SecEjec":1750, "NumeroPedido":"000123", ... } ],
    "Items":   [ { "TipoBien":"B","GrupoBien":"71","ClaseBien":"72",
                   "FamiliaBien":"0005","ItemBien":"0224",
                   "DescripcionServicio":null,
                   "Cantidad":10, "PrecioUnitario":12.50 } ]
  }

  ---------------------------------------------------------------------------
  LAS CUATRO VALIDACIONES QUE DEFINEN ESTE MODULO
  ---------------------------------------------------------------------------
  1. OCHO UIT (REQ-06). El tope sale de requerimiento.ParametroAnio y no de una
     constante: cambia cada anio. El mensaje dice el tope real para que el area
     usuaria sepa cuanto le sobra.
  2. CONDICION CMN (REQ-03, REQ-04). El registro (REQ-12) captura la necesidad
     y los pedidos SIGA. El Anexo 1 / Anexo 4 se elaboran despues (REQ-13),
     cuando el expediente pasa a REQ_DOC_PENDIENTE. En este procedimiento no se
     exige adjunto. Si el sobre trae IdSolicitudCmn, si se comprueba que esa
     modificacion exista y ya tenga el Anexo 4 en el area usuaria.
  3. DIEZ DIAS HABILES (PLZ-01). El requerimiento se presenta al menos diez dias
     habiles antes del inicio previsto, contados con sigcm.fnSumarDiasHabiles.
  4. COHERENCIA DEL MONTO. La suma de los items debe coincidir con el monto
     declarado. Sin esto, el tope de ocho UIT se controlaria sobre un numero que
     no corresponde a lo que se va a contratar.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. requerimiento.paRegistrarRequerimiento                                 */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE requerimiento.paRegistrarRequerimiento
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
        IF ISJSON(@parametro) <> 1
            THROW 51400, 'JSON incorrecto.', 1;

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

        SELECT @AnoEje                 = AnoEje,
               @SecEjec                = SecEjec,
               @CentroCosto            = CentroCosto,
               @Denominacion           = Denominacion,
               @CodigoTipoContratacion = CodigoTipoContratacion,
               @CodigoDec              = ISNULL(CodigoDec, 'ABASTECIMIENTO'),
               @CondicionCmn           = CondicionCmn,
               @IdSolicitudCmn         = TRY_CONVERT(uniqueidentifier, IdSolicitudCmn),
               @GeneradoDocumentoCmn   = GeneradoDocumentoCmn,
               @NombreDocumentoCmn     = NombreDocumentoCmn,
               @Monto                  = Monto,
               @PlazoDias              = PlazoDias,
               @FechaInicioPrevisto    = TRY_CONVERT(date, FechaInicioPrevisto),
               @Ate                    = Ate,
               @RucSugerido            = RucSugerido,
               @TieneDisponibilidad    = ISNULL(TieneDisponibilidad, 0),
               @GeneradoDocumentoDisp  = GeneradoDocumentoDisponibilidad,
               @NombreDocumentoDisp    = NombreDocumentoDisponibilidad,
               @Sustento               = Sustento,
               @DatosAdicionales       = DatosAdicionales
        FROM OPENJSON(@parametro, '$.Requerimiento')
        WITH (
            AnoEje                 smallint,
            SecEjec                int,
            CentroCosto            varchar(15),
            Denominacion           varchar(500),
            CodigoTipoContratacion varchar(20),
            CodigoDec              varchar(20),
            CondicionCmn           varchar(20),
            IdSolicitudCmn         varchar(50),
            GeneradoDocumentoCmn   nvarchar(1000),
            NombreDocumentoCmn     nvarchar(1000),
            Monto                  decimal(18,2),
            PlazoDias              int,
            FechaInicioPrevisto    varchar(30),
            Ate                    varchar(200),
            RucSugerido            varchar(11),
            TieneDisponibilidad    bit,
            GeneradoDocumentoDisponibilidad nvarchar(1000),
            NombreDocumentoDisponibilidad   nvarchar(1000),
            Sustento               nvarchar(max),
            DatosAdicionales       nvarchar(max) AS JSON
        );

        /* ---- Validaciones de cabecera --------------------------------- */
        IF @AnoEje IS NULL OR @SecEjec IS NULL
            THROW 51401, 'VALIDACION_PAYLOAD: Requerimiento.AnoEje y Requerimiento.SecEjec son obligatorios.', 1;
        IF NULLIF(LTRIM(RTRIM(@CentroCosto)), '') IS NULL
            THROW 51402, 'VALIDACION_PAYLOAD: falta Requerimiento.CentroCosto.', 1;
        IF NULLIF(LTRIM(RTRIM(@Denominacion)), '') IS NULL
            THROW 51403, 'VALIDACION_PAYLOAD: la denominacion del requerimiento es obligatoria.', 1;
        IF NULLIF(LTRIM(RTRIM(@Sustento)), '') IS NULL
            THROW 51404, 'VALIDACION_SUSTENTO: el sustento del requerimiento es obligatorio.', 1;
        IF @PlazoDias IS NULL OR @PlazoDias <= 0
            THROW 51405, 'VALIDACION_PLAZO: el plazo de ejecucion debe ser mayor que cero.', 1;

        IF @CodigoDec NOT IN ('ABASTECIMIENTO','DAI')
            THROW 51406, 'VALIDACION_PAYLOAD: CodigoDec debe ser ABASTECIMIENTO o DAI.', 1;
        IF @CondicionCmn NOT IN ('INCLUIDO','NO_INCLUIDO')
            THROW 51407, 'VALIDACION_PAYLOAD: CondicionCmn debe ser INCLUIDO o NO_INCLUIDO.', 1;

        IF NOT EXISTS (SELECT 1 FROM sigcm.TipoContratacion
                        WHERE CodigoTipoContratacion = @CodigoTipoContratacion AND Activo = 1)
        BEGIN
            DECLARE @errTipo nvarchar(400) = CONCAT(
                'VALIDACION_PAYLOAD: el tipo de contratacion ', ISNULL(@CodigoTipoContratacion, '(vacio)'),
                ' no existe. Validos: ',
                (SELECT STRING_AGG(CodigoTipoContratacion, ', ') FROM sigcm.TipoContratacion WHERE Activo = 1), '.');
            THROW 51408, @errTipo, 1;
        END

        IF ISJSON(ISNULL(@DatosAdicionales, N'{}')) <> 1 SET @DatosAdicionales = N'{}';
        SET @DatosAdicionales = ISNULL(@DatosAdicionales, N'{}');

        /* El area usuaria solo registra sobre SU centro de costo. */
        IF @CentroCostoActor IS NULL OR @CentroCostoActor <> @CentroCosto
        BEGIN
            DECLARE @errCentro nvarchar(400) = CONCAT(
                'NO_AUTORIZADO: la unidad del actor esta asociada al centro de costo ',
                ISNULL(@CentroCostoActor, '(ninguno)'), ' y el requerimiento es para ', @CentroCosto, '.');
            THROW 51409, @errCentro, 1;
        END

        IF NOT EXISTS (SELECT 1 FROM siga.vwCentroCosto
                        WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                          AND CentroCosto = @CentroCosto AND Activo = 1)
        BEGIN
            DECLARE @errCC nvarchar(400) = CONCAT(
                'MAESTRO_CENTRO_COSTO: el centro de costo ', @CentroCosto,
                ' no existe o no esta activo en SIGA para ', @AnoEje, '.');
            THROW 51410, @errCC, 1;
        END

        /* ---- REQ-06: el tope de ocho UIT ------------------------------ */
        DECLARE @MontoTope decimal(18,2), @ValorUit decimal(18,2);

        SELECT @MontoTope = MontoTope, @ValorUit = ValorUit
          FROM requerimiento.ParametroAnio
         WHERE AnoEje = @AnoEje AND Activo = 1;

        IF @MontoTope IS NULL
        BEGIN
            DECLARE @errParam nvarchar(400) = CONCAT(
                'CONFLICTO_CONFIGURACION: no hay parametros para el anio ', @AnoEje,
                '. Falta sembrar requerimiento.ParametroAnio con la UIT vigente.');
            THROW 51411, @errParam, 1;
        END

        IF @Monto IS NULL OR @Monto <= 0
            THROW 51412, 'VALIDACION_MONTO: el monto del requerimiento debe ser mayor que cero.', 1;

        /* Locacion: el tope se calcula con monto mensual x entregables de cada
           fila del Anexo 5, no solo con el monto declarado de cabecera. */
        IF @CodigoTipoContratacion = 'LOCACION'
        BEGIN
            DECLARE @MontoLocacion decimal(18,2) = 0;

            IF ISJSON(@DatosAdicionales) = 1
            BEGIN
                SELECT @MontoLocacion = ISNULL(SUM(
                           ISNULL(TRY_CONVERT(decimal(18,2), JSON_VALUE(p.value, '$.MontoMensual')), 0)
                         * ISNULL(TRY_CONVERT(int, JSON_VALUE(p.value, '$.CantidadEntregables')), 0)
                       ), 0)
                  FROM OPENJSON(@DatosAdicionales, '$.Proveedores') AS p;

                IF @MontoLocacion = 0
                    SET @MontoLocacion =
                        ISNULL(TRY_CONVERT(decimal(18,2), JSON_VALUE(@DatosAdicionales, '$.Proveedor.MontoMensual')), 0)
                      * ISNULL(TRY_CONVERT(int, JSON_VALUE(@DatosAdicionales, '$.Proveedor.CantidadEntregables')), 0);
            END

            IF @MontoLocacion > @MontoTope
            BEGIN
                DECLARE @errTopeLoc nvarchar(500) = CONCAT(
                    'VALIDACION_MONTO: el calculo monto mensual x entregables (S/ ',
                    CONVERT(varchar(30), @MontoLocacion),
                    ') supera el tope de ocho UIT para ', @AnoEje, ', que es S/ ',
                    CONVERT(varchar(30), @MontoTope), ' (UIT S/ ', CONVERT(varchar(30), @ValorUit),
                    '). Una contratacion mayor no se tramita por esta via.');
                THROW 51413, @errTopeLoc, 1;
            END
        END

        IF @Monto > @MontoTope
        BEGIN
            DECLARE @errTope nvarchar(500) = CONCAT(
                'VALIDACION_MONTO: el monto S/ ', CONVERT(varchar(30), @Monto),
                ' supera el tope de ocho UIT para ', @AnoEje, ', que es S/ ',
                CONVERT(varchar(30), @MontoTope), ' (UIT S/ ', CONVERT(varchar(30), @ValorUit),
                '). Una contratacion mayor no se tramita por esta via.');
            THROW 51413, @errTope, 1;
        END

        /* ---- REQ-03 y REQ-04: la condicion frente al CMN --------------
           El Anexo 1 firmado (incluido) y el Anexo 4 (no incluido) no se
           piden aqui: el formulario de registro ya no los captura, y el
           flujo los elabora en REQ-13 (estado REQ_DOC_PENDIENTE).
           Si el sobre apunta a una modificacion del CMN, esa referencia
           si se valida contra cmn.Solicitud. */
        IF @IdSolicitudCmn IS NOT NULL
        BEGIN
            DECLARE @EstadoCmn varchar(60);

            SELECT @EstadoCmn = e.CodigoEstado
              FROM cmn.Solicitud AS s
              JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
             WHERE s.IdSolicitud = @IdSolicitudCmn AND s.Activo = 1 AND e.Anulado = 0;

            IF @EstadoCmn IS NULL
                THROW 51416, 'NO_ENCONTRADO: la modificacion del CMN indicada no existe o esta anulada.', 1;

            /* El Anexo 4 llega al area usuaria en CMN_A4_ENVIADO, sin
               recepcion. CMN_FINALIZADO queda para expedientes que ya
               cerraron con el paso anterior. */
            IF @EstadoCmn NOT IN ('CMN_A4_ENVIADO', 'CMN_FINALIZADO')
            BEGIN
                DECLARE @errCmn nvarchar(500) = CONCAT(
                    'CONFLICTO_CMN: la modificacion del CMN esta en estado ', @EstadoCmn,
                    ' y solo habilita el requerimiento cuando el Anexo 4 ya esta en el area usuaria.');
                THROW 51417, @errCmn, 1;
            END
        END

        /* ---- REQ-05: evidencia de la disponibilidad ------------------- */
        IF @TieneDisponibilidad = 1
           AND NULLIF(LTRIM(RTRIM(@GeneradoDocumentoDisp)), '') IS NULL
            THROW 51418, 'VALIDACION_PRESUPUESTO: se declaro disponibilidad presupuestal y debe adjuntarse la evidencia del saldo o de la habilitacion.', 1;

        /* ---- PLZ-01: diez dias habiles de antelacion ------------------ */
        IF @FechaInicioPrevisto IS NOT NULL
        BEGIN
            DECLARE @Minima date = sigcm.fnSumarDiasHabiles(CONVERT(date, GETDATE()), 10);

            IF @FechaInicioPrevisto < @Minima
            BEGIN
                DECLARE @errPlazo nvarchar(500) = CONCAT(
                    'VALIDACION_PLAZO: el requerimiento debe presentarse al menos 10 dias habiles antes del inicio previsto. ',
                    'La fecha mas proxima posible es ', CONVERT(varchar(10), @Minima, 103), '.');
                THROW 51419, @errPlazo, 1;
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
        SELECT ROW_NUMBER() OVER (ORDER BY CONVERT(int, j0.[key])),
               ISNULL(j.AnoEje, @AnoEje), ISNULL(j.SecEjec, @SecEjec),
               j.NumeroPedido, j.SecPedido, TRY_CONVERT(date, j.FechaPedido),
               ISNULL(j.CentroCosto, @CentroCosto),
               j.SecFunc, j.Origen, j.FuenteFinanc, j.Clasificador
        FROM OPENJSON(@parametro, '$.Pedidos') AS j0
        CROSS APPLY OPENJSON(j0.value)
        WITH (
            AnoEje       smallint,
            SecEjec      int,
            NumeroPedido varchar(20),
            SecPedido    bigint,
            FechaPedido  varchar(30),
            CentroCosto  varchar(15),
            SecFunc      int,
            Origen       varchar(1),
            FuenteFinanc varchar(2),
            Clasificador varchar(20)
        ) AS j;

        /* REQ-01: uno o mas pedidos SIGA. Sin pedido no hay necesidad
           registrada en SIGA a la cual referirse. */
        IF NOT EXISTS (SELECT 1 FROM #Pedido)
            THROW 51420, 'VALIDACION_PEDIDOS: el requerimiento debe vincular al menos un pedido SIGA.', 1;

        DECLARE @OrdenMal int;

        SELECT TOP 1 @OrdenMal = Orden FROM #Pedido
         WHERE NULLIF(LTRIM(RTRIM(NumeroPedido)), '') IS NULL;
        IF @OrdenMal IS NOT NULL
        BEGIN
            DECLARE @errPed nvarchar(300) = CONCAT('VALIDACION_PEDIDOS: el pedido ', @OrdenMal, ' no tiene numero.');
            THROW 51421, @errPed, 1;
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
        SELECT ROW_NUMBER() OVER (ORDER BY CONVERT(int, j0.[key])),
               j.OrdenPedido, j.TipoBien, j.GrupoBien, j.ClaseBien,
               j.FamiliaBien, j.ItemBien, j.DescripcionServicio,
               j.Cantidad, j.PrecioUnitario
        FROM OPENJSON(@parametro, '$.Items') AS j0
        CROSS APPLY OPENJSON(j0.value)
        WITH (
            OrdenPedido         int,
            TipoBien            char(1),
            GrupoBien           varchar(2),
            ClaseBien           varchar(2),
            FamiliaBien         varchar(4),
            ItemBien            varchar(4),
            DescripcionServicio varchar(350),
            Cantidad            decimal(18,2),
            PrecioUnitario      decimal(16,6)
        ) AS j;

        IF NOT EXISTS (SELECT 1 FROM #Item)
            THROW 51422, 'VALIDACION_ITEMS: el requerimiento debe tener al menos un item.', 1;

        SET @OrdenMal = NULL;
        SELECT TOP 1 @OrdenMal = Orden FROM #Item
         WHERE Cantidad IS NULL OR Cantidad <= 0 OR PrecioUnitario IS NULL OR PrecioUnitario <= 0;
        IF @OrdenMal IS NOT NULL
        BEGIN
            DECLARE @errItem nvarchar(300) = CONCAT(
                'VALIDACION_ITEMS: el item ', @OrdenMal, ' necesita cantidad y precio unitario mayores que cero.');
            THROW 51423, @errItem, 1;
        END

        /* Un item es del catalogo o es un servicio descrito; nunca ninguno. */
        SET @OrdenMal = NULL;
        SELECT TOP 1 @OrdenMal = Orden FROM #Item
         WHERE ItemBien IS NULL AND NULLIF(LTRIM(RTRIM(DescripcionServicio)), '') IS NULL;
        IF @OrdenMal IS NOT NULL
        BEGIN
            SET @errItem = CONCAT('VALIDACION_ITEMS: el item ', @OrdenMal,
                ' debe elegirse del catalogo de SIGA o describirse como servicio.');
            THROW 51424, @errItem, 1;
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
            SET @errItem = CONCAT('MAESTRO_CATALOGO: el item ', @OrdenMal, ' (',
                (SELECT CONCAT_WS('.', TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien)
                   FROM #Item WHERE Orden = @OrdenMal),
                ') no existe o no esta activo en el catalogo de SIGA.');
            THROW 51425, @errItem, 1;
        END

        /* ---- Coherencia del monto ------------------------------------- */
        DECLARE @MontoItems decimal(18,2) =
            (SELECT SUM(ROUND(Cantidad * PrecioUnitario, 2)) FROM #Item);

        IF ABS(@MontoItems - @Monto) > 0.01
        BEGIN
            DECLARE @errMonto nvarchar(500) = CONCAT(
                'VALIDACION_MONTO: el monto declarado S/ ', CONVERT(varchar(30), @Monto),
                ' no coincide con la suma de los items S/ ', CONVERT(varchar(30), @MontoItems), '.');
            THROW 51426, @errMonto, 1;
        END

        /* ---- Escritura ------------------------------------------------ */
        DECLARE @CodigoEstadoInicial varchar(60);
        SELECT @CodigoEstadoInicial = CodigoEstado
          FROM sigcm.Estado
         WHERE CodigoModulo = 'REQUERIMIENTO' AND EsInicial = 1 AND Activo = 1;

        IF @CodigoEstadoInicial IS NULL
            THROW 51427, 'CONFLICTO_CONFIGURACION: el modulo REQUERIMIENTO no tiene estado inicial. Falta ejecutar S003.', 1;

        DECLARE @Codigo varchar(40);
        DECLARE @AreaNumerica varchar(20) =
            REPLACE(REPLACE(LTRIM(RTRIM(@CentroCosto)), '.', ''), ' ', '');
        DECLARE @IdUsuarioNumerico int;
        SELECT @IdUsuarioNumerico = IdUsuarioSso
          FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;
        IF @IdUsuarioNumerico IS NULL OR @IdUsuarioNumerico <= 0
            SET @IdUsuarioNumerico = (ABS(CHECKSUM(CONVERT(varchar(36), @IdUsuario))) % 900) + 100;

        EXEC sigcm.paSiguienteCodigo
             'REQ', @AnoEje, N'requerimiento.SeqRequerimiento', @Codigo OUTPUT,
             @AreaNumerica, @IdUsuarioNumerico;

        DECLARE @Ahora datetime = GETDATE();
        DECLARE @IdExpediente uniqueidentifier, @IdRequerimiento uniqueidentifier;

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

        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
             Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExpediente, NULL, @CodigoEstadoInicial, NULL,
             'Registro inicial del requerimiento', @IdUsuario, @CodigoRol, @IdUnidad,
             (SELECT @Codigo AS Codigo, @CentroCosto AS CentroCosto,
                     @CodigoTipoContratacion AS TipoContratacion, @CodigoDec AS Dec
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
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

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdRequerimiento AS IdRequerimiento,
                   @IdExpediente    AS IdExpediente,
                   @Codigo          AS Codigo,
                   @CodigoEstadoInicial AS CodigoEstado,
                   1 AS Version,
                   @Items   AS Items,
                   @Pedidos AS Pedidos,
                   @Monto   AS Monto,
                   @MontoTope AS MontoTope,
                   N'Se realizo el registro satisfactoriamente.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

/* ========================================================================== */
/* 2. requerimiento.paObtenerRequerimiento                                   */
/* ========================================================================== */

/* Requerimiento completo: cabecera, pedidos e items. Es lo que consume el visor
   y el formulario cuando esta editable (REQ-11).

   No une vistas SIGA (catalogo, unidad de medida, centro de costo): esas lecturas
   remotas pueden superar el timeout de 30 s del puente y dejan el Anexo 5 a
   medias despues de un grabado correcto. El nombre del area sale de sigcm.Unidad
   y la descripcion del item de RequerimientoItem.DescripcionServicio.

   Entrada: { "Actor": {...}, "IdRequerimiento": "..." } */
CREATE OR ALTER PROCEDURE requerimiento.paObtenerRequerimiento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51440, 'JSON incorrecto.', 1;

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

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        IF @IdRequerimiento IS NULL
            THROW 51441, 'VALIDACION_PAYLOAD: falta IdRequerimiento o no es un identificador valido.', 1;

        IF NOT EXISTS (SELECT 1 FROM requerimiento.Requerimiento
                        WHERE IdRequerimiento = @IdRequerimiento AND Activo = 1)
            THROW 51442, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   r.IdRequerimiento, r.Codigo, r.AnoEje, r.SecEjec, r.CentroCosto,
                   r.Denominacion, r.CodigoTipoContratacion,
                   TipoContratacion = tc.Nombre,
                   r.CodigoDec, r.CondicionCmn, r.IdSolicitudCmn,
                   r.GeneradoDocumentoCmn, r.NombreDocumentoCmn,
                   r.Monto, r.PlazoDias, r.FechaInicioPrevisto,
                   r.Ate, r.RucSugerido,
                   r.TieneDisponibilidad,
                   r.GeneradoDocumentoDisponibilidad, r.NombreDocumentoDisponibilidad,
                   r.Sustento, r.DatosAdicionales,
                   e.IdExpediente, e.CodigoEstado, e.Version, e.Anulado,
                   Estado = w.Nombre,
                   Responsable = CONCAT_WS(' ', u.Nombres, u.Apellidos),
                   CentroCostoNombre = ISNULL(un.Nombre, r.CentroCosto),
                   /* Si se apoya en una modificacion del CMN, se devuelve su
                      codigo: el visor la muestra sin una segunda consulta. */
                   SolicitudCmn = (SELECT TOP 1 s.Codigo FROM cmn.Solicitud AS s
                                    WHERE s.IdSolicitud = r.IdSolicitudCmn),
                   Pedidos = JSON_QUERY(COALESCE((
                       SELECT p.IdRequerimientoPedido, p.AnoEje, p.SecEjec, p.NumeroPedido,
                              p.SecPedido, p.FechaPedido, p.CentroCosto, p.SecFunc,
                              p.Origen, p.FuenteFinanc, p.Clasificador, p.Verificado
                         FROM requerimiento.RequerimientoPedido AS p
                        WHERE p.IdRequerimiento = r.IdRequerimiento AND p.Activo = 1
                        ORDER BY p.NumeroPedido
                          FOR JSON PATH), '[]')),
                   Items = JSON_QUERY(COALESCE((
                       SELECT i.IdRequerimientoItem, i.Orden,
                              CodigoItem = CONCAT_WS('.', i.TipoBien, i.GrupoBien,
                                                     i.ClaseBien, i.FamiliaBien, i.ItemBien),
                              i.TipoBien, i.GrupoBien, i.ClaseBien, i.FamiliaBien, i.ItemBien,
                              i.DescripcionServicio, i.UnidadMedida,
                              UnidadAbreviatura = CONVERT(varchar(20), NULL),
                              Descripcion = ISNULL(i.DescripcionServicio, CONVERT(varchar(350), N'')),
                              i.Cantidad, i.PrecioUnitario, i.Monto,
                              NumeroPedido = (SELECT TOP 1 p2.NumeroPedido
                                                FROM requerimiento.RequerimientoPedido AS p2
                                               WHERE p2.IdRequerimientoPedido = i.IdRequerimientoPedido)
                         FROM requerimiento.RequerimientoItem AS i
                        WHERE i.IdRequerimiento = r.IdRequerimiento AND i.Activo = 1
                        ORDER BY i.Orden
                          FOR JSON PATH), '[]')),
                   Filtros = JSON_QUERY(COALESCE((
                       SELECT f.IdFiltro, f.CodigoFiltro, Tipo = ft.Nombre, ft.Orden,
                              f.Resultado, f.Origen, f.Observacion, f.FechaVerificacion,
                              f.GeneradoDocumentoEvidencia, f.NombreDocumentoEvidencia
                         FROM requerimiento.FiltroIdoneidad AS f
                         JOIN requerimiento.FiltroTipo AS ft ON ft.CodigoFiltro = f.CodigoFiltro
                        WHERE f.IdRequerimiento = r.IdRequerimiento AND f.Activo = 1
                          AND ft.Activo = 1
                        ORDER BY ft.Orden
                          FOR JSON PATH), '[]')),
                   Ccp = JSON_QUERY((
                       SELECT TOP 1 c.IdCcp, c.NumeroCcp, c.NumeroExpedienteSiaf, c.MontoCertificado,
                              c.FechaSolicitud, c.FechaEmision,
                              c.GeneradoDocumentoCcp, c.NombreDocumentoCcp,
                              c.GeneradoDocumentoMemo, c.NombreDocumentoMemo,
                              c.GeneradoDocumentoMemoUp, c.NombreDocumentoMemoUp,
                              c.GeneradoDocumentoPrevision, c.NombreDocumentoPrevision,
                              c.CuerpoMemorando, c.Observacion, c.NumeroMemorando
                         FROM requerimiento.CertificacionCcp AS c
                        WHERE c.IdRequerimiento = r.IdRequerimiento AND c.Activo = 1
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                   OrdenServicio = JSON_QUERY((
                       SELECT TOP 1 o.IdOrdenServicio, o.NumeroOrden, o.FechaEmision,
                              o.CorreoLocador, o.CorreoAreaUsuaria, o.NotificadoEn,
                              o.EstadoIntegracion, o.SecCuadroSiga, o.ProveedorSiga,
                              o.ErrorIntegracion,
                              o.GeneradoDocumento, o.NombreDocumento
                         FROM requerimiento.OrdenServicio AS o
                        WHERE o.IdRequerimiento = r.IdRequerimiento AND o.Activo = 1
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                   'OK' AS mensaje
              FROM requerimiento.Requerimiento AS r
              JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
              JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
              JOIN sigcm.Usuario    AS u ON u.IdUsuario    = r.IdResponsable
              JOIN sigcm.TipoContratacion AS tc ON tc.CodigoTipoContratacion = r.CodigoTipoContratacion
              LEFT JOIN sigcm.Unidad AS un
                     ON un.CentroCostoSiga = r.CentroCosto AND un.Activo = 1
             WHERE r.IdRequerimiento = @IdRequerimiento
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

/* ========================================================================== */
/* 3. requerimiento.paListarRequerimiento                                    */
/* ========================================================================== */

/*
  Bandeja del modulo, con el mismo criterio que la de CMN: por defecto muestra
  lo que esta en la unidad del actor Y cuyo estado tiene como responsable su rol.

  Cada fila trae Transiciones: las mismas que sigcm.paListarTransicionDisponible
  para ese expediente y este actor. La bandeja pinta los botones de accion con
  ese arreglo y no vuelve a consultar el motor por cada fila.

  Entrada:
  { "Actor": {...},
    "Filtro": { "SoloMiBandeja":true, "CodigoEstado":null, "AnoEje":2026,
                "CentroCosto":null, "CodigoTipoContratacion":null,
                "Texto":null, "Limite":50, "Desplazamiento":0 } }
*/
CREATE OR ALTER PROCEDURE requerimiento.paListarRequerimiento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51450, 'JSON incorrecto.', 1;

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

        DECLARE @SoloMiBandeja bit, @CodigoEstado varchar(60), @AnoEje smallint,
                @CentroCosto varchar(15), @CodigoTipoContratacion varchar(20),
                @Texto varchar(200), @Limite int, @Desplazamiento int;

        SELECT @SoloMiBandeja          = ISNULL(SoloMiBandeja, 1),
               @CodigoEstado           = CodigoEstado,
               @AnoEje                 = AnoEje,
               @CentroCosto            = CentroCosto,
               @CodigoTipoContratacion = CodigoTipoContratacion,
               @Texto                  = Texto,
               @Limite                 = Limite,
               @Desplazamiento         = Desplazamiento
        FROM OPENJSON(@parametro, '$.Filtro')
        WITH (
            SoloMiBandeja          bit,
            CodigoEstado           varchar(60),
            AnoEje                 smallint,
            CentroCosto            varchar(15),
            CodigoTipoContratacion varchar(20),
            Texto                  varchar(200),
            Limite                 int,
            Desplazamiento         int
        );

        SET @SoloMiBandeja  = ISNULL(@SoloMiBandeja, 1);
        SET @Limite         = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50
                                   WHEN @Limite > 200 THEN 200 ELSE @Limite END;
        SET @Desplazamiento = CASE WHEN @Desplazamiento IS NULL OR @Desplazamiento < 0
                                   THEN 0 ELSE @Desplazamiento END;

        DECLARE @Total int;

        SELECT @Total = COUNT(*)
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
          JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE e.Anulado = 0 AND e.Activo = 1 AND r.Activo = 1
           AND (@SoloMiBandeja = 0
                OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol))
           AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
           AND (@AnoEje       IS NULL OR r.AnoEje       = @AnoEje)
           AND (@CentroCosto  IS NULL OR r.CentroCosto  = @CentroCosto)
           AND (@CodigoTipoContratacion IS NULL OR r.CodigoTipoContratacion = @CodigoTipoContratacion)
           AND (@Texto        IS NULL OR r.Codigo LIKE '%' + @Texto + '%'
                                      OR r.Denominacion LIKE '%' + @Texto + '%');

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @Total          AS total,
                   @Limite         AS limite,
                   @Desplazamiento AS desplazamiento,
                   Requerimientos = JSON_QUERY(COALESCE((
                       SELECT r.IdRequerimiento, r.Codigo, r.AnoEje, r.CentroCosto,
                              r.Denominacion, r.CodigoTipoContratacion,
                              TipoContratacion = tc.Nombre,
                              r.CodigoDec, r.CondicionCmn, r.Monto, r.PlazoDias,
                              r.FechaInicioPrevisto,
                              e.IdExpediente, e.CodigoEstado, e.Version,
                              Estado = w.Nombre,
                              RolResponsable = w.RolResponsable,
                              Items = (SELECT COUNT(*) FROM requerimiento.RequerimientoItem AS it
                                        WHERE it.IdRequerimiento = r.IdRequerimiento AND it.Activo = 1),
                              Pedidos = (SELECT COUNT(*) FROM requerimiento.RequerimientoPedido AS pe
                                          WHERE pe.IdRequerimiento = r.IdRequerimiento AND pe.Activo = 1),
                              /* Documento tecnico vigente (Anexo 5 en locacion).
                                 La bandeja muestra el PDF registrado, no uno rearmado. */
                              DocumentoSistema = doc.GeneradoDocumento,
                              NombreDocumento = doc.NombreDocumento,
                              EstadoDocumento = doc.Estado,
                              CodigoTipoDocumento = doc.CodigoTipoDocumento,
                              /* Mismas transiciones que sigcm.paListarTransicionDisponible
                                 para este expediente y este rol. JSON_QUERY evita
                                 que FOR JSON las escape como texto. */
                              Transiciones = JSON_QUERY(COALESCE((
                                  SELECT t.CodigoTransicion,
                                         NombreAccion = CASE
                                             WHEN t.CodigoTransicion = 'CMN_SUBS_JEFE_ENVIAR'
                                                  AND dest.CodigoEstado = 'CMN_EN_EVAL_OA'
                                                 THEN N'Firmar y remitir subsanado a OA'
                                             ELSE t.NombreAccion
                                         END,
                                         CodigoEstadoDestino = CASE
                                             WHEN t.CodigoTransicion = 'CMN_SUBS_JEFE_ENVIAR'
                                                  AND dest.CodigoEstado IS NOT NULL
                                                 THEN dest.CodigoEstado
                                             ELSE t.CodigoEstadoDestino
                                         END,
                                         EstadoDestino = d.Nombre,
                                         t.RequiereComentario, t.RequiereFirma, t.DocumentoRequerido,
                                         t.EncolaIntegracion, t.GeneraObservacion
                                    FROM sigcm.Transicion AS t
                                    JOIN sigcm.Estado AS d ON d.CodigoEstado =
                                         CASE
                                             WHEN t.CodigoTransicion = 'CMN_SUBS_JEFE_ENVIAR'
                                                  AND dest.CodigoEstado IS NOT NULL
                                                 THEN dest.CodigoEstado
                                             ELSE t.CodigoEstadoDestino
                                         END
                                   WHERE t.CodigoModulo = e.CodigoModulo
                                     AND t.CodigoEstadoOrigen = e.CodigoEstado
                                     AND t.Activo = 1
                                     AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS tr
                                                  WHERE tr.CodigoTransicion = t.CodigoTransicion
                                                    AND tr.CodigoRol = @CodigoRol)
                                     AND t.CodigoTransicion <> 'REQ_REMITIR_DAI'
                                     AND NOT (t.CodigoTransicion = 'REQ_REMITIR_OA' AND r.CodigoDec <> 'ABASTECIMIENTO')
                                     AND NOT (t.CodigoTransicion IN ('REQ_INICIAR_INDAGACION', 'REQ_INICIAR_FILTROS')
                                              AND r.CodigoTipoContratacion <> 'LOCACION')
                                   ORDER BY t.CodigoTransicion
                                     FOR JSON PATH), N'[]')),
                              ActualizadoEn = ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria)
                         FROM requerimiento.Requerimiento AS r
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
                         JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
                         JOIN sigcm.TipoContratacion AS tc ON tc.CodigoTipoContratacion = r.CodigoTipoContratacion
                         OUTER APPLY (
                             SELECT TOP 1 dv.GeneradoDocumento, dv.NombreDocumento, dv.Estado,
                                    d.CodigoTipoDocumento
                               FROM sigcm.DocumentoExpediente AS de
                               JOIN sigcm.Documento AS d ON d.IdDocumento = de.IdDocumento
                               JOIN sigcm.DocumentoVersion AS dv
                                 ON dv.IdDocumento = d.IdDocumento
                                AND dv.Version = d.VersionVigente
                              WHERE de.IdExpediente = e.IdExpediente
                                AND d.Anulado = 0 AND d.Activo = 1
                                AND d.CodigoTipoDocumento = CASE r.CodigoTipoContratacion
                                    WHEN 'LOCACION'    THEN 'REQ_PROPUESTA_LOCACION'
                                    WHEN 'SERVICIO'    THEN 'REQ_TDR_SERVICIO'
                                    WHEN 'CONSULTORIA' THEN 'REQ_TDR_CONSULTORIA'
                                    WHEN 'BIEN'        THEN 'REQ_EETT_BIEN'
                                END
                              ORDER BY d.FechaCreacionAuditoria DESC
                         ) AS doc
                         OUTER APPLY (
                             SELECT TOP 1 o.CodigoEstadoRetorno
                               FROM sigcm.Observacion AS o
                              WHERE o.IdExpediente = e.IdExpediente AND o.Activo = 1
                                AND o.Estado IN ('PENDIENTE','RECEPCIONADA','SUBSANADA')
                              ORDER BY o.FechaCreacionAuditoria DESC
                         ) AS obs
                         OUTER APPLY (
                             SELECT CASE
                                        WHEN obs.CodigoEstadoRetorno = 'CMN_EN_EVAL_OA'
                                            THEN 'CMN_EN_EVAL_OA'
                                        WHEN obs.CodigoEstadoRetorno LIKE 'CMN_EN_ABAST%'
                                            THEN 'CMN_EN_ABAST_JEFE'
                                        ELSE NULL
                                    END AS CodigoEstado
                         ) AS dest
                        WHERE e.Anulado = 0 AND e.Activo = 1 AND r.Activo = 1
                          AND (@SoloMiBandeja = 0
                               OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol))
                          AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
                          AND (@AnoEje       IS NULL OR r.AnoEje       = @AnoEje)
                          AND (@CentroCosto  IS NULL OR r.CentroCosto  = @CentroCosto)
                          AND (@CodigoTipoContratacion IS NULL OR r.CodigoTipoContratacion = @CodigoTipoContratacion)
                          AND (@Texto        IS NULL OR r.Codigo LIKE '%' + @Texto + '%'
                                                     OR r.Denominacion LIKE '%' + @Texto + '%')
                        ORDER BY ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria) DESC
                        OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY
                          FOR JSON PATH), '[]')),
                   'OK' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo,
                   JSON_QUERY('[]') AS Requerimientos
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

PRINT 'F005 aplicada: modulo Requerimiento.';
GO
