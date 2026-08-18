/*
===============================================================================
  SIGCM - Fase 1. Descubrimiento controlado del CMN en SIGA
  Archivo : 01_perfilado_cmn.sql
  Destino : localhost\SQLSERVER25 / SIGA_1750   (copia local de trabajo)
  Modo    : SOLO LECTURA. No contiene INSERT, UPDATE, DELETE ni DDL.
  Ejecutar:
      sqlcmd -S "localhost\SQLSERVER25" -d SIGA_1750 -E -W -s"|" -i 01_perfilado_cmn.sql

  Proposito
  ---------
  Establecer, con evidencia y no por intuicion, cual es el par de tablas que
  soporta cada uno de los dos procesos del CMN:
      (a) formulacion inicial       -> SIG_CUADRO_NECESIDAD / _DET
      (b) modificacion del cuadro   -> SIG_CUADRO_MODIFICADO / _DET / _SALDO / _CMN
  El SIGCM implementa (b) segun ADR-002.
===============================================================================
*/

SET NOCOUNT ON;

PRINT '===============================================================';
PRINT '1. Volumen de la ruta de FORMULACION por ejercicio y fase';
PRINT '===============================================================';

SELECT  'CN_CABECERA'           AS tabla,
        ANO_EJE,
        FASE_CUADRO,
        COUNT(*)                AS filas,
        COUNT(DISTINCT CENTRO_COSTO) AS centros
FROM    dbo.SIG_CUADRO_NECESIDAD
GROUP BY ANO_EJE, FASE_CUADRO
ORDER BY ANO_EJE, FASE_CUADRO;

SELECT  'CN_DETALLE'            AS tabla,
        ANO_EJE,
        FASE_CUADRO,
        ESTADO,
        COUNT(*)                AS filas
FROM    dbo.SIG_CUADRO_NECESIDAD_DET
GROUP BY ANO_EJE, FASE_CUADRO, ESTADO
ORDER BY ANO_EJE, FASE_CUADRO, ESTADO;


PRINT '===============================================================';
PRINT '2. Estado del cuadro por centro de costo';
PRINT '===============================================================';
/* SIG_CUADRO_X_CENTRO gobierna en que etapa esta el cuadro de cada area.
   SP_INT_FASE_SIGA la consulta para derivar la fase vigente de la ejecutora.
   Cualquier escritura externa debe ser coherente con esta tabla.          */

SELECT  'X_CENTRO'              AS tabla,
        ano_eje,
        estado,
        flag_modif,
        COUNT(*)                AS filas
FROM    dbo.SIG_CUADRO_X_CENTRO
GROUP BY ano_eje, estado, flag_modif
ORDER BY ano_eje, estado, flag_modif;


PRINT '===============================================================';
PRINT '3. Parametros que determinan la fase vigente del CMN';
PRINT '===============================================================';
/* Leidos por SP_INT_FASE_SIGA via sp_int_parametro_ejecutora_anio.
   La fase NO debe fijarse por constante en el codigo de integracion.     */

SELECT  ANO_EJE,
        SEC_EJEC,
        cod_maestro,
        valor,
        estado
FROM    dbo.SIG_PARAMETRO_EJECUTORA_ANIO
WHERE   cod_maestro IN ('FLAG_FASE_CN', 'FLAG_TECHO_ETAPAS')
ORDER BY ANO_EJE, SEC_EJEC, cod_maestro;


PRINT '===============================================================';
PRINT '4. Volumen de la ruta de MODIFICACION';
PRINT '===============================================================';

SELECT  'MODIFICADO_CAB'        AS tabla,
        ANNO_EJEC,
        COUNT(*)                AS filas,
        COUNT(DISTINCT CENTRO_COSTO) AS centros
FROM    dbo.SIG_CUADRO_MODIFICADO
GROUP BY ANNO_EJEC
ORDER BY ANNO_EJEC;

/* Los tres ejes que codifican la solicitud de modificacion:
     ESTADO           I / E / C / IT / ET
     PROCEDENCIA      N (nuevo) / C (viene del cuadro) / T (transferencia)
     MOTIVO_SOLICITUD 0 (sin solicitud) / 1 / 2 / 3
   FLAG_MODIFICADO=1 marca la fila alcanzada por una solicitud.            */

SELECT  'MODIFICADO_DET'        AS tabla,
        ANNO_EJEC,
        ESTADO,
        PROCEDENCIA,
        FLAG_MODIFICADO,
        FLAG_SOLICITUD,
        MOTIVO_SOLICITUD,
        COUNT(*)                AS filas
FROM    dbo.SIG_CUADRO_MODIFICADO_DET
WHERE   ANNO_EJEC = ANNO_PROG          -- solo el anio base, para no cuadruplicar
GROUP BY ANNO_EJEC, ESTADO, PROCEDENCIA,
         FLAG_MODIFICADO, FLAG_SOLICITUD, MOTIVO_SOLICITUD
ORDER BY ANNO_EJEC, ESTADO, PROCEDENCIA, MOTIVO_SOLICITUD;


PRINT '===============================================================';
PRINT '5. Claves de las tablas de modificacion';
PRINT '===============================================================';

SELECT  OBJECT_NAME(i.object_id)  AS tabla,
        i.name                    AS indice,
        i.is_primary_key          AS es_pk,
        ic.key_ordinal            AS orden,
        c.name                    AS columna
FROM    sys.indexes AS i
JOIN    sys.index_columns AS ic
  ON    ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN    sys.columns AS c
  ON    c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE   OBJECT_NAME(i.object_id) IN ('SIG_CUADRO_MODIFICADO',
                                     'SIG_CUADRO_MODIFICADO_DET',
                                     'SIG_CUADRO_MODIFICADO_SALDO',
                                     'SIG_CUADRO_MODIFICADO_CMN')
  AND   i.is_unique = 1
ORDER BY tabla, indice, ic.key_ordinal;


PRINT '===============================================================';
PRINT '6. Ausencia de disparadores en el nucleo CMN';
PRINT '===============================================================';
/* Si esta consulta devuelve filas, la estrategia de integracion debe
   revisarse: habria efectos colaterales no contemplados.                 */

SELECT  OBJECT_NAME(parent_id)  AS objeto,
        name                    AS disparador,
        is_disabled
FROM    sys.triggers
WHERE   OBJECT_NAME(parent_id) IN ('SIG_CUADRO_NECESIDAD',
                                   'SIG_CUADRO_NECESIDAD_DET',
                                   'SIG_CUADRO_MODIFICADO',
                                   'SIG_CUADRO_MODIFICADO_DET',
                                   'SIG_CUADRO_MODIFICADO_SALDO',
                                   'SIG_CUADRO_MODIFICADO_CMN');
