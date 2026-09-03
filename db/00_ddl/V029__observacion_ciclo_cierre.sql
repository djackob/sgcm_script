/*
===============================================================================
  SIGCM - V029 : Cierre del ciclo de vida de la observacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  QUE ESTABA ROTO
  ---------------
  sigcm.Observacion nace en 'PENDIENTE' (F004, cuando la transicion declara
  GeneraObservacion=1) y ahi se quedaba para siempre: no habia un solo UPDATE
  sobre la tabla en todo el repositorio. RecepcionadaEn, SubsanadaEn, CerradaEn
  y Respuesta -columnas que V003 creo para llevar ese recorrido- nunca se
  llenaban.

  La consecuencia no era cosmetica. F004 rechaza con CONFLICTO_OBSERVACION
  (51220) cualquier intento de observar un expediente que ya tenga una
  observacion en 'PENDIENTE' o 'RECEPCIONADA'. Un expediente observado una sola
  vez quedaba inmunizado: ni OA ni Abastecimiento podian volver a observarlo
  nunca, aunque el area usuaria hubiera subsanado y devuelto algo peor. El
  indice UQ_sigcm_Observacion_Abierta lo sellaba tambien a nivel de motor.

  QUE SE AGREGA
  -------------
  Una columna en sigcm.Transicion, simetrica de GeneraObservacion: si esa marca
  dice que transiciones ABREN una observacion, AccionObservacion dice que
  transiciones la HACEN AVANZAR, y hasta donde.

      RECEPCIONAR  el expediente llego al area usuaria y su gente lo tomo:
                   PENDIENTE -> RECEPCIONADA. Es la condicion que el CHECK
                   CK_sigcm_Observacion_Recepcion exige para salir de
                   'PENDIENTE': "el area usuaria debe recepcionar antes de
                   poder corregir" (V003).
      SUBSANAR     el especialista respondio: -> SUBSANADA, y su comentario
                   queda en Respuesta.
      CERRAR       lo subsanado salio del area usuaria y volvio a quien
                   observo: -> CERRADA, con CerradaEn. Recien aqui el
                   expediente vuelve a ser observable.

  Es una columna y no codigo por la misma razon que GeneraObservacion lo es:
  el motor de F004 no sabe que existe CMN ni Requerimiento, y agregar un
  escalon a un flujo tiene que seguir siendo agregar filas (CONTEXTO.md,
  seccion 3). El modulo PAGO, que hoy no genera observaciones formales, no
  necesita ninguna fila y no cambia.

  El reparto concreto por transicion vive en la semilla S018.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'sigcm.Transicion', N'AccionObservacion') IS NULL
    ALTER TABLE sigcm.Transicion ADD AccionObservacion varchar(15) NULL;
GO

/* Los valores admitidos se declaran; una marca mal escrita en una semilla debe
   fallar al aplicarla y no quedar como una transicion que silenciosamente no
   hace nada. Y abrir y cerrar a la vez no es un caso del flujo: la transicion
   que observa crea la observacion, no la avanza. */
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
                WHERE name = N'CK_sigcm_Transicion_AccionObs'
                  AND parent_object_id = OBJECT_ID(N'sigcm.Transicion'))
    ALTER TABLE sigcm.Transicion WITH CHECK
        ADD CONSTRAINT CK_sigcm_Transicion_AccionObs
            CHECK (AccionObservacion IS NULL
                OR (AccionObservacion IN ('RECEPCIONAR','SUBSANAR','CERRAR')
                    AND GeneraObservacion = 0));
GO

PRINT 'V029 aplicada: sigcm.Transicion.AccionObservacion.';
GO
