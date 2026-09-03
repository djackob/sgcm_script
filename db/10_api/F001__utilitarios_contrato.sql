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

    SET @Usuario = NULLIF(LTRIM(RTRIM(@Usuario)), '');
    SET @Rol     = NULLIF(LTRIM(RTRIM(@Rol)), '');
    SET @Unidad  = NULLIF(LTRIM(RTRIM(@Unidad)), '');

    IF @Usuario IS NULL
        THROW 51001, 'VALIDACION_ACTOR: falta Actor.Usuario. El backend debe completarlo desde la sesion SSO.', 1;

    /* El token del SSO institucional trae cod_perfil (PE092) y a menudo no
       trae cod_dependencia. Sin esta traduccion, la primera accion del
       especialista real revienta en VALIDACION_ACTOR aunque el padron ya
       tenga su terna. */
    IF @Rol IS NOT NULL
       AND OBJECT_ID(N'sigcm.PerfilSso', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sigcm.Rol WHERE CodigoRol = @Rol AND Activo = 1)
    BEGIN
        SELECT @Rol = NULLIF(LTRIM(RTRIM(m.CodigoRol)), '')
          FROM sigcm.PerfilSso AS m
         WHERE m.CodigoPerfilSso = @Rol AND m.Activo = 1;
    END

    IF @Rol IS NULL
        THROW 51002, 'VALIDACION_ACTOR: falta Actor.Rol.', 1;

    DECLARE @Hoy date = CONVERT(date, GETDATE());

    IF @Unidad IS NULL
    BEGIN
        IF (SELECT COUNT(*)
              FROM sigcm.UsuarioRol AS ur
              JOIN sigcm.Usuario    AS u  ON u.IdUsuario = ur.IdUsuario
              JOIN sigcm.Unidad     AS un ON un.IdUnidad = ur.IdUnidad
             WHERE u.Cuenta = @Usuario AND ur.CodigoRol = @Rol
               AND u.Activo = 1 AND un.Activo = 1 AND ur.Activo = 1
               AND ur.VigenteDesde <= @Hoy
               AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @Hoy)) = 1
        BEGIN
            SELECT @Unidad = un.Codigo
              FROM sigcm.UsuarioRol AS ur
              JOIN sigcm.Usuario    AS u  ON u.IdUsuario = ur.IdUsuario
              JOIN sigcm.Unidad     AS un ON un.IdUnidad = ur.IdUnidad
             WHERE u.Cuenta = @Usuario AND ur.CodigoRol = @Rol
               AND u.Activo = 1 AND un.Activo = 1 AND ur.Activo = 1
               AND ur.VigenteDesde <= @Hoy
               AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @Hoy);
        END
    END

    IF @Unidad IS NULL
        THROW 51003, 'VALIDACION_ACTOR: falta Actor.Unidad.', 1;

    /* Una correlacion invalida no debe tumbar la operacion: se genera una. */
    SET @CorrelacionId = TRY_CONVERT(uniqueidentifier, @CorrelacionTexto);
    IF @CorrelacionId IS NULL SET @CorrelacionId = NEWID();

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
      AND (un.Codigo = @Unidad OR un.CentroCostoSiga = @Unidad)
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
  Genera el codigo visible de un expediente.

  Formato de expediente (CMN / REQ), con area, usuario y correlativo del actor:
      PREFIJO-ANIO-{area}{idUsuario}{correlativo}
      CMN-2026-01070503125001
        2026       anio de ejecucion
        01070503   digitos del centro de costo (01.07.05.03)
        125        IdUsuarioSso del actor, con al menos tres cifras
        001        correlativo de expedientes de ESE usuario en ESE area y anio

  El contador vive en sigcm.Correlativo (V010), no en una SEQUENCE: el numero se
  consume DENTRO de la transaccion del llamador, asi un rollback no deja huecos.

  Sin @AreaNumerica / @IdUsuarioNumerico se conserva el formato corto
  PREFIJO-ANIO-000123 (paquetes Anexo 4 y llamadas antiguas).

  @Secuencia es la clave del contador. Con area y usuario se concatena
  |anio|area|idUsuario para que cada actor tenga su propia serie.
*/
CREATE OR ALTER PROCEDURE sigcm.paSiguienteCodigo
    @Prefijo           varchar(10),
    @AnoEje            smallint,
    @Secuencia         nvarchar(128),          /* p.ej. N'cmn.SeqSolicitud' */
    @Codigo            varchar(40) OUTPUT,
    @AreaNumerica      varchar(20) = NULL,
    @IdUsuarioNumerico int         = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NULLIF(LTRIM(RTRIM(@Secuencia)), '') IS NULL
        THROW 51010, 'No se indico el nombre del correlativo.', 1;

    DECLARE @Nombre nvarchar(128) = @Secuencia;
    DECLARE @ConActor bit = 0;
    DECLARE @Area varchar(20) = NULLIF(LTRIM(RTRIM(@AreaNumerica)), '');
    DECLARE @UsuarioTxt varchar(20);

    IF @Area IS NOT NULL AND @IdUsuarioNumerico IS NOT NULL AND @IdUsuarioNumerico > 0
    BEGIN
        SET @ConActor = 1;
        SET @UsuarioTxt = CONVERT(varchar(20), @IdUsuarioNumerico);
        IF LEN(@UsuarioTxt) < 3
            SET @UsuarioTxt = RIGHT(CONCAT('000', @UsuarioTxt), 3);
        SET @Nombre = CONCAT(@Secuencia, N'|', CONVERT(varchar(4), @AnoEje), N'|',
                             @Area, N'|', CONVERT(varchar(20), @IdUsuarioNumerico));
    END

    DECLARE @Valor bigint;

    IF NOT EXISTS (SELECT 1 FROM sigcm.Correlativo WITH (UPDLOCK, HOLDLOCK)
                    WHERE Nombre = @Nombre)
        INSERT INTO sigcm.Correlativo (Nombre, Valor) VALUES (@Nombre, 0);

    UPDATE sigcm.Correlativo
       SET @Valor = Valor = Valor + 1
     WHERE Nombre = @Nombre;

    IF @ConActor = 1
    BEGIN
        DECLARE @Corr varchar(20) = CONVERT(varchar(20), @Valor);
        IF @Valor < 1000
            SET @Corr = RIGHT(CONCAT('000', @Corr), 3);

        SET @Codigo = CONCAT(@Prefijo, '-', CONVERT(varchar(4), @AnoEje), '-',
                             @Area, @UsuarioTxt, @Corr);
    END
    ELSE
        SET @Codigo = CONCAT(@Prefijo, '-', CONVERT(varchar(4), @AnoEje), '-',
                             RIGHT(CONCAT('000000', CONVERT(varchar(20), @Valor)), 6));

    IF LEN(@Codigo) > 40
        THROW 51011, 'CONFLICTO_CONFIGURACION: el codigo de expediente excede 40 caracteres.', 1;
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
                @Limite      int,
                @TipoMovimiento varchar(20),
                @SecFunc     int,
                @Origen      varchar(1),
                @FuenteFinanc varchar(2),
                @NumeroPedido varchar(6),
                @CodigoTipoContratacion varchar(20),
                @TipoBien    char(1);

        SELECT @Maestro     = Maestro,
               @AnoEje      = AnoEje,
               @SecEjec     = SecEjec,
               @CentroCosto = CentroCosto,
               @Texto       = Texto,
               @Limite      = Limite,
               @TipoMovimiento = UPPER(LTRIM(RTRIM(TipoMovimiento))),
               @SecFunc     = SecFunc,
               @Origen      = Origen,
               @FuenteFinanc = FuenteFinanc,
               @NumeroPedido = NumeroPedido,
               @CodigoTipoContratacion = CodigoTipoContratacion,
               @TipoBien    = TipoBien
        FROM OPENJSON(@parametro)
        WITH (
            Maestro     varchar(40),
            AnoEje      smallint,
            SecEjec     int,
            CentroCosto varchar(15),
            Texto       varchar(200),
            Limite      int,
            TipoMovimiento varchar(20),
            SecFunc     int,
            Origen      varchar(1),
            FuenteFinanc varchar(2),
            NumeroPedido varchar(6),
            CodigoTipoContratacion varchar(20),
            TipoBien    char(1)
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

        /* META y FUENTE_FINANC SE DELIMITAN POR AREA USUARIA.

           Con CentroCosto se devuelven solo las metas asignadas a ese centro en
           SIG_METAS_X_CENTRO y solo las fuentes habilitadas dentro de esas
           metas. Sin CentroCosto se devuelve el maestro completo, que es lo que
           necesita Abastecimiento cuando consulta transversalmente.

           Por que importa: la entidad tiene 487 metas y 100 fuentes, y un area
           usuaria tiene techo en una sola meta con una sola fuente en casi todos
           los casos. Ofrecerle la lista entera la dejaba elegir combinaciones
           sin techo -canon, donaciones- y el clasificador quedaba vacio sin que
           la pantalla explicara por que. La delimitacion es de SIGA, no nuestra:
           esta tabla es con la que el propio SIGA arma esos combos. */
        ELSE IF @Maestro = 'META'
            SET @Datos = (SELECT TOP (@Limite) m.SecFunc, m.Nombre, m.Meta, m.Finalidad, m.ActProy, m.Activo
                            FROM siga.vwMeta AS m
                           WHERE m.AnoEje = @AnoEje AND m.SecEjec = @SecEjec
                             AND (@Texto IS NULL OR m.Nombre LIKE '%' + @Texto + '%')
                             AND (@CentroCosto IS NULL
                                  OR EXISTS (SELECT 1 FROM siga.vwMetaXCentro AS mc
                                              WHERE mc.AnoEje = @AnoEje AND mc.SecEjec = @SecEjec
                                                AND mc.CentroCosto = @CentroCosto
                                                AND mc.SecFunc = m.SecFunc))
                           ORDER BY m.SecFunc
                             FOR JSON PATH);

        ELSE IF @Maestro = 'FUENTE_FINANC'
            SET @Datos = (SELECT TOP (@Limite) f.Origen, f.FuenteFinanc, f.Descripcion, f.MontoAsignado, f.Activo
                            FROM siga.vwFuenteFinanc AS f
                           WHERE f.AnoEje = @AnoEje AND f.SecEjec = @SecEjec
                             AND (@CentroCosto IS NULL
                                  OR EXISTS (SELECT 1 FROM siga.vwMetaXCentro AS mc
                                              WHERE mc.AnoEje = @AnoEje AND mc.SecEjec = @SecEjec
                                                AND mc.CentroCosto = @CentroCosto
                                                AND mc.Origen = f.Origen
                                                AND mc.FuenteFinanc = f.FuenteFinanc
                                                /* Con SecFunc, la fuente ademas
                                                   tiene que pertenecer a esa meta. */
                                                AND (@SecFunc IS NULL OR mc.SecFunc = @SecFunc)))
                           ORDER BY f.Origen, f.FuenteFinanc
                             FOR JSON PATH);

        /* Las metas del area usuaria con sus fuentes, en una sola lectura. Es lo
           que la pantalla necesita para encadenar meta -> fuente sin volver a
           preguntar por cada cambio del combo. */
        ELSE IF @Maestro = 'META_X_CENTRO'
        BEGIN
            IF @CentroCosto IS NULL
                THROW 51028, 'VALIDACION_PAYLOAD: META_X_CENTRO exige CentroCosto.', 1;
            SET @Datos = (SELECT TOP (@Limite) mc.SecFunc, mc.Origen, mc.FuenteFinanc,
                                 mc.TipoRecurso, mc.PorcTecho,
                                 Meta = m.Nombre, MetaActiva = m.Activo,
                                 Fuente = f.Descripcion
                            FROM siga.vwMetaXCentro AS mc
                            LEFT JOIN siga.vwMeta AS m
                                   ON m.AnoEje = mc.AnoEje AND m.SecEjec = mc.SecEjec
                                  AND m.SecFunc = mc.SecFunc
                            LEFT JOIN siga.vwFuenteFinanc AS f
                                   ON f.AnoEje = mc.AnoEje AND f.SecEjec = mc.SecEjec
                                  AND f.Origen = mc.Origen AND f.FuenteFinanc = mc.FuenteFinanc
                           WHERE mc.AnoEje = @AnoEje AND mc.SecEjec = @SecEjec
                             AND mc.CentroCosto = @CentroCosto
                             AND (@SecFunc IS NULL OR mc.SecFunc = @SecFunc)
                           ORDER BY mc.SecFunc, mc.Origen, mc.FuenteFinanc
                             FOR JSON PATH);
        END

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
            SET @Datos = (SELECT TOP (@Limite) c.CodigoItem, c.TipoBien, c.GrupoBien, c.ClaseBien,
                                 c.FamiliaBien, c.ItemBien, c.Descripcion, c.UnidadMedida,
                                 c.PrecioRef, c.Activo
                            FROM siga.vwCatalogoItem AS c
                           WHERE c.SecEjec = @SecEjec
                             AND c.Activo = 1
                             AND (@Texto IS NULL OR c.Descripcion LIKE '%' + @Texto + '%'
                                                 OR c.CodigoItem  LIKE @Texto + '%')
                             /* Una inclusion no debe ofrecer un item que ya esta
                                vigente y con cantidades en el mismo centro. */
                             AND (@CentroCosto IS NULL OR @TipoMovimiento IS NULL
                                  OR @TipoMovimiento <> 'INCLUSION'
                                  OR NOT EXISTS
                                  (SELECT 1
                                     FROM siga.vwCuadroVigenteItem AS v
                                    WHERE v.AnoEje = @AnoEje AND v.SecEjec = @SecEjec
                                      AND v.CentroCosto = @CentroCosto
                                      AND v.TipoBien = c.TipoBien AND v.GrupoBien = c.GrupoBien
                                      AND v.ClaseBien = c.ClaseBien AND v.FamiliaBien = c.FamiliaBien
                                      AND v.ItemBien = c.ItemBien
                                      AND v.FlagModificado = 0 AND v.FlagSolicitud = 0
                                      AND v.MotivoSolicitud = '0' AND v.EstadoSiga IN ('C','I')
                                      AND v.CantAno0 + v.CantAno1 + v.CantAno2 + v.CantAno3 > 0))
                           ORDER BY c.Descripcion
                             FOR JSON PATH);
        END

        ELSE IF @Maestro = 'CUADRO_VIGENTE'
        BEGIN
            IF @CentroCosto IS NULL
                THROW 51024, 'VALIDACION_PAYLOAD: CUADRO_VIGENTE exige CentroCosto.', 1;
            /* Es el listado del que el area usuaria elige que excluir o que
               modificar, en vez de transcribirlo a mano. */
            SET @Datos = (SELECT TOP (@Limite) v.SecCuadro, v.SecItem, v.SecCuaModSal, CodigoItem =
                                 CONCAT_WS('.', v.TipoBien, v.GrupoBien, v.ClaseBien, v.FamiliaBien, v.ItemBien),
                                 v.TipoBien, v.GrupoBien, v.ClaseBien, v.FamiliaBien, v.ItemBien,
                                 v.UnidadMedida, v.PrecioUnit, v.EstadoSiga, v.ProcedenciaDesc, v.MotivoDesc,
                                 v.CantAno0, v.CantAno1, v.CantAno2, v.CantAno3,
                                 v.TipoTarea, v.NivelTarea, v.CodigoTarea, v.SecFunc, v.Origen, v.FuenteFinanc,
                                 v.Clasificador, v.TipoUso, c.Descripcion, CatalogoActivo = c.Activo
                            FROM siga.vwCuadroVigenteItem AS v
                            JOIN siga.vwCatalogoItem AS c
                              ON c.SecEjec = v.SecEjec AND c.TipoBien = v.TipoBien
                             AND c.GrupoBien = v.GrupoBien AND c.ClaseBien = v.ClaseBien
                             AND c.FamiliaBien = v.FamiliaBien AND c.ItemBien = v.ItemBien
                           WHERE v.AnoEje = @AnoEje AND v.SecEjec = @SecEjec
                             AND v.CentroCosto = @CentroCosto AND c.Activo = 1
                             AND v.FlagModificado = 0 AND v.FlagSolicitud = 0
                             AND v.MotivoSolicitud = '0' AND v.EstadoSiga IN ('C','I')
                             AND v.CantAno0 + v.CantAno1 + v.CantAno2 + v.CantAno3 > 0
                             AND (@Texto IS NULL OR c.Descripcion LIKE '%' + @Texto + '%'
                                                 OR c.CodigoItem LIKE @Texto + '%')
                           ORDER BY v.SecItem
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
            SET @Datos = (SELECT TOP (@Limite) Secuencia, CentroCosto, FaseCuadro,
                                 TipoTarea, NivelTarea, CodigoTarea, SecFunc, SecFuncProp,
                                 Origen, FuenteFinanc, Clasificador,
                                 MontoTecho0, MontoUsado0,
                                 MontoDisponible0 = MontoTecho0 - MontoUsado0,
                                 MontoProg1, MontoProg2, MontoProg3
                            FROM siga.vwTechoPresupuesto
                           WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                             AND CentroCosto IS NOT NULL
                             AND (@CentroCosto IS NULL OR CentroCosto = @CentroCosto)
                             AND (@SecFunc IS NULL OR SecFunc = @SecFunc)
                             AND (@Origen IS NULL OR Origen = @Origen)
                             AND (@FuenteFinanc IS NULL OR FuenteFinanc = @FuenteFinanc)
                             AND NULLIF(LTRIM(RTRIM(Clasificador)), '') IS NOT NULL
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

        ELSE IF @Maestro IN ('PEDIDO', 'PEDIDO_DETALLE')
        BEGIN
            /* REQ-02: el combo lista los pedidos SIGA del AREA USUARIA del
               actor, no de cualquier centro. CentroCostoSiga sale de la unidad
               de la sesion (igual que paRegistrarRequerimiento).

               TIPO_BIEN: S = servicios (locacion, servicio, consultoria);
               B = bienes / compras. En esta ejecutora los pedidos de servicio
               del area usuaria son TipoBien S y TipoPedido 2; TipoPedido 1
               es el pedido de compras (bienes). TipoPedido 2 + B es almacen.

               PEDIDO_DETALLE une en una sola respuesta lo que el sistema
               anterior pedia en dos HTTP al elegir un N°: la tarea del centro
               (listarCentroCostoTarea) y el resumen concatenado de items
               (listarItemsPedidoResumen). Solo lineas del tipo de bien del
               objeto: locacion no mezcla compras. */
            DECLARE @IdUsuarioPed      uniqueidentifier,
                    @CuentaPed         varchar(120),
                    @NombrePed         varchar(250),
                    @CargoPed          varchar(180),
                    @RolPed            varchar(40),
                    @IdUnidadPed       uniqueidentifier,
                    @CentroCostoActor  varchar(15),
                    @EsTitularPed      bit,
                    @IpPed             varchar(45),
                    @EquipoPed         varchar(50),
                    @ProgramaPed       varchar(50),
                    @CorrPed           uniqueidentifier,
                    @TipoPedidoPed     char(1);

            EXEC sigcm.paResolverActor
                @parametro,
                @IdUsuarioPed     OUTPUT,
                @CuentaPed        OUTPUT,
                @NombrePed        OUTPUT,
                @CargoPed         OUTPUT,
                @RolPed           OUTPUT,
                @IdUnidadPed      OUTPUT,
                @CentroCostoActor OUTPUT,
                @EsTitularPed     OUTPUT,
                @IpPed            OUTPUT,
                @EquipoPed        OUTPUT,
                @ProgramaPed      OUTPUT,
                @CorrPed          OUTPUT;

            IF NULLIF(LTRIM(RTRIM(@CentroCostoActor)), '') IS NULL
                THROW 51023, 'VALIDACION_PAYLOAD: PEDIDO exige que la unidad del actor tenga centro de costo SIGA (area usuaria).', 1;

            IF @CentroCosto IS NOT NULL
               AND LTRIM(RTRIM(@CentroCosto)) <> LTRIM(RTRIM(@CentroCostoActor))
                THROW 51026, 'NO_AUTORIZADO: los pedidos se listan solo del area usuaria del actor.', 1;

            SET @CentroCosto = LTRIM(RTRIM(@CentroCostoActor));

            SET @TipoBien = CASE
                WHEN @TipoBien IN ('B', 'S') THEN @TipoBien
                WHEN @CodigoTipoContratacion = 'BIEN' THEN 'B'
                ELSE 'S'
            END;
            SET @TipoPedidoPed = CASE WHEN @TipoBien = 'S' THEN '2' ELSE '1' END;

            IF @Maestro = 'PEDIDO'
                SET @Datos = (SELECT TOP (@Limite) NumeroPedido, MotivoPedido, AnoEje,
                                     TipoBien, TipoPedido, ActProy, FuenteFinanc, CodigoTarea,
                                     SecFunc, FechaPedido, Origen, CentroCosto, Programa
                                FROM siga.vwPedido
                               WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                                 AND CentroCosto = @CentroCosto
                                 AND TipoPedido = @TipoPedidoPed
                                 AND TipoBien = @TipoBien
                               ORDER BY NumeroPedido
                                 FOR JSON PATH);
            ELSE
            BEGIN
                SET @NumeroPedido = NULLIF(LTRIM(RTRIM(@NumeroPedido)), '');
                IF @NumeroPedido IS NULL
                    THROW 51027, 'VALIDACION_PAYLOAD: PEDIDO_DETALLE exige NumeroPedido.', 1;

                SET @Datos = (
                    SELECT TOP (1)
                           p.NumeroPedido,
                           p.AnoEje,
                           p.TipoBien,
                           p.CodigoTarea,
                           p.ActProy,
                           p.Origen,
                           p.FuenteFinanc,
                           p.Programa,
                           p.SecFunc,
                           t.TipoTarea,
                           t.NivelTarea,
                           t.NombreTarea,
                           i.CodigoItem,
                           i.NombreItem,
                           i.Clasificador
                      FROM siga.vwPedido AS p
                      LEFT JOIN siga.vwTarea AS t
                             ON t.AnoEje      = p.AnoEje
                            AND t.SecEjec     = p.SecEjec
                            AND t.CentroCosto = p.CentroCosto
                            AND t.CodigoTarea = p.CodigoTarea
                      OUTER APPLY (
                            SELECT CodigoItem   = STRING_AGG(CONVERT(varchar(max), x.CodigoItem),   ', ')
                                                      WITHIN GROUP (ORDER BY x.Secuencia),
                                   NombreItem   = STRING_AGG(CONVERT(varchar(max), x.NombreItem),   ', ')
                                                      WITHIN GROUP (ORDER BY x.Secuencia),
                                   Clasificador = STRING_AGG(CONVERT(varchar(max), x.Clasificador), ', ')
                                                      WITHIN GROUP (ORDER BY x.Secuencia)
                              FROM siga.vwPedidoItem AS x
                             WHERE x.AnoEje       = p.AnoEje
                               AND x.SecEjec      = p.SecEjec
                               AND x.TipoPedido   = p.TipoPedido
                               AND x.NumeroPedido = p.NumeroPedido
                               AND x.TipoBien     = p.TipoBien
                      ) AS i
                     WHERE p.AnoEje = @AnoEje AND p.SecEjec = @SecEjec
                       AND p.CentroCosto = @CentroCosto
                       AND p.TipoPedido = @TipoPedidoPed
                       AND p.TipoBien = @TipoBien
                       AND p.NumeroPedido = @NumeroPedido
                       FOR JSON PATH);
            END
        END

        ELSE
        BEGIN
            DECLARE @errMaestro nvarchar(300) = CONCAT(
                'VALIDACION_PAYLOAD: maestro desconocido "', @Maestro,
                '". Validos: CENTRO_COSTO, META, META_X_CENTRO, FUENTE_FINANC, TAREA, ',
                'UNIDAD_MEDIDA, CATALOGO, CUADRO_VIGENTE, TECHO, ETAPA_CENTRO, ',
                'PEDIDO, PEDIDO_DETALLE.');
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

/* ========================================================================== */
/* 6. sigcm.fnEstadoDestinoTransicion                                        */
/* ========================================================================== */

/*
  EL DESTINO REAL DE UNA TRANSICION, EN UN SOLO SITIO.

  Casi siempre es sigcm.Transicion.CodigoEstadoDestino y no hay nada que
  calcular. La excepcion es el retorno de lo subsanado: la regla del flujo -y de
  sigcm.Observacion.CodigoEstadoRetorno, ver V003- dice que lo que observa OA
  vuelve a OA y lo que observa Abastecimiento vuelve a Abastecimiento. La fila
  de la semilla no puede expresar eso, porque ahi el destino depende del
  expediente y no de la transicion.

  Esto vivia repetido en cmn.paObtenerSolicitud (F002) y en
  requerimiento.paObtenerRequerimiento (F005) -que SI lo aplicaban- mientras el
  motor, sigcm.paEjecutarTransicion, usaba el destino fijo de la tabla: la
  pantalla anunciaba "vuelve a OA" y el expediente terminaba en Abastecimiento.
  Aqui hay UNA definicion y todos la llaman: las dos bandejas, la lista de
  acciones disponibles y el motor que ejecuta.

  Se lee la observacion ABIERTA -PENDIENTE, RECEPCIONADA o SUBSANADA-, que en
  CMN_SUBS_JEFE_ENVIAR todavia lo esta cuando esto se evalua: S018 le asigno
  AccionObservacion='CERRAR' a esa misma transicion, asi que el motor tiene que
  resolver el destino ANTES de cerrarla. Cerrada la observacion, este calculo ya
  solo devuelve el destino de la tabla.

  El retorno de Abastecimiento se normaliza al Jefe: la observacion guarda el
  estado exacto en que estaba el expediente -especialista, coordinador o jefe-
  pero lo subsanado reingresa por el Jefe de Abastecimiento, que es justo lo que
  la semilla declara como destino fijo. Devolverlo al escritorio del
  especialista que observo se saltaria la linea.

  Sin observacion abierta, o con un retorno que no pertenece a ninguno de los
  dos circuitos, manda la tabla. Es una funcion en linea con subconsulta escalar:
  devuelve siempre exactamente una fila, tambien cuando no hay observacion.
*/
CREATE OR ALTER FUNCTION sigcm.fnEstadoDestinoTransicion
(
    @IdExpediente        uniqueidentifier,
    @CodigoTransicion    varchar(70),
    @CodigoEstadoDestino varchar(60),
    @NombreAccion        varchar(180)
)
RETURNS TABLE
AS
RETURN
    SELECT r.CodigoEstadoDestino,
           /* La etiqueta del boton viaja con el destino y no aparte: son el
              mismo hecho contado dos veces, y separarlas es como se llego a que
              la pantalla dijera "a OA" y el motor mandara a Abastecimiento. */
           NombreAccion = CASE
                              WHEN @CodigoTransicion = 'CMN_SUBS_JEFE_ENVIAR'
                                   AND r.CodigoEstadoDestino = 'CMN_EN_EVAL_OA'
                                  THEN N'Firmar y remitir subsanado a OA'
                              ELSE @NombreAccion
                          END
      FROM (
          SELECT CodigoEstadoDestino =
                     CASE
                         WHEN @CodigoTransicion <> 'CMN_SUBS_JEFE_ENVIAR'
                             THEN @CodigoEstadoDestino
                         WHEN obs.CodigoEstadoRetorno = 'CMN_EN_EVAL_OA'
                             THEN 'CMN_EN_EVAL_OA'
                         WHEN obs.CodigoEstadoRetorno LIKE 'CMN_EN_ABAST%'
                             THEN 'CMN_EN_ABAST_JEFE'
                         ELSE @CodigoEstadoDestino
                     END
            FROM (
                SELECT CodigoEstadoRetorno = (
                           SELECT TOP 1 o.CodigoEstadoRetorno
                             FROM sigcm.Observacion AS o
                            WHERE o.IdExpediente = @IdExpediente
                              AND o.Activo = 1
                              AND o.Estado IN ('PENDIENTE','RECEPCIONADA','SUBSANADA')
                            ORDER BY o.FechaCreacionAuditoria DESC)
            ) AS obs
      ) AS r;
GO

PRINT 'F001 aplicada: utilitarios del contrato.';
GO
