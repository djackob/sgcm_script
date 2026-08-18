/*
===============================================================================
  SIGCM - C001 : Creacion de la base DBSIGCM
  Motor  : SQL Server 2016 (13.x) o superior
  Ambito : se ejecuta en [master]

  Requiere haber corrido C000__preflight.sql sin errores.

  DOS DECISIONES QUE ESTE SCRIPT MATERIALIZA
  ------------------------------------------
  1. La intercalacion NO se escribe como literal: se LEE de la base SIGA y se
     aplica por SQL dinamico. En el entorno local SIGA usa Modern_Spanish_CI_AS
     mientras el servidor usa SQL_Latin1_General_CP1_CI_AS; si DBSIGCM heredara
     la del servidor, todo join cruzado fallaria:

         Msg 468: Cannot resolve the collation conflict between
                  "Modern_Spanish_CI_AS" and "SQL_Latin1_General_CP1_CI_AS"

     De la intercalacion de produccion no se sabe nada, asi que se descubre.

  2. READ_COMMITTED_SNAPSHOT ON. Es nuestra base y no cuesta nada; evita que
     los lectores del SIGCM bloqueen a sus propios escritores. No arregla el
     lado de SIGA (que tiene RCSI desactivado y no se toca): eso se mitiga con
     NOLOCK en las vistas de maestros y con LOCK_TIMEOUT / DEADLOCK_PRIORITY en
     las rutinas.

  Idempotente: si la base ya existe, no la recrea; solo verifica y reporta.

  Uso:
    sqlcmd -S "<servidor>" -d master -E -i C001__crear_dbsigcm.sql
    sqlcmd -S "<servidor>" -d master -E -v bdSiga="SIGA_1750" -i C001__crear_dbsigcm.sql
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @bdSiga  sysname = N'SIGA_1750';
DECLARE @bdSigcm sysname = N'DBSIGCM';

/* -------------------------------------------------------------------------- */
/* 1. Descubrir la intercalacion de SIGA                                      */
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
/* 2. Crear la base                                                           */
/* -------------------------------------------------------------------------- */

DECLARE @sql nvarchar(max);

IF DB_ID(@bdSigcm) IS NULL
BEGIN
    SET @sql = N'CREATE DATABASE ' + QUOTENAME(@bdSigcm) + N' COLLATE ' + @collation + N';';
    PRINT 'Creando: ' + @sql;
    EXEC sys.sp_executesql @sql;

    /* Compat 160 = SQL Server 2022, que es la version confirmada del servidor de
       produccion del ANIN. Se fija aqui aunque el motor local sea 2025: la red
       que impide que se cuele el tipo json nativo, que es de 2025 y en
       produccion no existe. */
    SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET COMPATIBILITY_LEVEL = 160;';
    EXEC sys.sp_executesql @sql;

    SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;';
    EXEC sys.sp_executesql @sql;

    SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET RECOVERY SIMPLE;';
    EXEC sys.sp_executesql @sql;

    /* Sin cierre automatico ni autoshrink: ambos son fuente de latencia
       erratica y no aportan nada en una base de servicio. */
    SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET AUTO_CLOSE OFF, AUTO_SHRINK OFF, AUTO_CREATE_STATISTICS ON, AUTO_UPDATE_STATISTICS ON;';
    EXEC sys.sp_executesql @sql;

    PRINT @bdSigcm + ' creada.';
END
ELSE
    PRINT @bdSigcm + ' ya existe; no se recrea.';

/* El nivel de compatibilidad se reafirma exista o no la base: si una instalacion
   anterior quedo en otro valor, reejecutar C001 debe converger al de produccion
   y no dejarla como estaba. */
IF (SELECT compatibility_level FROM sys.databases WHERE name = @bdSigcm) <> 160
BEGIN
    SET @sql = N'ALTER DATABASE ' + QUOTENAME(@bdSigcm) + N' SET COMPATIBILITY_LEVEL = 160;';
    PRINT 'Ajustando nivel de compatibilidad a 160.';
    EXEC sys.sp_executesql @sql;
END

/* -------------------------------------------------------------------------- */
/* 3. Verificar                                                               */
/* -------------------------------------------------------------------------- */

DECLARE @collSigcm sysname = CONVERT(sysname, DATABASEPROPERTYEX(@bdSigcm, 'Collation'));

IF @collSigcm <> @collation
BEGIN
    DECLARE @err nvarchar(400) =
        N'La base ' + @bdSigcm + N' tiene intercalacion ' + @collSigcm
      + N' pero ' + @bdSiga + N' usa ' + @collation
      + N'. Los joins cruzados fallaran con el error 468. Hay que recrear la base.';
    RAISERROR(@err, 16, 1);
END

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
PRINT 'Listo. Continuar con C002__acceso_lectura_siga.sql.';

SET NOEXEC OFF;
GO
