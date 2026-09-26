/*
===============================================================================
  SIGCM - SSO S05 : Especialista de area usuaria (SESDI)
  Motor  : PostgreSQL (base del SSO institucional, esquema login)
  NO SE EJECUTA EN DBSIGCM NI LO APLICA instalar.ps1

  QUE HACE
  --------
  Asigna el perfil PE092 ESPECIALISTA UNIDAD del sistema S0073 (SGCM-I) a la
  persona indicada, sobre la dependencia SESDI (D0023, centro 01.02.01).

  POR QUE
  -------
  Sin acceso activo a S0073 en el SSO, la persona no ve el tile de SGCM en
  "Mis aplicaciones", aunque ya exista la terna en DBSIGCM. PE092 es el mismo
  perfil que usa OTI para el especialista de unidad (p. ej. Cesar Ortiz).

  QUE NO HACE
  -----------
  No crea usuarios. No toca contrasenias. La persona tiene que existir ya.

  USO
  ---
    psql -h <host> -p <puerto> -U <usuario> -d saa_ \
         -v dni=42574546 -v cod_dependencia=D0023 \
         -f sso/S05__acceso_especialista_sesdi.sql

  Idempotente.
===============================================================================
*/

\set ON_ERROR_STOP on

\if :{?dni}
\else
\echo '>>> Falta el DNI. Invoque con:  -v dni=42574546 -v cod_dependencia=D0023'
\quit
\endif

\if :{?cod_dependencia}
\else
\echo '>>> Falta la dependencia. Invoque con:  -v dni=42574546 -v cod_dependencia=D0023'
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
    _id_perfil_sistema integer;
    _id_dependencia    integer;
    _id_acceso         integer;
BEGIN
    IF _dni IS NULL OR btrim(_dni) = '' THEN
        RAISE EXCEPTION 'Falta el DNI. Invoque con  -v dni=42574546';
    END IF;
    IF _cod_dependencia IS NULL OR btrim(_cod_dependencia) = '' THEN
        RAISE EXCEPTION 'Falta la dependencia. Invoque con  -v cod_dependencia=D0023';
    END IF;

    SELECT u.id_usuario INTO _id_usuario
      FROM login.tm_login_usuario u
     WHERE u.dni = _dni AND u.activo;

    IF _id_usuario IS NULL THEN
        RAISE EXCEPTION 'No hay ningun usuario activo con dni %. Este script no crea usuarios.', _dni;
    END IF;

    SELECT ps.id_perfil_sistema INTO _id_perfil_sistema
      FROM login.td_login_perfil_sistema ps
      JOIN login.tm_login_perfil  p ON p.id_perfil  = ps.id_perfil
      JOIN login.td_login_sistema s ON s.id_sistema = ps.id_sistema
     WHERE s.cod_sistema = 'S0073'
       AND p.cod_perfil  = 'PE092'
       AND COALESCE(ps.activo, true);

    IF _id_perfil_sistema IS NULL THEN
        RAISE EXCEPTION 'El sistema S0073 no tiene ligado el perfil PE092, o esta inactivo.';
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
        VALUES (_id_perfil_sistema, _id_usuario, 0, true, _dni, now())
        RETURNING id_acceso INTO _id_acceso;
        RAISE NOTICE 'Acceso PE092 creado para % (id_acceso %).', _dni, _id_acceso;
    ELSE
        UPDATE login.td_login_acceso
           SET activo = true, usuario_modificacion = _dni, fecha_modificacion = now()
         WHERE id_acceso = _id_acceso AND activo IS DISTINCT FROM true;
        RAISE NOTICE 'Acceso PE092 ya existia para % (id_acceso %); queda activo.', _dni, _id_acceso;
    END IF;

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

SELECT u.dni, p.cod_perfil, p.descripcion AS perfil, d.cod_dependencia, d.siglas, d.centro_costo
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
