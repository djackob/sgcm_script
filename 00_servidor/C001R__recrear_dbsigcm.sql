/*
===============================================================================
  SIGCM - C001R : RECREAR la base DBSIGCM desde cero
  Motor  : SQL Server 2022 (16.x) o superior
  Ambito : se ejecuta en [master]

  *** ESTE SCRIPT DESTRUYE DATOS. ***

  A diferencia de C001, que es idempotente y respeta la base existente, este
  script la BORRA y la vuelve a crear. Existe para una sola cosa: rearmar el
  entorno local de desarrollo igual al servidor de desarrollo del ANIN, sin
  arrastrar objetos huerfanos de instalaciones anteriores.

  NO se ejecuta en desarrollo compartido, QA ni produccion. Ahi va C001.

  PROTECCION
  ----------
  Exige la variable sqlcmd 'recrear' con el valor SI:

      sqlcmd -S "<servidor>" -d master -E -b ^
             -v recrear="SI" -i C001R__recrear_dbsigcm.sql

  Sin esa variable, sqlcmd aborta con "scripting variable not defined" y no
  llega a ejecutar nada. Abrirlo en SSMS sin el modo SQLCMD tambien falla, que
  es justamente lo que se quiere de un script destructivo.

  QUE REPRODUCE DEL SERVIDOR DE DESARROLLO
  ----------------------------------------
  Medido con C000B el 2026-08-18 contra 192.168.40.71:

      Motor            SQL Server 2022 - 16.0.4262.2 (CU25), Developer, Linux
      Collation DBSIGCM   Modern_Spanish_CI_AS
      Compat level     160
      RCSI             activo
      Recovery         SIMPLE

  La intercalacion no se cablea: se lee de la base SIGA de ESTA instancia, igual
  que en C001. En ambos entornos SIGA_1750 usa Modern_Spanish_CI_AS, asi que el
  resultado coincide con desarrollo por construccion y no por coincidencia.

  El compat 160 es lo que impide que el motor local (2025, version 17) acepte
  construcciones que desarrollo rechazaria.
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @confirmacion nvarchar(20) = N'$(recrear)';
DECLARE @bdSiga  sysname = N'SIGA_1750';
DECLARE @bdSigcm sysname = N'DBSIGCM';

IF UPPER(@confirmacion) <> N'SI'
BEGIN
    RAISERROR(N'C001R no ejecutado: hay que pasar -v recrear="SI" de forma explicita.', 16, 1);
    SET NOEXEC ON;
END

IF DB_NAME() <> N'master'
BEGIN
    RAISERROR(N'C001R debe ejecutarse en [master]. No se puede borrar la base a la que se esta conectado.', 16, 1);
    SET NOEXEC ON;
END

/* -------------------------------------------------------------------------- */
/* 1. Descubrir la intercalacion de SIGA (misma logica que C001)              */
/* -------------------------------------------------------------------------- */

IF DB_ID(@bdSiga) IS NULL
BEGIN
    RAISERROR(N'No existe la base SIGA indicada. Reejecuta con -v bdSiga="<nombre real>".', 16, 1);
    SET NOEXEC ON;
END

DECLARE @collation sysname = CONVERT(sysname, DATABASEPROPERTYEX(@bdSiga, 'Collation'));

IF @collation IS NULL
BEGIN
    RAISERROR(N'No se pudo leer la intercalacion de la base SIGA.', 16, 1);
    SET NOEXEC ON;
END

PRINT 'Intercalacion descubierta en ' + @bdSiga + ' : ' + @collation;

/* -------------------------------------------------------------------------- */
/* 2. Borrar la base existente                                                */
/* -------------------------------------------------------------------------- */

DECLARE @sql nvarchar(max);

IF DB_ID(@bdSigcm) IS NOT NULL
BEGIN
    PRINT 'Borrando ' + @bdSigcm + ' ...';

    /* SINGLE_USER con ROLLBACK IMMEDIATE echa a cualquier sesion abierta (una
       ventana de SSMS olvidada, el backend corriendo). Sin esto, el DROP se
       queda esperando indefinidamente. */
    SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
    EXEC sys.sp_executesql @sql;

    SET @sql = N'DROP DATABASE ' + QUOTENAME(@bdSigcm) + N';';
    EXEC sys.sp_executesql @sql;

    PRINT @bdSigcm + ' borrada.';
END
ELSE
    PRINT @bdSigcm + ' no existia; se crea desde cero.';

/* -------------------------------------------------------------------------- */
/* 3. Crear la base con los parametros de desarrollo                          */
/* -------------------------------------------------------------------------- */

SET @sql = N'CREATE DATABASE ' + QUOTENAME(@bdSigcm) + N' COLLATE ' + @collation + N';';
PRINT 'Creando: ' + @sql;
EXEC sys.sp_executesql @sql;

SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET COMPATIBILITY_LEVEL = 160;';
EXEC sys.sp_executesql @sql;

SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;';
EXEC sys.sp_executesql @sql;

SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET RECOVERY SIMPLE;';
EXEC sys.sp_executesql @sql;

SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET AUTO_CLOSE OFF, AUTO_SHRINK OFF, AUTO_CREATE_STATISTICS ON, AUTO_UPDATE_STATISTICS ON;';
EXEC sys.sp_executesql @sql;

PRINT @bdSigcm + ' creada.';

/* -------------------------------------------------------------------------- */
/* 4. Verificar contra la linea base de desarrollo                            */
/* -------------------------------------------------------------------------- */

DECLARE @collSigcm sysname = CONVERT(sysname, DATABASEPROPERTYEX(@bdSigcm, 'Collation'));
DECLARE @compat int = (SELECT compatibility_level FROM sys.databases WHERE name = @bdSigcm);
DECLARE @rcsi bit  = (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE name = @bdSigcm);

IF @collSigcm <> @collation
BEGIN
    DECLARE @err nvarchar(400) =
        N'La base ' + @bdSigcm + N' quedo con intercalacion ' + @collSigcm
      + N' pero ' + @bdSiga + N' usa ' + @collation + N'. Error 468 asegurado en los joins cruzados.';
    RAISERROR(@err, 16, 1);
END

IF @compat <> 160
    RAISERROR(N'La base no quedo en compat 160. Los scripts no reproducen la linea base de desarrollo.', 16, 1);

IF @rcsi <> 1
    RAISERROR(N'RCSI no quedo activo.', 16, 1);

SELECT d.name                            AS base,
       d.collation_name                  AS intercalacion,
       d.compatibility_level             AS compat_level,
       d.recovery_model_desc             AS recovery,
       d.is_read_committed_snapshot_on   AS rcsi,
       d.is_auto_close_on                AS auto_close,
       d.is_auto_shrink_on               AS auto_shrink
  FROM sys.databases d
 WHERE d.name IN (@bdSigcm, @bdSiga)
 ORDER BY d.name;

PRINT '';
PRINT 'Base recreada y alineada con desarrollo. Continuar con C003__sinonimos_siga.sql.';

SET NOEXEC OFF;
GO
