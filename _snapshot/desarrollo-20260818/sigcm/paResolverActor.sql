/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paResolverActor
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
CREATE   PROCEDURE sigcm.paResolverActor
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
    SET XACT_ABORT ON;

    DECLARE @Usuario varchar(120), @Rol varchar(40), @Unidad varchar(30),
            @CorrelacionTexto varchar(50), @Hoy date, @msg nvarchar(400);

    SET @Usuario          = sigcm.fnJsonTexto(@parametro, 'Actor.Usuario');
    SET @Rol              = sigcm.fnJsonTexto(@parametro, 'Actor.Rol');
    SET @Unidad           = sigcm.fnJsonTexto(@parametro, 'Actor.Unidad');
    SET @Ip               = sigcm.fnJsonTexto(@parametro, 'Actor.Ip');
    SET @Equipo           = sigcm.fnJsonTexto(@parametro, 'Actor.Equipo');
    SET @Programa         = sigcm.fnJsonTexto(@parametro, 'Actor.Programa');
    SET @CorrelacionTexto = sigcm.fnJsonTexto(@parametro, 'Actor.CorrelacionId');

    IF NULLIF(LTRIM(RTRIM(@Usuario)), '') IS NULL
    BEGIN
        RAISERROR('VALIDACION_ACTOR: falta Actor.Usuario. El backend debe completarlo desde la sesion SSO.', 16, 1);
        RETURN;
    END
    IF NULLIF(LTRIM(RTRIM(@Rol)), '') IS NULL
    BEGIN
        RAISERROR('VALIDACION_ACTOR: falta Actor.Rol.', 16, 1);
        RETURN;
    END
    IF NULLIF(LTRIM(RTRIM(@Unidad)), '') IS NULL
    BEGIN
        RAISERROR('VALIDACION_ACTOR: falta Actor.Unidad.', 16, 1);
        RETURN;
    END

    /* Una correlacion invalida no debe tumbar la operacion: se genera una. */
    SET @CorrelacionId = sigcm.fnTryGuid(@CorrelacionTexto);
    IF @CorrelacionId IS NULL SET @CorrelacionId = NEWID();

    SET @Hoy = CONVERT(date, GETDATE());

    SELECT
        @IdUsuario      = u.IdUsuario,
        @Cuenta         = u.Cuenta,
        @NombreCompleto = LTRIM(RTRIM(ISNULL(u.Nombres, '') + N' ' + ISNULL(u.Apellidos, ''))),
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
        SET @msg = 'NO_AUTORIZADO: la cuenta ' + ISNULL(@Usuario, '') + ' no ejerce hoy el rol '
                 + ISNULL(@Rol, '') + ' en la unidad ' + ISNULL(@Unidad, '') + '.';
        RAISERROR(@msg, 16, 1);
        RETURN;
    END

    /* Las cuentas tecnicas de integracion y conciliacion no operan el flujo
       institucional. Existen para el worker, no para pantallas. */
    IF EXISTS (SELECT 1 FROM sigcm.Rol WHERE CodigoRol = @CodigoRol AND EsTecnico = 1)
    BEGIN
        RAISERROR('NO_AUTORIZADO: es una cuenta tecnica y no puede ejecutar acciones del flujo.', 16, 1);
        RETURN;
    END
END
GO
