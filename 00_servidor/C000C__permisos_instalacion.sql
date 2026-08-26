/*
===============================================================================
  SIGCM - C000C : Permisos de la cuenta que va a instalar
  Motor  : SQL Server 2016 (13.x) o superior
  Ambito : se ejecuta en [master]
  Modo   : SOLO LECTURA. No contiene INSERT, UPDATE, DELETE ni DDL.

  Existe porque la instalacion en desarrollo se hace con una cuenta que no
  controlamos, y el archivo de credenciales del ANIN dice "Permiso: Lectura
  (verificar si es de escritura tambien)". Con solo lectura la serie muere en
  C001, que necesita CREATE DATABASE, despues de haber pedido la contrasena y
  de haber hecho perder el viaje.

  Este script responde antes de empezar: esta cuenta, en este servidor, puede
  instalar o no. No verifica version ni intercalacion ni tablas de SIGA; de eso
  se encarga C000__preflight.

  Uso:
    sqlcmd -S "<servidor>" -d master -U <usuario> -i C000C__permisos_instalacion.sql
===============================================================================
*/

SET NOCOUNT ON;

DECLARE @bdSiga  sysname = N'SIGA_1750';
DECLARE @bdSigcm sysname = N'DBSIGCM';

DECLARE @errores int = 0;
DECLARE @avisos  int = 0;

PRINT '===============================================================';
PRINT ' SIGCM - Permisos de instalacion';
PRINT ' Servidor : ' + CONVERT(nvarchar(200), SERVERPROPERTY('ServerName'));
PRINT ' Fecha    : ' + CONVERT(nvarchar(30), SYSDATETIME(), 120);
PRINT '===============================================================';
PRINT '';

/* -------------------------------------------------------------------------- */
/* 1. Quien soy                                                               */
/* -------------------------------------------------------------------------- */

PRINT '--- 1. Identidad ---';
PRINT '  Login          : ' + SUSER_SNAME();
PRINT '  Usuario en BD  : ' + USER_NAME();
PRINT '  Autenticacion  : ' +
      CASE WHEN SUSER_SNAME() LIKE '%\%' THEN 'Windows (integrada)' ELSE 'SQL Server' END;
PRINT '';

/* -------------------------------------------------------------------------- */
/* 2. Roles de servidor                                                       */
/* -------------------------------------------------------------------------- */

DECLARE @esSysadmin  int = IS_SRVROLEMEMBER('sysadmin');
DECLARE @esDbcreator int = IS_SRVROLEMEMBER('dbcreator');

PRINT '--- 2. Roles de servidor ---';
PRINT '  sysadmin       : ' + CASE @esSysadmin  WHEN 1 THEN 'SI' ELSE 'no' END;
PRINT '  dbcreator      : ' + CASE @esDbcreator WHEN 1 THEN 'SI' ELSE 'no' END;
PRINT '';

/* -------------------------------------------------------------------------- */
/* 3. Lo que C001 necesita: crear la base                                     */
/* -------------------------------------------------------------------------- */

DECLARE @existeSigcm bit = CASE WHEN DB_ID(@bdSigcm) IS NULL THEN 0 ELSE 1 END;
DECLARE @puedeCrear  int = HAS_PERMS_BY_NAME(NULL, NULL, 'CREATE ANY DATABASE');

PRINT '--- 3. Creacion de ' + @bdSigcm + ' ---';
PRINT '  La base ya existe        : ' + CASE @existeSigcm WHEN 1 THEN 'SI' ELSE 'no' END;
PRINT '  CREATE ANY DATABASE      : ' + CASE @puedeCrear  WHEN 1 THEN 'SI' ELSE 'no' END;

IF @existeSigcm = 1
BEGIN
    /* Si ya existe, C001 no la recrea; lo que hace falta es poder alterarla y
       escribir dentro. */
    DECLARE @rolEnSigcm nvarchar(200) = N'(no se pudo determinar)';
    DECLARE @sql nvarchar(400) = N'
        SELECT @r = CASE
                 WHEN IS_ROLEMEMBER(''db_owner'') = 1 THEN N''db_owner''
                 WHEN IS_ROLEMEMBER(''db_ddladmin'') = 1 THEN N''db_ddladmin''
                 WHEN IS_ROLEMEMBER(''db_datawriter'') = 1 THEN N''db_datawriter''
                 WHEN USER_ID() IS NULL THEN N''(sin usuario en esa base)''
                 ELSE N''(solo lectura o menos)'' END;';

    /* sp_executesql corre en la base actual, que aqui es master. Calificandolo
       con el nombre de la base se evalua IS_ROLEMEMBER dentro de DBSIGCM, que
       es lo que interesa. */
    DECLARE @execEnSigcm nvarchar(300) = QUOTENAME(@bdSigcm) + N'.sys.sp_executesql';

    BEGIN TRY
        EXEC @execEnSigcm
             @stmt = @sql,
             @params = N'@r nvarchar(200) OUTPUT',
             @r = @rolEnSigcm OUTPUT;
    END TRY
    BEGIN CATCH
        SET @rolEnSigcm = N'(sin acceso a la base)';
    END CATCH

    PRINT '  Rol dentro de la base    : ' + @rolEnSigcm;

    IF @rolEnSigcm NOT IN (N'db_owner', N'db_ddladmin')
    BEGIN
        PRINT '  [ERROR] Las migraciones crean tablas y funciones; hace falta db_owner';
        PRINT '          o db_ddladmin dentro de ' + @bdSigcm + '.';
        SET @errores = @errores + 1;
    END
END
ELSE IF @puedeCrear = 0 AND @esSysadmin = 0 AND @esDbcreator = 0
BEGIN
    PRINT '  [ERROR] La base no existe y esta cuenta no puede crearla. C001 va a';
    PRINT '          fallar. Hace falta dbcreator, o que el DBA cree ' + @bdSigcm;
    PRINT '          vacia y nos de db_owner sobre ella.';
    SET @errores = @errores + 1;
END

PRINT '';

/* -------------------------------------------------------------------------- */
/* 4. Lo que C003 necesita: leer SIGA                                         */
/* -------------------------------------------------------------------------- */

PRINT '--- 4. Lectura de ' + @bdSiga + ' ---';

IF DB_ID(@bdSiga) IS NULL
BEGIN
    PRINT '  [ERROR] No existe la base ' + @bdSiga + ' en este servidor, o esta';
    PRINT '          cuenta no la puede ver.';
    SET @errores = @errores + 1;
END
ELSE
BEGIN
    /* Los sinonimos de C003 se crean sin validar el destino, asi que un error
       de permisos aqui no aparece hasta que una vista consulta SIGA. Mejor
       enterarse ahora. */
    DECLARE @tabla sysname = N'SIG_CUADRO_NECESIDAD';
    DECLARE @puedeLeer int = NULL;
    DECLARE @sqlSiga nvarchar(600) = N'
        SELECT @p = HAS_PERMS_BY_NAME(N''' + QUOTENAME(@bdSiga) + N'.dbo.'
              + QUOTENAME(@tabla) + N''', ''OBJECT'', ''SELECT'');';
    BEGIN TRY
        EXEC sp_executesql
             @stmt = @sqlSiga,
             @params = N'@p int OUTPUT',
             @p = @puedeLeer OUTPUT;
    END TRY
    BEGIN CATCH
        SET @puedeLeer = NULL;
    END CATCH

    PRINT '  SELECT sobre dbo.' + @tabla + ' : ' +
          CASE WHEN @puedeLeer = 1 THEN 'SI'
               WHEN @puedeLeer = 0 THEN 'no'
               ELSE '(no se pudo determinar)' END;

    IF @puedeLeer = 0
    BEGIN
        PRINT '  [AVISO] Sin lectura sobre SIGA las vistas V004 y V012-V014 se';
        PRINT '          instalan pero devuelven error al consultarse. Hay que';
        PRINT '          ejecutar C002__acceso_lectura_siga.sql, que necesita';
        PRINT '          autorizacion del dueno de la base.';
        SET @avisos = @avisos + 1;
    END
END

PRINT '';

/* -------------------------------------------------------------------------- */
/* 5. Veredicto                                                               */
/* -------------------------------------------------------------------------- */

PRINT '===============================================================';
IF @errores > 0
BEGIN
    PRINT ' RESULTADO : NO SE PUEDE INSTALAR con esta cuenta.';
    PRINT ' Errores : ' + CONVERT(nvarchar(10), @errores)
        + '   Avisos : ' + CONVERT(nvarchar(10), @avisos);
    PRINT '===============================================================';
    RAISERROR(N'La cuenta no tiene permisos suficientes para instalar la serie.', 16, 1);
END
ELSE
BEGIN
    PRINT ' RESULTADO : la cuenta puede instalar la serie.';
    PRINT ' Avisos : ' + CONVERT(nvarchar(10), @avisos);
    PRINT '===============================================================';
END
