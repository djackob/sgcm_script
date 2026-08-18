/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paListarPerfilAcceso
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
CREATE   PROCEDURE sigcm.paListarPerfilAcceso
    @parametro nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF @parametro IS NULL OR LTRIM(RTRIM(@parametro)) = '' SET @parametro = N'{}';
        IF sigcm.fnEsJson(@parametro) <> 1
            RAISERROR('JSON incorrecto.', 16, 1);

        DECLARE @Texto varchar(200), @Limite int;

        SET @Texto  = sigcm.fnJsonTexto(@parametro, 'Texto');
        SET @Limite = sigcm.fnJsonEntero(@parametro, 'Limite');

        SET @Limite = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 50
                           WHEN @Limite > 200 THEN 200 ELSE @Limite END;

        DECLARE @Hoy date = CONVERT(date, GETDATE());
        DECLARE @Datos nvarchar(max);

        SET @Datos = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"Cuenta":'         + sigcm.fnJsonValorTexto(t.Cuenta)
                + N',"NombreCompleto":'+ sigcm.fnJsonValorTexto(t.NombreCompleto)
                + N',"Cargo":'         + sigcm.fnJsonValorTexto(t.Cargo)
                + N',"CodigoRol":'     + sigcm.fnJsonValorTexto(t.CodigoRol)
                + N',"Rol":'           + sigcm.fnJsonValorTexto(t.Rol)
                + N',"CodigoUnidad":'  + sigcm.fnJsonValorTexto(t.CodigoUnidad)
                + N',"Unidad":'        + sigcm.fnJsonValorTexto(t.Unidad)
                + N',"Sigla":'         + sigcm.fnJsonValorTexto(t.Sigla)
                + N',"CentroCosto":'   + sigcm.fnJsonValorTexto(t.CentroCosto)
                + N',"EsAreaUsuaria":' + CASE WHEN t.EsAreaUsuaria IS NULL THEN N'null' WHEN t.EsAreaUsuaria = 1 THEN N'true' ELSE N'false' END
                + N',"EsTitular":'     + CASE WHEN t.EsTitular IS NULL THEN N'null' WHEN t.EsTitular = 1 THEN N'true' ELSE N'false' END
                + N',"Modulos":'       + t.Modulos
                + N'}'
            FROM (
                SELECT TOP (@Limite)
                       Cuenta         = u.Cuenta,
                       NombreCompleto = LTRIM(RTRIM(ISNULL(u.Nombres, '') + N' ' + ISNULL(u.Apellidos, ''))),
                       Cargo          = u.Cargo,
                       CodigoRol      = ur.CodigoRol,
                       Rol            = r.Nombre,
                       CodigoUnidad   = n.Codigo,
                       Unidad         = n.Nombre,
                       Sigla          = n.Sigla,
                       CentroCosto    = n.CentroCostoSiga,
                       EsAreaUsuaria  = n.EsAreaUsuaria,
                       EsTitular      = ur.EsTitular,
                       Modulos = N'[' + ISNULL(STUFF((
                           SELECT N',' + N'{'
                               + N'"CodigoModulo":' + sigcm.fnJsonValorTexto(m.CodigoModulo)
                               + N',"Nombre":'       + sigcm.fnJsonValorTexto(m.Nombre)
                               + N',"Ruta":'         + sigcm.fnJsonValorTexto(m.Ruta)
                               + N'}'
                             FROM sigcm.RolModulo AS rm
                             JOIN sigcm.Modulo    AS m ON m.CodigoModulo = rm.CodigoModulo
                            WHERE rm.CodigoRol = ur.CodigoRol
                              AND rm.Activo = 1 AND m.Activo = 1
                            ORDER BY m.Orden
                              FOR XML PATH(N''), TYPE
                       ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']'
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
                        OR LTRIM(RTRIM(ISNULL(u.Nombres, '') + N' ' + ISNULL(u.Apellidos, ''))) LIKE '%' + @Texto + '%'
                        OR r.Nombre LIKE '%' + @Texto + '%')
                 ORDER BY n.Nombre, r.Nombre, u.Cuenta
            ) AS t
              FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SET @resultado = N'{"estado":1,"Perfiles":' + ISNULL(@Datos, N'[]') + N',"mensaje":"OK"}';

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N',"Perfiles":[]}';
        SELECT @resultado;
    END CATCH
END
GO
