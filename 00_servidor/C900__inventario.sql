/*
===============================================================================
  SIGCM - C900 : Inventario y verificacion posterior a la instalacion
  Ambito : se ejecuta en [DBSIGCM]
  Modo   : SOLO LECTURA.

  Se corre al final de la serie para responder una sola pregunta: ¿quedo esta
  base igual a la que describe el README y compatible con el servidor de
  desarrollo del ANIN (SQL Server 2022, compat 160, Modern_Spanish_CI_AS)?

  Falla con error si algo no cuadra, de modo que el instalador se detenga.

  Uso:
    sqlcmd -S "<servidor>" -d DBSIGCM -E -b -I -i C900__inventario.sql
===============================================================================
*/

SET NOCOUNT ON;

DECLARE @errores int = 0;

/* -------------------------------------------------------------------------- */
/* 1. Parametros de la base frente a la linea base de desarrollo              */
/* -------------------------------------------------------------------------- */

DECLARE @collation sysname = CONVERT(sysname, DATABASEPROPERTYEX(DB_NAME(), 'Collation'));
DECLARE @compat int  = (SELECT compatibility_level FROM sys.databases WHERE database_id = DB_ID());
DECLARE @rcsi   bit  = (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE database_id = DB_ID());
DECLARE @collSiga sysname = CONVERT(sysname, DATABASEPROPERTYEX(N'SIGA_1750', 'Collation'));

SELECT N'1. BASE' AS bloque,
       DB_NAME()      AS base,
       @collation     AS intercalacion,
       @compat        AS compat_level,
       @rcsi          AS rcsi,
       CONVERT(nvarchar(20), SERVERPROPERTY('ProductVersion')) AS motor,
       N'desarrollo: 16.0.4262.2 / 160 / Modern_Spanish_CI_AS' AS referencia;

IF @compat <> 160
BEGIN
    PRINT '[ERROR] compat level ' + CONVERT(nvarchar(10), @compat) + ', se esperaba 160.';
    SET @errores = @errores + 1;
END

IF @rcsi <> 1
BEGIN
    PRINT '[ERROR] RCSI desactivado.';
    SET @errores = @errores + 1;
END

IF @collSiga IS NOT NULL AND @collation <> @collSiga
BEGIN
    PRINT '[ERROR] La intercalacion no coincide con la de SIGA (' + @collSiga + '). Error 468 en joins cruzados.';
    SET @errores = @errores + 1;
END

/* -------------------------------------------------------------------------- */
/* 2. Inventario de objetos                                                   */
/* -------------------------------------------------------------------------- */

DECLARE @inventario TABLE (
    tipo      nvarchar(30) NOT NULL,
    cantidad  int          NOT NULL,
    esperado  int          NULL
);

/* Los esperados salen del README (seccion "Estado de verificacion") mas los
   objetos agregados despues: V007 a V009, F003, F005 y F006. */
INSERT INTO @inventario (tipo, cantidad, esperado) VALUES
    (N'Tablas',         (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0), NULL),
    (N'Vistas',         (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped = 0),  NULL),
    (N'Procedimientos', (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0), NULL),
    (N'Funciones',      (SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN','IF','TF') AND is_ms_shipped = 0), NULL),
    (N'Sinonimos maestros', (SELECT COUNT(*) FROM sys.synonyms
                              WHERE name <> N'usp_ext_registrar_item_cmn'), 14),
    (N'Secuencias',     (SELECT COUNT(*) FROM sys.sequences), NULL),
    (N'Esquemas SIGCM', (SELECT COUNT(*) FROM sys.schemas
                          WHERE name IN (N'sigcm', N'integracion', N'siga', N'cmn',
                                         N'requerimiento', N'ejecucion', N'pago',
                                         N'ampliacion', N'resolucion')), 9);

SELECT N'2. INVENTARIO' AS bloque, tipo, cantidad, esperado,
       CASE WHEN esperado IS NULL THEN N''
            WHEN cantidad = esperado THEN N'OK'
            ELSE N'*** NO COINCIDE ***' END AS estado
  FROM @inventario;

IF EXISTS (SELECT 1 FROM @inventario WHERE esperado IS NOT NULL AND cantidad <> esperado)
BEGIN
    PRINT '[ERROR] El inventario no coincide con lo esperado.';
    SET @errores = @errores + 1;
END

/* Detalle por esquema, para ver de un vistazo donde aterrizo cada cosa. */
SELECT N'2b. POR ESQUEMA' AS bloque,
       s.name AS esquema,
       SUM(CASE WHEN o.type = 'U'                 THEN 1 ELSE 0 END) AS tablas,
       SUM(CASE WHEN o.type = 'V'                 THEN 1 ELSE 0 END) AS vistas,
       SUM(CASE WHEN o.type = 'P'                 THEN 1 ELSE 0 END) AS procedimientos,
       SUM(CASE WHEN o.type IN ('FN','IF','TF')   THEN 1 ELSE 0 END) AS funciones,
       SUM(CASE WHEN o.type = 'SN'                THEN 1 ELSE 0 END) AS sinonimos
  FROM sys.schemas s
  LEFT JOIN sys.objects o
    ON o.schema_id = s.schema_id
   AND o.is_ms_shipped = 0
   AND o.type IN ('U','V','P','FN','IF','TF','SN')
 WHERE s.name IN (N'dbo', N'sigcm', N'integracion', N'siga', N'cmn',
                  N'requerimiento', N'ejecucion', N'pago', N'ampliacion', N'resolucion')
 GROUP BY s.name
 ORDER BY s.name;

/* -------------------------------------------------------------------------- */
/* 3. Los sinonimos resuelven de verdad                                       */
/* -------------------------------------------------------------------------- */

/* Un sinonimo se crea aunque su destino no exista: SQL Server no valida el
   objeto base. Por eso no basta contarlos, hay que resolverlos. */

DECLARE @rotos int = 0;

/* OBJECT_ID va sin tipo: en el esquema siga hay sinonimos hacia tablas y
   tambien hacia el procedimiento usp_ext_registrar_item_cmn que usa W001. */
SELECT @rotos = COUNT(*)
  FROM sys.synonyms sy
 WHERE OBJECT_ID(sy.base_object_name) IS NULL;

SELECT N'3. SINONIMOS' AS bloque,
       SCHEMA_NAME(sy.schema_id) + N'.' + sy.name AS sinonimo,
       sy.base_object_name                        AS apunta_a,
       CASE WHEN OBJECT_ID(sy.base_object_name) IS NULL
            THEN N'*** NO RESUELVE ***' ELSE N'OK' END AS estado
  FROM sys.synonyms sy
 ORDER BY CASE WHEN OBJECT_ID(sy.base_object_name) IS NULL THEN 0 ELSE 1 END,
          sy.name;

IF @rotos > 0
BEGIN
    PRINT '[ERROR] ' + CONVERT(nvarchar(10), @rotos) + ' sinonimo(s) no resuelven contra la base SIGA.';
    SET @errores = @errores + 1;
END

/* -------------------------------------------------------------------------- */
/* 4. Ningun objeto usa el tipo json nativo (prohibido: es de 2025)           */
/* -------------------------------------------------------------------------- */

DECLARE @jsonNativo int =
    (SELECT COUNT(*)
       FROM sys.columns c
       JOIN sys.types t ON t.user_type_id = c.user_type_id
      WHERE t.name = N'json');

SELECT N'4. LINEA BASE' AS bloque,
       @jsonNativo AS columnas_tipo_json_nativo,
       CASE WHEN @jsonNativo = 0
            THEN N'OK - el JSON se guarda como nvarchar(max) con CHECK ISJSON, como exige compat 160'
            ELSE N'*** Hay columnas con el tipo json nativo: no existen en SQL Server 2022 ***' END AS estado;

IF @jsonNativo > 0
BEGIN
    PRINT '[ERROR] Hay columnas con el tipo json nativo. En desarrollo (2022) la instalacion fallara.';
    SET @errores = @errores + 1;
END

/* -------------------------------------------------------------------------- */
/* 5. Semilla aplicada                                                        */
/* -------------------------------------------------------------------------- */

DECLARE @filas TABLE (tabla sysname NOT NULL, filas int NOT NULL);

INSERT INTO @filas (tabla, filas)
SELECT N'dbo.Numero',        COUNT(*) FROM dbo.Numero
UNION ALL SELECT N'sigcm.Modulo',      COUNT(*) FROM sigcm.Modulo
UNION ALL SELECT N'sigcm.Rol',         COUNT(*) FROM sigcm.Rol
UNION ALL SELECT N'sigcm.Estado',      COUNT(*) FROM sigcm.Estado
UNION ALL SELECT N'sigcm.Transicion',  COUNT(*) FROM sigcm.Transicion;

SELECT N'5. SEMILLA' AS bloque, tabla, filas,
       CASE WHEN filas = 0 THEN N'*** VACIA ***' ELSE N'OK' END AS estado
  FROM @filas
 ORDER BY tabla;

IF EXISTS (SELECT 1 FROM @filas WHERE filas = 0)
BEGIN
    PRINT '[ERROR] Hay tablas de configuracion vacias: la semilla no se aplico completa.';
    SET @errores = @errores + 1;
END

/* -------------------------------------------------------------------------- */
/* 6. Veredicto                                                               */
/* -------------------------------------------------------------------------- */

PRINT '';
IF @errores > 0
BEGIN
    DECLARE @msg nvarchar(200) =
        N'Inventario con ' + CONVERT(nvarchar(10), @errores) + N' error(es). Revisar arriba.';
    RAISERROR(@msg, 16, 1);
END
ELSE
    PRINT 'Inventario OK. La base local reproduce la linea base del servidor de desarrollo.';
GO
