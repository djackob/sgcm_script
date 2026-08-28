/*
===============================================================================
  SIGCM - F008 : Padron del SSO y destinatarios de derivacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51600-51699

  QUE RESUELVE
  ------------
  Tres piezas, en el orden en que se usan:

    fnDestinatarioDerivacion       quien puede recibir un expediente de manos de
                                   este rol, en este modulo, desde esta unidad.
    paSincronizarPadronSso         trae el padron del SSO y lo reconcilia contra
                                   sigcm.Usuario / Unidad / UsuarioRol.
    paListarPerfilSso              las ternas vigentes de una cuenta, para elegir
                                   con cual entrar cuando tiene mas de una.
    paListarDestinatarioDerivacion la version invocable de la funcion, para la
                                   pantalla de derivacion.

  -----------------------------------------------------------------------------
  POR QUE LA SINCRONIZACION ES POR DIFERENCIA DE CONJUNTOS Y NO UN UPSERT
  -----------------------------------------------------------------------------
  Esta es LA decision de este archivo y conviene entenderla antes de tocarlo.

  El SSO da de baja poniendo login.td_login_acceso.activo en false, y su vista
  vw_login_usuario_perfil_sistema_sgcm filtra por esa columna. Consecuencia: la
  persona dada de baja NO llega marcada como inactiva, SIMPLEMENTE DESAPARECE
  del resultado de la funcion. Al 2026-08-27 hay 43 accesos inactivos contra 20
  activos, o sea que la baja es la operacion frecuente, no la rara.

  Un upsert de lo que llega jamas se enteraria de una baja: la persona que se
  fue ya no vuelve a entrar, y si la sincronizacion solo actuara sobre quien
  inicia sesion, esa fila se quedaria vigente para siempre. El jefe seguiria
  viendo en su lista de derivacion al especialista que ya no trabaja aqui.

  Por eso el padron que llega se trata como LA VERDAD COMPLETA en ese instante y
  se reconcilia en tres movimientos:

      esta en el SSO y no lo tenemos  ->  alta de la asignacion
      esta en los dos                 ->  actualizacion de los datos personales
      lo tenemos vigente y no esta    ->  CIERRE con VigenteHasta = hoy

  El tercero es el que hace que la rotacion de personal funcione sin que el SSO
  tenga que avisarnos nada. Como son 20 filas, la corrida completa cuesta tan
  poco que se dispara en CADA validacion de token, y no solo desde una opcion de
  mantenimiento: asi el padron nunca tiene tiempo de quedar viejo.

  LAS TRES SALVAGUARDAS
  ---------------------
  1. Un padron vacio NO reconcilia, aborta con 51603. Si el PostgreSQL del SSO
     tiene un hipo y devuelve cero filas, la lectura literal seria "ya nadie
     trabaja aqui" y daria de baja a la entidad completa en una transaccion.
  2. Solo se cierran asignaciones de usuarios con IdUsuarioSso NOT NULL. Los
     usuarios ficticios de S900 y las cuentas tecnicas no los gobierna el SSO,
     asi que el SSO no puede darlos de baja.
  3. Completo = 0 desactiva el cierre. Es para sincronizar a una sola persona
     sin tocar al resto; el backend siempre manda el padron completo.

  QUE PASA CON EL EXPEDIENTE DE QUIEN SE FUE
  ------------------------------------------
  Nada: sigue su curso. La bandeja se filtra por UNIDAD y ROL, no por persona
  (F002, cmn.paListarSolicitud), asi que el reemplazo lo ve el lunes sin que
  nadie tenga que reasignar nada.

  De ahi la regla que gobierna la derivacion a persona:

      IdResponsableActual es una INDICACION de a quien le toco, nunca el unico
      filtro de la bandeja. El expediente pertenece al PUESTO; la persona es
      quien lo atiende hoy.

  Si algun dia se filtrara la bandeja solo por responsable, volveria a existir el
  expediente huerfano. No se haga.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. sigcm.fnDestinatarioDerivacion                                          */
/* ========================================================================== */

/*
  Los candidatos a recibir un expediente. Es una funcion en linea y no una vista
  ni codigo repetido porque la MISMA regla la necesitan dos consumidores que no
  pueden discrepar:

    paListarDestinatarioDerivacion  para pintar la lista en la pantalla
    paEjecutarTransicion            para validar lo que el cliente eligio

  Si la pantalla ofrece un destinatario que la transicion despues rechaza, o al
  reves, el usuario se queda sin saber que hizo mal. Una sola definicion.

  Devuelve PERSONAS, no puestos, porque es lo que la pantalla necesita mostrar.
  El puesto -el par rol/unidad- viaja en las columnas para que quien llame pueda
  agrupar. Un puesto vacante no produce filas y eso es correcto: no se puede
  derivar a nadie.
*/
CREATE OR ALTER FUNCTION sigcm.fnDestinatarioDerivacion
(
    @CodigoModulo    varchar(30),
    @CodigoRolOrigen varchar(40),
    @IdUnidadOrigen  uniqueidentifier
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        CodigoRol      = d.CodigoRolDestino,
        Rol            = r.Nombre,
        Alcance        = d.Alcance,
        Orden          = d.Orden,
        IdUsuario      = u.IdUsuario,
        Cuenta         = u.Cuenta,
        NombreCompleto = CONCAT_WS(' ', u.Nombres, u.Apellidos),
        Cargo          = u.Cargo,
        Correo         = u.Correo,
        IdUnidad       = n.IdUnidad,
        CodigoUnidad   = n.Codigo,
        Unidad         = n.Nombre,
        Sigla          = n.Sigla,
        CentroCosto    = n.CentroCostoSiga,
        EsTitular      = ur.EsTitular
      FROM sigcm.RolDerivacion AS d
      JOIN sigcm.Rol           AS r  ON r.CodigoRol = d.CodigoRolDestino
      JOIN sigcm.UsuarioRol    AS ur ON ur.CodigoRol = d.CodigoRolDestino
      JOIN sigcm.Usuario       AS u  ON u.IdUsuario = ur.IdUsuario
      JOIN sigcm.Unidad        AS n  ON n.IdUnidad  = ur.IdUnidad
     WHERE d.CodigoModulo    = @CodigoModulo
       AND d.CodigoRolOrigen = @CodigoRolOrigen
       AND d.Activo = 1 AND r.Activo = 1 AND r.EsTecnico = 0
       AND ur.Activo = 1 AND u.Activo = 1 AND n.Activo = 1
       AND ur.VigenteDesde <= CONVERT(date, GETDATE())
       AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()))
       /* El alcance decide DONDE se busca al ocupante del puesto destino. */
       AND (
             (d.Alcance = 'MISMA_UNIDAD' AND ur.IdUnidad = @IdUnidadOrigen)
          OR (d.Alcance = 'UNIDAD_PADRE' AND ur.IdUnidad = (SELECT o.IdUnidadPadre
                                                              FROM sigcm.Unidad AS o
                                                             WHERE o.IdUnidad = @IdUnidadOrigen))
          OR  d.Alcance = 'ENTIDAD'
           )
       /* Derivarse a uno mismo no es derivar. El rol ya lo impide por la
          restriccion CK_sigcm_RolDeriv_NoReflexiva, pero con alcance ENTIDAD la
          misma persona podria ocupar los dos puestos. */
       AND NOT (ur.IdUnidad = @IdUnidadOrigen AND ur.CodigoRol = @CodigoRolOrigen)
);
GO

/* ========================================================================== */
/* 2. sigcm.paSincronizarPadronSso                                            */
/* ========================================================================== */

/*
  Entrada:
  {
    "Disparador": "INGRESO",           INGRESO | MANTENIMIENTO
    "Cuenta": "44687266",              quien la disparo, para la bitacora
    "Completo": true,                  false = no cerrar nada. Ver salvaguarda 3.
    "Equipo": "...", "Programa": "...",
    "Dependencia": [                   login.tm_login_dependencia
       { "id_dependencia":17, "id_padre":11, "cod_dependencia":"D0017",
         "siglas":"UA", "descripcion":"UNIDAD DE ABASTECIMIENTO",
         "centro_costo":"01.07.03.01" } ],
    "Padron": {                        la respuesta CRUDA de la funcion del SSO
       "usuario":[ { "id_usuario":1476, "dni":"09086695", "usuario":"09086695",
                     "nombre":"CESAR AUGUSTO", "apellido_paterno":"CALVO",
                     "apellido_materno":"...", "cod_perfil":"PE082",
                     "perfil":"JEFE UA", "correo":"...",
                     "centro_costo":"01.07.03.01" } ],
       "cantidad": 20 }
  }

  Salida: { "estado":1, "Resumen":{...}, "Descartes":[...], "mensaje":"OK" }

  El backend no interpreta el JSON del SSO: lo trae y lo entrega tal cual. Toda
  la traduccion ocurre aqui, que es donde vive la logica de negocio.
*/
CREATE OR ALTER PROCEDURE sigcm.paSincronizarPadronSso
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF @parametro IS NULL OR ISJSON(@parametro) <> 1
            THROW 51600, 'JSON incorrecto.', 1;

        DECLARE @Disparador varchar(30), @CuentaDisparo varchar(120),
                @Completo bit, @Equipo varchar(50), @Programa varchar(50);

        SELECT @Disparador    = Disparador,
               @CuentaDisparo = Cuenta,
               @Completo      = Completo,
               @Equipo        = Equipo,
               @Programa      = Programa
        FROM OPENJSON(@parametro)
        WITH (Disparador varchar(30), Cuenta varchar(120), Completo bit,
              Equipo varchar(50), Programa varchar(50));

        SET @Disparador = COALESCE(NULLIF(LTRIM(RTRIM(@Disparador)), ''), 'INGRESO');
        SET @Completo   = COALESCE(@Completo, 1);
        SET @Equipo     = COALESCE(@Equipo, 'sso');
        SET @Programa   = COALESCE(@Programa, 'SIGCM-SSO');

        DECLARE @Hoy date = CONVERT(date, GETDATE());
        DECLARE @Ahora datetime = GETDATE();

        /* ---- El padron que llega ------------------------------------- */
        /*
          Una fila por PUESTO, no por persona: centro_costo puede traer varios
          separados por punto y coma cuando el mismo acceso cubre dos areas
          -hoy la coordinadora que atiende UDS y Abastecimiento-, y cada uno es
          una terna distinta con su propia bandeja.
        */
        DECLARE @Puesto TABLE (
            IdUsuarioSso   int          NOT NULL,
            Dni            varchar(20)      NULL,
            Cuenta         varchar(120) NOT NULL,
            Nombres        varchar(120) NOT NULL,
            Apellidos      varchar(120) NOT NULL,
            Correo         varchar(200)     NULL,
            CodigoPerfilSso varchar(20) NOT NULL,
            NombrePerfil   varchar(150)     NULL,
            CentroCosto    varchar(15)  NOT NULL,
            CodigoRol      varchar(40)      NULL,
            IdUnidad       uniqueidentifier NULL,
            IdUsuario      uniqueidentifier NULL
        );

        INSERT INTO @Puesto
              (IdUsuarioSso, Dni, Cuenta, Nombres, Apellidos, Correo,
               CodigoPerfilSso, NombrePerfil, CentroCosto)
        SELECT DISTINCT
               p.id_usuario,
               NULLIF(LTRIM(RTRIM(p.dni)), ''),
               /* La cuenta es el usuario del SSO; si viniera vacio, el DNI. Sin
                  una de las dos no hay identidad que registrar. */
               COALESCE(NULLIF(LTRIM(RTRIM(p.usuario)), ''), LTRIM(RTRIM(p.dni))),
               LTRIM(RTRIM(p.nombre)),
               LTRIM(RTRIM(CONCAT_WS(' ', p.apellido_paterno, p.apellido_materno))),
               /* correo llega como lista separada por punto y coma; se guarda el
                  primero, que es el que la notificacion usa. */
               NULLIF(LTRIM(RTRIM(
                   CASE WHEN CHARINDEX(';', p.correo) > 0
                        THEN LEFT(p.correo, CHARINDEX(';', p.correo) - 1)
                        ELSE p.correo END)), ''),
               LTRIM(RTRIM(p.cod_perfil)),
               LTRIM(RTRIM(p.perfil)),
               LTRIM(RTRIM(cc.value))
          FROM OPENJSON(@parametro, '$.Padron.usuario')
          WITH (
              id_usuario       int,
              dni              varchar(20),
              usuario          varchar(120),
              nombre           varchar(120),
              apellido_paterno varchar(120),
              apellido_materno varchar(120),
              correo           varchar(400),
              cod_perfil       varchar(20),
              perfil           varchar(150),
              centro_costo     varchar(400)
          ) AS p
         CROSS APPLY STRING_SPLIT(COALESCE(p.centro_costo, ''), ';') AS cc
         WHERE p.id_usuario IS NOT NULL
           AND NULLIF(LTRIM(RTRIM(cc.value)), '') IS NOT NULL
           AND COALESCE(NULLIF(LTRIM(RTRIM(p.usuario)), ''), NULLIF(LTRIM(RTRIM(p.dni)), '')) IS NOT NULL;

        DECLARE @Recibidos int = (SELECT COUNT(*) FROM @Puesto);

        /* SALVAGUARDA 1. Un padron vacio no es "ya no trabaja nadie aqui": es un
           fallo de lectura. Reconciliar contra el vaciaria la entidad. */
        IF @Recibidos = 0
            THROW 51603, 'PADRON_VACIO: el SSO no devolvio ninguna terna. No se reconcilia nada.', 1;

        /* ---- Unidades: alta y actualizacion desde las dependencias ---- */
        DECLARE @Dependencia TABLE (
            IdDependenciaSso int          NOT NULL PRIMARY KEY,
            IdPadreSso       int              NULL,
            Codigo           varchar(30)  NOT NULL,
            Sigla            varchar(30)      NULL,
            Nombre           varchar(200) NOT NULL,
            CentroCosto      varchar(15)  NOT NULL
        );

        INSERT INTO @Dependencia (IdDependenciaSso, IdPadreSso, Codigo, Sigla, Nombre, CentroCosto)
        SELECT d.id_dependencia, d.id_padre,
               LTRIM(RTRIM(d.cod_dependencia)),
               NULLIF(LTRIM(RTRIM(d.siglas)), ''),
               LTRIM(RTRIM(d.descripcion)),
               LTRIM(RTRIM(d.centro_costo))
          FROM OPENJSON(@parametro, '$.Dependencia')
          WITH (
              id_dependencia  int,
              id_padre        int,
              cod_dependencia varchar(30),
              siglas          varchar(30),
              descripcion     varchar(200),
              centro_costo    varchar(15)
          ) AS d
         WHERE d.id_dependencia IS NOT NULL
           AND NULLIF(LTRIM(RTRIM(d.centro_costo)), '') IS NOT NULL
           AND NULLIF(LTRIM(RTRIM(d.descripcion)), '') IS NOT NULL;

        DECLARE @UnidadesAlta int = 0, @UsuariosAlta int = 0,
                @AsignacionesAlta int = 0, @AsignacionesBaja int = 0;

        BEGIN TRANSACTION; SET @TranPropia = 1;

        /*
          El emparejamiento va por CENTRO DE COSTO antes que por el id del SSO,
          y ese orden importa: sigcm.Unidad puede haberse creado a mano o por
          S900 con su propio codigo -UO-UDS-, y el centro de costo es lo unico
          que las dos fuentes comparten. Emparejar por el id del SSO primero
          crearia una unidad duplicada con el mismo centro de costo, y a partir
          de ahi las bandejas se parten en dos.
        */
        UPDATE n
           SET n.IdDependenciaSso              = s.IdDependenciaSso,
               n.Nombre                        = s.Nombre,
               n.Sigla                         = COALESCE(s.Sigla, n.Sigla),
               n.UsuarioModificacionAuditoria  = 'sso',
               n.FechaModificacionAuditoria    = @Ahora,
               n.EquipoModificacionAuditoria   = @Equipo,
               n.ProgramaModificacionAuditoria = @Programa
          FROM sigcm.Unidad AS n
          JOIN @Dependencia AS s ON s.CentroCosto = n.CentroCostoSiga
         WHERE n.Activo = 1;

        /*
          EsAreaUsuaria se fija en el alta y NUNCA se toca en la actualizacion.
          El SSO no sabe cuales areas originan un CMN y cuales solo lo tramitan:
          eso es configuracion nuestra, y vive en sigcm.UnidadTramitadora.
          Sobrescribirla en cada sincronizacion borraria esa curaduria cada vez
          que alguien inicia sesion.

          La consulta a UnidadTramitadora va aqui, en el alta, y no en la semilla:
          cuando S005 corre, estas unidades todavia no existen.
        */
        INSERT INTO sigcm.Unidad
              (Codigo, Nombre, Sigla, CentroCostoSiga, IdDependenciaSso, EsAreaUsuaria,
               UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT s.Codigo, s.Nombre, s.Sigla, s.CentroCosto, s.IdDependenciaSso,
               CASE WHEN EXISTS (SELECT 1 FROM sigcm.UnidadTramitadora AS t
                                  WHERE t.CentroCosto = s.CentroCosto AND t.Activo = 1)
                    THEN 0 ELSE 1 END,
               'sso', @Equipo, @Programa
          FROM @Dependencia AS s
         WHERE NOT EXISTS (SELECT 1 FROM sigcm.Unidad AS n
                            WHERE n.CentroCostoSiga = s.CentroCosto
                               OR n.IdDependenciaSso = s.IdDependenciaSso
                               OR n.Codigo = s.Codigo);

        SET @UnidadesAlta = @@ROWCOUNT;

        /* El arbol de areas, en segunda pasada: el padre tiene que existir. */
        UPDATE n
           SET n.IdUnidadPadre = p.IdUnidad
          FROM sigcm.Unidad AS n
          JOIN @Dependencia AS s ON s.IdDependenciaSso = n.IdDependenciaSso
          JOIN sigcm.Unidad AS p ON p.IdDependenciaSso = s.IdPadreSso
         WHERE s.IdPadreSso IS NOT NULL
           AND (n.IdUnidadPadre IS NULL OR n.IdUnidadPadre <> p.IdUnidad)
           AND p.IdUnidad <> n.IdUnidad;

        /* ---- Traduccion del perfil y de la unidad -------------------- */
        UPDATE p
           SET p.CodigoRol = m.CodigoRol
          FROM @Puesto AS p
          JOIN sigcm.PerfilSso AS m ON m.CodigoPerfilSso = p.CodigoPerfilSso
                                   AND m.Activo = 1
          JOIN sigcm.Rol AS r ON r.CodigoRol = m.CodigoRol AND r.Activo = 1;

        UPDATE p
           SET p.IdUnidad = n.IdUnidad
          FROM @Puesto AS p
          JOIN sigcm.Unidad AS n ON n.CentroCostoSiga = p.CentroCosto AND n.Activo = 1;

        /* ---- Personas ------------------------------------------------ */
        UPDATE u
           SET u.Nombres                       = s.Nombres,
               u.Apellidos                     = s.Apellidos,
               u.DocumentoIdentidad            = COALESCE(s.Dni, u.DocumentoIdentidad),
               u.Correo                        = COALESCE(s.Correo, u.Correo),
               u.Cargo                         = COALESCE(s.NombrePerfil, u.Cargo),
               u.Activo                        = 1,
               u.UsuarioModificacionAuditoria  = 'sso',
               u.FechaModificacionAuditoria    = @Ahora,
               u.EquipoModificacionAuditoria   = @Equipo,
               u.ProgramaModificacionAuditoria = @Programa
          FROM sigcm.Usuario AS u
          JOIN (SELECT IdUsuarioSso, Dni, Nombres, Apellidos, Correo,
                       NombrePerfil = MIN(NombrePerfil)
                  FROM @Puesto GROUP BY IdUsuarioSso, Dni, Nombres, Apellidos, Correo) AS s
            ON s.IdUsuarioSso = u.IdUsuarioSso;

        /* Alta. El emparejamiento por Cuenta cubre el primer encuentro con una
           persona que ya existia en DBSIGCM sin su id del SSO. */
        UPDATE u
           SET u.IdUsuarioSso = s.IdUsuarioSso
          FROM sigcm.Usuario AS u
          JOIN (SELECT DISTINCT IdUsuarioSso, Cuenta FROM @Puesto) AS s
            ON s.Cuenta = u.Cuenta
         WHERE u.IdUsuarioSso IS NULL;

        INSERT INTO sigcm.Usuario
              (Cuenta, DocumentoIdentidad, Nombres, Apellidos, Correo, Cargo, IdUsuarioSso,
               UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT s.Cuenta, s.Dni, s.Nombres, s.Apellidos, s.Correo, s.NombrePerfil, s.IdUsuarioSso,
               'sso', @Equipo, @Programa
          FROM (SELECT IdUsuarioSso, Cuenta, Dni, Nombres, Apellidos, Correo,
                       NombrePerfil = MIN(NombrePerfil)
                  FROM @Puesto
                 GROUP BY IdUsuarioSso, Cuenta, Dni, Nombres, Apellidos, Correo) AS s
         WHERE NOT EXISTS (SELECT 1 FROM sigcm.Usuario AS u
                            WHERE u.IdUsuarioSso = s.IdUsuarioSso OR u.Cuenta = s.Cuenta);

        SET @UsuariosAlta = @@ROWCOUNT;

        UPDATE p
           SET p.IdUsuario = u.IdUsuario
          FROM @Puesto AS p
          JOIN sigcm.Usuario AS u ON u.IdUsuarioSso = p.IdUsuarioSso;

        /* ---- Asignaciones: alta ------------------------------------- */
        /*
          Reabrir una asignacion cerrada NO es actualizar la fila vieja: entra una
          fila nueva. La anterior conserva su VigenteDesde y su VigenteHasta, que
          es lo que permite responder quien ejercia que rol el dia que se firmo un
          Anexo 3. Un expediente auditable lo exige.
        */
        INSERT INTO sigcm.UsuarioRol
              (IdUsuario, CodigoRol, IdUnidad, VigenteDesde,
               UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT DISTINCT p.IdUsuario, p.CodigoRol, p.IdUnidad, @Hoy,
               'sso', @Equipo, @Programa
          FROM @Puesto AS p
         WHERE p.IdUsuario IS NOT NULL
           AND p.CodigoRol IS NOT NULL
           AND p.IdUnidad  IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM sigcm.UsuarioRol AS ur
                            WHERE ur.IdUsuario = p.IdUsuario
                              AND ur.CodigoRol = p.CodigoRol
                              AND ur.IdUnidad  = p.IdUnidad
                              AND ur.Activo = 1
                              AND ur.VigenteHasta IS NULL);

        SET @AsignacionesAlta = @@ROWCOUNT;

        /* ---- Asignaciones: cierre por diferencia de conjuntos -------- */
        /*
          El movimiento que hace que la rotacion funcione. Ver la cabecera.

          SALVAGUARDA 2: el filtro por IdUsuarioSso NOT NULL. Los usuarios de
          prueba de S900 y las cuentas tecnicas no vienen del SSO y por lo tanto
          el SSO no puede darlos de baja. Sin esa condicion, la primera
          sincronizacion en un entorno con datos de prueba los borraria a todos.
        */
        IF @Completo = 1
        BEGIN
            /*
              SE CIERRA CON LAS DOS MARCAS: VigenteHasta Y Activo = 0.

              VigenteHasta sola no alcanza, y el defecto es sutil. El predicado
              de vigencia que usan todas las rutinas es

                  VigenteHasta IS NULL OR VigenteHasta >= hoy

              o sea que "vigente hasta hoy" TODAVIA VALE HOY. Una persona dada
              de baja y vuelta a dar de alta el mismo dia -o simplemente
              consultada el mismo dia de su baja- aparecia DOS VECES en la lista
              de derivacion: la fila cerrada seguia calificando junto con la
              nueva. Se vio en la prueba contra el padron real.

              Adelantar VigenteHasta un dia no sirve: una asignacion creada y
              cerrada el mismo dia violaria CK_sigcm_UsuarioRol_Vigencia. Y
              cambiar el predicado a > hoy obligaria a tocar F001, F004 y F006
              por un caso de borde. Activo = 0 es el borrado logico que la tabla
              ya declara (V001) y que todos los consumidores ya filtran: la fila
              deja de calificar en el acto y el rastro historico queda intacto.
            */
            UPDATE ur
               SET ur.VigenteHasta                  = @Hoy,
                   ur.Activo                        = 0,
                   ur.UsuarioModificacionAuditoria  = 'sso',
                   ur.FechaModificacionAuditoria    = @Ahora,
                   ur.EquipoModificacionAuditoria   = @Equipo,
                   ur.ProgramaModificacionAuditoria = @Programa
              FROM sigcm.UsuarioRol AS ur
              JOIN sigcm.Usuario    AS u ON u.IdUsuario = ur.IdUsuario
             WHERE u.IdUsuarioSso IS NOT NULL
               AND ur.Activo = 1
               AND ur.VigenteHasta IS NULL
               AND NOT EXISTS (SELECT 1 FROM @Puesto AS p
                                WHERE p.IdUsuario = ur.IdUsuario
                                  AND p.CodigoRol = ur.CodigoRol
                                  AND p.IdUnidad  = ur.IdUnidad);

            SET @AsignacionesBaja = @@ROWCOUNT;

            /* Una persona sin ninguna asignacion vigente ya no accede. No se
               borra: su rastro en expedientes y firmas tiene que sobrevivirle. */
            UPDATE u
               SET u.Activo                        = 0,
                   u.UsuarioModificacionAuditoria  = 'sso',
                   u.FechaModificacionAuditoria    = @Ahora,
                   u.EquipoModificacionAuditoria   = @Equipo,
                   u.ProgramaModificacionAuditoria = @Programa
              FROM sigcm.Usuario AS u
             WHERE u.IdUsuarioSso IS NOT NULL
               AND u.Activo = 1
               AND NOT EXISTS (SELECT 1 FROM sigcm.UsuarioRol AS ur
                                WHERE ur.IdUsuario = u.IdUsuario
                                  AND ur.Activo = 1
                                  AND ur.VigenteHasta IS NULL);
        END

        /* ---- Descartes: lo que llego y no se pudo aterrizar ---------- */
        /*
          Un perfil sin traduccion o un centro de costo sin unidad no son un
          error de la sincronizacion, pero tampoco pueden pasar en silencio: es
          gente que no va a poder entrar y alguien tiene que enterarse.
        */
        DECLARE @Descartes nvarchar(max) = (
            SELECT Cuenta         = p.Cuenta,
                   NombreCompleto = CONCAT_WS(' ', p.Nombres, p.Apellidos),
                   CodigoPerfilSso = p.CodigoPerfilSso,
                   Perfil         = p.NombrePerfil,
                   CentroCosto    = p.CentroCosto,
                   Motivo         = CASE WHEN p.CodigoRol IS NULL
                                         THEN 'El cod_perfil no esta mapeado en sigcm.PerfilSso.'
                                         ELSE 'El centro de costo no corresponde a ninguna unidad activa.' END
              FROM @Puesto AS p
             WHERE p.CodigoRol IS NULL OR p.IdUnidad IS NULL
             ORDER BY p.Cuenta
               FOR JSON PATH);

        SET @Descartes = COALESCE(@Descartes, '[]');

        INSERT INTO sigcm.SincronizacionSso
              (Disparador, CuentaDisparo, PadronRecibido, UnidadesAlta, UsuariosAlta,
               AsignacionesAlta, AsignacionesBaja, Descartes)
        VALUES (@Disparador, @CuentaDisparo, @Recibidos, @UnidadesAlta, @UsuariosAlta,
                @AsignacionesAlta, @AsignacionesBaja, @Descartes);

        COMMIT TRANSACTION; SET @TranPropia = 0;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   'OK' AS mensaje,
                   Resumen = JSON_QUERY((
                       SELECT PadronRecibido   = @Recibidos,
                              UnidadesAlta     = @UnidadesAlta,
                              UsuariosAlta     = @UsuariosAlta,
                              AsignacionesAlta = @AsignacionesAlta,
                              AsignacionesBaja = @AsignacionesBaja,
                              Completo         = @Completo
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                   Descartes = JSON_QUERY(@Descartes)
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @TranPropia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

/* ========================================================================== */
/* 3. sigcm.paListarPerfilSso                                                 */
/* ========================================================================== */

/*
  Entrada: { "Cuenta":"44687266" }
  Salida : { "estado":1, "Perfiles":[ ... ], "mensaje":"OK" }

  Las ternas vigentes de UNA cuenta, ya sincronizadas. No es lo mismo que
  paListarPerfilAcceso, que enumera las de todo el mundo y por eso solo puede
  existir con acceso_local encendido: esta responde por quien ya se autentico
  contra el SSO y no revela a nadie mas.

  Existe porque el frontend consume detalle[0].perfil[0]: una sesion lleva UNA
  terna. Quien ejerce dos -hoy la coordinadora que atiende UDS y
  Abastecimiento- tiene que elegir con cual entra, igual que en /acceso-local.
*/
CREATE OR ALTER PROCEDURE sigcm.paListarPerfilSso
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF @parametro IS NULL OR ISJSON(@parametro) <> 1
            THROW 51610, 'JSON incorrecto.', 1;

        DECLARE @Cuenta varchar(120);
        SELECT @Cuenta = Cuenta FROM OPENJSON(@parametro) WITH (Cuenta varchar(120));

        IF NULLIF(LTRIM(RTRIM(@Cuenta)), '') IS NULL
            THROW 51611, 'VALIDACION_PAYLOAD: falta Cuenta.', 1;

        DECLARE @Hoy date = CONVERT(date, GETDATE());

        DECLARE @Datos nvarchar(max) = (
            SELECT Cuenta         = u.Cuenta,
                   NombreCompleto = CONCAT_WS(' ', u.Nombres, u.Apellidos),
                   Cargo          = u.Cargo,
                   CodigoRol      = ur.CodigoRol,
                   Rol            = r.Nombre,
                   CodigoUnidad   = n.Codigo,
                   Unidad         = n.Nombre,
                   Sigla          = n.Sigla,
                   CentroCosto    = n.CentroCostoSiga,
                   EsAreaUsuaria  = n.EsAreaUsuaria,
                   EsTitular      = ur.EsTitular
              FROM sigcm.UsuarioRol AS ur
              JOIN sigcm.Usuario    AS u ON u.IdUsuario = ur.IdUsuario
              JOIN sigcm.Unidad     AS n ON n.IdUnidad  = ur.IdUnidad
              JOIN sigcm.Rol        AS r ON r.CodigoRol = ur.CodigoRol
             WHERE u.Cuenta = @Cuenta
               AND u.Activo = 1 AND n.Activo = 1 AND ur.Activo = 1 AND r.Activo = 1
               AND r.EsTecnico = 0
               AND ur.VigenteDesde <= @Hoy
               AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @Hoy)
             ORDER BY n.Nombre, r.Nombre
               FOR JSON PATH);

        SELECT @resultado = (
            SELECT 1 AS estado,
                   JSON_QUERY(COALESCE(@Datos, '[]')) AS Perfiles,
                   'OK' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo,
                   JSON_QUERY('[]') AS Perfiles
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

/* ========================================================================== */
/* 4. sigcm.paListarDestinatarioDerivacion                                    */
/* ========================================================================== */

/*
  Entrada: { "Actor":{...}, "IdExpediente":"...", "CodigoModulo":"CMN",
             "CodigoTransicion":"CMN_ABAST_JEFE_DERIVAR" }
  Salida : { "estado":1, "Puestos":[ { ..., "Personas":[...] } ], "mensaje":"OK" }

  Agrupado por PUESTO y con las personas adentro, porque es la forma que la
  pantalla necesita: primero se elige el escalon -coordinador o especialista- y
  despues, solo si el puesto tiene mas de un ocupante, a quien. Con un solo
  ocupante la pantalla puede resolverlo sin preguntar.

  El modulo sale del expediente cuando se manda IdExpediente. Pedirlo aparte
  seria dejar que el cliente diga que un expediente de CMN es de Requerimiento y
  se lleve el arbol equivocado.

  CODIGOTRANSICION ES OPCIONAL Y CAMBIA LA PREGUNTA
  Sin el, la respuesta es "a quien puede derivar este rol en este modulo": el
  arbol completo, util para una pantalla de consulta.
  Con el, se acota al rol que declara el ESTADO DESTINO de esa transicion, que
  es lo unico que paEjecutarTransicion va a aceptar despues. Una transicion que
  no es una derivacion devuelve la lista vacia, y con eso la pantalla sabe que no
  tiene nada que preguntar.

  El filtro va aqui y no en el cliente a proposito. Si el frontend cruzara la
  lista contra el rol destino estaria reimplementando un pedazo de la maquina de
  estados en TypeScript, que es exactamente lo que este proyecto decidio no
  hacer. La pantalla pinta lo que recibe.
*/
CREATE OR ALTER PROCEDURE sigcm.paListarDestinatarioDerivacion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF @parametro IS NULL OR ISJSON(@parametro) <> 1
            THROW 51620, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120),
                @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier,
                @CentroCosto varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50),
                @CorrelacionId uniqueidentifier;

        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCosto OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        DECLARE @IdExpediente uniqueidentifier, @CodigoModulo varchar(30),
                @CodigoTransicion varchar(70);

        SELECT @IdExpediente     = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @CodigoModulo     = CodigoModulo,
               @CodigoTransicion = CodigoTransicion
        FROM OPENJSON(@parametro)
        WITH (IdExpediente varchar(50), CodigoModulo varchar(30),
              CodigoTransicion varchar(70));

        IF @IdExpediente IS NOT NULL
            SELECT @CodigoModulo = e.CodigoModulo
              FROM sigcm.Expediente AS e
             WHERE e.IdExpediente = @IdExpediente;

        IF NULLIF(LTRIM(RTRIM(@CodigoModulo)), '') IS NULL
            THROW 51621, 'VALIDACION_PAYLOAD: falta CodigoModulo o IdExpediente.', 1;

        /* El rol al que quedara el expediente despues de la accion. Es el mismo
           que paEjecutarTransicion exigira del destinatario elegido, y por eso
           se lee del estado destino y no de un parametro: que el cliente pudiera
           decirlo convertiria el filtro en una sugerencia. */
        DECLARE @RolDestino varchar(40) = NULL;

        IF NULLIF(LTRIM(RTRIM(@CodigoTransicion)), '') IS NOT NULL
        BEGIN
            SELECT @RolDestino = d.RolResponsable
              FROM sigcm.Transicion AS t
              JOIN sigcm.Estado     AS d ON d.CodigoEstado = t.CodigoEstadoDestino
             WHERE t.CodigoTransicion = @CodigoTransicion
               AND t.CodigoModulo     = @CodigoModulo
               AND t.Activo = 1;

            /* Transicion que no lleva a ningun rol responsable -o que no existe
               en este modulo-: no hay a quien derivar. Se responde vacio en vez
               de ignorar el filtro, que ofreceria destinatarios que la
               transicion despues rechazaria. */
            IF @RolDestino IS NULL
            BEGIN
                SELECT @resultado = (
                    SELECT 1 AS estado, JSON_QUERY('[]') AS Puestos, 'OK' AS mensaje
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

                SELECT @resultado;
                RETURN;
            END
        END

        DECLARE @Datos nvarchar(max) = (
            SELECT CodigoRol    = d.CodigoRol,
                   Rol          = d.Rol,
                   Alcance      = d.Alcance,
                   Orden        = d.Orden,
                   CodigoUnidad = d.CodigoUnidad,
                   Unidad       = d.Unidad,
                   Sigla        = d.Sigla,
                   CentroCosto  = d.CentroCosto,
                   Ocupantes    = COUNT(*),
                   Personas = JSON_QUERY((
                       SELECT IdUsuario      = CONVERT(varchar(50), i.IdUsuario),
                              Cuenta         = i.Cuenta,
                              NombreCompleto = i.NombreCompleto,
                              Cargo          = i.Cargo,
                              Correo         = i.Correo,
                              EsTitular      = i.EsTitular
                         FROM sigcm.fnDestinatarioDerivacion(@CodigoModulo, @CodigoRol, @IdUnidad) AS i
                        WHERE i.CodigoRol = d.CodigoRol AND i.IdUnidad = d.IdUnidad
                        ORDER BY i.NombreCompleto
                          FOR JSON PATH))
              FROM sigcm.fnDestinatarioDerivacion(@CodigoModulo, @CodigoRol, @IdUnidad) AS d
             WHERE @RolDestino IS NULL OR d.CodigoRol = @RolDestino
             GROUP BY d.CodigoRol, d.Rol, d.Alcance, d.Orden,
                      d.IdUnidad, d.CodigoUnidad, d.Unidad, d.Sigla, d.CentroCosto
             ORDER BY d.Orden, d.Rol
               FOR JSON PATH);

        SELECT @resultado = (
            SELECT 1 AS estado,
                   JSON_QUERY(COALESCE(@Datos, '[]')) AS Puestos,
                   'OK' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo,
                   JSON_QUERY('[]') AS Puestos
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

PRINT 'F008 aplicada: padron del SSO y destinatarios de derivacion.';
GO
