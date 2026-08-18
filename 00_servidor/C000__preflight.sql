/*
===============================================================================
  SIGCM - C000 : Preflight del entorno
  Motor  : SQL Server 2016 (13.x) o superior
  Ambito : se ejecuta en [master]
  Modo   : SOLO LECTURA. No contiene INSERT, UPDATE, DELETE ni DDL.

  Este script es lo PRIMERO que se corre en cada entorno, y en particular es lo
  primero que se corre contra el servidor del ANIN. Su salida es tambien el
  informe que se les envia.

  Existe porque el entorno de desarrollo es una COPIA RESTAURADA de la base del
  ANIN sobre SQL Server 2025, y del servidor de produccion no se conoce version,
  edicion, intercalacion, nombre de base ni carga. Todo lo que el resto de los
  scripts asume debe verificarse aqui antes de instalar nada.

  Uso:
    sqlcmd -S "<servidor>" -d master -E -i C000__preflight.sql
    sqlcmd -S "<servidor>" -d master -E -v bdSiga="SIGA_1750" -i C000__preflight.sql
===============================================================================
*/

SET NOCOUNT ON;

/* Nombre de la base SIGA. En produccion muy probablemente NO sea SIGA_1750:
   ese nombre codifica la ejecutora 1750. Se puede sobreescribir con -v bdSiga=. */
DECLARE @bdSiga sysname = N'SIGA_1750';
DECLARE @bdSigcm sysname = N'DBSIGCM';

/* Linea base del proyecto: SQL Server 2022 = 16.0, confirmado por el equipo como
   la version del servidor de produccion del ANIN. Antes de esa confirmacion la
   linea base era 2016 (13.0), por precaucion; ya no hace falta.

   Con 2022 quedan disponibles STRING_AGG, TRIM, CONCAT_WS, GENERATE_SERIES y
   JSON_OBJECT. Lo unico que sigue prohibido es el tipo json nativo, que es de
   SQL Server 2025. */
DECLARE @versionMinima int = 16;
DECLARE @compatMinimo  int = 160;

DECLARE @errores int = 0;
DECLARE @avisos  int = 0;
DECLARE @msg nvarchar(400);

PRINT '===============================================================';
PRINT ' SIGCM - Preflight';
PRINT ' Servidor : ' + CONVERT(nvarchar(200), SERVERPROPERTY('ServerName'));
PRINT ' Fecha    : ' + CONVERT(nvarchar(30), SYSDATETIME(), 120);
PRINT ' Base SIGA esperada : ' + @bdSiga;
PRINT '===============================================================';
PRINT '';

/* -------------------------------------------------------------------------- */
/* 1. Motor                                                                   */
/* -------------------------------------------------------------------------- */

DECLARE @productVersion nvarchar(50) = CONVERT(nvarchar(50), SERVERPROPERTY('ProductVersion'));
DECLARE @versionMayor int =
    CONVERT(int, LEFT(@productVersion, CHARINDEX('.', @productVersion) - 1));

PRINT '--- 1. Motor ---';
PRINT '  Version      : ' + @productVersion + '  (' + CONVERT(nvarchar(20), SERVERPROPERTY('ProductLevel')) + ')';
PRINT '  Edicion      : ' + CONVERT(nvarchar(100), SERVERPROPERTY('Edition'));
PRINT '  Intercalacion del servidor : ' + CONVERT(nvarchar(100), SERVERPROPERTY('Collation'));

IF @versionMayor < @versionMinima
BEGIN
    SET @msg = '  [ERROR] El motor es anterior a SQL Server 2022 (16.x), que es la version '
             + 'de produccion del ANIN y la linea base del proyecto. Revisar antes de instalar.';
    PRINT @msg;
    SET @errores = @errores + 1;
END
ELSE
    PRINT '  [OK] Cumple la linea base de SQL Server 2022.';

IF @versionMayor > 16
BEGIN
    PRINT '  [AVISO] El motor es mas nuevo que produccion (2022). Los scripts se escriben '
        + 'contra compat 160 a proposito. En particular, NO usar el tipo json nativo: es de '
        + 'SQL Server 2025 y no existe en produccion.';
    SET @avisos = @avisos + 1;
END
PRINT '';

/* -------------------------------------------------------------------------- */
/* 2. Base SIGA                                                               */
/* -------------------------------------------------------------------------- */

PRINT '--- 2. Base SIGA ---';

IF DB_ID(@bdSiga) IS NULL
BEGIN
    PRINT '  [ERROR] No existe la base ' + @bdSiga + ' en este servidor. '
        + 'Reejecuta con -v bdSiga="<nombre real>".';
    SET @errores = @errores + 1;
END
ELSE
BEGIN
    DECLARE @collSiga sysname = CONVERT(sysname, DATABASEPROPERTYEX(@bdSiga, 'Collation'));
    DECLARE @compatSiga int;
    DECLARE @rcsiSiga bit;
    DECLARE @recoverySiga nvarchar(30);

    SELECT @compatSiga   = d.compatibility_level,
           @rcsiSiga     = d.is_read_committed_snapshot_on,
           @recoverySiga = d.recovery_model_desc
      FROM sys.databases d
     WHERE d.name = @bdSiga;

    PRINT '  Intercalacion : ' + ISNULL(@collSiga, '(desconocida)');
    PRINT '  Compat level  : ' + CONVERT(nvarchar(10), @compatSiga);
    PRINT '  Recovery      : ' + @recoverySiga;
    PRINT '  RCSI          : ' + CASE WHEN @rcsiSiga = 1 THEN 'ACTIVO' ELSE 'DESACTIVADO' END;

    IF @rcsiSiga = 0
    BEGIN
        PRINT '  [AVISO] RCSI desactivado en SIGA: nuestras lecturas toman bloqueos compartidos '
            + 'y pueden frenar a los escritores de SIGA. Por eso las vistas de maestros cuasi '
            + 'estaticos llevan NOLOCK y toda rutina que lea SIGA abre con LOCK_TIMEOUT y '
            + 'DEADLOCK_PRIORITY LOW.';
        SET @avisos = @avisos + 1;
    END

    IF @collSiga <> CONVERT(sysname, SERVERPROPERTY('Collation'))
    BEGIN
        PRINT '  [AVISO] La intercalacion de SIGA difiere de la del servidor. DBSIGCM debe '
            + 'crearse con la de SIGA (C001 lo hace automaticamente) o los joins cruzados '
            + 'fallan con el error 468.';
        SET @avisos = @avisos + 1;
    END
END
PRINT '';

/* -------------------------------------------------------------------------- */
/* 3. Tablas de origen que consumen las vistas mst                            */
/* -------------------------------------------------------------------------- */

PRINT '--- 3. Tablas de origen exigidas por las vistas mst ---';

IF DB_ID(@bdSiga) IS NOT NULL
BEGIN
    DECLARE @requeridas TABLE (tabla sysname NOT NULL PRIMARY KEY);
    INSERT INTO @requeridas (tabla) VALUES
        (N'SIG_CENTRO_COSTO'),
        (N'META'),
        (N'FUENTE_FINANC_EJEC'),
        (N'FUENTE_FINANC'),
        (N'SIG_CENTRO_COSTO_TAREA'),
        (N'UNIDAD_MEDIDA'),
        (N'CATALOGO_BIEN_SERV'),
        (N'SIG_TECHO_PRESUPUESTO'),
        (N'SIG_CUADRO_MODIFICADO'),
        (N'SIG_CUADRO_MODIFICADO_DET'),
        (N'SIG_CUADRO_MODIFICADO_SALDO'),
        (N'SIG_CUADRO_MODIFICADO_CMN'),
        (N'SIG_CUADRO_X_CENTRO'),
        (N'SIG_PARAMETRO_EJECUTORA_ANIO');

    DECLARE @existentes TABLE (tabla sysname NOT NULL PRIMARY KEY, filas bigint NULL);
    DECLARE @sql nvarchar(max) =
        N'SELECT t.name, SUM(p.rows)
            FROM ' + QUOTENAME(@bdSiga) + N'.sys.tables t
            JOIN ' + QUOTENAME(@bdSiga) + N'.sys.partitions p
              ON p.object_id = t.object_id AND p.index_id IN (0, 1)
           GROUP BY t.name;';

    INSERT INTO @existentes (tabla, filas)
    EXEC sys.sp_executesql @sql;

    DECLARE @faltantes int =
        (SELECT COUNT(*) FROM @requeridas r
          WHERE NOT EXISTS (SELECT 1 FROM @existentes e WHERE e.tabla = r.tabla));

    SELECT r.tabla                                         AS tabla_origen,
           CASE WHEN e.tabla IS NULL THEN 'FALTA' ELSE 'OK' END AS estado,
           e.filas                                         AS filas
      FROM @requeridas r
      LEFT JOIN @existentes e ON e.tabla = r.tabla
     ORDER BY CASE WHEN e.tabla IS NULL THEN 0 ELSE 1 END, r.tabla;

    IF @faltantes > 0
    BEGIN
        PRINT '  [ERROR] Faltan ' + CONVERT(nvarchar(10), @faltantes)
            + ' tabla(s) de origen. V004 no se puede instalar.';
        SET @errores = @errores + 1;
    END
    ELSE
        PRINT '  [OK] Las 14 tablas de origen estan presentes.';
END
PRINT '';

/* -------------------------------------------------------------------------- */
/* 4. Disparadores en las tablas que escribe el integrador                    */
/* -------------------------------------------------------------------------- */

PRINT '--- 4. Disparadores en las tablas de cuadro modificado ---';
PRINT '  (Si aparece alguno, la estrategia de escritura debe revisarse: habria';
PRINT '   efectos colaterales no contemplados.)';

IF DB_ID(@bdSiga) IS NOT NULL
BEGIN
    DECLARE @sqlTrg nvarchar(max) =
        N'SELECT OBJECT_NAME(tr.parent_id, DB_ID(''' + @bdSiga + N''')) AS tabla,
                 tr.name AS disparador,
                 tr.is_disabled
            FROM ' + QUOTENAME(@bdSiga) + N'.sys.triggers tr
           WHERE tr.parent_id IN (
                     SELECT t.object_id
                       FROM ' + QUOTENAME(@bdSiga) + N'.sys.tables t
                      WHERE t.name LIKE ''SIG_CUADRO_MODIFICADO%'');';
    EXEC sys.sp_executesql @sqlTrg;
END
PRINT '';

/* -------------------------------------------------------------------------- */
/* 5. Base del SIGCM                                                          */
/* -------------------------------------------------------------------------- */

PRINT '--- 5. Base del SIGCM ---';

IF DB_ID(@bdSigcm) IS NULL
    PRINT '  ' + @bdSigcm + ' aun no existe. C001 la creara.';
ELSE
BEGIN
    DECLARE @collSigcm sysname = CONVERT(sysname, DATABASEPROPERTYEX(@bdSigcm, 'Collation'));
    DECLARE @compatSigcm int;
    DECLARE @rcsiSigcm bit;

    SELECT @compatSigcm = d.compatibility_level,
           @rcsiSigcm   = d.is_read_committed_snapshot_on
      FROM sys.databases d
     WHERE d.name = @bdSigcm;

    PRINT '  Ya existe. Intercalacion : ' + @collSigcm;
    PRINT '             Compat level  : ' + CONVERT(nvarchar(10), @compatSigcm);
    PRINT '             RCSI          : ' + CASE WHEN @rcsiSigcm = 1 THEN 'ACTIVO' ELSE 'DESACTIVADO' END;

    IF DB_ID(@bdSiga) IS NOT NULL
       AND @collSigcm <> CONVERT(sysname, DATABASEPROPERTYEX(@bdSiga, 'Collation'))
    BEGIN
        PRINT '  [ERROR] La intercalacion de ' + @bdSigcm + ' NO coincide con la de ' + @bdSiga
            + '. Los joins cruzados fallaran con el error 468. Hay que recrear la base.';
        SET @errores = @errores + 1;
    END

    IF @compatSigcm > @compatMinimo
    BEGIN
        PRINT '  [AVISO] Compat level por encima de ' + CONVERT(nvarchar(10), @compatMinimo)
            + '. Para verificar la linea base, reejecuta la serie con '
            + 'ALTER DATABASE ' + @bdSigcm + ' SET COMPATIBILITY_LEVEL = 130.';
        SET @avisos = @avisos + 1;
    END

    IF @rcsiSigcm = 0
    BEGIN
        PRINT '  [AVISO] RCSI desactivado en ' + @bdSigcm + '. Deberia estar activo.';
        SET @avisos = @avisos + 1;
    END
END
PRINT '';

/* -------------------------------------------------------------------------- */
/* 6. Capacidades opcionales                                                  */
/* -------------------------------------------------------------------------- */

PRINT '--- 6. Capacidades opcionales ---';

IF CONVERT(int, SERVERPROPERTY('IsFullTextInstalled')) = 1
    PRINT '  Full-Text Search : instalado (no se usa; la busqueda del catalogo va por LIKE).';
ELSE
    PRINT '  Full-Text Search : NO instalado. Es lo esperado; la busqueda del catalogo usa LIKE.';

BEGIN TRY
    DECLARE @agente nvarchar(20);
    SELECT @agente = CONVERT(nvarchar(20), status_desc)
      FROM sys.dm_server_services
     WHERE servicename LIKE N'SQL Server Agent%';
    PRINT '  SQL Server Agent : ' + ISNULL(@agente, 'no detectado');
    IF ISNULL(@agente, '') <> 'Running'
    BEGIN
        PRINT '  [AVISO] El Agent no esta corriendo. Solo importa si el drenaje de la cola se '
            + 'implementa como job en vez de BackgroundService .NET.';
        SET @avisos = @avisos + 1;
    END
END TRY
BEGIN CATCH
    PRINT '  SQL Server Agent : sin permiso para consultar sys.dm_server_services.';
END CATCH

DECLARE @maxMem bigint = (SELECT CONVERT(bigint, value_in_use)
                            FROM sys.configurations
                           WHERE name = 'max server memory (MB)');
DECLARE @memFisica bigint = (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info);
PRINT '  Memoria fisica   : ' + CONVERT(nvarchar(20), @memFisica) + ' MB';
PRINT '  max server memory: ' + CONVERT(nvarchar(20), @maxMem) + ' MB';
IF @maxMem > @memFisica
BEGIN
    PRINT '  [AVISO] max server memory sin acotar. Con dos bases conviene fijarlo por debajo '
        + 'de la memoria fisica para no competir con el sistema operativo.';
    SET @avisos = @avisos + 1;
END
PRINT '';

/* -------------------------------------------------------------------------- */
/* 7. Permisos del ejecutor                                                   */
/* -------------------------------------------------------------------------- */

PRINT '--- 7. Permisos del ejecutor ---';
PRINT '  Login : ' + SUSER_NAME();
PRINT '  sysadmin  : ' + CASE WHEN IS_SRVROLEMEMBER('sysadmin')  = 1 THEN 'si' ELSE 'no' END;
PRINT '  dbcreator : ' + CASE WHEN IS_SRVROLEMEMBER('dbcreator') = 1 THEN 'si' ELSE 'no' END;

IF IS_SRVROLEMEMBER('sysadmin') = 0 AND IS_SRVROLEMEMBER('dbcreator') = 0
BEGIN
    PRINT '  [ERROR] Sin permiso para crear bases de datos. C001 fallara.';
    SET @errores = @errores + 1;
END
PRINT '';

/* -------------------------------------------------------------------------- */
/* 8. Veredicto                                                               */
/* -------------------------------------------------------------------------- */

PRINT '===============================================================';
PRINT ' Resultado : ' + CONVERT(nvarchar(10), @errores) + ' error(es), '
                      + CONVERT(nvarchar(10), @avisos)  + ' aviso(s)';
PRINT '===============================================================';

IF @errores > 0
BEGIN
    RAISERROR(N'Preflight fallido: el entorno no cumple la linea base. No continuar con C001.',
              16, 1);
END
ELSE
    PRINT 'Entorno apto. Continuar con C001__crear_dbsigcm.sql.';
GO
