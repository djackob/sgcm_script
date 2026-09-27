/*
===============================================================================
  SIGCM - F020 : Perfiles de area para el numeral 8.1 del Anexo 3
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Unidades activas y los perfiles que de verdad ejercen. El Anexo 3 arma con
  esto la ruta que el pago recorrera antes de la conformidad.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE requerimiento.paListarPerfilArea
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52001, 'JSON incorrecto.', 1;

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

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Unidades = JSON_QUERY(COALESCE((
                       SELECT u.IdUnidad, u.Codigo, u.Nombre,
                              Perfiles = JSON_QUERY((
                                  SELECT r.CodigoRol, r.Nombre
                                    FROM sigcm.Rol AS r
                                   WHERE r.Activo = 1
                                     AND r.EsTecnico = 0
                                     AND r.CodigoRol NOT IN ('PROVEEDOR', 'ADMIN_SISTEMA')
                                     AND EXISTS (
                                          SELECT 1
                                            FROM sigcm.UsuarioRol AS ur
                                           WHERE ur.IdUnidad = u.IdUnidad
                                             AND ur.CodigoRol = r.CodigoRol
                                             AND ur.Activo = 1
                                             AND (ur.VigenteHasta IS NULL
                                                  OR ur.VigenteHasta >= CONVERT(date, GETDATE())))
                                   ORDER BY r.Nombre
                                     FOR JSON PATH))
                         FROM sigcm.Unidad AS u
                        WHERE u.Activo = 1
                          AND EXISTS (
                               SELECT 1
                                 FROM sigcm.UsuarioRol AS ur
                                 JOIN sigcm.Rol AS r ON r.CodigoRol = ur.CodigoRol
                                WHERE ur.IdUnidad = u.IdUnidad
                                  AND ur.Activo = 1
                                  AND r.Activo = 1
                                  AND r.EsTecnico = 0
                                  AND r.CodigoRol NOT IN ('PROVEEDOR', 'ADMIN_SISTEMA')
                                  AND (ur.VigenteHasta IS NULL
                                       OR ur.VigenteHasta >= CONVERT(date, GETDATE())))
                        ORDER BY u.Nombre
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO
