/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paObtenerSesion
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
CREATE   PROCEDURE sigcm.paObtenerSesion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF sigcm.fnEsJson(@parametro) <> 1
            RAISERROR('JSON incorrecto.', 16, 1);

        DECLARE @Cuenta varchar(120), @CodigoRol varchar(40), @CodigoUnidad varchar(30);

        SET @Cuenta       = sigcm.fnJsonTexto(@parametro, 'Cuenta');
        SET @CodigoRol    = sigcm.fnJsonTexto(@parametro, 'CodigoRol');
        SET @CodigoUnidad = sigcm.fnJsonTexto(@parametro, 'CodigoUnidad');

        IF NULLIF(LTRIM(RTRIM(@Cuenta)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta Cuenta.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@CodigoRol)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta CodigoRol.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@CodigoUnidad)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta CodigoUnidad.', 16, 1);

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
            DECLARE @msg nvarchar(400);
            SET @msg = 'NO_AUTORIZADO: la cuenta ' + ISNULL(@Cuenta, '') + ' no ejerce hoy el rol '
                     + ISNULL(@CodigoRol, '') + ' en la unidad ' + ISNULL(@CodigoUnidad, '') + '.';
            RAISERROR(@msg, 16, 1);
        END

        IF @EsTecnico = 1
            RAISERROR('NO_AUTORIZADO: es una cuenta tecnica y no abre sesion de pantalla.', 16, 1);

        /* Numeracion estable mientras no cambie el padron de cuentas. */
        DECLARE @IdNumerico int = (
            SELECT n.Fila FROM (
                SELECT IdUsuario, Fila = ROW_NUMBER() OVER (ORDER BY Cuenta)
                  FROM sigcm.Usuario
            ) AS n WHERE n.IdUsuario = @IdUsuario);

        DECLARE @OrdenRol int = (
            SELECT COUNT(*) FROM sigcm.Rol AS r2
             WHERE r2.CodigoRol <= @CodigoRol COLLATE DATABASE_DEFAULT);

        DECLARE @Nombres varchar(250), @Apellidos varchar(250),
                @CargoU varchar(180), @CuentaU varchar(120), @CorreoU varchar(200);
        DECLARE @DepNombre varchar(250), @DepCodigo varchar(30),
                @DepCentro varchar(15), @DepEsArea bit;
        DECLARE @RolNombre varchar(180);
        DECLARE @CorreoJson nvarchar(max), @MenuJson nvarchar(max),
                @PerfilJson nvarchar(max), @DetalleJson nvarchar(max),
                @SesionJson nvarchar(max);

        SELECT @Nombres = u.Nombres, @Apellidos = u.Apellidos,
               @CargoU = u.Cargo, @CuentaU = u.Cuenta, @CorreoU = u.Correo
          FROM sigcm.Usuario AS u
         WHERE u.IdUsuario = @IdUsuario;

        SELECT @DepNombre = n.Nombre, @DepCodigo = n.Codigo,
               @DepCentro = n.CentroCostoSiga, @DepEsArea = n.EsAreaUsuaria
          FROM sigcm.Unidad AS n
         WHERE n.IdUnidad = @IdUnidad;

        SELECT @RolNombre = r.Nombre
          FROM sigcm.Rol AS r
         WHERE r.CodigoRol = @CodigoRol;

        SET @CorreoJson = CASE WHEN @CorreoU IS NULL THEN N'[]'
                               ELSE N'[' + sigcm.fnJsonValorTexto(@CorreoU) + N']' END;

        SET @MenuJson = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"id_perfil_menu":'    + CASE WHEN m.Orden IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), m.Orden) END
                + N',"id_perfil_sistema":'+ ISNULL(CONVERT(nvarchar(20), @OrdenRol), N'null')
                + N',"id_menu":'          + CASE WHEN m.Orden IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), m.Orden) END
                + N',"nombre_menu":'      + sigcm.fnJsonValorTexto(m.Nombre)
                + N',"id_menu_padre":null'
                + N',"url":'              + sigcm.fnJsonValorTexto(m.Ruta)
                + N',"nivel":0'
                + N',"orden":'            + CASE WHEN m.Orden IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), m.Orden) END
                + N',"icono":'            + sigcm.fnJsonValorTexto(ISNULL(m.Icono, 'mdi mdi-file-document-outline'))
                + N',"es_componente":false'
                + N'}'
              FROM sigcm.RolModulo AS rm
              JOIN sigcm.Modulo    AS m ON m.CodigoModulo = rm.CodigoModulo
             WHERE rm.CodigoRol = @CodigoRol
               AND rm.Activo = 1 AND m.Activo = 1
               /* Sin ruta no hay pantalla que abrir; incluirlo
                  daria un menu que lleva a page-no-found. */
               AND m.Ruta IS NOT NULL
             ORDER BY m.Orden
               FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        /* perfil y detalle salen como ARREGLO (FOR JSON PATH sin WITHOUT_ARRAY_WRAPPER). */
        SET @PerfilJson = N'[{'
            + N'"id_perfil_sistema":' + ISNULL(CONVERT(nvarchar(20), @OrdenRol), N'null')
            + N',"id_sistema":73'
            + N',"id_perfil":'        + ISNULL(CONVERT(nvarchar(20), @OrdenRol), N'null')
            + N',"perfil":'           + sigcm.fnJsonValorTexto(@RolNombre)
            + N',"cod_perfil":'       + sigcm.fnJsonValorTexto(@CodigoRol)
            + N',"componente":[]'
            + N',"menu":'             + @MenuJson
            + N'}]';

        SET @DetalleJson = N'[{'
            + N'"id_acceso":'       + ISNULL(CONVERT(nvarchar(20), @IdNumerico), N'null')
            + N',"id_dependencia":1'
            + N',"dependencia":'    + sigcm.fnJsonValorTexto(@DepNombre)
            + N',"cod_dependencia":'+ sigcm.fnJsonValorTexto(@DepCodigo)
            + N',"centro_costo":'   + sigcm.fnJsonValorTexto(@DepCentro)
            + N',"es_area_usuaria":'+ CASE WHEN @DepEsArea IS NULL THEN N'null' WHEN @DepEsArea = 1 THEN N'true' ELSE N'false' END
            + N',"es_titular":'     + CASE WHEN @EsTitular IS NULL THEN N'null' WHEN @EsTitular = 1 THEN N'true' ELSE N'false' END
            + N',"perfil":'         + @PerfilJson
            + N'}]';

        SET @SesionJson = N'{'
            + N'"id_usuario":'         + ISNULL(CONVERT(nvarchar(20), @IdNumerico), N'null')
            + N',"id_padre":0'
            + N',"nombre":'            + sigcm.fnJsonValorTexto(@Nombres)
            + N',"apellido_paterno":'  + sigcm.fnJsonValorTexto(@Apellidos)
            + N',"apellido_materno":""'
            + N',"cargo":'             + sigcm.fnJsonValorTexto(@CargoU)
            + N',"cambio_clave":false'
            + N',"usuario":'           + sigcm.fnJsonValorTexto(@CuentaU)
            + N',"token":"@token"'
            + N',"fecha_modificacion":'+ sigcm.fnJsonValorTexto(CONVERT(varchar(19), GETDATE(), 126))
            + N',"origen":"LOCAL"'
            + N',"correo":'            + @CorreoJson
            + N',"telefono":[]'
            + N',"detalle":'           + @DetalleJson
            + N'}';

        SET @resultado = N'{"estado":1,"mensaje":"OK","Sesion":' + @SesionJson + N'}';

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
