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

  HISTORIA: se ejecuto el 2026-08-20 sobre cuatro centros y se REVIRTIO el
  mismo dia; las banderas volvieron a NULL, como estaban. Ademas resulto
  innecesario: flag_da_aprob solo la pide la pantalla "Demanda Adicional", que
  no usamos. Lo que registra el SIGCM se verifica en Modificacion de C.M.N.

  Ver Proyecto/SIGA_APLICATIVO.md, seccion "Regla: no se corrige data dentro de
  SIGA_1750".
*/

/*
===============================================================================
  Habilitacion de la Demanda Adicional para un area usuaria
  Base: SIGA_1750  (copia local de trabajo)

  QUE ES ESTO
  -----------
  Para que el aplicativo abra "Demanda Adicional - Identificacion" no basta con
  que el centro de costo este en estado '4' (Consolidacion y Aprobacion). Hace
  falta ademas una HABILITACION explicita por area usuaria.

  Evidencia directa, capturada con Extended Events mientras el aplicativo
  mostraba el mensaje "Verificar Habilitacion de Demanda Adicional". La ultima
  consulta que envio antes del mensaje fue exactamente esta:

      select flag_da_aprob from sig_cuadro_x_centro
       WHERE ano_eje = 2026 AND sec_ejec = 1750 AND centro_costo = '01.07.05.03'

  En SIG_CUADRO_X_CENTRO hay dos banderas, una por fase:

      flag_da_prog   Demanda Adicional de la Fase Clasificacion
      flag_da_aprob  Demanda Adicional de la Fase Consolidacion  <- la que pide
                                                                    esta pantalla

  En esta copia estan en NULL en los 131 registros de 2024, 2025 y 2026: nadie
  las habilito nunca, para ningun centro. Por eso la pantalla no abre para
  ninguna area usuaria, no solo para la de prueba.

  QUIEN LA OTORGA
  ---------------
  Abastecimiento, desde el propio SIGA. El UPDATE vive en el mismo modulo que
  muestra el mensaje (sig_aba_wind20_te.pbd):

      update sig_cuadro_x_centro set flag_da_aprob = <valor>
       where ano_eje = ... and sec_ejec = ... and centro_costo = ...

  ES UNA DECISION DE GESTION, NO UN DATO TECNICO. El SIGCM no debe escribir
  nunca esta bandera: equivaldria a auto-otorgarse el permiso para modificar el
  cuadro. Este script existe solo para poder DEMOSTRAR el flujo en la copia
  local, donde no hay quien la otorgue.

  MODO DE USO
  -----------
  Ejecutar la seccion 1 para habilitar; la seccion 2 para devolverlo a como
  estaba. Ambas imprimen el antes y el despues.
===============================================================================
*/

USE [SIGA_1750];
GO
SET NOCOUNT ON;
GO

/*
  Los centros a habilitar. Son cuatro y no uno porque el Anexo 4 multiple agrupa
  Anexos 3 de varias areas usuarias: si solo se habilita una, en el aplicativo se
  vera un cuarto de la prueba. Son las mismas cuatro que siembra
  db/90_pruebas/S904__casos_anexo4_multiple.sql.

  Agregar o quitar centros es editar esta lista; el resto del script no cambia.
*/
DECLARE @Centros TABLE (centro varchar(15), area varchar(10));
INSERT INTO @Centros VALUES
    ('01.07.05.03', 'OTI'),
    ('01.07.05.01', 'UDS'),
    ('01.07.05.02', 'US'),
    ('01.07.04',    'ORH');

DECLARE @AnoEje      numeric(4,0) = 2026;
DECLARE @SecEjec     numeric(6,0) = 1750;

PRINT '===== ANTES =====';
SELECT c.area, x.ano_eje, x.centro_costo, x.estado, x.flag_da_prog, x.flag_da_aprob
  FROM @Centros AS c
  JOIN dbo.SIG_CUADRO_X_CENTRO AS x
    ON x.ano_eje=@AnoEje AND x.sec_ejec=@SecEjec AND x.centro_costo=c.centro
 ORDER BY c.area;

/* -------------------------------------------------------------------------- */
/* 1. HABILITAR                                                                */
/* -------------------------------------------------------------------------- */
/* Se habilita solo la fase de Consolidacion, que es la que pide la pantalla
   "Demanda Adicional - Identificacion". flag_da_prog se deja como estaba: no
   hace falta y cambiar de mas es cambiar sin saber. */

UPDATE x
   SET x.flag_da_aprob = '1'
  FROM dbo.SIG_CUADRO_X_CENTRO AS x
  JOIN @Centros AS c ON c.centro = x.centro_costo
 WHERE x.ano_eje=@AnoEje AND x.sec_ejec=@SecEjec
   AND x.flag_da_aprob IS NULL;

PRINT '  Filas habilitadas: ' + CONVERT(varchar(10), @@ROWCOUNT);

/* El estado del cuadro no lo toca este script, pero conviene verlo: un centro
   que no este en '4' no abre la pantalla aunque tenga la bandera. */
IF EXISTS (SELECT 1 FROM dbo.SIG_CUADRO_X_CENTRO AS x
             JOIN @Centros AS c ON c.centro = x.centro_costo
            WHERE x.ano_eje=@AnoEje AND x.sec_ejec=@SecEjec AND x.estado <> '4')
    PRINT '  [AVISO] Algun centro de la lista NO esta en estado 4: no abrira la pantalla.';

PRINT '===== DESPUES =====';
SELECT c.area, x.ano_eje, x.centro_costo, x.estado, x.flag_da_prog, x.flag_da_aprob
  FROM @Centros AS c
  JOIN dbo.SIG_CUADRO_X_CENTRO AS x
    ON x.ano_eje=@AnoEje AND x.sec_ejec=@SecEjec AND x.centro_costo=c.centro
 ORDER BY c.area;
GO

/* -------------------------------------------------------------------------- */
/* 2. DESHACER                                                                 */
/* -------------------------------------------------------------------------- */
/* Devuelve la bandera a NULL, que es como estaba antes de esta prueba y como
   siguen todos los demas centros.

UPDATE dbo.SIG_CUADRO_X_CENTRO
   SET flag_da_aprob = NULL
 WHERE ano_eje=2026 AND sec_ejec=1750
   AND centro_costo IN ('01.07.05.03','01.07.05.01','01.07.05.02','01.07.04');

SELECT ano_eje, centro_costo, estado, flag_da_prog, flag_da_aprob
  FROM dbo.SIG_CUADRO_X_CENTRO
 WHERE ano_eje=2026 AND sec_ejec=1750
   AND centro_costo IN ('01.07.05.03','01.07.05.01','01.07.05.02','01.07.04');
*/
