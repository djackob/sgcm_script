/*
===============================================================================
  SIGCM - F006 : Acceso y armado de la sesion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51500-51599

  QUE RESUELVE
  ------------
  En el ambiente de la ANIN la identidad la entrega el SSO institucional y el
  backend solo la traduce. Fuera de esa red no hay SSO al que preguntarle, y sin
  identidad no se puede recorrer ningun flujo: cada rutina de negocio empieza por
  sigcm.paResolverActor, que exige la terna usuario-rol-unidad vigente.

  Estos dos procedimientos separan las dos preguntas que el SSO respondia juntas:

    paListarPerfilAcceso  que ternas usuario-rol-unidad estan vigentes hoy.
                          Es la lista que el selector local ofrece en lugar de la
                          pantalla del SSO. NO autentica: no hay contrasenia que
                          verificar porque esta tabla nunca guarda contrasenias
                          (V001). La restringe el backend, con la bandera
                          acceso_local de appsettings, no la base.

    paObtenerSesion       dada una terna, arma el payload de sesion con la MISMA
                          forma que devuelve el SSO, para que el frontend, el
                          guard de rutas y el menu lateral no distingan de donde
                          vino la sesion. El menu sale de sigcm.RolModulo y de
                          sigcm.Modulo.Ruta (V007), que es la matriz de acceso
                          real, no una lista paralela.

  EL MARCADOR @token
  ------------------
  El campo token del payload sale con el literal '@token'. Es el contrato vigente
  en la ANIN: anin.scm.Services.TokenService.CreateToken firma el payload y
  sustituye ese marcador por el JWT resultante. La base no emite tokens.

  ADVERTENCIA DE ENTORNO
  ----------------------
  paListarPerfilAcceso enumera cuentas. En produccion el acceso se resuelve por
  SSO y este procedimiento no debe quedar expuesto: la bandera acceso_local del
  backend va en false y el endpoint responde 404. Ver Proyecto/ESTANDARES.md.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. sigcm.paListarPerfilAcceso                                             */
/* ========================================================================== */

/*
  Entrada:  { "Texto": "...", "Limite": 50 }   ambos opcionales
  Salida :  { "estado":1, "Perfiles":[ ... ], "mensaje":"OK" }

  Una fila por terna vigente, no por usuario: la misma persona puede ejercer dos
  roles (prueba.abastecim es coordinador y jefe) y son dos ingresos distintos,
  con acciones distintas. Colapsarlos por usuario haria imposible probar la mitad
  del flujo.
*/
CREATE OR ALTER PROCEDURE sigcm.paListarPerfilAcceso
    @parametro nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF @parametro IS NULL OR LTRIM(RTRIM(@parametro)) = '' SET @parametro = N'{}';
        IF ISJSON(@parametro) <> 1
            THROW 51500, 'JSON incorrecto.', 1;

        DECLARE @Texto varchar(200), @Limite int;

        SELECT @Texto = Texto, @Limite = Limite
        FROM OPENJSON(@parametro)
        WITH (Texto varchar(200), Limite int);

        SET @Limite = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50
                           WHEN @Limite > 200 THEN 200 ELSE @Limite END;

        DECLARE @Hoy date = CONVERT(date, GETDATE());

        DECLARE @Datos nvarchar(max) = (
            SELECT TOP (@Limite)
                   Cuenta         = u.Cuenta,
                   NombreCompleto = CONCAT_WS(' ', u.Nombres, u.Apellidos),
                   Cargo          = u.Cargo,
                   CodigoRol      = ur.CodigoRol,
                   Rol            = r.Nombre,
                   CodigoUnidad   = n.Codigo,
                   Unidad         = n.Nombre,
                   Sigla          = n.Sigla,
                   CentroCosto    = n.CentroCostoSiga,
                   EsAreaUsuaria  = n.EsAreaUsuaria,
                   EsTitular      = ur.EsTitular,
                   Modulos = JSON_QUERY(COALESCE((
                       SELECT m.CodigoModulo, m.Nombre, m.Ruta
                         FROM sigcm.RolModulo AS rm
                         JOIN sigcm.Modulo    AS m ON m.CodigoModulo = rm.CodigoModulo
                        WHERE rm.CodigoRol = ur.CodigoRol
                          AND rm.Activo = 1 AND m.Activo = 1
                        ORDER BY m.Orden
                          FOR JSON PATH), '[]'))
              FROM sigcm.UsuarioRol AS ur
              JOIN sigcm.Usuario    AS u ON u.IdUsuario  = ur.IdUsuario
              JOIN sigcm.Unidad     AS n ON n.IdUnidad   = ur.IdUnidad
              JOIN sigcm.Rol        AS r ON r.CodigoRol  = ur.CodigoRol
             WHERE u.Activo = 1 AND n.Activo = 1 AND ur.Activo = 1 AND r.Activo = 1
               /* Las cuentas tecnicas no operan pantallas (F001). Ofrecerlas en
                  el selector solo produce un NO_AUTORIZADO en la primera accion. */
               AND r.EsTecnico = 0
               AND ur.VigenteDesde <= @Hoy
               AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @Hoy)
               AND (@Texto IS NULL
                    OR u.Cuenta LIKE '%' + @Texto + '%'
                    OR CONCAT_WS(' ', u.Nombres, u.Apellidos) LIKE '%' + @Texto + '%'
                    OR r.Nombre LIKE '%' + @Texto + '%')
             ORDER BY n.Nombre, r.Nombre, u.Cuenta
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
/* 2. sigcm.paObtenerSesion                                                  */
/* ========================================================================== */

/*
  Entrada:  { "Cuenta":"...", "CodigoRol":"...", "CodigoUnidad":"...",
              "Ip":"...", "Equipo":"...", "Programa":"..." }
  Salida :  { "estado":1, "Sesion": { ... }, "mensaje":"OK" }

  La forma de "Sesion" es la del SSO institucional y no se negocia aqui: el
  frontend ya la consume en session.service, en el guard y en el menu lateral.
  Cambiarla obligaria a tocar tres piezas que hoy funcionan con el SSO real.

  id_usuario es un entero porque el guard comprueba id_usuario > 0 y la identidad
  del SIGCM es uniqueidentifier. Se numera por orden de cuenta; el identificador
  que importa para el negocio es la Cuenta, que viaja en "usuario" y es la que
  paResolverActor valida en cada accion.
*/
CREATE OR ALTER PROCEDURE sigcm.paObtenerSesion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51510, 'JSON incorrecto.', 1;

        DECLARE @Cuenta varchar(120), @CodigoRol varchar(40), @CodigoUnidad varchar(30);

        SELECT @Cuenta       = Cuenta,
               @CodigoRol    = CodigoRol,
               @CodigoUnidad = CodigoUnidad
        FROM OPENJSON(@parametro)
        WITH (Cuenta varchar(120), CodigoRol varchar(40), CodigoUnidad varchar(30));

        IF NULLIF(LTRIM(RTRIM(@Cuenta)), '') IS NULL
            THROW 51511, 'VALIDACION_PAYLOAD: falta Cuenta.', 1;
        IF NULLIF(LTRIM(RTRIM(@CodigoRol)), '') IS NULL
            THROW 51512, 'VALIDACION_PAYLOAD: falta CodigoRol.', 1;
        IF NULLIF(LTRIM(RTRIM(@CodigoUnidad)), '') IS NULL
            THROW 51513, 'VALIDACION_PAYLOAD: falta CodigoUnidad.', 1;

        DECLARE @Hoy date = CONVERT(date, GETDATE());

        DECLARE @IdUsuario uniqueidentifier, @IdUnidad uniqueidentifier,
                @EsTitular bit, @EsTecnico bit;

        SELECT @IdUsuario = u.IdUsuario,
               @IdUnidad  = n.IdUnidad,
               @EsTitular = ur.EsTitular,
               @EsTecnico = r.EsTecnico
          FROM sigcm.UsuarioRol AS ur
          JOIN sigcm.Usuario    AS u ON u.IdUsuario = ur.IdUsuario
          JOIN sigcm.Unidad     AS n ON n.IdUnidad  = ur.IdUnidad
          JOIN sigcm.Rol        AS r ON r.CodigoRol = ur.CodigoRol
         WHERE u.Cuenta = @Cuenta AND ur.CodigoRol = @CodigoRol AND n.Codigo = @CodigoUnidad
           AND u.Activo = 1 AND n.Activo = 1 AND ur.Activo = 1 AND r.Activo = 1
           AND ur.VigenteDesde <= @Hoy
           AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @Hoy);

        /* Mismo criterio que paResolverActor: no basta con existir, hay que
           ejercer ese rol en esa unidad hoy. Si la sesion se armara sin este
           control, el usuario entraria y fallaria en la primera accion. */
        IF @IdUsuario IS NULL
        BEGIN
            DECLARE @msg nvarchar(400) = CONCAT(
                'NO_AUTORIZADO: la cuenta ', @Cuenta, ' no ejerce hoy el rol ',
                @CodigoRol, ' en la unidad ', @CodigoUnidad, '.');
            THROW 51514, @msg, 1;
        END

        IF @EsTecnico = 1
            THROW 51515, 'NO_AUTORIZADO: es una cuenta tecnica y no abre sesion de pantalla.', 1;

        /* Numeracion estable mientras no cambie el padron de cuentas. */
        DECLARE @IdNumerico int = (
            SELECT n.Fila FROM (
                SELECT IdUsuario, Fila = ROW_NUMBER() OVER (ORDER BY Cuenta)
                  FROM sigcm.Usuario
            ) AS n WHERE n.IdUsuario = @IdUsuario);

        DECLARE @OrdenRol int = (
            SELECT COUNT(*) FROM sigcm.Rol AS r2
             WHERE r2.CodigoRol <= @CodigoRol COLLATE DATABASE_DEFAULT);

        SELECT @resultado = (
            SELECT 1 AS estado,
                   'OK' AS mensaje,
                   Sesion = JSON_QUERY((
                       SELECT id_usuario         = @IdNumerico,
                              id_padre           = 0,
                              nombre             = u.Nombres,
                              apellido_paterno   = u.Apellidos,
                              apellido_materno   = '',
                              cargo              = u.Cargo,
                              cambio_clave       = CONVERT(bit, 0),
                              usuario            = u.Cuenta,
                              token              = '@token',
                              fecha_modificacion = CONVERT(varchar(19), GETDATE(), 126),
                              origen             = 'LOCAL',
                              correo    = JSON_QUERY(CASE WHEN u.Correo IS NULL THEN '[]'
                                                          ELSE '["' + u.Correo + '"]' END),
                              telefono  = JSON_QUERY('[]'),
                              detalle = JSON_QUERY((
                                  SELECT id_acceso        = @IdNumerico,
                                         id_dependencia   = 1,
                                         dependencia      = n.Nombre,
                                         cod_dependencia  = n.Codigo,
                                         centro_costo     = n.CentroCostoSiga,
                                         es_area_usuaria  = n.EsAreaUsuaria,
                                         es_titular       = @EsTitular,
                                         perfil = JSON_QUERY((
                                             SELECT id_perfil_sistema = @OrdenRol,
                                                    id_sistema        = 73,
                                                    id_perfil         = @OrdenRol,
                                                    perfil            = r.Nombre,
                                                    cod_perfil        = r.CodigoRol,
                                                    componente = JSON_QUERY('[]'),
                                                    menu = JSON_QUERY(COALESCE((
                                                        SELECT id_perfil_menu    = m.Orden,
                                                               id_perfil_sistema = @OrdenRol,
                                                               id_menu           = m.Orden,
                                                               nombre_menu       = m.Nombre,
                                                               id_menu_padre     = NULL,
                                                               url               = m.Ruta,
                                                               nivel             = 0,
                                                               orden             = m.Orden,
                                                               icono             = ISNULL(m.Icono, 'mdi mdi-file-document-outline'),
                                                               es_componente     = CONVERT(bit, 0)
                                                          FROM sigcm.RolModulo AS rm
                                                          JOIN sigcm.Modulo    AS m ON m.CodigoModulo = rm.CodigoModulo
                                                         WHERE rm.CodigoRol = r.CodigoRol
                                                           AND rm.Activo = 1 AND m.Activo = 1
                                                           /* Sin ruta no hay pantalla que abrir; incluirlo
                                                              daria un menu que lleva a page-no-found. */
                                                           AND m.Ruta IS NOT NULL
                                                         ORDER BY m.Orden
                                                           FOR JSON PATH), '[]'))
                                               FROM sigcm.Rol AS r
                                              WHERE r.CodigoRol = @CodigoRol
                                                FOR JSON PATH))
                                    FROM sigcm.Unidad AS n
                                   WHERE n.IdUnidad = @IdUnidad
                                     FOR JSON PATH))
                         FROM sigcm.Usuario AS u
                        WHERE u.IdUsuario = @IdUsuario
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER))
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

PRINT 'F006 aplicada: acceso y armado de la sesion.';
GO
