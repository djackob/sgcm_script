/*
===============================================================================
  SIGCM - Semilla S018 : Que transicion avanza y cierra la observacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  V029 agrego sigcm.Transicion.AccionObservacion. Aqui se reparte, por modulo,
  en que punto del flujo la observacion pasa de PENDIENTE a RECEPCIONADA, a
  SUBSANADA y finalmente a CERRADA.

  ---------------------------------------------------------------------------
  CMN: donde va el cierre, y por que no va antes
  ---------------------------------------------------------------------------
  El camino de subsanacion es

    CMN_OBSERVADO -> CMN_SUBSANAR -> CMN_SUBS_AU_COORD -> CMN_SUBS_COORD_DERIVAR
    -> CMN_SUBS_AU_JEFE -> CMN_SUBS_JEFE_ENVIAR -> Abastecimiento / OA

  RECEPCIONAR va en la entrada a CMN_OBSERVADO, que es el estado donde el
  especialista del area usuaria recien puede corregir. Son sus DOS entradas: la
  larga por el coordinador (CMN_OBS_AU_COORD_DERIVAR) y el salto directo del
  jefe (CMN_OBS_AU_JEFE_DERIVAR_ESP, S006). Marcar solo una dejaria la mitad de
  los expedientes sin recepcionar segun por donde bajaron.

  SUBSANAR va en CMN_SUBSANAR: es la unica transicion del tramo que exige
  comentario, y ese comentario ES la respuesta a la observacion.

  CERRAR va en CMN_SUBS_JEFE_ENVIAR y NO en CMN_SUBSANAR, por dos razones:

  1. Mientras el expediente sigue dentro del area usuaria -coordinador, jefe-
     la observacion no esta respondida ante quien la hizo. El jefe todavia
     puede no firmar. Cerrarla al primer paso declararia satisfecho un tramite
     que aun no salio de la unidad.

  2. sigcm.fnEstadoDestinoTransicion (F001) calcula el destino real de
     CMN_SUBS_JEFE_ENVIAR leyendo la observacion ABIERTA del expediente -Estado
     IN ('PENDIENTE','RECEPCIONADA','SUBSANADA')- para aplicar la regla "lo que
     observa OA vuelve a OA, lo que observa Abastecimiento vuelve a
     Abastecimiento". La usan las bandejas (F002, F005), la lista de acciones y
     el motor (F004), que la evalua ANTES del UPDATE del expediente y antes de
     cerrar la observacion, en esa misma transicion. Cerrarla en CMN_SUBSANAR
     borraria ese dato justo antes de que se necesite, y el expediente subsanado
     volveria al destino equivocado. Por eso 'SUBSANADA' es un estado y no un
     adorno: libera el candado de CONFLICTO_OBSERVACION -que solo mira PENDIENTE
     y RECEPCIONADA- sin perder todavia el estado de retorno.

  ---------------------------------------------------------------------------
  Requerimiento: un solo paso
  ---------------------------------------------------------------------------
  Alli el tramo no existe: REQ_SUBSANAR va de REQ_OBSERVADO directo a
  REQ_BORRADOR y el requerimiento vuelve a recorrer el flujo entero, con sus
  firmas. No hay un "remitir subsanado" posterior donde colgar el cierre, y
  dejar la observacion abierta impediria observar el requerimiento en la
  segunda vuelta, que es exactamente el defecto que se corrige. Asi que
  REQ_SUBSANAR CIERRA. F004 rellena en ese mismo acto la recepcion y la
  subsanacion que el flujo de Requerimiento no registra por separado, para no
  violar CK_sigcm_Observacion_Recepcion.

  El modulo PAGO no aparece: sus devoluciones (PAG_OBSERVAR_AU, PAG_OBSERVAR_UC_*)
  tienen GeneraObservacion=0 y no crean filas en sigcm.Observacion.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Reparto por transicion                                                  */
/* -------------------------------------------------------------------------- */

DECLARE @Accion TABLE (CodigoTransicion varchar(70), AccionObservacion varchar(15));
INSERT INTO @Accion VALUES
  /* CMN */
  ('CMN_OBS_AU_COORD_DERIVAR',    'RECEPCIONAR'),
  ('CMN_OBS_AU_JEFE_DERIVAR_ESP', 'RECEPCIONAR'),
  ('CMN_SUBSANAR',                'SUBSANAR'),
  ('CMN_SUBS_JEFE_ENVIAR',        'CERRAR'),
  /* Requerimiento */
  ('REQ_SUBSANAR',                'CERRAR');

UPDATE d
   SET d.AccionObservacion = s.AccionObservacion
  FROM sigcm.Transicion AS d
  JOIN @Accion AS s ON s.CodigoTransicion = d.CodigoTransicion
 WHERE ISNULL(d.AccionObservacion, '') <> s.AccionObservacion;
GO

/* -------------------------------------------------------------------------- */
/* 2. Reparacion de las observaciones que quedaron colgadas                   */
/* -------------------------------------------------------------------------- */

/*
  Antes de V029 ninguna rutina cerraba una observacion. Un ambiente que ya
  hubiera observado expedientes tiene filas en PENDIENTE cuyo expediente hace
  rato salio del circuito de subsanacion -esta en Abastecimiento, aprobado o
  finalizado- y que siguen bloqueando toda observacion futura sobre el.

  Se cierran SOLO esas: las que ya no se corresponden con el estado del
  expediente. Una observacion cuyo expediente sigue en un estado del circuito
  es una observacion viva y se deja como esta, para que el flujo la avance por
  su camino normal.

  RecepcionadaEn se rellena con la fecha de creacion, no con la de hoy:
  CK_sigcm_Observacion_Recepcion exige el dato para salir de 'PENDIENTE' y
  fechar hoy una recepcion que ocurrio hace meses seria inventar un hecho.
*/
DECLARE @Circuito TABLE (CodigoEstado varchar(60) PRIMARY KEY);
INSERT INTO @Circuito VALUES
  ('CMN_OBS_ABAST_COORD'), ('CMN_OBS_ABAST_JEFE'), ('CMN_OBS_AU_JEFE'),
  ('CMN_OBS_AU_COORD'),    ('CMN_OBSERVADO'),
  ('CMN_SUBS_AU_COORD'),   ('CMN_SUBS_AU_JEFE'),
  ('REQ_OBSERVADO');

DECLARE @Reparadas int;

UPDATE o
   SET o.Estado            = 'CERRADA',
       o.RecepcionadaEn    = COALESCE(o.RecepcionadaEn, o.FechaCreacionAuditoria, GETDATE()),
       o.CerradaEn         = COALESCE(o.CerradaEn, GETDATE()),
       o.UsuarioModificacionAuditoria  = 'S018',
       o.FechaModificacionAuditoria    = GETDATE(),
       o.ProgramaModificacionAuditoria = 'S018__observacion_cierre'
  FROM sigcm.Observacion AS o
  JOIN sigcm.Expediente  AS e ON e.IdExpediente = o.IdExpediente
 WHERE o.Activo = 1
   AND o.Estado IN ('PENDIENTE','RECEPCIONADA')
   AND e.CodigoEstado NOT IN (SELECT CodigoEstado FROM @Circuito);

SET @Reparadas = @@ROWCOUNT;
PRINT CONCAT('S018: observaciones colgadas cerradas por reparacion: ', @Reparadas, '.');
GO

PRINT 'S018 aplicada: recepcion, subsanacion y cierre de observaciones repartidos por transicion.';
GO
