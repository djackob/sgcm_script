/*
===============================================================================
  SIGCM - F002 : Modulo Gestion CMN - registro y consulta del Anexo 3
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51100-51199

  Port de SIGCM/db/10_api/F002__cmn_solicitud.sql (PostgreSQL 14).

  Alcance (ADR-002): MODIFICACION del Cuadro Multianual de Necesidades.

  ---------------------------------------------------------------------------
  SOBRE DE ENTRADA de cmn.paRegistrarSolicitud
  ---------------------------------------------------------------------------
  {
    "Actor": { "Usuario":"...", "Rol":"...", "Unidad":"...", "Ip":"...",
               "Equipo":"...", "Programa":"...", "CorrelacionId":"..." },
    "Solicitud": {
      "AnoEje": 2026, "SecEjec": 1750, "CentroCosto": "01.02.02",
      "TipoOperacion": "MODIFICACION", "Sustento": "...",
      "TipoInclusion": "ORDINARIA",              o "EXTRAORDINARIA"
      "JustificacionUrgencia": "...",            obligatoria si es EXTRAORDINARIA
      "DatosAdicionales": { }
    },
    "Items": [
      { "TipoMovimiento": "INCLUSION",
        "TipoTarea":"A", "NivelTarea":"1", "CodigoTarea":1, "SecFunc":1,
        "Origen":"1", "FuenteFinanc":"00", "Clasificador":"2.3.1 5.1 2",
        "TipoRecurso":"1", "TipoPpto":1, "TipoUso":"C",
        "TipoBien":"B", "GrupoBien":"71", "ClaseBien":"72",
        "FamiliaBien":"0017", "ItemBien":"0042",
        "PrecioUnitario": 1.50,
        "RefSecCuadro": null, "RefSecItem": null,
        "Periodos": [ { "AnoOffset":0, "Mes":1, "Cantidad":100 } ]
      }
    ]
  }

  REGLA DEL MOCKUP: por cada item se registra exclusion O inclusion, nunca ambas,
  y la tabla debe conservar al menos un item. Aqui eso es TipoMovimiento, que es
  un solo valor por linea, mas la validacion de items no vacios.

  SOLO INCLUSION O EXCLUSION. El Anexo 3 oficial tiene dos pares de columnas
  -exclusion e inclusion- y no tiene una tercera para modificar. MODIFICACION era
  una via propia del sistema que no figura en el formato ni en la Directiva:
  cambiar la cantidad de un item programado se expresa excluyendo la linea
  vigente e incluyendola con la cantidad nueva, que es lo que el area usuaria
  puede firmar tal como se imprime. El valor sigue existiendo en el modelo
  -cmn.SolicitudItem lo admite y W001 sabe proyectarlo- porque hay expedientes
  historicos con esa marca; lo que no se admite es registrar uno nuevo.

  TIPIFICACION DE LA SOLICITUD. TipoInclusion se declara AQUI, al registrar, y lo
  declara el area usuaria. Antes lo ponia el especialista de Abastecimiento al
  conformar el Anexo 3 (F004), lo que llegaba tarde: de esa marca depende el
  plazo -el Anexo 4 ordinario sale los viernes, el extraordinario cualquier dia-
  y quien conoce la urgencia es quien tiene la necesidad. Una solicitud
  EXTRAORDINARIA exige ademas JustificacionUrgencia; el archivo de sustento
  -informe o nota tecnica- se adjunta como documento del expediente
  (CMN_SUSTENTO_URGENCIA) con sigcm.paRegistrarDocumento.

  LOS 48 PERIODOS. El cliente envia solo los meses con cantidad. El procedimiento
  materializa 4 anios x 12 meses = 48 filas por item, rellenando con cero los no
  informados. Nunca se omiten: es criterio de aceptacion del MVP y ademas es lo
  que permite proyectar hacia las dos representaciones distintas de SIGA sin
  rediseno.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 0. cmn.fnDocumentoVigente                                                 */
/* ========================================================================== */

/*
  El archivo del file server que corresponde HOY a un tipo de documento de un
  expediente: la version vigente del unico documento vivo de ese tipo.

  Por que existe. La pantalla necesita el PDF ya subido para dos cosas: abrirlo
  al firmar y volver a mostrarlo despues. Sin este dato en la bandeja, el front
  solo conoce el archivo dentro de la sesion en que lo genero; al recargar, el
  boton de ver el Anexo se quedaba sin nada que abrir, y el que firmaba no veia
  el documento que estaba firmando.

  Por que es una funcion y no un OUTER APPLY repetido. Lo consultan las dos
  rutinas de lectura, por dos tipos de documento cada una: cuatro copias del
  mismo JOIN de tres tablas. Una sola definicion evita que se separen.

  El TOP 1 no deberia hacer falta —el indice unico filtrado deja un documento
  vivo por tipo y expediente— pero el ORDER BY lo hace determinista si alguna
  vez lo hiciera. Es inline: el optimizador la expande, no cuesta nada frente
  al APPLY escrito a mano.
*/
CREATE OR ALTER FUNCTION cmn.fnDocumentoVigente
(
    @IdExpediente        uniqueidentifier,
    @CodigoTipoDocumento varchar(60)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP 1
           dv.GeneradoDocumento,
           dv.NombreDocumento,
           dv.Estado AS EstadoVersion,
           d.VersionVigente
      FROM sigcm.Documento AS d
      JOIN sigcm.DocumentoExpediente AS de ON de.IdDocumento = d.IdDocumento
      JOIN sigcm.DocumentoVersion    AS dv ON dv.IdDocumento = d.IdDocumento
                                          AND dv.Version     = d.VersionVigente
     WHERE de.IdExpediente        = @IdExpediente
       AND d.CodigoTipoDocumento  = @CodigoTipoDocumento
       AND d.Anulado = 0 AND d.Activo = 1
     ORDER BY d.FechaCreacionAuditoria DESC
);
GO

/* ========================================================================== */
/* 0bis. cmn.fnPuedeEditar                                                   */
/* ========================================================================== */

/*
  Si ESTE actor puede corregir el contenido de un Anexo 3 que esta en ESTE
  estado. Una sola definicion, consultada por las dos rutinas que la necesitan:
  cmn.paRegistrarSolicitud, que lo exige antes de escribir, y
  cmn.paListarSolicitud, que se lo dice a la pantalla para que ofrezca el boton.
  Repartida en dos sitios terminaria diciendo cosas distintas.

  LOS TRES CANDADOS
  1. El expediente esta en un estado del AREA USUARIA en el que el Anexo 3
     todavia no vale como firmado.
  2. El expediente esta EN LA UNIDAD del actor. Sin esto, un especialista podria
     corregir el expediente de otra oficina que casualmente este en el mismo
     estado.
  3. El actor ejerce un rol del area usuaria. El negocio pidio que puedan
     corregir tanto el especialista que lo registro como su jefe, sin importar a
     cual de los dos le toque el turno: el jefe que encuentra un error no tiene
     que devolverlo para que lo arreglen.

  QUE ESTADOS Y POR QUE
    CMN_BORRADOR        aun no se genero el documento
    CMN_OBS_AU_JEFE     volvio observado y esta con el jefe
    CMN_OBS_AU_COORD    el jefe lo derivo al coordinador
    CMN_OBSERVADO       el coordinador lo derivo al especialista para subsanar

  CMN_PEND_FIRMA_A3 queda fuera: el Anexo 3 ya se envio al jefe del area y no
  se corrige. CMN_A3_FIRMADO (historico) y los CMN_SUBS_* tambien: alli el area
  ya declaro el contenido y el expediente va de salida.
*/
CREATE OR ALTER FUNCTION cmn.fnPuedeEditar
(
    @CodigoEstado varchar(60),
    @CodigoRol    varchar(40),
    @EnMiUnidad   bit
)
RETURNS bit
AS
BEGIN
    IF @EnMiUnidad <> 1 RETURN 0;

    IF @CodigoRol NOT IN ('AREA_ESPECIALISTA','AREA_COORDINADOR','AREA_JEFE')
        RETURN 0;

    IF @CodigoEstado NOT IN ('CMN_BORRADOR',
                             'CMN_OBS_AU_JEFE','CMN_OBS_AU_COORD','CMN_OBSERVADO')
        RETURN 0;

    RETURN 1;
END
GO

/* Nombre del jefe titular del area usuaria de origen: es quien firma el Anexo 3,
   no el especialista que lo registro. */
CREATE OR ALTER FUNCTION cmn.fnNombreJefeArea
(
    @IdUnidad uniqueidentifier
)
RETURNS varchar(250)
AS
BEGIN
    DECLARE @Nombre varchar(250);

    SELECT TOP (1) @Nombre = CONCAT_WS(' ', uj.Nombres, uj.Apellidos)
      FROM sigcm.UsuarioRol AS urj
      JOIN sigcm.Usuario    AS uj ON uj.IdUsuario = urj.IdUsuario
     WHERE urj.IdUnidad = @IdUnidad
       AND urj.CodigoRol = 'AREA_JEFE'
       AND urj.Activo = 1
       AND urj.VigenteHasta IS NULL
       AND uj.Activo = 1
     ORDER BY CASE WHEN uj.IdUsuarioSso IS NOT NULL THEN 0 ELSE 1 END,
              urj.EsTitular DESC, uj.Apellidos, uj.Nombres;

    RETURN @Nombre;
END
GO

/* ========================================================================== */
/* 1. cmn.paRegistrarSolicitud                                               */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE cmn.paRegistrarSolicitud
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
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51100, 'JSON incorrecto.', 1;

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
                @TipoInclusion varchar(15), @JustificacionUrgencia nvarchar(max),
                @DatosAdicionales nvarchar(max), @IdSolicitud uniqueidentifier;

        /* Con IdSolicitud la rutina CORRIGE una solicitud existente; sin el,
           registra una nueva. Es la misma operacion desde el punto de vista del
           negocio —el area usuaria declara que necesita— y por eso comparte
           todas las validaciones: lo que cambia es donde aterriza el resultado.

           Antes este campo se leia y se descartaba en silencio, de modo que
           subsanar una observacion creaba un expediente nuevo con correlativo
           nuevo y dejaba el observado vivo. Ese era el pendiente 1 del
           2026-08-20. */
        SET @IdSolicitud = TRY_CONVERT(uniqueidentifier,
                                       JSON_VALUE(@parametro, '$.Solicitud.IdSolicitud'));

        SELECT @AnoEje                = AnoEje,
               @SecEjec               = SecEjec,
               @CentroCosto           = CentroCosto,
               @TipoOperacion         = ISNULL(TipoOperacion, 'MODIFICACION'),
               @Sustento              = Sustento,
               @TipoInclusion         = UPPER(NULLIF(LTRIM(RTRIM(TipoInclusion)), '')),
               @JustificacionUrgencia = NULLIF(LTRIM(RTRIM(JustificacionUrgencia)), ''),
               @DatosAdicionales      = DatosAdicionales
        FROM OPENJSON(@parametro, '$.Solicitud')
        WITH (
            AnoEje                smallint,
            SecEjec               int,
            CentroCosto           varchar(15),
            TipoOperacion         varchar(20),
            Sustento              nvarchar(max),
            TipoInclusion         varchar(15),
            JustificacionUrgencia nvarchar(max),
            DatosAdicionales      nvarchar(max) AS JSON
        );

        /* ---- Modo correccion: quien, sobre que y desde que estado ------ */
        DECLARE @IdExpedienteEdit uniqueidentifier, @CodigoEstadoEdit varchar(60),
                @CodigoEdit varchar(40), @IdUnidadActualEdit uniqueidentifier;

        IF @IdSolicitud IS NOT NULL
        BEGIN
            SELECT @IdExpedienteEdit   = e.IdExpediente,
                   @CodigoEstadoEdit   = e.CodigoEstado,
                   @CodigoEdit         = s.Codigo,
                   @IdUnidadActualEdit = e.IdUnidadActual,
                   /* Las coordenadas del cuadro NO se reciben del cliente al
                      corregir: se toman de la fila. Cambiar el ejercicio o el
                      centro de costo de un expediente ya numerado no es una
                      correccion, es otro expediente. */
                   @AnoEje             = s.AnoEje,
                   @SecEjec            = s.SecEjec,
                   @CentroCosto        = s.CentroCosto
              FROM cmn.Solicitud AS s
              JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
             WHERE s.IdSolicitud = @IdSolicitud AND s.Activo = 1
               AND e.Anulado = 0 AND e.Activo = 1;

            IF @IdExpedienteEdit IS NULL
                THROW 51127, 'NO_ENCONTRADO: la solicitud que se intenta corregir no existe, esta anulada o fue dada de baja.', 1;

            IF cmn.fnPuedeEditar(@CodigoEstadoEdit, @CodigoRol,
                                 CASE WHEN @IdUnidadActualEdit = @IdUnidad THEN 1 ELSE 0 END) = 0
            BEGIN
                DECLARE @errEdit nvarchar(400) = CONCAT(
                    'NO_AUTORIZADO: ', @CodigoEdit, ' no puede corregirse por este perfil en el estado ',
                    @CodigoEstadoEdit,
                    '. Solo el area usuaria que lo tiene, en borrador o cuando volvio observado. Una vez enviado al jefe ya no se edita.');
                THROW 51128, @errEdit, 1;
            END
        END

        IF @AnoEje IS NULL OR @SecEjec IS NULL
            THROW 51101, 'VALIDACION_PAYLOAD: Solicitud.AnoEje y Solicitud.SecEjec son obligatorios.', 1;
        IF NULLIF(LTRIM(RTRIM(@CentroCosto)), '') IS NULL
            THROW 51102, 'VALIDACION_PAYLOAD: falta Solicitud.CentroCosto.', 1;
        IF NULLIF(LTRIM(RTRIM(@Sustento)), '') IS NULL
            THROW 51103, 'VALIDACION_SUSTENTO: el sustento de la solicitud es obligatorio.', 1;
        IF @TipoOperacion <> 'MODIFICACION'
            THROW 51104, 'VALIDACION_PAYLOAD: la v1 solo habilita TipoOperacion = MODIFICACION (ADR-002).', 1;

        /* Tipificacion: la declara el area usuaria al registrar, y de ella
           depende cuando podra generarse el Anexo 4 que la aprueba. */
        IF @TipoInclusion IS NULL
            THROW 51122, 'VALIDACION_TIPO_SOLICITUD: indique si la solicitud es ORDINARIA o EXTRAORDINARIA.', 1;
        IF @TipoInclusion NOT IN ('ORDINARIA','EXTRAORDINARIA')
            THROW 51123, 'VALIDACION_TIPO_SOLICITUD: TipoInclusion debe ser ORDINARIA o EXTRAORDINARIA.', 1;

        /* La urgencia se sustenta o no es urgencia. Es lo que Abastecimiento
           tiene que poder leer para validarla contra las directivas del MEF. */
        IF @TipoInclusion = 'EXTRAORDINARIA' AND @JustificacionUrgencia IS NULL
            THROW 51124, 'VALIDACION_JUSTIFICACION: una solicitud extraordinaria debe justificar por escrito la urgencia de la necesidad.', 1;

        /* Una ordinaria no arrastra justificacion de urgencia: si el usuario
           cambio de opinion en el formulario, el texto que quedo escrito no
           corresponde a lo que se esta registrando. */
        IF @TipoInclusion <> 'EXTRAORDINARIA'
            SET @JustificacionUrgencia = NULL;

        IF ISJSON(ISNULL(@DatosAdicionales, N'{}')) <> 1
            SET @DatosAdicionales = N'{}';
        SET @DatosAdicionales = ISNULL(@DatosAdicionales, N'{}');

        /* El area usuaria solo puede registrar sobre SU centro de costo. Sin
           esto, cualquier especialista podria modificar el cuadro de otra area. */
        IF @CentroCostoActor IS NULL OR @CentroCostoActor <> @CentroCosto
        BEGIN
            DECLARE @errCentro nvarchar(400) = CONCAT(
                'NO_AUTORIZADO: la unidad del actor esta asociada al centro de costo ',
                ISNULL(@CentroCostoActor, '(ninguno)'), ' y la solicitud es para ', @CentroCosto, '.');
            THROW 51105, @errCentro, 1;
        END

        /* El centro de costo debe existir y estar activo en SIGA. */
        IF NOT EXISTS (SELECT 1 FROM siga.vwCentroCosto
                        WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                          AND CentroCosto = @CentroCosto AND Activo = 1)
        BEGIN
            DECLARE @errCC nvarchar(400) = CONCAT(
                'MAESTRO_CENTRO_COSTO: el centro de costo ', @CentroCosto,
                ' no existe o no esta activo en SIGA para ', @AnoEje, '.');
            THROW 51106, @errCC, 1;
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
            Periodos            nvarchar(max) NULL
        );

        INSERT INTO #Item (Orden, TipoMovimiento, TipoTarea, NivelTarea, CodigoTarea,
                           SecFunc, SecFuncProp, Origen, FuenteFinanc, Clasificador,
                           TipoRecurso, TipoPpto, TipoUso, TipoBien, GrupoBien, ClaseBien,
                           FamiliaBien, ItemBien, DescripcionServicio, PrecioUnitario,
                           RefSecCuadro, RefSecItem, Periodos)
        /* El orden lo fija la posicion en el arreglo, y [key] es texto: sin el
           CONVERT a int, con diez o mas items quedaria 0,1,10,11,2,... */
        SELECT ROW_NUMBER() OVER (ORDER BY CONVERT(int, j0.[key])),
               j.TipoMovimiento, j.TipoTarea, j.NivelTarea, j.CodigoTarea,
               j.SecFunc, j.SecFuncProp,
               ISNULL(j.Origen, '1'), ISNULL(j.FuenteFinanc, '00'), j.Clasificador,
               ISNULL(j.TipoRecurso, '1'), ISNULL(j.TipoPpto, 1), ISNULL(j.TipoUso, 'C'),
               j.TipoBien, j.GrupoBien, j.ClaseBien, j.FamiliaBien, j.ItemBien,
               j.DescripcionServicio, j.PrecioUnitario,
               j.RefSecCuadro, j.RefSecItem, j.Periodos
        FROM OPENJSON(@parametro, '$.Items') AS j0
        CROSS APPLY OPENJSON(j0.value)
        WITH (
            TipoMovimiento      varchar(15),
            TipoTarea           char(1),
            NivelTarea          char(1),
            CodigoTarea         bigint,
            SecFunc             int,
            SecFuncProp         int,
            Origen              varchar(1),
            FuenteFinanc        varchar(2),
            Clasificador        varchar(20),
            TipoRecurso         varchar(2),
            TipoPpto            smallint,
            TipoUso             varchar(1),
            TipoBien            char(1),
            GrupoBien           varchar(2),
            ClaseBien           varchar(2),
            FamiliaBien         varchar(4),
            ItemBien            varchar(4),
            DescripcionServicio varchar(350),
            PrecioUnitario      decimal(16,6),
            RefSecCuadro        bigint,
            RefSecItem          bigint,
            Periodos            nvarchar(max) AS JSON
        ) AS j;

        IF NOT EXISTS (SELECT 1 FROM #Item)
            THROW 51110, 'VALIDACION_ITEMS: la solicitud debe tener al menos un item.', 1;

        /* ---- Validaciones por item ------------------------------------ */
        DECLARE @Orden int, @errItem nvarchar(400);

        SELECT TOP 1 @Orden = Orden FROM #Item
         WHERE TipoMovimiento NOT IN ('INCLUSION','EXCLUSION') OR TipoMovimiento IS NULL;
        IF @Orden IS NOT NULL
        BEGIN
            /* MODIFICACION se distingue del resto porque no es un valor erroneo
               sino uno retirado: el mensaje tiene que decir que hacer en su
               lugar, no solo que no vale. Ver la nota de la cabecera. */
            IF (SELECT TipoMovimiento FROM #Item WHERE Orden = @Orden) = 'MODIFICACION'
            BEGIN
                SET @errItem = CONCAT('VALIDACION_ITEMS: el item ', @Orden,
                    ' es una MODIFICACION, y el Anexo 3 solo registra inclusiones y exclusiones. ',
                    'Para cambiar la cantidad de un item programado, excluya la linea vigente e incluyala con la cantidad nueva.');
                THROW 51125, @errItem, 1;
            END

            SET @errItem = CONCAT('VALIDACION_ITEMS: el item ', @Orden,
                ' tiene un TipoMovimiento invalido. Valores: INCLUSION, EXCLUSION.');
            THROW 51111, @errItem, 1;
        END

        SET @Orden = NULL;
        SELECT TOP 1 @Orden = Orden FROM #Item WHERE PrecioUnitario IS NULL OR PrecioUnitario <= 0;
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = CONCAT('VALIDACION_PRECIO: el item ', @Orden, ' necesita un precio unitario mayor que cero.');
            THROW 51112, @errItem, 1;
        END

        /* Excluir o modificar exige senialar cual item del cuadro vigente se
           toca. Sin la referencia, SIGA no sabria sobre que fila operar. */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = Orden FROM #Item
         WHERE TipoMovimiento <> 'INCLUSION' AND (RefSecCuadro IS NULL OR RefSecItem IS NULL);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = CONCAT('VALIDACION_REFERENCIA: el item ', @Orden,
                ' es una ', (SELECT TipoMovimiento FROM #Item WHERE Orden = @Orden),
                ' y debe indicar RefSecCuadro y RefSecItem del cuadro vigente.');
            THROW 51113, @errItem, 1;
        END

        /* La referencia debe existir, seguir activa y no estar alcanzada por
           otra solicitud. La vista contiene tambien exclusiones historicas;
           esas filas no son elegibles aunque la clave aun exista. */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = i.Orden
          FROM #Item AS i
         WHERE i.TipoMovimiento <> 'INCLUSION'
           AND NOT EXISTS (SELECT 1 FROM siga.vwCuadroVigenteItem AS c
                            WHERE c.AnoEje = @AnoEje AND c.SecEjec = @SecEjec
                              AND c.CentroCosto = @CentroCosto
                              AND c.SecCuadro = i.RefSecCuadro AND c.SecItem = i.RefSecItem
                              AND c.FlagModificado = 0 AND c.FlagSolicitud = 0
                              AND c.MotivoSolicitud = '0' AND c.EstadoSiga IN ('C','I')
                              AND c.CantAno0 + c.CantAno1 + c.CantAno2 + c.CantAno3 > 0);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = CONCAT('MAESTRO_CUADRO: el item ', @Orden,
                ' referencia un item que no existe en el cuadro vigente de SIGA para ese centro de costo.');
            THROW 51114, @errItem, 1;
        END

        /* En exclusion/modificacion la referencia de SIGA es la autoridad. El
           navegador no puede cambiar item, clasificacion o precio de la fila
           elegida y hacer que la cola opere sobre una combinacion inventada. */
        UPDATE i
           SET i.TipoTarea     = c.TipoTarea,
               i.NivelTarea   = c.NivelTarea,
               i.CodigoTarea  = c.CodigoTarea,
               i.SecFunc      = c.SecFunc,
               i.Origen       = c.Origen,
               i.FuenteFinanc = c.FuenteFinanc,
               i.Clasificador = c.Clasificador,
               i.TipoUso      = c.TipoUso,
               i.TipoBien     = c.TipoBien,
               i.GrupoBien    = c.GrupoBien,
               i.ClaseBien    = c.ClaseBien,
               i.FamiliaBien  = c.FamiliaBien,
               i.ItemBien     = c.ItemBien,
               i.PrecioUnitario = c.PrecioUnit
          FROM #Item AS i
          JOIN siga.vwCuadroVigenteItem AS c
            ON c.AnoEje = @AnoEje AND c.SecEjec = @SecEjec
           AND c.CentroCosto = @CentroCosto
           AND c.SecCuadro = i.RefSecCuadro AND c.SecItem = i.RefSecItem
         WHERE i.TipoMovimiento <> 'INCLUSION';

        /* Catalogo. La unidad de medida se toma de SIGA, no de lo que mande el
           cliente: es dato del catalogo y no del formulario. */
        UPDATE #Item SET UnidadMedida = NULL;

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
            SET @errItem = CONCAT('MAESTRO_CATALOGO: el item ', @Orden, ' (',
                (SELECT CONCAT_WS('.', TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien)
                   FROM #Item WHERE Orden = @Orden),
                ') no existe o no esta activo en el catalogo de SIGA.');
            THROW 51115, @errItem, 1;
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
            SET @errItem = CONCAT('MAESTRO_META: el item ', @Orden, ' referencia la meta ',
                (SELECT SecFunc FROM #Item WHERE Orden = @Orden), ', que no existe o no esta activa en SIGA.');
            THROW 51116, @errItem, 1;
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
            SET @errItem = CONCAT('MAESTRO_FUENTE: el item ', @Orden,
                ' referencia una fuente de financiamiento que no existe en SIGA.');
            THROW 51117, @errItem, 1;
        END

        /* La meta y la fuente tienen que estar ASIGNADAS A ESTA AREA USUARIA.

           Que existan en la entidad no basta: SIG_METAS_X_CENTRO es la tabla con
           la que SIGA delimita con que metas y con que fuentes puede programar
           cada centro de costo, y es la misma que ahora filtra los combos del
           formulario. Sin esta comprobacion, un cliente que no use la pantalla
           -o una pantalla con la lista en cache- podria registrar contra la meta
           de otra area, que es justamente lo que el negocio pidio impedir.

           Solo sobre INCLUSION: en exclusion la clasificacion no la elige el
           usuario, se copia de la linea vigente del cuadro, y una linea historica
           programada bajo una asignacion anterior seguiria siendo excluible. */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = i.Orden
          FROM #Item AS i
         WHERE i.TipoMovimiento = 'INCLUSION'
           AND NOT EXISTS (SELECT 1 FROM siga.vwMetaXCentro AS mc
                            WHERE mc.AnoEje = @AnoEje AND mc.SecEjec = @SecEjec
                              AND mc.CentroCosto = @CentroCosto
                              AND mc.SecFunc = i.SecFunc
                              AND mc.Origen = i.Origen
                              AND mc.FuenteFinanc = i.FuenteFinanc);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = CONCAT('MAESTRO_META_CENTRO: el item ', @Orden, ' usa la meta ',
                (SELECT SecFunc FROM #Item WHERE Orden = @Orden), ' con la fuente ',
                (SELECT CONCAT(Origen, '-', FuenteFinanc) FROM #Item WHERE Orden = @Orden),
                ', y esa combinacion no esta asignada al centro de costo ', @CentroCosto, ' en SIGA.');
            THROW 51126, @errItem, 1;
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
            SET @errItem = CONCAT('MAESTRO_TAREA: el item ', @Orden,
                ' referencia una tarea que no existe o no esta activa para el centro de costo ', @CentroCosto, '.');
            THROW 51118, @errItem, 1;
        END

        /* Una inclusion solo se guarda si la combinacion presupuestal existe
           en el techo real de SIGA. Esto evita descubrir el error recien cuando
           el worker intenta escribir. */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = i.Orden
          FROM #Item AS i
         WHERE i.TipoMovimiento = 'INCLUSION'
           AND NOT EXISTS (SELECT 1
                             FROM siga.vwTechoPresupuesto AS t
                            WHERE t.AnoEje = @AnoEje AND t.SecEjec = @SecEjec
                              AND t.CentroCosto = @CentroCosto AND t.FaseCuadro = 5
                              AND t.SecFunc = i.SecFunc
                              AND t.Origen = i.Origen AND t.FuenteFinanc = i.FuenteFinanc
                              AND t.Clasificador = i.Clasificador);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = CONCAT('MAESTRO_TECHO: el item ', @Orden,
                ' no tiene una combinacion valida de tarea, meta, fuente y clasificador en SIGA.');
            THROW 51121, @errItem, 1;
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
        SELECT i.Orden, p.AnoOffset, p.Mes, SUM(ISNULL(p.Cantidad, 0))
          FROM #Item AS i
         CROSS APPLY OPENJSON(ISNULL(i.Periodos, N'[]'))
         WITH (
            AnoOffset smallint,
            Mes       smallint,
            Cantidad  decimal(18,2)
         ) AS p
         WHERE p.AnoOffset BETWEEN 0 AND 3
           AND p.Mes BETWEEN 1 AND 12
         GROUP BY i.Orden, p.AnoOffset, p.Mes;

        /* Un item sin ninguna cantidad no es una solicitud, es una linea vacia. */
        SET @Orden = NULL;
        SELECT TOP 1 @Orden = i.Orden
          FROM #Item AS i
         WHERE NOT EXISTS (SELECT 1 FROM #Periodo AS p WHERE p.Orden = i.Orden AND p.Cantidad > 0);
        IF @Orden IS NOT NULL
        BEGIN
            SET @errItem = CONCAT('VALIDACION_PERIODOS: el item ', @Orden,
                ' no tiene ninguna cantidad mayor que cero en los 48 periodos.');
            THROW 51119, @errItem, 1;
        END

        /* ---- Escritura ------------------------------------------------ */
        DECLARE @CodigoEstadoInicial varchar(60);
        SELECT @CodigoEstadoInicial = CodigoEstado
          FROM sigcm.Estado
         WHERE CodigoModulo = 'CMN' AND EsInicial = 1 AND Activo = 1;

        IF @CodigoEstadoInicial IS NULL
            THROW 51120, 'CONFLICTO_CONFIGURACION: el modulo CMN no tiene estado inicial. Falta ejecutar S001.', 1;

        DECLARE @EsCorreccion bit = CASE WHEN @IdSolicitud IS NULL THEN 0 ELSE 1 END;
        DECLARE @Codigo varchar(40);
        DECLARE @CodigoEstado varchar(60);
        DECLARE @Ahora datetime = GETDATE();
        DECLARE @IdExpediente uniqueidentifier;

        /* El correlativo SOLO se consume al crear. Una correccion conserva el
           numero con que el expediente ya circula: es el que un auditor pide y
           el que figura impreso en el Anexo 3 que ya se genero. */
        IF @EsCorreccion = 0
        BEGIN
            DECLARE @AreaNumerica varchar(20) =
                REPLACE(REPLACE(LTRIM(RTRIM(@CentroCosto)), '.', ''), ' ', '');
            DECLARE @IdUsuarioNumerico int;
            SELECT @IdUsuarioNumerico = IdUsuarioSso
              FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;
            IF @IdUsuarioNumerico IS NULL OR @IdUsuarioNumerico <= 0
                SET @IdUsuarioNumerico = (ABS(CHECKSUM(CONVERT(varchar(36), @IdUsuario))) % 900) + 100;

            EXEC sigcm.paSiguienteCodigo
                 'CMN', @AnoEje, N'cmn.SeqSolicitud', @Codigo OUTPUT,
                 @AreaNumerica, @IdUsuarioNumerico;
        END
        ELSE
        BEGIN
            SET @Codigo       = @CodigoEdit;
            SET @IdExpediente = @IdExpedienteEdit;
            SET @CodigoEstado = @CodigoEstadoEdit;
        END

        BEGIN TRANSACTION; SET @TranPropia = 1;

        IF @EsCorreccion = 0
        BEGIN
            SET @CodigoEstado = @CodigoEstadoInicial;

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
                 TipoInclusion, JustificacionUrgencia,
                 Sustento, IdResponsable, DatosAdicionales,
                 UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                 EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdExpediente, @Codigo, @AnoEje, @SecEjec, @CentroCosto, @TipoOperacion,
                 @TipoInclusion, @JustificacionUrgencia,
                 @Sustento, @IdUsuario, @DatosAdicionales,
                 @Cuenta, @Ahora, @Equipo, @Programa);

            SELECT @IdSolicitud = IdSolicitud FROM cmn.Solicitud WHERE IdExpediente = @IdExpediente;
        END
        ELSE
        BEGIN
            /* La correccion NO mueve el expediente: el estado, la unidad y el
               responsable actual son de la maquina de transiciones, y esto es
               contenido. Tampoco toca IdResponsable, que es quien figura como
               solicitante en el Anexo 3: que el jefe corrija una linea no lo
               convierte en el area que pidio. */
            UPDATE cmn.Solicitud
               SET Sustento                      = @Sustento,
                   TipoInclusion                 = @TipoInclusion,
                   JustificacionUrgencia         = @JustificacionUrgencia,
                   DatosAdicionales              = @DatosAdicionales,
                   UsuarioModificacionAuditoria  = @Cuenta,
                   FechaModificacionAuditoria    = @Ahora,
                   EquipoModificacionAuditoria   = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdSolicitud = @IdSolicitud;

            /* Los items se reescriben en bloque en vez de reconciliarse linea
               por linea. Nada cuelga de un IdSolicitudItem fuera de sus periodos
               —el mapeo hacia SIGA nace al encolar, y eso ocurre despues de la
               firma, cuando ya no se puede corregir—, asi que comparar item por
               item seria complejidad sin ganancia. Los 48 periodos se van por la
               cascada de su item. */
            DELETE FROM cmn.SolicitudItem WHERE IdSolicitud = @IdSolicitud;

            UPDATE sigcm.Expediente
               SET UsuarioModificacionAuditoria  = @Cuenta,
                   FechaModificacionAuditoria    = @Ahora,
                   EquipoModificacionAuditoria   = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdExpediente = @IdExpediente;
        END

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
            (@IdExpediente,
             /* Sin origen al crear; en una correccion origen y destino son el
                mismo estado, porque el expediente no se movio. */
             CASE WHEN @EsCorreccion = 1 THEN @CodigoEstado END,
             @CodigoEstado, NULL,
             CASE WHEN @EsCorreccion = 1
                  THEN 'Correccion del contenido del Anexo 3'
                  ELSE 'Registro inicial del Anexo 3' END,
             @IdUsuario, @CodigoRol, @IdUnidad,
             (SELECT @Codigo AS Codigo, @CentroCosto AS CentroCosto FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
             @Cuenta, @Equipo, @Programa);

        COMMIT TRANSACTION; SET @TranPropia = 0;

        DECLARE @Items int = (SELECT COUNT(*) FROM #Item);
        DECLARE @VersionExp int =
            (SELECT Version FROM sigcm.Expediente WHERE IdExpediente = @IdExpediente);
        /* En variable y no inline: un EXEC solo admite constantes o variables
           como argumento, no una expresion CASE. */
        DECLARE @AccionAud varchar(80) =
            CASE WHEN @EsCorreccion = 1 THEN 'ACTUALIZAR' ELSE 'REGISTRAR' END;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = 'CMN',
             @Entidad = 'cmn.Solicitud', @IdEntidad = @IdSolicitud,
             @Accion = @AccionAud,
             @Resultado = 'OK', @IdActor = @IdUsuario, @ActorCuenta = @Cuenta,
             @ActorRol = @CodigoRol, @IdActorUnidad = @IdUnidad,
             @OrigenIp = @Ip, @Equipo = @Equipo, @Programa = @Programa,
             @DatosDespues = NULL, @Metadata = NULL;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdSolicitud  AS IdSolicitud,
                   @IdExpediente AS IdExpediente,
                   @Codigo       AS Codigo,
                   @CodigoEstado AS CodigoEstado,
                   @VersionExp   AS Version,
                   @Items AS Items,
                   (@Items * 48) AS Periodos,
                   CASE WHEN @EsCorreccion = 1
                        THEN N'Se actualizo la solicitud satisfactoriamente.'
                        ELSE N'Se realizo el registro satisfactoriamente.' END AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        /* Solo se deshace la transaccion que ESTA rutina abrio.

           Antes decia "IF @@TRANCOUNT > 0 ROLLBACK", y eso deshacia tambien la
           transaccion de quien llama. Casi todos los errores de aqui son de
           validacion y ocurren ANTES de abrir nada: con la version anterior, un
           "falta IdExpediente" bastaba para tirar abajo el trabajo del llamador,
           que ni siquiera sabria por que. Ademas, bajo INSERT ... EXEC el motor
           prohibe el ROLLBACK y el error real quedaba tapado por un 3915. */
        IF @TranPropia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado,
                   ERROR_MESSAGE() AS mensaje,
                   ERROR_NUMBER()  AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

/* ========================================================================== */
/* 2. cmn.paObtenerSolicitud                                                 */
/* ========================================================================== */

/* Devuelve la solicitud completa: cabecera, items y los 48 periodos anidados por
   item. Es lo que consume el visor del Anexo 3.

   Entrada: { "Actor": {...}, "IdSolicitud": "..." } */
CREATE OR ALTER PROCEDURE cmn.paObtenerSolicitud
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51130, 'JSON incorrecto.', 1;

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

        DECLARE @IdSolicitud uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdSolicitud'));

        IF @IdSolicitud IS NULL
            THROW 51131, 'VALIDACION_PAYLOAD: falta IdSolicitud o no es un identificador valido.', 1;

        IF NOT EXISTS (SELECT 1 FROM cmn.Solicitud WHERE IdSolicitud = @IdSolicitud AND Activo = 1)
            THROW 51132, 'NO_ENCONTRADO: la solicitud no existe.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   s.IdSolicitud, s.Codigo, s.AnoEje, s.SecEjec, s.CentroCosto,
                   s.TipoOperacion, s.TipoInclusion, s.JustificacionUrgencia,
                   s.Sustento, s.FechaSolicitud,
                   e.IdExpediente, e.CodigoEstado, e.Version, e.Anulado,
                   Estado = w.Nombre,
                   PuedeEditar = cmn.fnPuedeEditar(
                       e.CodigoEstado, @CodigoRol,
                       CASE WHEN e.IdUnidadActual = @IdUnidad THEN 1 ELSE 0 END),
                   Responsable = CONCAT_WS(' ', u.Nombres, u.Apellidos),
                   JefeAreaUsuaria = cmn.fnNombreJefeArea(e.IdUnidadOrigen),
                   CentroCostoNombre = cc.NombreDepend,
                   /* El PDF que vive en el file server, para firmarlo y para
                      volver a verlo. Sin esto la pantalla solo conoce el archivo
                      dentro de la sesion en que lo genero: al recargar, el boton
                      de ver el Anexo se quedaba sin nada que abrir. */
                   DocumentoSistemaAnexo3 = a3.GeneradoDocumento,
                   DocumentoSistemaAnexo4 = a4.GeneradoDocumento,
                   /* El informe o nota tecnica con que el area usuaria sustenta
                      la urgencia. Abastecimiento tiene que poder abrirlo desde
                      el mismo sitio donde evalua la solicitud. */
                   DocumentoSustentoUrgencia = su.GeneradoDocumento,
                   NombreSustentoUrgencia    = su.NombreDocumento,
                   Items = JSON_QUERY(COALESCE((
                       SELECT r.IdSolicitudItem, r.Orden, r.TipoMovimiento, r.CodigoItem,
                              r.Descripcion, r.UnidadMedida, r.UnidadAbreviatura,
                              r.PrecioUnitario, r.SecFunc, r.Clasificador,
                              r.RefSecCuadro, r.RefSecItem,
                              r.CantidadAno0, r.CantidadAno1, r.CantidadAno2, r.CantidadAno3,
                              r.MontoAno0, r.MontoAno1, r.MontoAno2, r.MontoAno3,
                              r.CantidadTotal, r.MontoTotal,
                              Periodos = JSON_QUERY(COALESCE((
                                  SELECT p.AnoOffset, p.Mes, p.Cantidad, p.Monto
                                    FROM cmn.SolicitudItemPeriodo AS p
                                   WHERE p.IdSolicitudItem = r.IdSolicitudItem
                                   ORDER BY p.AnoOffset, p.Mes
                                     FOR JSON PATH), '[]'))
                         FROM cmn.vwItemResumen AS r
                        WHERE r.IdSolicitud = s.IdSolicitud
                        ORDER BY r.Orden
                          FOR JSON PATH), '[]')),
                   'OK' AS mensaje
              FROM cmn.Solicitud AS s
              JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
              JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
              JOIN sigcm.Usuario    AS u ON u.IdUsuario    = s.IdResponsable
              LEFT JOIN siga.vwCentroCosto AS cc
                     ON cc.AnoEje = s.AnoEje AND cc.SecEjec = s.SecEjec
                    AND cc.CentroCosto = s.CentroCosto
              OUTER APPLY cmn.fnDocumentoVigente(e.IdExpediente, N'CMN_ANEXO_3_SOLICITUD_MODIFICACION') AS a3
              OUTER APPLY cmn.fnDocumentoVigente(e.IdExpediente, N'CMN_ANEXO_4_APROBACION_MODIFICACION') AS a4
              OUTER APPLY cmn.fnDocumentoVigente(e.IdExpediente, N'CMN_SUSTENTO_URGENCIA') AS su
             WHERE s.IdSolicitud = @IdSolicitud
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        /* Solo se deshace la transaccion que ESTA rutina abrio.

           Antes decia "IF @@TRANCOUNT > 0 ROLLBACK", y eso deshacia tambien la
           transaccion de quien llama. Casi todos los errores de aqui son de
           validacion y ocurren ANTES de abrir nada: con la version anterior, un
           "falta IdExpediente" bastaba para tirar abajo el trabajo del llamador,
           que ni siquiera sabria por que. Ademas, bajo INSERT ... EXEC el motor
           prohibe el ROLLBACK y el error real quedaba tapado por un 3915. */
        IF @TranPropia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

/* ========================================================================== */
/* 3. cmn.paListarSolicitud                                                  */
/* ========================================================================== */

/*
  Bandeja del modulo.   El filtro por defecto es "mi bandeja": lo que esta en la
  unidad del actor Y cuyo estado tiene como responsable el rol del actor. Asi el
  especialista no ve lo que le toca firmar al jefe, ni al reves.

  Cada fila trae Transiciones: las mismas que sigcm.paListarTransicionDisponible
  para ese expediente y este actor. La bandeja pinta los botones de accion con
  ese arreglo y no vuelve a consultar el motor por cada fila.

  Entrada:
  { "Actor": {...},
    "Filtro": { "SoloMiBandeja": true, "CodigoEstado": "...", "AnoEje": 2026,
                "CentroCosto": "...", "Texto": "...", "Limite": 50, "Desplazamiento": 0 } }
*/
CREATE OR ALTER PROCEDURE cmn.paListarSolicitud
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51140, 'JSON incorrecto.', 1;

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
                @CentroCosto varchar(15), @Texto varchar(200),
                @Limite int, @Desplazamiento int;

        SELECT @SoloMiBandeja  = ISNULL(SoloMiBandeja, 1),
               @CodigoEstado   = CodigoEstado,
               @AnoEje         = AnoEje,
               @CentroCosto    = CentroCosto,
               @Texto          = Texto,
               @Limite         = Limite,
               @Desplazamiento = Desplazamiento
        FROM OPENJSON(@parametro, '$.Filtro')
        WITH (
            SoloMiBandeja  bit,
            CodigoEstado   varchar(60),
            AnoEje         smallint,
            CentroCosto    varchar(15),
            Texto          varchar(200),
            Limite         int,
            Desplazamiento int
        );

        SET @SoloMiBandeja  = ISNULL(@SoloMiBandeja, 1);
        SET @Limite         = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50
                                   WHEN @Limite > 200 THEN 200 ELSE @Limite END;
        SET @Desplazamiento = CASE WHEN @Desplazamiento IS NULL OR @Desplazamiento < 0
                                   THEN 0 ELSE @Desplazamiento END;

        DECLARE @Total int;

        SELECT @Total = COUNT(*)
          FROM cmn.Solicitud AS s
          JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
          JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE e.Anulado = 0 AND e.Activo = 1 AND s.Activo = 1
           AND (@SoloMiBandeja = 0
                OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol))
           AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
           AND (@AnoEje       IS NULL OR s.AnoEje       = @AnoEje)
           AND (@CentroCosto  IS NULL OR s.CentroCosto  = @CentroCosto)
           AND (@Texto        IS NULL OR s.Codigo LIKE '%' + @Texto + '%'
                                      OR s.Sustento LIKE '%' + @Texto + '%');

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @Total          AS total,
                   @Limite         AS limite,
                   @Desplazamiento AS desplazamiento,
                   Solicitudes = JSON_QUERY(COALESCE((
                       SELECT s.IdSolicitud, s.Codigo, s.AnoEje, s.CentroCosto,
                              s.TipoOperacion, s.TipoInclusion, s.FechaSolicitud,
                              e.IdExpediente, e.CodigoEstado, e.Version,
                              Estado = w.Nombre,
                              RolResponsable = w.RolResponsable,
                              /* Si este actor puede corregir el contenido. La
                                 pantalla no lo deduce del estado: lo pregunta,
                                 igual que hace con las acciones del flujo. */
                              PuedeEditar = cmn.fnPuedeEditar(
                                  e.CodigoEstado, @CodigoRol,
                                  CASE WHEN e.IdUnidadActual = @IdUnidad THEN 1 ELSE 0 END),
                              Items = (SELECT COUNT(*) FROM cmn.SolicitudItem AS it
                                        WHERE it.IdSolicitud = s.IdSolicitud AND it.Activo = 1),
                              MontoTotal = (SELECT ISNULL(SUM(p.Monto), 0)
                                              FROM cmn.SolicitudItem AS it
                                              JOIN cmn.SolicitudItemPeriodo AS p
                                                ON p.IdSolicitudItem = it.IdSolicitudItem
                                             WHERE it.IdSolicitud = s.IdSolicitud),
                              /* Area usuaria de origen: en la bandeja de
                                 Abastecimiento conviven expedientes de varias, y
                                 sin esto la fila no dice de quien es. */
                              AreaUsuaria = uo.Nombre,
                              SiglaArea   = uo.Sigla,
                              /* El Anexo 4 que agrupa esta solicitud, si ya lo
                                 hay. La pantalla lo usa para agrupar las filas
                                 de un mismo paquete y para no volver a ofrecer
                                 en la seleccion algo ya tomado. */
                              pq.IdPaquete,
                              CodigoAnexo4 = pq.Codigo,
                              /* El PDF ya subido al file server, por Anexo. La
                                 fila necesita conocerlo para ofrecer «ver el
                                 Anexo» sin depender de que esta misma sesion lo
                                 haya generado. */
                              DocumentoSistemaAnexo3 = a3.GeneradoDocumento,
                              DocumentoSistemaAnexo4 = a4.GeneradoDocumento,
                              /* El sustento de la urgencia viaja en la bandeja
                                 porque es ahi donde Abastecimiento decide, y
                                 abrirlo no debe costar una consulta por fila. */
                              DocumentoSustentoUrgencia = su.GeneradoDocumento,
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
                                     AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS r
                                                  WHERE r.CodigoTransicion = t.CodigoTransicion
                                                    AND r.CodigoRol = @CodigoRol)
                                   ORDER BY t.CodigoTransicion
                                     FOR JSON PATH), N'[]')),
                              ActualizadoEn = ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria)
                         FROM cmn.Solicitud AS s
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
                         JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
                         JOIN sigcm.Unidad     AS uo ON uo.IdUnidad = e.IdUnidadOrigen
                         OUTER APPLY (SELECT TOP 1 pk.IdPaquete, pk.Codigo
                                        FROM cmn.PaqueteSolicitud AS ps
                                        JOIN cmn.Paquete AS pk ON pk.IdPaquete = ps.IdPaquete
                                       WHERE ps.IdSolicitud = s.IdSolicitud
                                         AND ps.Activo = 1 AND pk.Anulado = 0) AS pq
                         OUTER APPLY cmn.fnDocumentoVigente(e.IdExpediente, N'CMN_ANEXO_3_SOLICITUD_MODIFICACION') AS a3
                         OUTER APPLY cmn.fnDocumentoVigente(e.IdExpediente, N'CMN_ANEXO_4_APROBACION_MODIFICACION') AS a4
                         OUTER APPLY cmn.fnDocumentoVigente(e.IdExpediente, N'CMN_SUSTENTO_URGENCIA') AS su
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
                        WHERE e.Anulado = 0 AND e.Activo = 1 AND s.Activo = 1
                          AND (@SoloMiBandeja = 0
                               OR (e.IdUnidadActual = @IdUnidad AND w.RolResponsable = @CodigoRol))
                          AND (@CodigoEstado IS NULL OR e.CodigoEstado = @CodigoEstado)
                          AND (@AnoEje       IS NULL OR s.AnoEje       = @AnoEje)
                          AND (@CentroCosto  IS NULL OR s.CentroCosto  = @CentroCosto)
                          AND (@Texto        IS NULL OR s.Codigo LIKE '%' + @Texto + '%'
                                                     OR s.Sustento LIKE '%' + @Texto + '%')
                        ORDER BY ISNULL(e.FechaModificacionAuditoria, e.FechaCreacionAuditoria) DESC
                        OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY
                          FOR JSON PATH), '[]')),
                   'OK' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        /* Solo se deshace la transaccion que ESTA rutina abrio.

           Antes decia "IF @@TRANCOUNT > 0 ROLLBACK", y eso deshacia tambien la
           transaccion de quien llama. Casi todos los errores de aqui son de
           validacion y ocurren ANTES de abrir nada: con la version anterior, un
           "falta IdExpediente" bastaba para tirar abajo el trabajo del llamador,
           que ni siquiera sabria por que. Ademas, bajo INSERT ... EXEC el motor
           prohibe el ROLLBACK y el error real quedaba tapado por un 3915. */
        IF @TranPropia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo,
                   JSON_QUERY('[]') AS Solicitudes
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

PRINT 'F002 aplicada: modulo CMN.';
GO
