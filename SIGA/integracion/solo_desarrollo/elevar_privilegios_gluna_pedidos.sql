/*
===============================================================================
  SIGA - Elevar privilegios de GLUNA en Pedidos (homologacion)
  Ambito : [SIGA_1750]

  Problema:
    SIGAMEF es plantilla con MANTENIMIENTO=1 (operacion basica). En la pantalla
    "Pedidos de Compra B/S" (pagina 03010200) hace falta privilegio 2 para
    editar "Valor autorizado".

  Solucion:
    Copia niveles MANTENIMIENTO mas altos desde un usuario operativo real
    (JMARINO) y reconstruye SEG_ROL_PAGINA_PRIVILEGIO del rol GLUNA.

  Uso:
    sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" -i solo_desarrollo/elevar_privilegios_gluna_pedidos.sql
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

DECLARE @Destino    varchar(30) = 'GLUNA';
DECLARE @Referencia varchar(30) = 'JMARINO';
DECLARE @Plantilla  varchar(30) = 'SIGAMEF';
DECLARE @SecEjec    decimal(6,0) = 1750;
DECLARE @opcionesActualizadas int;
DECLARE @privReconstruidos int;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE g
       SET g.MANTENIMIENTO = r.MANTENIMIENTO
      FROM dbo.USERS_OPCION AS g
      JOIN dbo.USERS_OPCION AS r
        ON r.CUSER_ID = @Referencia
       AND g.CUSER_ID = @Destino
       AND g.CMENU_ID = r.CMENU_ID
       AND g.TITULO = r.TITULO
       AND g.TITULO_SEC = r.TITULO_SEC
       AND g.OPCION = r.OPCION
       AND g.SEC_EJEC = r.SEC_EJEC
     WHERE r.MANTENIMIENTO > g.MANTENIMIENTO;

    SET @opcionesActualizadas = @@ROWCOUNT;

    DELETE FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO
     WHERE UPPER(LTRIM(RTRIM(ROL))) = @Destino
       AND SEC_EJEC IN (0, @SecEjec);

    INSERT INTO dbo.SEG_ROL_PAGINA_PRIVILEGIO (PRIVILEGIO, ROL, PAGINA, SEC_EJEC)
    SELECT DISTINCT
           A.MANTENIMIENTO, @Destino, B.ORDEN, @SecEjec
      FROM dbo.USERS_OPCION AS A
      JOIN dbo.USERS_OPCION AS B
        ON B.CUSER_ID = @Plantilla
       AND A.CUSER_ID = @Destino
       AND A.TITULO = B.TITULO
       AND B.CMENU_ID = 20
       AND A.CMENU_ID = 20
       AND A.TITULO_SEC = B.TITULO_SEC
       AND A.OPCION = B.OPCION
     WHERE NOT A.MANTENIMIENTO IS NULL;

    SET @privReconstruidos = @@ROWCOUNT;

    INSERT INTO dbo.SEG_ROL_PAGINA_PRIVILEGIO (PRIVILEGIO, ROL, PAGINA, SEC_EJEC)
    SELECT 2, @Destino, 1020000, e.SEC_EJEC
      FROM dbo.SIG_EJECUTORA AS e
     WHERE e.SEC_EJEC = @SecEjec
       AND NOT EXISTS (
           SELECT 1
             FROM dbo.SEG_ROL_PAGINA_PRIVILEGIO AS p
            WHERE p.ROL = @Destino
              AND p.PAGINA = 1020000
              AND p.SEC_EJEC = e.SEC_EJEC);

    COMMIT TRANSACTION;

    PRINT '=== Privilegios elevados ===';
    PRINT CONCAT('Opciones actualizadas: ', @opcionesActualizadas);
    PRINT CONCAT('Paginas reconstruidas: ', @privReconstruidos);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @err nvarchar(4000) = ERROR_MESSAGE();
    RAISERROR('ELEVACION_FALLIDA: %s', 16, 1, @err);
    RETURN;
END CATCH;
GO

PRINT '';
PRINT '=== Verificacion (Pedidos de Compra B/S) ===';

SELECT a.opcion, a.nombre, a.mantenimiento, p.privilegio, p.pagina
  FROM dbo.USERS_OPCION AS a
  JOIN dbo.USERS_OPCION AS b
    ON b.CUSER_ID = 'SIGAMEF'
   AND b.CMENU_ID = 20
   AND a.CMENU_ID = 20
   AND a.TITULO = b.TITULO
   AND a.TITULO_SEC = b.TITULO_SEC
   AND a.OPCION = b.OPCION
  LEFT JOIN dbo.SEG_ROL_PAGINA_PRIVILEGIO AS p
    ON p.ROL = 'GLUNA'
   AND p.SEC_EJEC = 1750
   AND p.PAGINA = b.ORDEN
 WHERE a.CUSER_ID = 'GLUNA'
   AND a.TITULO = '03'
   AND a.TITULO_SEC = '00'
   AND a.OPCION IN ('02', '03', '04', '15')
 ORDER BY a.OPCION;

PRINT '';
PRINT 'Cierre SIGA y vuelva a entrar con GLUNA.';
GO
