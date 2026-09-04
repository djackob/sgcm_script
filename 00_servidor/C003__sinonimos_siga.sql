/*
===============================================================================
  SIGCM - C003 : Sinonimos hacia la base SIGA
  Motor  : SQL Server 2016 (13.x) o superior
  Ambito : se ejecuta en [DBSIGCM]

  ESTE ES EL UNICO ARCHIVO DE TODO EL SISTEMA DONDE APARECE EL NOMBRE DE LA
  BASE SIGA.

  Ninguna vista, procedimiento ni consulta escribe SIGA_1750 en ningun sitio:
  todo lee el esquema [siga] de sinonimos que se define aqui. Tres razones:

  1. El nombre SIGA_1750 codifica la ejecutora 1750. La base de produccion del
     ANIN muy probablemente se llame de otra forma. Cambiar de entorno debe ser
     reejecutar este archivo, no una busqueda y reemplazo por todo el proyecto.

  2. Si maniana el SIGCM no puede convivir en la misma instancia, los sinonimos
     pueden repuntar a un servidor vinculado, y solo cambia este archivo.

  3. Si se decidiera volver al espejo de tablas (la estrategia de la version
     PostgreSQL), basta reemplazar V004; el resto del sistema no se entera.

  Idempotente: los sinonimos se recrean en cada ejecucion.

  Uso:
    sqlcmd -S "<servidor>" -d DBSIGCM -E -i C003__sinonimos_siga.sql
    sqlcmd -S "<servidor>" -d DBSIGCM -E -v bdSiga="SIGA_2001" -i C003__sinonimos_siga.sql
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @bdSiga sysname = N'SIGA_1750';

IF DB_ID(@bdSiga) IS NULL
BEGIN
    DECLARE @err nvarchar(400) =
        N'No existe la base ' + @bdSiga + N' en este servidor. Reejecuta con '
      + N'-v bdSiga="<nombre real>", o repunta los sinonimos a un servidor vinculado.';
    RAISERROR(@err, 16, 1);
    SET NOEXEC ON;
END

IF SCHEMA_ID(N'siga') IS NULL
    EXEC(N'CREATE SCHEMA siga AUTHORIZATION dbo;');
GO

/* -------------------------------------------------------------------------- */
/* Sinonimos                                                                  */
/* -------------------------------------------------------------------------- */

SET NOCOUNT ON;

DECLARE @bdSiga sysname = N'SIGA_1750';

DECLARE @tablas TABLE (tabla sysname NOT NULL PRIMARY KEY);
INSERT INTO @tablas (tabla) VALUES
    /* Maestros cuasi estaticos: alimentan formularios y validacion temprana */
    (N'SIG_CENTRO_COSTO'),
    (N'META'),
    (N'FUENTE_FINANC_EJEC'),
    (N'FUENTE_FINANC'),
    (N'SIG_CENTRO_COSTO_TAREA'),
    /* Metas y fuentes habilitadas por area usuaria. Es la tabla con la que el
       SIGA delimita los combos de cada unidad: sin ella el formulario ofrece
       las 487 metas de la entidad y las fuentes de toda la ejecutora. */
    (N'SIG_METAS_X_CENTRO'),
    (N'UNIDAD_MEDIDA'),
    (N'CATALOGO_BIEN_SERV'),
    /* Datos que si se mueven */
    (N'SIG_TECHO_PRESUPUESTO'),
    (N'SIG_CUADRO_MODIFICADO'),
    (N'SIG_CUADRO_MODIFICADO_DET'),
    (N'SIG_CUADRO_MODIFICADO_SALDO'),
    (N'SIG_CUADRO_MODIFICADO_CMN'),
    /* Gobierno de etapa y fase: hallazgos 5.3 y 5.4 del mapa-siga-cmn */
    (N'SIG_CUADRO_X_CENTRO'),
    (N'SIG_PARAMETRO_EJECUTORA_ANIO'),
    /* Pedidos del area usuaria: combo del requerimiento (REQ-02 / siga.vwPedido)
       y lineas del pedido (REQ-02 / siga.vwPedidoItem). */
    (N'SIG_PEDIDOS'),
    (N'SIG_DETALLE_PEDIDOS'),
    /* Cuadro de adquisicion de servicios y enlace pedido -> cuadro (O/S) */
    (N'SIG_CUADRO_ADQUISICION'),
    (N'SIG_DETALLE_PEDIDO_CUADRO'),
    (N'SIG_DETALLE_BSERV_CUADRO'),
    (N'SIG_DETALLE_ANEXO_CUADRO'),
    (N'SIG_DETALLE_PEDIDOS_ANEXO'),
    (N'SIG_ORDEN_ITEM'),
    (N'SIG_ORDEN_ITEM_ANEXO'),
    /* Orden de servicio y su interfase SIAF: el modulo de pagos lee de aqui el
       estado real de la O/S (hitos 1 y 4). Ver siga.vwOrdenServicioSiga. */
    (N'SIG_ORDEN_ADQUISICION'),
    (N'SIG_ORDEN_INTERFASE'),
    (N'SIG_CONTRATISTAS');

DECLARE @tabla sysname, @sql nvarchar(max), @creados int = 0;

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT tabla FROM @tablas ORDER BY tabla;
OPEN cur;
FETCH NEXT FROM cur INTO @tabla;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.synonyms
                WHERE name = @tabla AND SCHEMA_NAME(schema_id) = N'siga')
    BEGIN
        SET @sql = N'DROP SYNONYM siga.' + QUOTENAME(@tabla) + N';';
        EXEC sys.sp_executesql @sql;
    END

    SET @sql = N'CREATE SYNONYM siga.' + QUOTENAME(@tabla)
             + N' FOR ' + QUOTENAME(@bdSiga) + N'.dbo.' + QUOTENAME(@tabla) + N';';
    EXEC sys.sp_executesql @sql;
    SET @creados = @creados + 1;

    FETCH NEXT FROM cur INTO @tabla;
END
CLOSE cur;
DEALLOCATE cur;

PRINT CONVERT(nvarchar(10), @creados) + ' sinonimos apuntando a ' + @bdSiga + '.';
GO

/* -------------------------------------------------------------------------- */
/* Verificacion: que cada sinonimo resuelva                                   */
/* -------------------------------------------------------------------------- */

SET NOCOUNT ON;

/* OBJECT_ID va SIN tipo a proposito. Forzando 'U' solo resuelven las tablas, y
   en el esquema siga tambien vive el sinonimo hacia
   usp_ext_registrar_item_cmn que crea W001, que es un procedimiento: con 'U'
   se reportaba como no resuelto y abortaba una instalacion sana. */
SELECT s.name                         AS sinonimo,
       s.base_object_name             AS apunta_a,
       CASE WHEN OBJECT_ID(s.base_object_name) IS NULL
            THEN 'NO RESUELVE' ELSE 'OK' END AS estado
  FROM sys.synonyms s
 WHERE SCHEMA_NAME(s.schema_id) = N'siga'
 ORDER BY s.name;

IF EXISTS (SELECT 1 FROM sys.synonyms s
            WHERE SCHEMA_NAME(s.schema_id) = N'siga'
              AND OBJECT_ID(s.base_object_name) IS NULL)
BEGIN
    RAISERROR(N'Hay sinonimos que no resuelven. Revisa el nombre de la base o los permisos.', 16, 1);
END
ELSE
    PRINT 'Todos los sinonimos resuelven. Continuar con db/00_ddl/V001.';
GO
