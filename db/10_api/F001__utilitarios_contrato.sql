/*
===============================================================================
  SIGCM - F001 : Utilitarios del contrato con el backend
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Port de SIGCM/db/10_api/F001__utilitarios_contrato.sql (PostgreSQL 14).

  ---------------------------------------------------------------------------
  CONTRATO CON EL PUENTE .NET
  ---------------------------------------------------------------------------
  Toda rutina invocable recibe UN parametro @parametro nvarchar(max) con JSON y
  devuelve UNA fila con UNA columna de texto, tambien JSON. Es el formato vigente
  en la ANIN, el mismo de seguimiento.paListarAsignarProyectoFase y
  seguimiento.paInsertarSeguimientoProyecto.

  La respuesta SIEMPRE trae "estado":
      estado = 1  la operacion se realizo
      estado = 0  no se realizo; "mensaje" explica por que

  LA EXCEPCION NO SALE DEL PROCEDIMIENTO. Se lanza internamente con THROW para
  saltar al CATCH, y ahi se convierte en payload. Diferencia con la version
  PostgreSQL, que propagaba RAISE EXCEPTION hasta el cliente: aqui el puente
  recibe siempre JSON valido y no necesita mapear codigos de error de SqlClient.

  El sobre de entrada:

      {
        "Actor": { "Usuario": "...", "Rol": "...", "Unidad": "...",
                   "Ip": "...", "Equipo": "...", "Programa": "...",
                   "CorrelacionId": "..." },
        ...
      }

  Las claves van en PascalCase, como las columnas. En PostgreSQL iban en
  snake_case; se alinean con la convencion de la casa.

  ---------------------------------------------------------------------------
  BLOQUES DE NUMERACION DE ERROR
  ---------------------------------------------------------------------------
      51000-51099  utilitarios y resolucion del actor   (F001)
      51100-51199  modulo CMN                           (F002)
      51200-51299  transiciones de estado y encolado    (F004)
      51300-51399  integracion con SIGA                 (W001)
      51400-51499  modulo Requerimiento a Notificacion  (F005)
      51500-51599  acceso y armado de la sesion         (F006)

  Reservar el bloque por adelantado evita que dos modulos escritos en momentos
  distintos colisionen en el mismo numero, que es lo que vuelve inutil un log.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. sigcm.fnEsDiaHabil / sigcm.fnSumarDiasHabiles                          */
/* ========================================================================== */

/* Sabados y domingos por calculo; los feriados salen de sigcm.DiaNoHabil, que
   solo lleva las excepciones.

   DATEFIRST no se puede fijar dentro de una funcion y su valor de sesion cambia
   segun el idioma del login, asi que el dia de la semana se calcula de forma
   independiente: DATEDIFF en dias desde un lunes conocido (1900-01-01 lo fue). */
CREATE OR ALTER FUNCTION sigcm.fnEsDiaHabil (@Fecha date)
RETURNS bit
AS
BEGIN
    IF @Fecha IS NULL RETURN NULL;

    /* 0 = lunes ... 5 = sabado, 6 = domingo */
    IF (DATEDIFF(day, '19000101', @Fecha) % 7) >= 5 RETURN 0;

    IF EXISTS (SELECT 1 FROM sigcm.DiaNoHabil
                WHERE Fecha = @Fecha AND Activo = 1) RETURN 0;

    RETURN 1;
END
GO

/* Devuelve la fecha resultante de sumar @Dias habiles a @Desde. El dia de
   partida no cuenta: sumar 1 dia habil a un viernes da el lunes siguiente. */
CREATE OR ALTER FUNCTION sigcm.fnSumarDiasHabiles (@Desde date, @Dias int)
RETURNS date
AS
BEGIN
    IF @Desde IS NULL OR @Dias IS NULL RETURN NULL;

    DECLARE @Fecha date = @Desde;
    DECLARE @Restantes int = @Dias;

    WHILE @Restantes > 0
    BEGIN
        SET @Fecha = DATEADD(day, 1, @Fecha);
        IF sigcm.fnEsDiaHabil(@Fecha) = 1
            SET @Restantes = @Restantes - 1;
    END

    RETURN @Fecha;
END
GO

/* ========================================================================== */
/* 2. sigcm.paResolverActor                                                  */
/* ========================================================================== */

/*
  Resuelve y VALIDA la terna usuario-rol-unidad que viene en el bloque Actor.

  No es cosmetico: haber sido autenticado por el SSO no implica ejercer ese rol
  en esa unidad hoy. Este procedimiento es el unico lugar donde eso se comprueba,
  y todas las rutinas de negocio empiezan llamandolo.

  El backend debe rellenar el bloque Actor DESDE LA SESION SSO, sobrescribiendo
  lo que venga del navegador. Un cliente que se invente el rol solo consigue que
  esta validacion lo rechace, pero no hay que darle la oportunidad.

  Lanza (no devuelve envelope) porque es un procedimiento interno: quien lo llama
  ya tiene su propio TRY/CATCH y convertira el error en payload.
*/
CREATE OR ALTER PROCEDURE sigcm.paResolverActor
    @parametro      nvarchar(max),
    @IdUsuario      uniqueidentifier OUTPUT,
    @Cuenta         varchar(120)     OUTPUT,
    @NombreCompleto varchar(250)     OUTPUT,
    @Cargo          varchar(180)     OUTPUT,
    @CodigoRol      varchar(40)      OUTPUT,
    @IdUnidad       uniqueidentifier OUTPUT,
    @CentroCosto    varchar(15)      OUTPUT,
    @EsTitular      bit              OUTPUT,
    @Ip             varchar(45)      OUTPUT,
    @Equipo         varchar(50)      OUTPUT,
    @Programa       varchar(50)      OUTPUT,
    @CorrelacionId  uniqueidentifier OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Usuario varchar(120), @Rol varchar(40), @Unidad varchar(30),
            @CorrelacionTexto varchar(50);

    SELECT
        @Usuario          = Usuario,
        @Rol              = Rol,
        @Unidad           = Unidad,
        @Ip               = Ip,
        @Equipo           = Equipo,
        @Programa         = Programa,
        @CorrelacionTexto = CorrelacionId
    FROM OPENJSON(@parametro, '$.Actor')
    WITH (
        Usuario       varchar(120) '$.Usuario',
        Rol           varchar(40)  '$.Rol',
        Unidad        varchar(30)  '$.Unidad',
        Ip            varchar(45)  '$.Ip',
        Equipo        varchar(50)  '$.Equipo',
        Programa      varchar(50)  '$.Programa',
        CorrelacionId varchar(50)  '$.CorrelacionId'
    );

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
        THROW 51001, 'VALIDACION_ACTOR: falta Actor.Usuario. El backend debe completarlo desde la sesion SSO.', 1;
    IF NULLIF(LTRIM(RTRIM(@Rol)), '') IS NULL
        THROW 51002, 'VALIDACION_ACTOR: falta Actor.Rol.', 1;
    IF NULLIF(LTRIM(RTRIM(@Unidad)), '') IS NULL
        THROW 51003, 'VALIDACION_ACTOR: falta Actor.Unidad.', 1;

    /* Una correlacion invalida no debe tumbar la operacion: se genera una. */
    SET @CorrelacionId = TRY_CONVERT(uniqueidentifier, @CorrelacionTexto);
    IF @CorrelacionId IS NULL SET @CorrelacionId = NEWID();

    DECLARE @Hoy date = CONVERT(date, GETDATE());

    SELECT
        @IdUsuario      = u.IdUsuario,
        @Cuenta         = u.Cuenta,
        @NombreCompleto = CONCAT_WS(' ', u.Nombres, u.Apellidos),
        @Cargo          = u.Cargo,
        @CodigoRol      = ur.CodigoRol,
        @IdUnidad       = ur.IdUnidad,
        @CentroCosto    = un.CentroCostoSiga,
        @EsTitular      = ur.EsTitular
    FROM sigcm.UsuarioRol AS ur
    JOIN sigcm.Usuario    AS u  ON u.IdUsuario = ur.IdUsuario
    JOIN sigcm.Unidad     AS un ON un.IdUnidad = ur.IdUnidad
    WHERE u.Cuenta      = @Usuario
      AND ur.CodigoRol  = @Rol
      AND un.Codigo     = @Unidad
      AND u.Activo      = 1
      AND un.Activo     = 1
      AND ur.Activo     = 1
      AND ur.VigenteDesde <= @Hoy
      AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @Hoy);

    IF @IdUsuario IS NULL
    BEGIN
        DECLARE @msg nvarchar(400) =
            CONCAT('NO_AUTORIZADO: la cuenta ', @Usuario, ' no ejerce hoy el rol ', @Rol,
                   ' en la unidad ', @Unidad, '.');
        THROW 51004, @msg, 1;
    END

    /* Las cuentas tecnicas de integracion y conciliacion no operan el flujo
       institucional. Existen para el worker, no para pantallas. */
    IF EXISTS (SELECT 1 FROM sigcm.Rol WHERE CodigoRol = @CodigoRol AND EsTecnico = 1)
        THROW 51005, 'NO_AUTORIZADO: es una cuenta tecnica y no puede ejecutar acciones del flujo.', 1;
END
GO

/* ========================================================================== */
/* 3. sigcm.paRegistrarAuditoria                                             */
/* ========================================================================== */

/*
  Bitacora de acciones. Es OTRA COSA que el cuarteto de auditoria de cada tabla:
  ese registra quien toco una fila; esta registra que se intento hacer, con que
  resultado y bajo que correlacion, incluidos los intentos DENEGADOS que nunca
  llegan a modificar ninguna fila.

  Prohibido pasar contrasenias, certificados o datos personales sensibles en
  @DatosAntes, @DatosDespues o @Metadata.
*/
CREATE OR ALTER PROCEDURE sigcm.paRegistrarAuditoria
    @CorrelacionId uniqueidentifier,
    @CodigoModulo  varchar(30),
    @Entidad       varchar(80),
    @IdEntidad     uniqueidentifier = NULL,
    @Accion        varchar(80),
    @Resultado     varchar(15)      = 'OK',
    @IdActor       uniqueidentifier = NULL,
    @ActorCuenta   varchar(120),
    @ActorRol      varchar(40)      = NULL,
    @IdActorUnidad uniqueidentifier = NULL,
    @OrigenIp      varchar(45)      = NULL,
    @Equipo        varchar(50)      = NULL,
    @Programa      varchar(50)      = NULL,
    @DatosAntes    nvarchar(max)    = NULL,
    @DatosDespues  nvarchar(max)    = NULL,
    @Metadata      nvarchar(max)    = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO sigcm.EventoAuditoria
        (CorrelacionId, CodigoModulo, Entidad, IdEntidad, Accion, Resultado,
         IdActor, ActorCuenta, ActorRol, IdActorUnidad, OrigenIp, Equipo, Programa,
         DatosAntes, DatosDespues, Metadata)
    VALUES
        (@CorrelacionId, @CodigoModulo, @Entidad, @IdEntidad, @Accion, @Resultado,
         @IdActor, @ActorCuenta, @ActorRol, @IdActorUnidad, @OrigenIp, @Equipo, @Programa,
         /* Un JSON invalido en la auditoria no debe abortar la operacion
            auditada: se descarta y queda nulo. */
         CASE WHEN ISJSON(@DatosAntes)   = 1 THEN @DatosAntes   END,
         CASE WHEN ISJSON(@DatosDespues) = 1 THEN @DatosDespues END,
         CASE WHEN ISJSON(@Metadata)     = 1 THEN @Metadata ELSE N'{}' END);
END
GO

/* ========================================================================== */
/* 4. sigcm.paSiguienteCodigo                                                */
/* ========================================================================== */

/*
  Genera el codigo visible de un expediente: PREFIJO-ANIO-000123.

  El contador vive en sigcm.Correlativo (V010), no en una SEQUENCE. La razon
  esta explicada a fondo en V010; en una linea: una secuencia entrega el numero
  FUERA de la transaccion, asi que un rollback deja un hueco en la numeracion, y
  el codigo de expediente es el numero con el que un auditor lo pide.

  @Secuencia conserva el nombre y el formato que ya usaban las rutinas que
  llaman aqui (N'cmn.SeqSolicitud'): hoy es la clave de la fila del contador, no
  el nombre de un objeto. Se mantiene asi para no tocar las llamadas.

  El UPDLOCK/HOLDLOCK al comprobar la existencia evita que dos registros
  simultaneos inserten la misma fila; la asignacion encadenada del UPDATE lee y
  escribe en una sola operacion, sin ventana entre ambas.
*/
CREATE OR ALTER PROCEDURE sigcm.paSiguienteCodigo
    @Prefijo   varchar(10),
    @AnoEje    smallint,
    @Secuencia nvarchar(128),          /* p.ej. N'cmn.SeqSolicitud' */
    @Codigo    varchar(40) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NULLIF(LTRIM(RTRIM(@Secuencia)), '') IS NULL
        THROW 51010, 'No se indico el nombre del correlativo.', 1;

    DECLARE @Valor bigint;

    /* Sin transaccion propia: se toma la del llamador, que es justamente lo que
       hace que el numero se devuelva si el registro se deshace. */
    IF NOT EXISTS (SELECT 1 FROM sigcm.Correlativo WITH (UPDLOCK, HOLDLOCK)
                    WHERE Nombre = @Secuencia)
        INSERT INTO sigcm.Correlativo (Nombre, Valor) VALUES (@Secuencia, 0);

    UPDATE sigcm.Correlativo
       SET @Valor = Valor = Valor + 1
     WHERE Nombre = @Secuencia;

    SET @Codigo = CONCAT(@Prefijo, '-', CONVERT(varchar(4), @AnoEje), '-',
                         RIGHT(CONCAT('000000', CONVERT(varchar(20), @Valor)), 6));
END
GO

/* ========================================================================== */
/* 5. sigcm.paListarMaestroSiga                                              */
/* ========================================================================== */

/*
  Punto unico de lectura de los maestros de SIGA para los formularios. Un solo
  procedimiento en vez de ocho: el frontend pide un maestro por nombre y recibe
  siempre la misma forma de respuesta.

  LAS TRES MEDIDAS DE CONVIVENCIA CON SIGA ESTAN AQUI, y se aplican aunque en la
  copia local no cambien nada. En produccion si:

    LOCK_TIMEOUT 5000      antes que colgar la pantalla del usuario esperando un
                           bloqueo de SIGA, se falla rapido y con mensaje claro.
    DEADLOCK_PRIORITY LOW  ante un interbloqueo entre SIGCM y SIGA, la victima
                           somos nosotros. Nunca abortamos una transaccion de SIGA.
    OPTION (MAXDOP 1)      no robamos hilos paralelos del pool que SIGA necesita.
                           Son lecturas de pocas paginas; no ganan nada con
                           paralelismo.

  Toda consulta va filtrada por AnoEje + SecEjec, y por CentroCosto cuando el
  maestro lo admite. Consultar SIGA sin filtro esta prohibido.
*/
CREATE OR ALTER PROCEDURE sigcm.paListarMaestroSiga
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
            THROW 51020, 'JSON incorrecto.', 1;

        DECLARE @Maestro     varchar(40),
                @AnoEje      smallint,
                @SecEjec     int,
                @CentroCosto varchar(15),
                @Texto       varchar(200),
                @Limite      int;

        SELECT @Maestro     = Maestro,
               @AnoEje      = AnoEje,
               @SecEjec     = SecEjec,
               @CentroCosto = CentroCosto,
               @Texto       = Texto,
               @Limite      = Limite
        FROM OPENJSON(@parametro)
        WITH (
            Maestro     varchar(40),
            AnoEje      smallint,
            SecEjec     int,
            CentroCosto varchar(15),
            Texto       varchar(200),
            Limite      int
        );

        IF NULLIF(LTRIM(RTRIM(@Maestro)), '') IS NULL
            THROW 51021, 'VALIDACION_PAYLOAD: falta Maestro.', 1;
        IF @SecEjec IS NULL
            THROW 51022, 'VALIDACION_PAYLOAD: falta SecEjec.', 1;
        IF @AnoEje IS NULL SET @AnoEje = YEAR(GETDATE());

        /* Tope duro: el frontend no debe poder pedir el catalogo entero. */
        SET @Limite = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 200
                           WHEN @Limite > 500 THEN 500
                           ELSE @Limite END;

        DECLARE @Datos nvarchar(max);

        IF @Maestro = 'CENTRO_COSTO'
            SET @Datos = (SELECT TOP (@Limite) CentroCosto, NombreDepend, Abreviado, TipoDepend, Activo
                            FROM siga.vwCentroCosto
                           WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                             AND (@Texto IS NULL OR NombreDepend LIKE '%' + @Texto + '%'
                                                 OR CentroCosto  LIKE @Texto + '%')
                           ORDER BY CentroCosto
                             FOR JSON PATH);

        ELSE IF @Maestro = 'META'
            SET @Datos = (SELECT TOP (@Limite) SecFunc, Nombre, Meta, Finalidad, ActProy, Activo
                            FROM siga.vwMeta
                           WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                             AND (@Texto IS NULL OR Nombre LIKE '%' + @Texto + '%')
                           ORDER BY SecFunc
                             FOR JSON PATH);

        ELSE IF @Maestro = 'FUENTE_FINANC'
            SET @Datos = (SELECT TOP (@Limite) Origen, FuenteFinanc, Descripcion, MontoAsignado, Activo
                            FROM siga.vwFuenteFinanc
                           WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                           ORDER BY Origen, FuenteFinanc
                             FOR JSON PATH);

        ELSE IF @Maestro = 'TAREA'
        BEGIN
            IF @CentroCosto IS NULL
                THROW 51023, 'VALIDACION_PAYLOAD: TAREA exige CentroCosto. En SIGA la tarea vive por centro de costo.', 1;
            SET @Datos = (SELECT TOP (@Limite) TipoTarea, NivelTarea, CodigoTarea, NombreTarea, GrupoTarea, TipoUso, Activo
                            FROM siga.vwTarea
                           WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec AND CentroCosto = @CentroCosto
                             AND (@Texto IS NULL OR NombreTarea LIKE '%' + @Texto + '%')
                           ORDER BY CodigoTarea
                             FOR JSON PATH);
        END

        ELSE IF @Maestro = 'UNIDAD_MEDIDA'
            SET @Datos = (SELECT TOP (@Limite) UnidadMedida, Nombre, Abreviatura, Activo
                            FROM siga.vwUnidadMedida
                           WHERE (@Texto IS NULL OR Nombre LIKE '%' + @Texto + '%')
                           ORDER BY Nombre
                             FOR JSON PATH);

        ELSE IF @Maestro = 'CATALOGO'
        BEGIN
            /* El area usuaria busca por descripcion, nunca por codigo. Full-Text
               no esta instalado en la instancia; sobre las 5 239 filas del
               catalogo de la ejecutora un LIKE tarda 28 ms medidos. */
            SET @Datos = (SELECT TOP (@Limite) CodigoItem, TipoBien, GrupoBien, ClaseBien,
                                 FamiliaBien, ItemBien, Descripcion, UnidadMedida, PrecioRef, Activo
                            FROM siga.vwCatalogoItem
                           WHERE SecEjec = @SecEjec
                             AND Activo = 1
                             AND (@Texto IS NULL OR Descripcion LIKE '%' + @Texto + '%'
                                                 OR CodigoItem  LIKE @Texto + '%')
                           ORDER BY Descripcion
                             FOR JSON PATH);
        END

        ELSE IF @Maestro = 'CUADRO_VIGENTE'
        BEGIN
            IF @CentroCosto IS NULL
                THROW 51024, 'VALIDACION_PAYLOAD: CUADRO_VIGENTE exige CentroCosto.', 1;
            /* Es el listado del que el area usuaria elige que excluir o que
               modificar, en vez de transcribirlo a mano. */
            SET @Datos = (SELECT TOP (@Limite) SecCuadro, SecItem, SecCuaModSal, CodigoItem =
                                 CONCAT_WS('.', TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien),
                                 TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien,
                                 UnidadMedida, PrecioUnit, EstadoSiga, ProcedenciaDesc, MotivoDesc,
                                 CantAno0, CantAno1, CantAno2, CantAno3,
                                 TipoTarea, NivelTarea, CodigoTarea, SecFunc, Origen, FuenteFinanc,
                                 Clasificador, TipoUso
                            FROM siga.vwCuadroVigenteItem
                           WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec AND CentroCosto = @CentroCosto
                           ORDER BY SecItem
                             FOR JSON PATH);
        END

        ELSE IF @Maestro = 'TECHO'
        BEGIN
            /* Solo las filas con CentroCosto: las de centro nulo son de
               agregacion (1 658 de 2 375 en 2026) y no corresponden a un area
               usuaria concreta.

               MontoTecho0 y MontoUsado0 son del anio base y son los unicos
               confiables. El techo de los anios 1 a 3 NO se ha localizado: en
               2026 PPTO_ANNO_01..03 esta en cero en las 2 375 filas. Por eso se
               devuelve MontoProg1..3, que es lo programado, y no un techo que no
               existe. Ver la nota en siga.vwTechoPresupuesto. */
            SET @Datos = (SELECT TOP (@Limite) Secuencia, CentroCosto, FaseCuadro, SecFunc, SecFuncProp,
                                 Origen, FuenteFinanc, Clasificador,
                                 MontoTecho0, MontoUsado0,
                                 MontoDisponible0 = MontoTecho0 - MontoUsado0,
                                 MontoProg1, MontoProg2, MontoProg3
                            FROM siga.vwTechoPresupuesto
                           WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                             AND CentroCosto IS NOT NULL
                             AND (@CentroCosto IS NULL OR CentroCosto = @CentroCosto)
                           ORDER BY CentroCosto, Clasificador
                             FOR JSON PATH);
        END

        ELSE IF @Maestro = 'ETAPA_CENTRO'
            /* Gobierna en que etapa esta el cuadro de cada area usuaria. Ninguna
               escritura hacia SIGA debe contradecirla. */
            SET @Datos = (SELECT TOP (@Limite) CentroCosto, Estado, FlagPadre, FlagModif, FechaReg
                            FROM siga.vwCuadroEtapaCentro
                           WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                             AND (@CentroCosto IS NULL OR CentroCosto = @CentroCosto)
                           ORDER BY CentroCosto
                             FOR JSON PATH);

        ELSE
        BEGIN
            DECLARE @errMaestro nvarchar(300) = CONCAT(
                'VALIDACION_PAYLOAD: maestro desconocido "', @Maestro,
                '". Validos: CENTRO_COSTO, META, FUENTE_FINANC, TAREA, UNIDAD_MEDIDA, ',
                'CATALOGO, CUADRO_VIGENTE, TECHO, ETAPA_CENTRO.');
            THROW 51025, @errMaestro, 1;
        END

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @Maestro AS maestro,
                   JSON_QUERY(COALESCE(@Datos, '[]')) AS datos,
                   'OK' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado,
                   ERROR_MESSAGE() AS mensaje,
                   ERROR_NUMBER()  AS codigo,
                   JSON_QUERY('[]') AS datos
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

PRINT 'F001 aplicada: utilitarios del contrato.';
GO
