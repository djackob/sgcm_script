/*
===============================================================================
  SIGCM - SSO S02 : Coordinador de area usuaria (OTI)
  Motor  : PostgreSQL (base del SSO institucional, esquema login)
  NO SE EJECUTA EN DBSIGCM NI LO APLICA instalar.ps1

  QUE HACE
  --------
  1. Crea el perfil PE099 COORDINADOR OFICINA si no existe.
  2. Lo liga al sistema S0073 (SGCM-I).
  3. Se lo asigna a la persona indicada sobre la dependencia OTI (D0001,
     centro de costo 01.07.05.03).

  POR QUE UN PERFIL NUEVO
  -----------------------
  PE083 COORDINADOR UA es de Abastecimiento y el SIGCM lo traduce a
  ABAST_COORDINADOR. Requerimiento necesita AREA_COORDINADOR en el area
  usuaria. OTI es oficina (el jefe entra con PE079 JEFE OFICINA), asi que el
  par que faltaba es COORDINADOR OFICINA. No se reutiliza PE093: ese codigo
  ya es SEGUIMIENTO CIERRE en otro sistema.

  QUE NO HACE
  -----------
  No crea usuarios. No toca contrasenias. La persona tiene que existir ya.

  TODO SE RESUELVE POR CODIGO, NUNCA POR ID
  -----------------------------------------
  dni, cod_sistema S0073, cod_perfil PE099, cod_dependencia D0001.

  USO
  ---
    psql -h <host> -p <puerto> -U <usuario> -d saa_ \
         -v dni=41159236 -v cod_dependencia=D0001 \
         -f sso/S02__acceso_coordinador_oti.sql

  Idempotente: correrlo dos veces no duplica el acceso ni el perfil.

  PARA REVERTIRLO
  ---------------
    UPDATE login.td_login_acceso a
       SET activo = false
      FROM login.td_login_perfil_sistema ps
      JOIN login.tm_login_perfil p ON p.id_perfil = ps.id_perfil
      JOIN login.td_login_sistema s ON s.id_sistema = ps.id_sistema
     WHERE a.id_perfil_sistema = ps.id_perfil_sistema
       AND s.cod_sistema = 'S0073' AND p.cod_perfil = 'PE099'
       AND a.id_usuario = (SELECT id_usuario FROM login.tm_login_usuario WHERE dni = '<dni>');
===============================================================================
*/

\set ON_ERROR_STOP on

\if :{?dni}
\else
\echo '>>> Falta el DNI. Invoque con:  -v dni=41159236 -v cod_dependencia=D0001'
\quit
\endif

\if :{?cod_dependencia}
\else
\echo '>>> Falta la dependencia. Invoque con:  -v dni=41159236 -v cod_dependencia=D0001'
\quit
\endif

SELECT set_config('sigcm.dni', :'dni', false);
SELECT set_config('sigcm.cod_dependencia', :'cod_dependencia', false);

BEGIN;

DO $$
DECLARE
    _dni               varchar := current_setting('sigcm.dni', true);
    _cod_dependencia   varchar := current_setting('sigcm.cod_dependencia', true);
    _id_usuario        integer;
    _id_perfil         integer;
    _id_sistema        integer;
    _id_perfil_sistema integer;
    _id_dependencia    integer;
    _id_acceso         integer;
BEGIN
    IF _dni IS NULL OR btrim(_dni) = '' THEN
        RAISE EXCEPTION 'Falta el DNI. Invoque con  -v dni=41159236';
    END IF;
    IF _cod_dependencia IS NULL OR btrim(_cod_dependencia) = '' THEN
        RAISE EXCEPTION 'Falta la dependencia. Invoque con  -v cod_dependencia=D0001';
    END IF;

    /* ---- La persona ------------------------------------------------- */
    SELECT u.id_usuario INTO _id_usuario
      FROM login.tm_login_usuario u
     WHERE u.dni = _dni AND u.activo;

    IF _id_usuario IS NULL THEN
        RAISE EXCEPTION 'No hay ningun usuario activo con dni %. Este script no crea usuarios.', _dni;
    END IF;

    /* ---- El perfil PE099 -------------------------------------------- */
    SELECT p.id_perfil INTO _id_perfil
      FROM login.tm_login_perfil p
     WHERE p.cod_perfil = 'PE099';

    IF _id_perfil IS NULL THEN
        INSERT INTO login.tm_login_perfil
              (cod_perfil, descripcion, activo, usuario_creacion, fecha_creacion)
        VALUES ('PE099', 'COORDINADOR OFICINA', true, _dni, now())
        RETURNING id_perfil INTO _id_perfil;
        RAISE NOTICE 'Perfil PE099 COORDINADOR OFICINA creado (id_perfil %).', _id_perfil;
    ELSE
        UPDATE login.tm_login_perfil
           SET descripcion = 'COORDINADOR OFICINA',
               activo = true,
               usuario_modificacion = _dni,
               fecha_modificacion = now()
         WHERE id_perfil = _id_perfil
           AND (descripcion IS DISTINCT FROM 'COORDINADOR OFICINA' OR activo IS DISTINCT FROM true);
        RAISE NOTICE 'Perfil PE099 ya existia (id_perfil %); queda activo como COORDINADOR OFICINA.', _id_perfil;
    END IF;

    /* ---- El sistema S0073 ------------------------------------------- */
    SELECT s.id_sistema INTO _id_sistema
      FROM login.td_login_sistema s
     WHERE s.cod_sistema = 'S0073' AND COALESCE(s.activo, true);

    IF _id_sistema IS NULL THEN
        RAISE EXCEPTION 'No existe el sistema S0073 activo.';
    END IF;

    SELECT ps.id_perfil_sistema INTO _id_perfil_sistema
      FROM login.td_login_perfil_sistema ps
     WHERE ps.id_perfil = _id_perfil AND ps.id_sistema = _id_sistema;

    IF _id_perfil_sistema IS NULL THEN
        INSERT INTO login.td_login_perfil_sistema
              (id_perfil, id_sistema, activo, usuario_creacion, fecha_creacion)
        VALUES (_id_perfil, _id_sistema, true, _dni, now())
        RETURNING id_perfil_sistema INTO _id_perfil_sistema;
        RAISE NOTICE 'PE099 ligado a S0073 (id_perfil_sistema %).', _id_perfil_sistema;
    ELSE
        UPDATE login.td_login_perfil_sistema
           SET activo = true, usuario_modificacion = _dni, fecha_modificacion = now()
         WHERE id_perfil_sistema = _id_perfil_sistema AND activo IS DISTINCT FROM true;
        RAISE NOTICE 'PE099 ya estaba ligado a S0073 (id_perfil_sistema %).', _id_perfil_sistema;
    END IF;

    /* ---- La dependencia OTI ----------------------------------------- */
    SELECT d.id_dependencia INTO _id_dependencia
      FROM login.tm_login_dependencia d
     WHERE d.cod_dependencia = _cod_dependencia AND COALESCE(d.activo, true);

    IF _id_dependencia IS NULL THEN
        RAISE EXCEPTION 'No hay dependencia activa con codigo %.', _cod_dependencia;
    END IF;

    /* ---- El acceso --------------------------------------------------- */
    SELECT a.id_acceso INTO _id_acceso
      FROM login.td_login_acceso a
     WHERE a.id_usuario = _id_usuario
       AND a.id_perfil_sistema = _id_perfil_sistema;

    IF _id_acceso IS NULL THEN
        INSERT INTO login.td_login_acceso
              (id_perfil_sistema, id_usuario, id_municipalidad, activo, usuario_creacion, fecha_creacion)
        VALUES (_id_perfil_sistema, _id_usuario, 0, true, _dni, now())
        RETURNING id_acceso INTO _id_acceso;
        RAISE NOTICE 'Acceso PE099 creado para % (id_acceso %).', _dni, _id_acceso;
    ELSE
        UPDATE login.td_login_acceso
           SET activo = true, usuario_modificacion = _dni, fecha_modificacion = now()
         WHERE id_acceso = _id_acceso AND activo IS DISTINCT FROM true;
        RAISE NOTICE 'Acceso PE099 ya existia para % (id_acceso %); queda activo.', _dni, _id_acceso;
    END IF;

    /* ---- Su dependencia ---------------------------------------------- */
    IF EXISTS (SELECT 1 FROM login.td_login_acceso_dependencia
                WHERE id_acceso = _id_acceso AND id_dependencia = _id_dependencia) THEN
        UPDATE login.td_login_acceso_dependencia
           SET activo = true, usuario_modificacion = _dni, fecha_modificacion = now()
         WHERE id_acceso = _id_acceso AND id_dependencia = _id_dependencia
           AND activo IS DISTINCT FROM true;
    ELSE
        INSERT INTO login.td_login_acceso_dependencia
              (id_acceso, id_dependencia, activo, usuario_creacion, fecha_creacion)
        VALUES (_id_acceso, _id_dependencia, true, _dni, now());
        RAISE NOTICE 'Dependencia % ligada al acceso %.', _cod_dependencia, _id_acceso;
    END IF;
END
$$;

COMMIT;

SELECT u.usuario, p.cod_perfil, p.descripcion AS perfil, d.cod_dependencia, d.siglas, d.centro_costo
  FROM login.td_login_acceso a
  JOIN login.tm_login_usuario u ON u.id_usuario = a.id_usuario
  JOIN login.td_login_perfil_sistema ps ON ps.id_perfil_sistema = a.id_perfil_sistema
  JOIN login.tm_login_perfil p ON p.id_perfil = ps.id_perfil
  JOIN login.td_login_sistema s ON s.id_sistema = ps.id_sistema
  JOIN login.td_login_acceso_dependencia ad ON ad.id_acceso = a.id_acceso
  JOIN login.tm_login_dependencia d ON d.id_dependencia = ad.id_dependencia
 WHERE u.dni = current_setting('sigcm.dni', true)
   AND s.cod_sistema = 'S0073'
   AND a.activo AND ad.activo
 ORDER BY p.cod_perfil, d.centro_costo;
