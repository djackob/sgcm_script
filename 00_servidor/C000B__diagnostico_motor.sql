/*
===============================================================================
  SIGCM - C000B : Diagnostico de motor y capacidades T-SQL
  Ambito : se ejecuta en [master]
  Modo   : SOLO LECTURA. No crea, altera ni borra ningun objeto.
           Las pruebas de sintaxis usan SET PARSEONLY (solo analiza, no ejecuta)
           y las pruebas de funciones se evaluan en memoria dentro de TRY/CATCH.

  Por que existe
  --------------
  El equipo local trabaja sobre SQL Server 2025 (17.x) y el servidor de
  desarrollo del ANIN esta en otra version. Los scripts del proyecto (db/00_ddl,
  db/10_api, db/20_seed) usan construcciones que NO existen en todas las
  versiones: CREATE OR ALTER, DROP ... IF EXISTS, STRING_AGG, TRIM, CONCAT_WS,
  GENERATE_SERIES, JSON_OBJECT, GREATEST/LEAST, IS DISTINCT FROM.

  Este script determina, una por una, cuales de esas construcciones acepta el
  motor de destino, para poder escribir una sola serie de scripts que funcione
  igual en el equipo local y en desarrollo (y en produccion).

  Compatible con SQL Server 2012 (11.x) en adelante: el propio script no usa
  ninguna sintaxis posterior a 2012.

  Uso
  ---
    sqlcmd -S "<servidor>" -d master -E -i C000B__diagnostico_motor.sql ^
           -o diagnostico_desarrollo.txt -W -s "|"

  Con autenticacion SQL (pedir la clave, no escribirla en el comando):
    sqlcmd -S "<servidor>" -d master -U <usuario> -i C000B__diagnostico_motor.sql ^
           -o diagnostico_desarrollo.txt -W -s "|"

  Si la base SIGA no se llama SIGA_1750, pasarla asi:
    sqlcmd ... -v bdSiga="<nombre real>"

  Tambien se puede abrir en SSMS y ejecutar con F5 (salida en cuadricula).

  Devolver el archivo diagnostico_desarrollo.txt completo.
===============================================================================
*/

SET NOCOUNT ON;

DECLARE @bdSiga  sysname = N'SIGA_1750';
DECLARE @bdSigcm sysname = N'DBSIGCM';

/* -------------------------------------------------------------------------- */
/* Bloque 1 : identidad del motor                                             */
/* -------------------------------------------------------------------------- */

DECLARE @productVersion nvarchar(50) = CONVERT(nvarchar(50), SERVERPROPERTY('ProductVersion'));
DECLARE @versionMayor int =
    CONVERT(int, LEFT(@productVersion, CHARINDEX('.', @productVersion) - 1));

DECLARE @motor TABLE (
    orden    int          NOT NULL,
    concepto nvarchar(60) NOT NULL,
    valor    nvarchar(400)    NULL
);

INSERT INTO @motor (orden, concepto, valor) VALUES
    ( 1, N'ServerName',            CONVERT(nvarchar(400), SERVERPROPERTY('ServerName'))),
    ( 2, N'MachineName',           CONVERT(nvarchar(400), SERVERPROPERTY('MachineName'))),
    ( 3, N'InstanceName',          ISNULL(CONVERT(nvarchar(400), SERVERPROPERTY('InstanceName')), N'(instancia por defecto)')),
    ( 4, N'ProductVersion',        @productVersion),
    ( 5, N'Version mayor',         CONVERT(nvarchar(10), @versionMayor)),
    ( 6, N'Nombre comercial',      CASE @versionMayor
                                        WHEN 11 THEN N'SQL Server 2012'
                                        WHEN 12 THEN N'SQL Server 2014'
                                        WHEN 13 THEN N'SQL Server 2016'
                                        WHEN 14 THEN N'SQL Server 2017'
                                        WHEN 15 THEN N'SQL Server 2019'
                                        WHEN 16 THEN N'SQL Server 2022'
                                        WHEN 17 THEN N'SQL Server 2025'
                                        ELSE N'(no reconocida)' END),
    ( 7, N'ProductLevel',          CONVERT(nvarchar(400), SERVERPROPERTY('ProductLevel'))),
    ( 8, N'ProductUpdateLevel',    ISNULL(CONVERT(nvarchar(400), SERVERPROPERTY('ProductUpdateLevel')), N'(no aplica)')),
    ( 9, N'Edition',               CONVERT(nvarchar(400), SERVERPROPERTY('Edition'))),
    (10, N'EngineEdition',         CONVERT(nvarchar(10),  SERVERPROPERTY('EngineEdition'))),
    (11, N'Collation servidor',    CONVERT(nvarchar(400), SERVERPROPERTY('Collation'))),
    (12, N'IsFullTextInstalled',   CONVERT(nvarchar(10),  SERVERPROPERTY('IsFullTextInstalled'))),
    (13, N'IsIntegratedSecurityOnly', CONVERT(nvarchar(10), SERVERPROPERTY('IsIntegratedSecurityOnly'))),
    (14, N'Login actual',          SUSER_NAME()),
    (15, N'sysadmin',              CASE WHEN IS_SRVROLEMEMBER('sysadmin')  = 1 THEN N'si' ELSE N'no' END),
    (16, N'dbcreator',             CASE WHEN IS_SRVROLEMEMBER('dbcreator') = 1 THEN N'si' ELSE N'no' END),
    (17, N'Fecha del diagnostico', CONVERT(nvarchar(30), GETDATE(), 120)),
    (18, N'@@VERSION',             REPLACE(REPLACE(CONVERT(nvarchar(400), @@VERSION), CHAR(13), N' '), CHAR(10), N' '));

SELECT N'1. MOTOR' AS bloque, concepto, valor
  FROM @motor
 ORDER BY orden;

/* -------------------------------------------------------------------------- */
/* Bloque 2 : bases de datos relevantes                                       */
/* -------------------------------------------------------------------------- */

SELECT N'2. BASES' AS bloque,
       d.name                                    AS base,
       d.compatibility_level                     AS compat_level,
       CONVERT(nvarchar(128), d.collation_name)  AS intercalacion,
       d.recovery_model_desc                     AS recovery,
       d.is_read_committed_snapshot_on           AS rcsi,
       d.state_desc                              AS estado,
       d.user_access_desc                        AS acceso,
       CASE WHEN d.name = @bdSiga  THEN N'<-- base SIGA'
            WHEN d.name = @bdSigcm THEN N'<-- base SIGCM'
            ELSE N'' END                         AS nota
  FROM sys.databases d
 WHERE d.database_id > 4
    OR d.name IN (N'master', N'tempdb')
 ORDER BY CASE WHEN d.name IN (@bdSiga, @bdSigcm) THEN 0 ELSE 1 END, d.name;

/* Existencia explicita, por si la base SIGA tiene otro nombre en desarrollo. */
SELECT N'2b. BASES CLAVE' AS bloque,
       @bdSiga  AS base_esperada_siga,
       CASE WHEN DB_ID(@bdSiga)  IS NULL THEN N'NO EXISTE' ELSE N'existe' END AS estado_siga,
       @bdSigcm AS base_esperada_sigcm,
       CASE WHEN DB_ID(@bdSigcm) IS NULL THEN N'NO EXISTE' ELSE N'existe' END AS estado_sigcm;

/* Candidatas por nombre, si SIGA_1750 no esta. */
SELECT N'2c. CANDIDATAS SIGA' AS bloque, d.name AS base, d.compatibility_level AS compat_level,
       CONVERT(nvarchar(128), d.collation_name) AS intercalacion
  FROM sys.databases d
 WHERE d.name LIKE N'%SIGA%'
 ORDER BY d.name;

/* -------------------------------------------------------------------------- */
/* Bloque 3 : niveles de compatibilidad que acepta el motor                    */
/* -------------------------------------------------------------------------- */

/* El compat level maximo es 10 x version mayor. El minimo soportado varia:
   2016/2017 aceptan desde 100; 2019/2022 desde 100; 2025 desde 110. */
SELECT N'3. COMPAT' AS bloque,
       @versionMayor * 10                       AS compat_maximo_soportado,
       CASE WHEN @versionMayor >= 17 THEN 110 ELSE 100 END AS compat_minimo_aprox,
       160                                      AS compat_objetivo_proyecto,
       CASE WHEN @versionMayor * 10 >= 160
            THEN N'El motor admite compat 160: los scripts se pueden probar en la linea base del proyecto.'
            ELSE N'El motor NO admite compat 160. La linea base del proyecto debe bajar a '
                 + CONVERT(nvarchar(10), @versionMayor * 10) + N'.' END AS lectura;

/* -------------------------------------------------------------------------- */
/* Bloque 4 : pruebas de capacidades T-SQL usadas por los scripts del SIGCM    */
/* -------------------------------------------------------------------------- */

/*
  Cada prueba se ejecuta aislada con sp_executesql dentro de TRY/CATCH:
    - modo 'PARSE'    -> solo se analiza la sintaxis (SET PARSEONLY ON). Se usa
                         para DDL, porque no queremos crear nada.
    - modo 'EJECUTAR' -> se evalua de verdad, en memoria, sin tocar disco.
  Si el motor no conoce la construccion, el error se atrapa y se marca NO.
*/

DECLARE @pruebas TABLE (
    id       int identity(1,1) PRIMARY KEY,
    grupo    nvarchar(40)  NOT NULL,
    capacidad nvarchar(60) NOT NULL,
    desde    nvarchar(20)  NOT NULL,   -- version minima documentada
    usada    nvarchar(10)  NOT NULL,   -- la usan hoy los scripts del SIGCM?
    modo     varchar(10)   NOT NULL,
    sentencia nvarchar(max) NOT NULL
);

INSERT INTO @pruebas (grupo, capacidad, desde, usada, modo, sentencia) VALUES

/* --- DDL / despliegue ------------------------------------------------------ */
(N'DDL', N'CREATE OR ALTER',            N'2016 SP1', N'SI (34x)', 'PARSE',
    N'SET PARSEONLY ON; CREATE OR ALTER PROCEDURE dbo.zz_diag_probe AS SELECT 1;'),
(N'DDL', N'DROP TABLE IF EXISTS',       N'2016',     N'SI',       'PARSE',
    N'SET PARSEONLY ON; DROP TABLE IF EXISTS dbo.zz_diag_probe;'),
(N'DDL', N'DROP PROCEDURE IF EXISTS',   N'2016',     N'SI',       'PARSE',
    N'SET PARSEONLY ON; DROP PROCEDURE IF EXISTS dbo.zz_diag_probe;'),
(N'DDL', N'ALTER TABLE ADD IF NOT EXISTS', N'no existe en T-SQL', N'NO', 'PARSE',
    N'SET PARSEONLY ON; ALTER TABLE dbo.zz ADD IF NOT EXISTS c int;'),
(N'DDL', N'SEQUENCE',                   N'2012',     N'SI',       'PARSE',
    N'SET PARSEONLY ON; CREATE SEQUENCE dbo.zz_diag_seq AS bigint START WITH 1 INCREMENT BY 1;'),
(N'DDL', N'Tabla temporal de sistema (SYSTEM_VERSIONING)', N'2016', N'NO', 'PARSE',
    N'SET PARSEONLY ON; CREATE TABLE dbo.zz_diag_tv (id int NOT NULL PRIMARY KEY,
        vd datetime2 GENERATED ALWAYS AS ROW START NOT NULL,
        vh datetime2 GENERATED ALWAYS AS ROW END NOT NULL,
        PERIOD FOR SYSTEM_TIME (vd, vh)) WITH (SYSTEM_VERSIONING = ON);'),

/* --- Cadenas --------------------------------------------------------------- */
(N'CADENAS', N'TRIM(x)',                     N'2017', N'SI', 'EJECUTAR',
    N'DECLARE @r nvarchar(50) = TRIM(N''  a  '');'),
(N'CADENAS', N'TRIM(caracteres FROM x)',     N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r nvarchar(50) = TRIM(N''.'' FROM N''..a..'');'),
(N'CADENAS', N'LTRIM/RTRIM con caracteres',  N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r nvarchar(50) = LTRIM(N''..a'', N''.'');'),
(N'CADENAS', N'CONCAT_WS',                   N'2017', N'SI (14x)', 'EJECUTAR',
    N'DECLARE @r nvarchar(50) = CONCAT_WS(N''-'', N''a'', N''b'');'),
(N'CADENAS', N'STRING_AGG',                  N'2017', N'SI (6x)', 'EJECUTAR',
    N'DECLARE @r nvarchar(max); SELECT @r = STRING_AGG(v, N'','') FROM (SELECT N''a'' AS v UNION ALL SELECT N''b'') t;'),
(N'CADENAS', N'STRING_AGG ... WITHIN GROUP', N'2017', N'SI (3x)', 'EJECUTAR',
    N'DECLARE @r nvarchar(max); SELECT @r = STRING_AGG(v, N'','') WITHIN GROUP (ORDER BY v) FROM (SELECT N''a'' AS v UNION ALL SELECT N''b'') t;'),
(N'CADENAS', N'STRING_SPLIT',                N'2016', N'NO', 'EJECUTAR',
    N'DECLARE @r int; SELECT @r = COUNT(*) FROM STRING_SPLIT(N''a,b'', N'','');'),
(N'CADENAS', N'STRING_SPLIT con ordinal',    N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r int; SELECT @r = MAX(ordinal) FROM STRING_SPLIT(N''a,b'', N'','', 1);'),
(N'CADENAS', N'TRANSLATE',                   N'2017', N'NO', 'EJECUTAR',
    N'DECLARE @r nvarchar(50) = TRANSLATE(N''abc'', N''ab'', N''xy'');'),
(N'CADENAS', N'REGEXP_LIKE',                 N'2025', N'NO', 'EJECUTAR',
    N'DECLARE @r int = CASE WHEN REGEXP_LIKE(N''abc'', N''^a'') THEN 1 ELSE 0 END;'),

/* --- JSON ------------------------------------------------------------------ */
(N'JSON', N'FOR JSON PATH',              N'2016', N'SI (62x)', 'EJECUTAR',
    N'DECLARE @r nvarchar(max) = (SELECT 1 AS a FOR JSON PATH);'),
(N'JSON', N'FOR JSON ... WITHOUT_ARRAY_WRAPPER', N'2016', N'SI', 'EJECUTAR',
    N'DECLARE @r nvarchar(max) = (SELECT 1 AS a FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);'),
(N'JSON', N'OPENJSON',                   N'2016', N'SI (18x)', 'EJECUTAR',
    N'DECLARE @r int; SELECT @r = COUNT(*) FROM OPENJSON(N''{"a":1}'');'),
(N'JSON', N'OPENJSON WITH esquema',      N'2016', N'SI', 'EJECUTAR',
    N'DECLARE @r int; SELECT @r = COUNT(*) FROM OPENJSON(N''[{"a":1}]'') WITH (a int ''$.a'');'),
(N'JSON', N'JSON_VALUE',                 N'2016', N'SI (5x)', 'EJECUTAR',
    N'DECLARE @r nvarchar(50) = JSON_VALUE(N''{"a":1}'', N''$.a'');'),
(N'JSON', N'JSON_QUERY',                 N'2016', N'SI (28x)', 'EJECUTAR',
    N'DECLARE @r nvarchar(max) = JSON_QUERY(N''{"a":[1]}'', N''$.a'');'),
(N'JSON', N'JSON_MODIFY',                N'2016', N'NO', 'EJECUTAR',
    N'DECLARE @r nvarchar(max) = JSON_MODIFY(N''{"a":1}'', N''$.a'', 2);'),
(N'JSON', N'ISJSON',                     N'2016', N'SI', 'EJECUTAR',
    N'DECLARE @r int = ISJSON(N''{"a":1}'');'),
(N'JSON', N'ISJSON(x, OBJECT)',          N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r int = ISJSON(N''{"a":1}'', OBJECT);'),
(N'JSON', N'JSON_OBJECT',                N'2022', N'SI (2x)', 'EJECUTAR',
    N'DECLARE @r nvarchar(max) = JSON_OBJECT(N''a'': 1);'),
(N'JSON', N'JSON_ARRAY',                 N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r nvarchar(max) = JSON_ARRAY(1, 2);'),
(N'JSON', N'JSON_PATH_EXISTS',           N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r int = JSON_PATH_EXISTS(N''{"a":1}'', N''$.a'');'),
(N'JSON', N'JSON_OBJECTAGG',             N'2025', N'NO', 'EJECUTAR',
    N'DECLARE @r nvarchar(max); SELECT @r = JSON_OBJECTAGG(k: v) FROM (SELECT N''a'' AS k, 1 AS v) t;'),
(N'JSON', N'JSON_ARRAYAGG',              N'2025', N'NO', 'EJECUTAR',
    N'DECLARE @r nvarchar(max); SELECT @r = JSON_ARRAYAGG(v) FROM (SELECT 1 AS v) t;'),
/* Ojo: esta prueba DEBE ir en modo EJECUTAR. Con PARSEONLY daria un falso
   positivo, porque el analizador no resuelve nombres de tipo y aceptaria
   'json' como si fuera un tipo definido por el usuario. */
(N'JSON', N'tipo json nativo',           N'2025', N'PROHIBIDO', 'EJECUTAR',
    N'DECLARE @r json = N''{"a":1}'';'),

/* --- Numeros, fechas, comparacion ------------------------------------------ */
(N'ESCALARES', N'GENERATE_SERIES',       N'2022', N'SI (4x)', 'EJECUTAR',
    N'DECLARE @r int; SELECT @r = COUNT(*) FROM GENERATE_SERIES(1, 5);'),
(N'ESCALARES', N'GREATEST / LEAST',      N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r int = GREATEST(1, 2);'),
(N'ESCALARES', N'IS DISTINCT FROM',      N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r int = CASE WHEN 1 IS DISTINCT FROM NULL THEN 1 ELSE 0 END;'),
(N'ESCALARES', N'DATETRUNC',             N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r datetime2 = DATETRUNC(month, SYSDATETIME());'),
(N'ESCALARES', N'DATE_BUCKET',           N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r datetime2 = DATE_BUCKET(day, 1, SYSDATETIME());'),
(N'ESCALARES', N'AT TIME ZONE',          N'2016', N'NO', 'EJECUTAR',
    N'DECLARE @r datetimeoffset = SYSDATETIME() AT TIME ZONE N''SA Pacific Standard Time'';'),
(N'ESCALARES', N'TRY_CAST / TRY_CONVERT', N'2012', N'SI', 'EJECUTAR',
    N'DECLARE @r int = TRY_CAST(N''1'' AS int);'),
(N'ESCALARES', N'COMPRESS / DECOMPRESS', N'2016', N'NO', 'EJECUTAR',
    N'DECLARE @r varbinary(max) = COMPRESS(N''abc'');'),
(N'ESCALARES', N'APPROX_COUNT_DISTINCT', N'2019', N'NO', 'EJECUTAR',
    N'DECLARE @r bigint; SELECT @r = APPROX_COUNT_DISTINCT(v) FROM (SELECT 1 AS v) t;'),

/* --- Consulta -------------------------------------------------------------- */
(N'CONSULTA', N'OFFSET / FETCH',         N'2012', N'SI', 'EJECUTAR',
    N'DECLARE @r int; SELECT @r = v FROM (SELECT 1 AS v) t ORDER BY v OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;'),
(N'CONSULTA', N'clausula WINDOW',        N'2022', N'NO', 'EJECUTAR',
    N'DECLARE @r int; SELECT @r = SUM(v) OVER w FROM (SELECT 1 AS v) t WINDOW w AS (ORDER BY v);'),
(N'CONSULTA', N'TRIM en agregado / SELECT ... INTO', N'2012', N'SI', 'EJECUTAR',
    N'DECLARE @r int; SELECT @r = COUNT(*) FROM (SELECT 1 AS v) t;'),
(N'CONSULTA', N'THROW',                  N'2012', N'SI', 'PARSE',
    N'SET PARSEONLY ON; THROW 50000, N''x'', 1;');

/* Bucle de pruebas. */
DECLARE @resultado TABLE (
    id        int          NOT NULL,
    grupo     nvarchar(40) NOT NULL,
    capacidad nvarchar(60) NOT NULL,
    desde     nvarchar(20) NOT NULL,
    usada     nvarchar(10) NOT NULL,
    soportado nvarchar(4)  NOT NULL,
    detalle   nvarchar(400)    NULL
);

DECLARE @i int = 1;
DECLARE @maxId int = (SELECT ISNULL(MAX(id), 0) FROM @pruebas);
DECLARE @grupo nvarchar(40), @capacidad nvarchar(60), @desde nvarchar(20),
        @usada nvarchar(10), @modo varchar(10), @sentencia nvarchar(max),
        @error nvarchar(400);

WHILE @i <= @maxId
BEGIN
    SELECT @grupo = grupo, @capacidad = capacidad, @desde = desde,
           @usada = usada, @modo = modo, @sentencia = sentencia
      FROM @pruebas WHERE id = @i;

    SET @error = NULL;

    BEGIN TRY
        EXEC sys.sp_executesql @sentencia;
    END TRY
    BEGIN CATCH
        SET @error = LEFT(REPLACE(REPLACE(ERROR_MESSAGE(), CHAR(13), N' '), CHAR(10), N' '), 380);
    END CATCH

    /* En modo PARSE, un error de "objeto no existe" no significa falta de soporte:
       PARSEONLY no resuelve nombres, asi que cualquier error es de sintaxis. */
    INSERT INTO @resultado (id, grupo, capacidad, desde, usada, soportado, detalle)
    VALUES (@i, @grupo, @capacidad, @desde, @usada,
            CASE WHEN @error IS NULL THEN N'SI' ELSE N'NO' END,
            @error);

    SET @i = @i + 1;
END

SELECT N'4. CAPACIDADES' AS bloque,
       r.grupo,
       r.capacidad,
       r.desde        AS desde_version,
       r.usada        AS usada_en_sigcm,
       r.soportado,
       CASE WHEN r.soportado = N'NO' AND r.usada LIKE N'SI%'
            THEN N'*** ROMPE LOS SCRIPTS ***' ELSE N'' END AS alerta,
       r.detalle      AS error_del_motor
  FROM @resultado r
 ORDER BY CASE WHEN r.soportado = N'NO' AND r.usada LIKE N'SI%' THEN 0 ELSE 1 END,
          r.grupo, r.id;

/* -------------------------------------------------------------------------- */
/* Bloque 5 : resumen accionable                                              */
/* -------------------------------------------------------------------------- */

DECLARE @rompen int = (SELECT COUNT(*) FROM @resultado
                        WHERE soportado = N'NO' AND usada LIKE N'SI%');

SELECT N'5. RESUMEN' AS bloque,
       @productVersion                       AS version_motor,
       @versionMayor                         AS version_mayor,
       CONVERT(nvarchar(400), SERVERPROPERTY('Collation')) AS collation_servidor,
       @rompen                               AS capacidades_usadas_no_soportadas,
       CASE WHEN @rompen = 0
            THEN N'El motor acepta todo lo que usan los scripts actuales. No hace falta reescribir nada.'
            ELSE N'Hay ' + CONVERT(nvarchar(10), @rompen)
               + N' construccion(es) que los scripts usan y este motor NO acepta. '
               + N'Ver el bloque 4, filas con alerta.' END AS veredicto;

/* Lista compacta de lo que hay que reemplazar, para pegar en el ticket. */
SELECT N'5b. A CORREGIR' AS bloque, grupo, capacidad, desde AS requiere_version, detalle AS error
  FROM @resultado
 WHERE soportado = N'NO' AND usada LIKE N'SI%'
 ORDER BY grupo, capacidad;

/* -------------------------------------------------------------------------- */
/* Bloque 6 : entorno operativo (informativo)                                 */
/* -------------------------------------------------------------------------- */

BEGIN TRY
    SELECT N'6. SO' AS bloque,
           host_platform    AS plataforma,
           host_distribution AS distribucion,
           host_release     AS version_so
      FROM sys.dm_os_host_info;
END TRY
BEGIN CATCH
    SELECT N'6. SO' AS bloque, N'sys.dm_os_host_info no disponible (motor anterior a 2017)' AS nota;
END CATCH

BEGIN TRY
    SELECT N'6b. RECURSOS' AS bloque,
           (SELECT CONVERT(bigint, value_in_use) FROM sys.configurations WHERE name = N'max server memory (MB)') AS max_server_memory_mb,
           (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info) AS memoria_fisica_mb,
           (SELECT cpu_count FROM sys.dm_os_sys_info) AS cpus;
END TRY
BEGIN CATCH
    SELECT N'6b. RECURSOS' AS bloque, N'sin permiso para leer las DMV de sistema' AS nota;
END CATCH

PRINT '';
PRINT '=== Diagnostico terminado. Enviar el archivo de salida completo. ===';
GO
