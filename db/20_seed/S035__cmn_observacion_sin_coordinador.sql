/*
===============================================================================
  SIGCM - Semilla S035 : En CMN la observacion no pasa por el coordinador
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Coordinado con el area el 2026-09-08: EN CMN NO HAY COORDINADOR. Cuando un
  expediente vuelve observado, el jefe del area usuaria lo deriva a CUALQUIERA
  de sus especialistas, ese lo subsana y se lo devuelve al jefe, que lo firma y
  lo remite a Abastecimiento. Vale para TODAS las areas usuarias por igual.

  ---------------------------------------------------------------------------
  QUE CAMBIA, Y POR QUE
  ---------------------------------------------------------------------------
  S006 ya habia creado el salto directo Jefe -> Especialista
  (CMN_OBS_AU_JEFE_DERIVAR_ESP). S029 lo desactivo para que CMN se pareciera a
  Requerimiento, que si tiene coordinador. Esa simetria era el error: en CMN el
  area usuaria nunca paso por el coordinador -esta escrito en INIT.md y en
  CONTEXTO.md desde el principio-, y el unico sitio donde se habia colado era
  justamente el ciclo de observacion.

  Queda asi:

      ANTES                                  AHORA
      Jefe AU -> Coordinador AU              Jefe AU -> Especialista
      Coordinador -> Especialista            (el coordinador ya no interviene)
      Especialista -> Coordinador            Especialista -> Jefe AU
      Coordinador -> Jefe AU
      Jefe AU firma y remite                 Jefe AU firma y remite

  Dos escalones menos, y el que subsana le responde a quien le encargo.

  ---------------------------------------------------------------------------
  A QUIEN PUEDE DERIVAR EL JEFE
  ---------------------------------------------------------------------------
  A cualquier especialista de SU unidad: la arista CMN / AREA_JEFE ->
  AREA_ESPECIALISTA de sigcm.RolDerivacion tiene alcance MISMA_UNIDAD, asi que
  el combo se llena solo con los especialistas del area, sean uno o diez, y
  funciona igual en todas las areas usuarias sin sembrar nada por area.

  ---------------------------------------------------------------------------
  LOS ESTADOS DEL COORDINADOR NO SE BORRAN
  ---------------------------------------------------------------------------
  CMN_OBS_AU_COORD y CMN_SUBS_AU_COORD quedan sin transiciones activas que
  entren o salgan. No se eliminan porque un expediente historico pudo pasar por
  ellos y sigcm.Historial los referencia; se renombran para que quien los vea en
  una trazabilidad vieja sepa que son de un circuito retirado.
  Comprobado antes de aplicar: ningun expediente esta parado en ellos.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. El jefe deriva directo al especialista                                  */
/* -------------------------------------------------------------------------- */

UPDATE sigcm.Transicion
   SET Activo = 1,
       CodigoEstadoDestino = 'CMN_OBSERVADO',
       NombreAccion = 'Derivar al Especialista para subsanar',
       AccionObservacion = 'RECEPCIONAR'
 WHERE CodigoTransicion = 'CMN_OBS_AU_JEFE_DERIVAR_ESP';

/* El jefe y su secretaria. La secretaria hereda de AREA_JEFE en S033, que corre
   antes que esta semilla y por eso no alcanzo a ver esta transicion: se le
   concede aqui, con el mismo criterio -no exige firma-. */
INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT v.CodigoTransicion, v.CodigoRol
  FROM (VALUES
    ('CMN_OBS_AU_JEFE_DERIVAR_ESP', 'AREA_JEFE'),
    ('CMN_OBS_AU_JEFE_DERIVAR_ESP', 'AREA_SECRETARIA')
  ) AS v(CodigoTransicion, CodigoRol)
 WHERE EXISTS (SELECT 1 FROM sigcm.Rol r WHERE r.CodigoRol = v.CodigoRol AND r.Activo = 1)
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol d
                    WHERE d.CodigoTransicion = v.CodigoTransicion
                      AND d.CodigoRol = v.CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 2. El especialista devuelve directo al jefe                                */
/* -------------------------------------------------------------------------- */

UPDATE sigcm.Transicion
   SET CodigoEstadoDestino = 'CMN_SUBS_AU_JEFE',
       NombreAccion = 'Registrar la subsanacion y devolver al Jefe'
 WHERE CodigoTransicion = 'CMN_SUBSANAR';
GO

/* -------------------------------------------------------------------------- */
/* 3. Se retiran los dos pasos del coordinador                                */
/* -------------------------------------------------------------------------- */

UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion IN ('CMN_OBS_AU_JEFE_DERIVAR', 'CMN_OBS_AU_COORD_DERIVAR',
                            'CMN_SUBS_COORD_DERIVAR');

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion IN ('CMN_OBS_AU_JEFE_DERIVAR', 'CMN_OBS_AU_COORD_DERIVAR',
                            'CMN_SUBS_COORD_DERIVAR');
GO

UPDATE sigcm.Estado
   SET Nombre = 'Observado - Coordinador AU (circuito retirado)'
 WHERE CodigoEstado = 'CMN_OBS_AU_COORD' AND CodigoModulo = 'CMN';

UPDATE sigcm.Estado
   SET Nombre = 'Subsanado - Coordinador AU (circuito retirado)'
 WHERE CodigoEstado = 'CMN_SUBS_AU_COORD' AND CodigoModulo = 'CMN';
GO

/* -------------------------------------------------------------------------- */
/* 4. Comprobacion: el circuito tiene que quedar entero                       */
/* -------------------------------------------------------------------------- */

/* Si alguna de las cuatro patas falta, la semilla falla en vez de dejar el
   ciclo a medias: un expediente observado que no puede volver es peor que uno
   que no se puede observar. */
DECLARE @faltan int = (
    SELECT COUNT(*) FROM (VALUES
        ('CMN_OBS_AU_JEFE',  'CMN_OBSERVADO'),
        ('CMN_OBSERVADO',    'CMN_SUBS_AU_JEFE'),
        ('CMN_SUBS_AU_JEFE', 'CMN_EN_ABAST_JEFE')
    ) AS v(origen, destino)
     WHERE NOT EXISTS (SELECT 1 FROM sigcm.Transicion t
                        WHERE t.CodigoEstadoOrigen = v.origen
                          AND t.CodigoEstadoDestino = v.destino
                          AND t.Activo = 1));

IF @faltan > 0
    THROW 51935, 'CONFLICTO_CONFIGURACION: el ciclo de observacion del CMN quedo incompleto.', 1;
GO

PRINT 'S035 aplicada: en CMN la observacion va Jefe AU -> Especialista -> Jefe AU, sin coordinador.';
GO
