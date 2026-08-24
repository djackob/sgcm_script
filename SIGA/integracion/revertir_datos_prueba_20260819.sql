/*
###############################################################################
##                                                                           ##
##   NO EJECUTAR.  Este script ESCRIBE A MANO en SIGA_1750.                  ##
##                                                                           ##
###############################################################################

  Regla vigente desde 2026-08-20: sobre SIGA_1750 solo escribe el FLUJO, a
  traves de los procedimientos usp_ext_* homologados. La unica data que entra a
  SIGA es la que envia nuestro sistema.

  Este archivo se conserva como DOCUMENTACION de lo que se hizo y de como
  deshacerlo, no como herramienta. Ejecutarlo deja la base en un estado que
  ningun camino del sistema puede reproducir.

  QUE HACIA: borrar data de prueba directamente de SIGA. Si un caso de prueba
  queda mal, lo correcto es corregir el sistema y rehacer el caso desde el
  SIGCM, no limpiar SIGA a mano.

  Ver SIGA_APLICATIVO.md, seccion "Regla: no se corrige data dentro de
  SIGA_1750".
*/

/*
===============================================================================
  Reversion de los datos que dejaron las pruebas de integracion del SIGCM
  Base   : SIGA_1750  (copia local de trabajo)
  Fecha  : 2026-08-19

  QUE REVIERTE
  ------------
  1. La inclusion de prueba en la ruta de FORMULACION:
       SIG_CUADRO_NECESIDAD_DET  2026 / 1750 / 01.09 / sec 170 / item 1
       SIG_CUADRO_NECESIDAD      2026 / 1750 / 01.09 / sec 170
     La cabecera se borra entera porque su unico item es el de la prueba
     (verificado: ITEM_SEC 1 es la unica fila, CUSER_ID='w001').

  2. La exclusion de prueba en la ruta de MODIFICACION:
       item 2026 / 1750 / 01.01 / cuadro 1 / item 1, sus cuatro filas.
     Era un item REAL de 300 unidades registrado por NDIBURGA. Se reconstruye
     desde su propia foto previa SIG_CUADRO_MODIFICADO_DET_ORI TIPO='2', que
     guarda las doce cantidades mensuales de cada anio.
     Se borran ademas la foto previa, la solicitud 442 con su detalle y el
     movimiento de documento 4307.

  LO QUE NO SE PUEDE DEVOLVER
  ---------------------------
  CUSER_MOD / FECHA_MOD / EQUIPO_MOD del detalle y de la cabecera del cuadro
  fueron sobreescritos por la prueba y su valor anterior no quedo registrado en
  ninguna parte. Se dejan en NULL, que es lo que significa "no modificado".
  Es la unica huella que la reversion no borra del todo.

  LO QUE NO HAY QUE TOCAR
  -----------------------
  SIG_CUADRO_MODIFICADO_SALDO. La exclusion nunca lo modifico: los saldos 401
  a 404 siguen con sus 300 unidades intactas. Reconstruir el detalle desde la
  foto previa lo deja coherente sin escribir una sola fila de saldo.

  MODO DE USO
  -----------
  El script corre entero dentro de una transaccion y se autoverifica antes de
  confirmar. Si algo no cuadra, hace ROLLBACK y no deja nada a medias.
===============================================================================
*/

USE [SIGA_1750];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT '===== ANTES =====';
SELECT etiqueta = 'formulacion: cabecera de prueba', filas = COUNT(*)
  FROM dbo.SIG_CUADRO_NECESIDAD
 WHERE ANO_EJE=2026 AND SEC_EJEC=1750 AND CENTRO_COSTO='01.09'
   AND SECUENCIA=170 AND FASE_CUADRO=5;
SELECT etiqueta = 'formulacion: detalle de prueba', filas = COUNT(*)
  FROM dbo.SIG_CUADRO_NECESIDAD_DET
 WHERE ANO_EJE=2026 AND SEC_EJEC=1750 AND CENTRO_COSTO='01.09'
   AND SECUENCIA=170 AND FASE_CUADRO=5;
SELECT etiqueta = 'modificacion: item excluido', ANNO_PROG, ESTADO, MOTIVO_SOLICITUD,
       CANT_TOTAL, MNTO_TOTAL
  FROM dbo.SIG_CUADRO_MODIFICADO_DET
 WHERE ANNO_EJEC=2026 AND SEC_EJEC=1750 AND CENTRO_COSTO='01.01'
   AND SEC_CUADRO=1 AND SEC_ITEM=1 ORDER BY ANNO_PROG;
GO

BEGIN TRANSACTION;
GO

/* ------------------------------------------------------------------------- */
/* 1. Deshacer la exclusion: devolver las cantidades desde la foto previa     */
/* ------------------------------------------------------------------------- */

UPDATE d
   SET d.ESTADO           = 'C',    /* PROCEDENCIA='C' => vuelve a 'C' */
       d.FLAG_MODIFICADO  = '0',
       d.FLAG_SOLICITUD   = '0',
       d.MOTIVO_SOLICITUD = '0',
       d.FLG_MNTO_01 = o.FLG_MNTO_01_INI, d.FLG_MNTO_02 = o.FLG_MNTO_02_INI,
       d.FLG_MNTO_03 = o.FLG_MNTO_03_INI, d.FLG_MNTO_04 = o.FLG_MNTO_04_INI,
       d.FLG_MNTO_05 = o.FLG_MNTO_05_INI, d.FLG_MNTO_06 = o.FLG_MNTO_06_INI,
       d.FLG_MNTO_07 = o.FLG_MNTO_07_INI, d.FLG_MNTO_08 = o.FLG_MNTO_08_INI,
       d.FLG_MNTO_09 = o.FLG_MNTO_09_INI, d.FLG_MNTO_10 = o.FLG_MNTO_10_INI,
       d.FLG_MNTO_11 = o.FLG_MNTO_11_INI, d.FLG_MNTO_12 = o.FLG_MNTO_12_INI,
       d.CANT_01 = o.CANT_01_INI, d.CANT_02 = o.CANT_02_INI,
       d.CANT_03 = o.CANT_03_INI, d.CANT_04 = o.CANT_04_INI,
       d.CANT_05 = o.CANT_05_INI, d.CANT_06 = o.CANT_06_INI,
       d.CANT_07 = o.CANT_07_INI, d.CANT_08 = o.CANT_08_INI,
       d.CANT_09 = o.CANT_09_INI, d.CANT_10 = o.CANT_10_INI,
       d.CANT_11 = o.CANT_11_INI, d.CANT_12 = o.CANT_12_INI,
       d.CANT_TOTAL = o.CANT_TOTAL_INI,
       d.MNTO_01 = ROUND(o.CANT_01_INI * d.PRECIO_UNIT, 2),
       d.MNTO_02 = ROUND(o.CANT_02_INI * d.PRECIO_UNIT, 2),
       d.MNTO_03 = ROUND(o.CANT_03_INI * d.PRECIO_UNIT, 2),
       d.MNTO_04 = ROUND(o.CANT_04_INI * d.PRECIO_UNIT, 2),
       d.MNTO_05 = ROUND(o.CANT_05_INI * d.PRECIO_UNIT, 2),
       d.MNTO_06 = ROUND(o.CANT_06_INI * d.PRECIO_UNIT, 2),
       d.MNTO_07 = ROUND(o.CANT_07_INI * d.PRECIO_UNIT, 2),
       d.MNTO_08 = ROUND(o.CANT_08_INI * d.PRECIO_UNIT, 2),
       d.MNTO_09 = ROUND(o.CANT_09_INI * d.PRECIO_UNIT, 2),
       d.MNTO_10 = ROUND(o.CANT_10_INI * d.PRECIO_UNIT, 2),
       d.MNTO_11 = ROUND(o.CANT_11_INI * d.PRECIO_UNIT, 2),
       d.MNTO_12 = ROUND(o.CANT_12_INI * d.PRECIO_UNIT, 2),
       d.MNTO_TOTAL = ROUND(o.CANT_TOTAL_INI * d.PRECIO_UNIT, 2),
       d.CUSER_MOD = NULL, d.FECHA_MOD = NULL, d.EQUIPO_MOD = NULL
  FROM dbo.SIG_CUADRO_MODIFICADO_DET AS d
  JOIN dbo.SIG_CUADRO_MODIFICADO_DET_ORI AS o
    ON o.SEC_EJEC = d.SEC_EJEC AND o.ANNO_EJEC = d.ANNO_EJEC
   AND o.CENTRO_COSTO = d.CENTRO_COSTO AND o.SEC_CUADRO = d.SEC_CUADRO
   AND o.SEC_ITEM = d.SEC_ITEM AND o.ANNO_PROG = d.ANNO_PROG
   AND o.TIPO = '2'
 WHERE d.ANNO_EJEC = 2026 AND d.SEC_EJEC = 1750
   AND d.CENTRO_COSTO = '01.01' AND d.SEC_CUADRO = 1 AND d.SEC_ITEM = 1;

IF @@ROWCOUNT <> 4
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('No se restauraron exactamente las cuatro filas del item. Nada se cambio.', 16, 1);
END
GO

/* ------------------------------------------------------------------------- */
/* 2. Borrar la foto previa, la solicitud y el movimiento de documento        */
/* ------------------------------------------------------------------------- */

DELETE FROM dbo.SIG_CUADRO_MODIFICADO_DET_ORI
 WHERE ANNO_EJEC = 2026 AND SEC_EJEC = 1750 AND CENTRO_COSTO = '01.01'
   AND SEC_CUADRO = 1 AND SEC_ITEM = 1 AND TIPO = '2';

DELETE FROM dbo.SIG_DOCUMENTO_ESTADO
 WHERE SEC_EJEC = 1750 AND SOL_ANNO_EJEC = 2026 AND SOL_CC = '01.01'
   AND SEC_SOL_MOD = 442 AND CUSER_ID = 'PRUEBA_W001';

DELETE FROM dbo.SIG_SOLICITUD_MODIFICACION_DET
 WHERE SEC_EJEC = 1750 AND ANNO_EJEC = 2026 AND CENTRO_COSTO = '01.01'
   AND SEC_SOL_MOD = 442 AND CUSER_ID = 'PRUEBA_W001';

DELETE FROM dbo.SIG_SOLICITUD_MODIFICACION
 WHERE SEC_EJEC = 1750 AND ANNO_EJEC = 2026 AND CENTRO_COSTO = '01.01'
   AND SEC_SOL_MOD = 442 AND CUSER_ID = 'PRUEBA_W001';

/* La cabecera del cuadro solo fue tocada en su auditoria. */
UPDATE dbo.SIG_CUADRO_MODIFICADO
   SET CUSER_MOD = NULL, FECHA_MOD = NULL, EQUIPO_MOD = NULL
 WHERE SEC_EJEC = 1750 AND ANNO_EJEC = 2026 AND CENTRO_COSTO = '01.01'
   AND SEC_CUADRO = 1 AND CUSER_MOD = 'PRUEBA_W001';
GO

/* ------------------------------------------------------------------------- */
/* 3. Borrar la inclusion de prueba de la ruta de formulacion                 */
/* ------------------------------------------------------------------------- */

DELETE FROM dbo.SIG_CUADRO_NECESIDAD_DET
 WHERE ANO_EJE = 2026 AND SEC_EJEC = 1750 AND CENTRO_COSTO = '01.09'
   AND SECUENCIA = 170 AND FASE_CUADRO = 5 AND CUSER_ID = 'w001';

DELETE FROM dbo.SIG_CUADRO_NECESIDAD
 WHERE ANO_EJE = 2026 AND SEC_EJEC = 1750 AND CENTRO_COSTO = '01.09'
   AND SECUENCIA = 170 AND FASE_CUADRO = 5 AND CUSER_ID = 'w001'
   AND NOT EXISTS (SELECT 1 FROM dbo.SIG_CUADRO_NECESIDAD_DET AS x
                    WHERE x.ANO_EJE = 2026 AND x.SEC_EJEC = 1750
                      AND x.CENTRO_COSTO = '01.09' AND x.SECUENCIA = 170
                      AND x.FASE_CUADRO = 5);
GO

/* ------------------------------------------------------------------------- */
/* 4. Autoverificacion antes de confirmar                                     */
/* ------------------------------------------------------------------------- */

DECLARE @errores int = 0, @msg nvarchar(400) = N'';

IF EXISTS (SELECT 1 FROM dbo.SIG_CUADRO_MODIFICADO_DET
            WHERE ANNO_EJEC=2026 AND SEC_EJEC=1750 AND CENTRO_COSTO='01.01'
              AND SEC_CUADRO=1 AND SEC_ITEM=1
              AND (ESTADO<>'C' OR MOTIVO_SOLICITUD<>'0' OR FLAG_MODIFICADO<>'0'))
BEGIN SET @errores+=1; SET @msg=N'El item no volvio al estado C/0/0.'; END

IF (SELECT SUM(CANT_TOTAL) FROM dbo.SIG_CUADRO_MODIFICADO_DET
     WHERE ANNO_EJEC=2026 AND SEC_EJEC=1750 AND CENTRO_COSTO='01.01'
       AND SEC_CUADRO=1 AND SEC_ITEM=1) <> 900
BEGIN SET @errores+=1; SET @msg=N'Las cantidades restauradas no suman las 900 unidades originales.'; END

IF EXISTS (SELECT 1 FROM dbo.SIG_CUADRO_MODIFICADO_DET
            WHERE ANNO_EJEC=2026 AND SEC_EJEC=1750 AND CENTRO_COSTO='01.01'
              AND SEC_CUADRO=1 AND SEC_ITEM=1
              AND CANT_TOTAL <> CANT_01+CANT_02+CANT_03+CANT_04+CANT_05+CANT_06
                              + CANT_07+CANT_08+CANT_09+CANT_10+CANT_11+CANT_12)
BEGIN SET @errores+=1; SET @msg=N'CANT_TOTAL no es la suma de los doce meses.'; END

IF EXISTS (SELECT 1 FROM dbo.SIG_CUADRO_MODIFICADO_DET_ORI WHERE TIPO='2')
BEGIN SET @errores+=1; SET @msg=N'Quedaron fotos previas con TIPO=2.'; END

IF EXISTS (SELECT 1 FROM dbo.SIG_SOLICITUD_MODIFICACION WHERE CUSER_ID='PRUEBA_W001')
    OR EXISTS (SELECT 1 FROM dbo.SIG_SOLICITUD_MODIFICACION_DET WHERE CUSER_ID='PRUEBA_W001')
    OR EXISTS (SELECT 1 FROM dbo.SIG_DOCUMENTO_ESTADO WHERE CUSER_ID='PRUEBA_W001')
BEGIN SET @errores+=1; SET @msg=N'Quedo rastro de PRUEBA_W001 en solicitudes o documentos.'; END

IF EXISTS (SELECT 1 FROM dbo.SIG_CUADRO_NECESIDAD_DET WHERE CUSER_ID='w001')
    OR EXISTS (SELECT 1 FROM dbo.SIG_CUADRO_NECESIDAD WHERE CUSER_ID='w001')
BEGIN SET @errores+=1; SET @msg=N'Quedo rastro de w001 en la ruta de formulacion.'; END

IF @errores > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR(@msg, 16, 1);
END
ELSE
BEGIN
    COMMIT TRANSACTION;
    PRINT '  Reversion confirmada.';
END
GO

PRINT '===== DESPUES =====';
SELECT etiqueta='item restaurado', ANNO_PROG, ESTADO, PROCEDENCIA, FLAG_MODIFICADO,
       MOTIVO_SOLICITUD, CANT_TOTAL, MNTO_TOTAL, CUSER_ID, CUSER_MOD
  FROM dbo.SIG_CUADRO_MODIFICADO_DET
 WHERE ANNO_EJEC=2026 AND SEC_EJEC=1750 AND CENTRO_COSTO='01.01'
   AND SEC_CUADRO=1 AND SEC_ITEM=1 ORDER BY ANNO_PROG;

SELECT etiqueta='rastros restantes',
       cn      = (SELECT COUNT(*) FROM dbo.SIG_CUADRO_NECESIDAD     WHERE CUSER_ID='w001'),
       cn_det  = (SELECT COUNT(*) FROM dbo.SIG_CUADRO_NECESIDAD_DET WHERE CUSER_ID='w001'),
       ori2    = (SELECT COUNT(*) FROM dbo.SIG_CUADRO_MODIFICADO_DET_ORI WHERE TIPO='2'),
       sol     = (SELECT COUNT(*) FROM dbo.SIG_SOLICITUD_MODIFICACION WHERE CUSER_ID='PRUEBA_W001'),
       sol_det = (SELECT COUNT(*) FROM dbo.SIG_SOLICITUD_MODIFICACION_DET WHERE CUSER_ID='PRUEBA_W001'),
       doc     = (SELECT COUNT(*) FROM dbo.SIG_DOCUMENTO_ESTADO WHERE CUSER_ID='PRUEBA_W001');
GO
