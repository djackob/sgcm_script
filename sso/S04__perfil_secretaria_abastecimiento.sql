/*
===============================================================================
  SIGCM - SSO S04 : Secretaria de Abastecimiento
  Motor  : PostgreSQL (base del SSO institucional, esquema login)
  NO SE EJECUTA EN DBSIGCM NI LO APLICA instalar.ps1

  QUE HACE
  --------
  1. Crea el perfil PE102 SECRETARIA ABASTECIMIENTO si no existe.
  2. Lo liga al sistema S0073 (SGCM-I).
  3. Si se invoca con -v dni=..., ademas se lo asigna a esa persona sobre la
     dependencia indicada. Sin dni solo crea el perfil.

  POR QUE UN CODIGO PROPIO Y NO PE100/PE101
  -----------------------------------------
  PE100 y PE101 (sso/S03) los traduce S033 a AREA_SECRETARIA, que es el area
  usuaria: quien pide. Abastecimiento es quien tramita, y su secretaria tiene
  otras acciones -deriva dentro de Abastecimiento, no dentro del area usuaria-.
  Son roles distintos del mismo oficio, asi que llevan codigos distintos, igual
  que JEFE UA (PE082) y JEFE OFICINA (PE079) son dos perfiles y no uno.

  A diferencia del area usuaria, aqui basta un solo codigo: Abastecimiento es
  una unidad concreta -la UA-, no "cualquier oficina o unidad que contrate".

  QUE NO HACE
  -----------
  No crea usuarios. No toca contrasenias. La persona tiene que existir ya.

  TODO SE RESUELVE POR CODIGO, NUNCA POR ID
  -----------------------------------------
  cod_sistema S0073, cod_perfil PE102, cod_dependencia. Los id son distintos en
  cada ambiente.

  USO
  ---
    Solo crear el perfil:
      psql -h <host> -p <puerto> -U <usuario> -d saa_ \
           -f sso/S04__perfil_secretaria_abastecimiento.sql

    Crear y asignar a una persona:
      psql -h <host> -p <puerto> -U <usuario> -d saa_ \
           -v dni=46970816 -v cod_dependencia=D0017 \
           -f sso/S04__perfil_secretaria_abastecimiento.sql

  Idempotente: correrlo dos veces no duplica el perfil ni el acceso.

  PARA REVERTIRLO
  ---------------
    UPDATE login.td_login_perfil_sistema ps
       SET activo = false
      FROM login.tm_login_perfil p, login.td_login_sistema s
     WHERE ps.id_perfil = p.id_perfil AND ps.id_sistema = s.id_sistema
       AND p.cod_perfil = 'PE102' AND s.cod_sistema = 'S0073';
===============================================================================
*/

\set ON_ERROR_STOP on

\if :{?dni}
\else
\set dni ''
\endif

\if :{?cod_dependencia}
\else
\set cod_dependencia ''
\endif

SELECT set_config('sigcm.dni', :'dni', false);
SELECT set_config('sigcm.cod_dependencia', :'cod_dependencia', false);

BEGIN;

DO $$
DECLARE
    _dni               varchar := NULLIF(btrim(current_setting('sigcm.dni', true)), '');
    _cod_dependencia   varchar := NULLIF(btrim(current_setting('sigcm.cod_dependencia', true)), '');
    _auditor           varchar := COALESCE(NULLIF(btrim(current_setting('sigcm.dni', true)), ''), 'SIGCM-S04');
    _cod_perfil        varchar := 'PE102';
    _descripcion       varchar := 'SECRETARIA ABASTECIMIENTO';
    _id_usuario        integer;
    _id_perfil         integer;
    _id_sistema        integer;
    _id_perfil_sistema integer;
    _id_dependencia    integer;
    _id_acceso         integer;
BEGIN
    /* ---- El sistema S0073 ------------------------------------------- */
    SELECT s.id_sistema INTO _id_sistema
      FROM login.td_login_sistema s
     WHERE s.cod_sistema = 'S0073' AND COALESCE(s.activo, true);

    IF _id_sistema IS NULL THEN
        RAISE EXCEPTION 'No existe el sistema S0073 activo.';
    END IF;

    /* ---- El perfil PE102 -------------------------------------------- */
    SELECT p.id_perfil INTO _id_perfil
      FROM login.tm_login_perfil p
     WHERE p.cod_perfil = _cod_perfil;

    IF _id_perfil IS NULL THEN
        INSERT INTO login.tm_login_perfil
              (cod_perfil, descripcion, activo, usuario_creacion, fecha_creacion)
        VALUES (_cod_perfil, _descripcion, true, _auditor, now())
        RETURNING id_perfil INTO _id_perfil;
        RAISE NOTICE 'Perfil % % creado (id_perfil %).', _cod_perfil, _descripcion, _id_perfil;
    ELSE
        UPDATE login.tm_login_perfil
           SET descripcion = _descripcion,
               activo = true,
               usuario_modificacion = _auditor,
               fecha_modificacion = now()
         WHERE id_perfil = _id_perfil
           AND (descripcion IS DISTINCT FROM _descripcion OR activo IS DISTINCT FROM true);
        RAISE NOTICE 'Perfil % ya existia (id_perfil %); queda activo.', _cod_perfil, _id_perfil;
    END IF;

    SELECT ps.id_perfil_sistema INTO _id_perfil_sistema
      FROM login.td_login_perfil_sistema ps
     WHERE ps.id_perfil = _id_perfil AND ps.id_sistema = _id_sistema;

    IF _id_perfil_sistema IS NULL THEN
        INSERT INTO login.td_login_perfil_sistema
              (id_perfil, id_sistema, activo, usuario_creacion, fecha_creacion)
        VALUES (_id_perfil, _id_sistema, true, _auditor, now())
        RETURNING id_perfil_sistema INTO _id_perfil_sistema;
        RAISE NOTICE '% ligado a S0073 (id_perfil_sistema %).', _cod_perfil, _id_perfil_sistema;
    ELSE
        UPDATE login.td_login_perfil_sistema
           SET activo = true, usuario_modificacion = _auditor, fecha_modificacion = now()
         WHERE id_perfil_sistema = _id_perfil_sistema AND activo IS DISTINCT FROM true;
        RAISE NOTICE '% ya estaba ligado a S0073 (id_perfil_sistema %).', _cod_perfil, _id_perfil_sistema;
    END IF;

    /* ---- La asignacion a una persona, solo si se pidio --------------- */
    IF _dni IS NULL THEN
        RAISE NOTICE 'Sin dni: se creo el perfil y no se asigno acceso a nadie.';
        RETURN;
    END IF;

    IF _cod_dependencia IS NULL THEN
        RAISE EXCEPTION 'Se indico dni pero no la dependencia. Invoque con  -v cod_dependencia=D0017';
    END IF;

    SELECT u.id_usuario INTO _id_usuario
      FROM login.tm_login_usuario u
     WHERE u.dni = _dni AND u.activo;

    IF _id_usuario IS NULL THEN
        RAISE EXCEPTION 'No hay ningun usuario activo con dni %. Este script no crea usuarios.', _dni;
    END IF;

    SELECT d.id_dependencia INTO _id_dependencia
      FROM login.tm_login_dependencia d
     WHERE d.cod_dependencia = _cod_dependencia AND COALESCE(d.activo, true);

    IF _id_dependencia IS NULL THEN
        RAISE EXCEPTION 'No hay dependencia activa con codigo %.', _cod_dependencia;
    END IF;

    SELECT a.id_acceso INTO _id_acceso
      FROM login.td_login_acceso a
     WHERE a.id_usuario = _id_usuario
       AND a.id_perfil_sistema = _id_perfil_sistema;

    IF _id_acceso IS NULL THEN
        INSERT INTO login.td_login_acceso
              (id_perfil_sistema, id_usuario, id_municipalidad, activo, usuario_creacion, fecha_creacion)
        VALUES (_id_perfil_sistema, _id_usuario, 0, true, _auditor, now())
        RETURNING id_acceso INTO _id_acceso;
        RAISE NOTICE 'Acceso % creado para % (id_acceso %).', _cod_perfil, _dni, _id_acceso;
    ELSE
        UPDATE login.td_login_acceso
           SET activo = true, usuario_modificacion = _auditor, fecha_modificacion = now()
         WHERE id_acceso = _id_acceso AND activo IS DISTINCT FROM true;
        RAISE NOTICE 'Acceso % ya existia para % (id_acceso %); queda activo.', _cod_perfil, _dni, _id_acceso;
    END IF;

    IF EXISTS (SELECT 1 FROM login.td_login_acceso_dependencia
                WHERE id_acceso = _id_acceso AND id_dependencia = _id_dependencia) THEN
        UPDATE login.td_login_acceso_dependencia
           SET activo = true, usuario_modificacion = _auditor, fecha_modificacion = now()
         WHERE id_acceso = _id_acceso AND id_dependencia = _id_dependencia
           AND activo IS DISTINCT FROM true;
    ELSE
        INSERT INTO login.td_login_acceso_dependencia
              (id_acceso, id_dependencia, activo, usuario_creacion, fecha_creacion)
        VALUES (_id_acceso, _id_dependencia, true, _auditor, now());
        RAISE NOTICE 'Dependencia % ligada al acceso %.', _cod_dependencia, _id_acceso;
    END IF;
END
$$;

COMMIT;

SELECT p.cod_perfil, p.descripcion AS perfil, s.cod_sistema, ps.activo
  FROM login.tm_login_perfil p
  JOIN login.td_login_perfil_sistema ps ON ps.id_perfil = p.id_perfil
  JOIN login.td_login_sistema s ON s.id_sistema = ps.id_sistema
 WHERE p.cod_perfil = 'PE102' AND s.cod_sistema = 'S0073';
