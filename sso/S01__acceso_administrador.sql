/*
===============================================================================
  SIGCM - SSO S01 : Perfil de administrador del sistema
  Motor  : PostgreSQL (base del SSO institucional, esquema login)
  NO SE EJECUTA EN DBSIGCM NI LO APLICA instalar.ps1

  QUE HACE
  --------
  Le da a una persona el perfil P0001 ADMINISTRADOR del sistema S0073 (SGCM-I),
  ligado a la dependencia que ya usa en ese sistema. Con eso entra al SIGCM como
  ADMIN_SISTEMA y puede abrir el panel de accesos y perfiles.

  POR QUE HACE FALTA
  ------------------
  El mapeo P0001 -> ADMIN_SISTEMA vive en db/20_seed/S007 y viaja versionado,
  pero de nada sirve si en el SSO nadie tiene ese perfil asignado: la
  sincronizacion traduce lo que llega, y si no llega ningun administrador, no lo
  hay. Sin administrador no se puede abrir el panel, que es justamente la
  herramienta para diagnosticar por que alguien no entra.

  QUE NO HACE
  -----------
  No crea usuarios. No crea ni cambia ni lee contrasenias. La persona tiene que
  existir ya en el SSO con su cuenta y su clave; esto solo le agrega una
  asignacion de perfil.

  TODO SE RESUELVE POR CODIGO, NUNCA POR ID
  -----------------------------------------
  Los identificadores numericos son distintos en cada ambiente. En desarrollo el
  P0001 del SGCM es el id_perfil_sistema 194; en produccion sera otro. Y la
  trampa concreta con la que ya tropezamos: Gustavo Cruz YA TENIA un P0001
  activo, pero del id_perfil_sistema 184, que pertenece al sistema 66. Buscar por
  cod_perfil sin mirar el sistema lleva a concluir que ya estaba resuelto.

  Por eso todo se resuelve por dni, cod_sistema y cod_perfil, y si algo no existe
  el script ABORTA sin escribir en vez de insertar contra un id equivocado.

  USO
  ---
    psql -h <host> -p <puerto> -U <usuario> -d saa_ \
         -v dni=44687266 -f sso/S01__acceso_administrador.sql

  Idempotente: correrlo dos veces no duplica el acceso.

  PARA REVERTIRLO
  ---------------
    UPDATE login.td_login_acceso a
       SET activo = false
      FROM login.td_login_perfil_sistema ps
      JOIN login.tm_login_perfil p ON p.id_perfil = ps.id_perfil
      JOIN login.td_login_sistema s ON s.id_sistema = ps.id_sistema
     WHERE a.id_perfil_sistema = ps.id_perfil_sistema
       AND s.cod_sistema = 'S0073' AND p.cod_perfil = 'P0001'
       AND a.id_usuario = (SELECT id_usuario FROM login.tm_login_usuario WHERE dni = '<dni>');

  La siguiente sincronizacion del SIGCM cierra la terna sola, por diferencia de
  conjuntos. No hay que tocar DBSIGCM.
===============================================================================
*/

\set ON_ERROR_STOP on

/* -v dni=... crea una variable de psql, que el cuerpo PL/pgSQL no ve. Se pasa a
   un ajuste de sesion para que el bloque DO pueda leerla. Si falta, se corta
   aqui: es mejor no arrancar que arrancar sin saber sobre quien. */
\if :{?dni}
\else
\echo '>>> Falta el DNI. Invoque con:  -v dni=44687266'
\quit
\endif

SELECT set_config('sigcm.dni', :'dni', false);

BEGIN;

DO $$
DECLARE
    _dni               varchar := current_setting('sigcm.dni', true);
    _id_usuario        integer;
    _id_perfil_sistema integer;
    _id_dependencia    integer;
    _id_acceso         integer;
BEGIN
    IF _dni IS NULL OR btrim(_dni) = '' THEN
        RAISE EXCEPTION 'Falta el DNI. Invoque con  -v dni=44687266';
    END IF;

    /* ---- La persona ------------------------------------------------- */
    SELECT u.id_usuario INTO _id_usuario
      FROM login.tm_login_usuario u
     WHERE u.dni = _dni AND u.activo;

    IF _id_usuario IS NULL THEN
        RAISE EXCEPTION 'No hay ningun usuario activo con dni %. Este script no crea usuarios.', _dni;
    END IF;

    /* ---- El perfil, resuelto por codigo de sistema Y de perfil ------- */
    SELECT ps.id_perfil_sistema INTO _id_perfil_sistema
      FROM login.td_login_perfil_sistema ps
      JOIN login.tm_login_perfil  p ON p.id_perfil  = ps.id_perfil
      JOIN login.td_login_sistema s ON s.id_sistema = ps.id_sistema
     WHERE s.cod_sistema = 'S0073'
       AND p.cod_perfil  = 'P0001'
       AND ps.activo;

    IF _id_perfil_sistema IS NULL THEN
        RAISE EXCEPTION 'El sistema S0073 no tiene ligado el perfil P0001, o esta inactivo. Ligarlo primero en el SGA.';
    END IF;

    /* ---- La dependencia --------------------------------------------- */
    /*
      Se reutiliza la que la persona ya usa en ESTE sistema. Elegirle una nueva
      seria decidir por el negocio a que area pertenece; reutilizar la que ya
      tiene es reflejar lo que el SSO ya dice de ella.
    */
    SELECT ad.id_dependencia INTO _id_dependencia
      FROM login.td_login_acceso            a
      JOIN login.td_login_perfil_sistema   ps ON ps.id_perfil_sistema = a.id_perfil_sistema
      JOIN login.td_login_sistema           s ON s.id_sistema         = ps.id_sistema
      JOIN login.td_login_acceso_dependencia ad ON ad.id_acceso       = a.id_acceso
     WHERE a.id_usuario = _id_usuario
       AND s.cod_sistema = 'S0073'
       AND a.activo AND ad.activo
     ORDER BY a.id_acceso DESC
     LIMIT 1;

    IF _id_dependencia IS NULL THEN
        RAISE EXCEPTION
            'El dni % no tiene ningun acceso activo con dependencia en el sistema S0073. '
            'Dele primero su perfil de trabajo desde el SGA; sin dependencia no hay centro de costo '
            'y el SIGCM no podria ubicarlo en ninguna unidad.', _dni;
    END IF;

    /* ---- El acceso --------------------------------------------------- */
    SELECT a.id_acceso INTO _id_acceso
      FROM login.td_login_acceso a
     WHERE a.id_usuario = _id_usuario
       AND a.id_perfil_sistema = _id_perfil_sistema;

    IF _id_acceso IS NULL THEN
        INSERT INTO login.td_login_acceso (id_perfil_sistema, id_usuario, activo, usuario_creacion, fecha_creacion)
        VALUES (_id_perfil_sistema, _id_usuario, true, _dni, now())
        RETURNING id_acceso INTO _id_acceso;

        RAISE NOTICE 'Acceso de administrador creado para % (id_acceso %).', _dni, _id_acceso;
    ELSE
        /* Ya existia: puede estar apagado de una vez anterior. */
        UPDATE login.td_login_acceso
           SET activo = true, usuario_modificacion = _dni, fecha_modificacion = now()
         WHERE id_acceso = _id_acceso AND activo IS DISTINCT FROM true;

        RAISE NOTICE 'Acceso de administrador ya existia para % (id_acceso %); queda activo.', _dni, _id_acceso;
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
    END IF;
END
$$;

COMMIT;

/* Comprobacion: la funcion que consume el SIGCM debe devolver ahora el P0001. */
SELECT usuario, cod_perfil, perfil, centro_costo, descripcion
  FROM login.vw_login_usuario_perfil_sistema_sgcm
 WHERE usuario = (SELECT usuario FROM login.tm_login_usuario WHERE dni = current_setting('sigcm.dni', true))
 ORDER BY cod_perfil;
