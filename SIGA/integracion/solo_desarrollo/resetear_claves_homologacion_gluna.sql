/*
===============================================================================
  SIGA - Homologacion: igualar claves de todos los usuarios a la de GLUNA
  Ambito : [SIGA_1750]  (solo desarrollo / homologacion)

  Copia el valor cifrado de dbo.USERS.cpassword y dbo.SEG_USUARIO.PASSWORD
  desde GLUNA hacia el resto de usuarios. No altera privilegios ni menus.

  IMPORTANTE:
    - Suspende dbo.USERS_T1 (evita reconstruir SEG_ROL_* en masa).
    - No usar en produccion.
    - La clave en texto plano es la misma que ya usa GLUNA hoy en SIGA.

  Uso:
    sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" -i solo_desarrollo/resetear_claves_homologacion_gluna.sql
===============================================================================
*/

IF N'$(entorno)' <> N'DESARROLLO'
BEGIN
    RAISERROR(N'Solo desarrollo local. Este script no forma parte de instalar.ps1 y no pasa a produccion. Ejecute con -v entorno="DESARROLLO".', 16, 1);
    SET NOEXEC ON;
END
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Plantilla varchar(30) = 'GLUNA';
DECLARE @PwdUsers varchar(100);
DECLARE @PwdSeg varchar(30);
DECLARE @Vigencia datetime = '2027-12-31T23:59:59';
DECLARE @UsersActualizados int;
DECLARE @SegActualizados int;

IF NOT EXISTS (SELECT 1 FROM dbo.USERS WHERE cuser_id = @Plantilla AND cpassword IS NOT NULL)
BEGIN
    RAISERROR('RESET_CLAVES_FALLIDO: %s no tiene cpassword en dbo.USERS.', 16, 1, @Plantilla);
    RETURN;
END;

SELECT @PwdUsers = cpassword
  FROM dbo.USERS
 WHERE cuser_id = @Plantilla;

SELECT @PwdSeg = PASSWORD
  FROM dbo.SEG_USUARIO
 WHERE USUARIO = @Plantilla;

IF @PwdSeg IS NULL
    SET @PwdSeg = @PwdUsers;

BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.triggers WHERE object_id = OBJECT_ID('dbo.USERS_T1') AND is_disabled = 0)
        DISABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;

    BEGIN TRANSACTION;

    UPDATE dbo.USERS
       SET cpassword = @PwdUsers,
           cestado = 1,
           DT_VIGEN_FECHA = @Vigencia
     WHERE cpassword IS NULL
        OR cpassword <> @PwdUsers
        OR ISNULL(cestado, 0) <> 1
        OR DT_VIGEN_FECHA IS NULL
        OR DT_VIGEN_FECHA < @Vigencia;

    SET @UsersActualizados = @@ROWCOUNT;

    UPDATE dbo.SEG_USUARIO
       SET PASSWORD = @PwdSeg,
           ESTADO = 'A',
           CADUCIDAD = 'N',
           BLOQUEO = 'N',
           FECHA_BLOQUEO = NULL
     WHERE PASSWORD IS NULL
        OR PASSWORD <> @PwdSeg
        OR ISNULL(ESTADO, '') <> 'A'
        OR ISNULL(CADUCIDAD, '') <> 'N'
        OR ISNULL(BLOQUEO, '') <> 'N'
        OR FECHA_BLOQUEO IS NOT NULL;

    SET @SegActualizados = @@ROWCOUNT;

    COMMIT TRANSACTION;

    PRINT '=== Claves igualadas a GLUNA (homologacion) ===';
    PRINT 'USERS actualizados     : ' + CONVERT(varchar(10), @UsersActualizados);
    PRINT 'SEG_USUARIO actualizados: ' + CONVERT(varchar(10), @SegActualizados);
    PRINT 'Vigencia extendida hasta: ' + CONVERT(varchar(10), @Vigencia, 120);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @err nvarchar(4000) = ERROR_MESSAGE();
    RAISERROR('RESET_CLAVES_FALLIDO: %s', 16, 1, @err);
END CATCH;

IF EXISTS (SELECT 1 FROM sys.triggers WHERE object_id = OBJECT_ID('dbo.USERS_T1') AND is_disabled = 1)
    ENABLE TRIGGER dbo.USERS_T1 ON dbo.USERS;
GO

PRINT '';
PRINT 'Verificacion (muestra): todos deben coincidir con GLUNA.';
SELECT TOP 5
       u.cuser_id,
       CASE WHEN u.cpassword = g.cpassword THEN 'OK' ELSE 'DISTINTO' END AS users_pwd,
       CASE WHEN s.PASSWORD = gs.PASSWORD THEN 'OK' ELSE 'DISTINTO' END AS seg_pwd
  FROM dbo.USERS AS u
  JOIN dbo.USERS AS g ON g.cuser_id = 'GLUNA'
  LEFT JOIN dbo.SEG_USUARIO AS s ON s.USUARIO = u.cuser_id
  LEFT JOIN dbo.SEG_USUARIO AS gs ON gs.USUARIO = 'GLUNA'
 WHERE u.cuser_id IN ('GLUNA', 'HBOJORQUEZ', 'IRIVERA', 'SIGAMEF', 'GGONZALES')
 ORDER BY u.cuser_id;
GO
