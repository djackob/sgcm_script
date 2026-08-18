/*
===============================================================================
 SIGCM - Base inicial PostgreSQL para Gestión CMN e integración controlada SIGA
===============================================================================

 Objetivo
 --------
 - Mantener en PostgreSQL el flujo institucional ANIN, los Anexos 3 y 4,
   observaciones, firmas, versiones, auditoría y trazabilidad.
 - Mantener una réplica de consulta (cache) de los maestros SIGA necesarios.
 - Preparar una bandeja transaccional (outbox) para que un backend puente invoque
   en SQL Server dbo.usp_ext_registrar_item_cmn y registre su respuesta.
 - Exponer funciones JSONB -> JSONB. Angular no debe acceder a tablas ni enviar
   directamente credenciales o nombres de procedimientos SQL Server.

 Límites confirmados por Manual_SIGA_CMN.docx y el SP analizado
 ----------------------------------------------------------------
 - usp_ext_registrar_item_cmn registra un ítem por llamada.
 - El procedimiento escribe SIG_CUADRO_NECESIDAD y
   SIG_CUADRO_NECESIDAD_DET, dejando el detalle en ESTADO='5'.
 - No consolida ni aprueba (ESTADO='6').
 - No implementa la modificación del CMN ni escribe
   SIG_CUADRO_MODIFICADO_CMN.
 - Por ello, este script solo encola hacia dicho SP solicitudes
   ALTA_ORDINARIA con ítems de INCLUSION. MODIFICACION y EXCLUSION quedan
   registradas localmente, pero requieren otro SP SIGA previamente homologado.

 Estrategia de integración
 -------------------------
 Angular 18 -> Backend -> funciones api_* PostgreSQL
 Backend worker -> api_integracion_siga_tomar_pendientes()
 Backend worker -> SQL Server dbo.usp_ext_registrar_item_cmn
 Backend worker -> api_integracion_siga_registrar_resultado()

 La validación final de catálogos, duplicidad, concurrencia y techo corresponde
 al procedimiento SQL Server. La cache PostgreSQL permite validar temprano y
 mejorar la experiencia, pero no reemplaza la autoridad transaccional de SIGA.

 Requiere PostgreSQL 14 o superior.
===============================================================================
*/

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS seguridad;
CREATE SCHEMA IF NOT EXISTS maestro;
CREATE SCHEMA IF NOT EXISTS workflow;
CREATE SCHEMA IF NOT EXISTS cmn;
CREATE SCHEMA IF NOT EXISTS integracion;
CREATE SCHEMA IF NOT EXISTS auditoria;
CREATE SCHEMA IF NOT EXISTS api;

/* -------------------------------------------------------------------------- */
/* 1. Seguridad y organización                                                */
/* -------------------------------------------------------------------------- */

CREATE TABLE IF NOT EXISTS seguridad.rol (
    codigo              varchar(40) PRIMARY KEY,
    nombre              varchar(120) NOT NULL,
    descripcion         text,
    activo              boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS seguridad.usuario (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cuenta              varchar(120) NOT NULL UNIQUE,
    nombres             varchar(160) NOT NULL,
    correo              varchar(200),
    activo              boolean NOT NULL DEFAULT true,
    creado_en           timestamptz NOT NULL DEFAULT clock_timestamp(),
    actualizado_en      timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS seguridad.usuario_rol (
    usuario_id          uuid NOT NULL REFERENCES seguridad.usuario(id),
    rol_codigo          varchar(40) NOT NULL REFERENCES seguridad.rol(codigo),
    unidad_codigo       varchar(30),
    vigente_desde       date NOT NULL DEFAULT current_date,
    vigente_hasta       date,
    PRIMARY KEY (usuario_id, rol_codigo, unidad_codigo)
);

INSERT INTO seguridad.rol(codigo, nombre, descripcion) VALUES
('AREA_ESPECIALISTA', 'Área usuaria - Especialista', 'Registra CMN y subsana observaciones'),
('AREA_JEFE', 'Área usuaria - Jefe', 'Firma Anexo 3, remite y recepciona Anexo 4'),
('OA', 'Oficina de Administración', 'Revisa, observa o deriva a Abastecimiento'),
('ABAST_ESPECIALISTA', 'Abastecimiento - Especialista', 'Revisa y opera expedientes CMN'),
('ABAST_COORDINADOR', 'Abastecimiento - Coordinador', 'Controla y valida expedientes CMN'),
('ABAST_JEFE', 'Abastecimiento - Jefe', 'Firma y remite documentos de aprobación'),
('MAX_AUT_ADMIN', 'Máxima autoridad administrativa', 'Segunda firma del Anexo 4'),
('INTEGRACION_SIGA', 'Servicio de integración SIGA', 'Cuenta técnica de mínimo privilegio'),
('ADMIN_SISTEMA', 'Administrador del sistema', 'Administración funcional y técnica')
ON CONFLICT (codigo) DO UPDATE
SET nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion;

/* -------------------------------------------------------------------------- */
/* 2. Cache de maestros SIGA                                                   */
/* -------------------------------------------------------------------------- */

CREATE TABLE IF NOT EXISTS maestro.siga_centro_costo (
    ano_eje             smallint NOT NULL,
    sec_ejec            integer NOT NULL,
    centro_costo        varchar(15) NOT NULL,
    descripcion         varchar(250) NOT NULL,
    estado              char(1) NOT NULL DEFAULT 'A',
    sincronizado_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload_origen      jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (ano_eje, sec_ejec, centro_costo),
    CONSTRAINT ck_siga_centro_estado CHECK (estado IN ('A','I'))
);

CREATE TABLE IF NOT EXISTS maestro.siga_meta (
    ano_eje             smallint NOT NULL,
    sec_ejec            integer NOT NULL,
    sec_func            integer NOT NULL,
    sec_func_prop       integer,
    descripcion         varchar(300),
    estado              char(1) NOT NULL DEFAULT 'A',
    sincronizado_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload_origen      jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (ano_eje, sec_ejec, sec_func),
    CONSTRAINT ck_siga_meta_estado CHECK (estado IN ('A','I'))
);

CREATE TABLE IF NOT EXISTS maestro.siga_fuente_financiamiento (
    ano_eje             smallint NOT NULL,
    sec_ejec            integer NOT NULL,
    origen              varchar(1) NOT NULL,
    fuente_financ       varchar(2) NOT NULL,
    descripcion         varchar(250),
    estado              char(1) NOT NULL DEFAULT 'A',
    sincronizado_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload_origen      jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (ano_eje, sec_ejec, origen, fuente_financ),
    CONSTRAINT ck_siga_fuente_estado CHECK (estado IN ('A','I'))
);

CREATE TABLE IF NOT EXISTS maestro.siga_actividad_tarea (
    ano_eje             smallint NOT NULL,
    sec_ejec            integer NOT NULL,
    tipo_tarea          varchar(1) NOT NULL,
    nivel_tarea         varchar(1) NOT NULL,
    codigo_tarea        bigint NOT NULL,
    descripcion         varchar(400),
    estado              char(1) NOT NULL DEFAULT 'A',
    sincronizado_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload_origen      jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (ano_eje, sec_ejec, tipo_tarea, nivel_tarea, codigo_tarea),
    CONSTRAINT ck_siga_tarea_estado CHECK (estado IN ('A','I'))
);

CREATE TABLE IF NOT EXISTS maestro.siga_catalogo_item (
    sec_ejec            integer NOT NULL,
    tipo_bien           varchar(1) NOT NULL,
    grupo_bien          varchar(2) NOT NULL,
    clase_bien          varchar(2) NOT NULL,
    familia_bien        varchar(4) NOT NULL,
    item_bien           varchar(4) NOT NULL,
    descripcion         varchar(350) NOT NULL,
    unidad_medida       integer NOT NULL,
    estado              char(1) NOT NULL DEFAULT 'A',
    sincronizado_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload_origen      jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (sec_ejec, tipo_bien, grupo_bien, clase_bien, familia_bien, item_bien),
    CONSTRAINT ck_siga_catalogo_tipo CHECK (tipo_bien IN ('B','S','O')),
    CONSTRAINT ck_siga_catalogo_estado CHECK (estado IN ('A','I'))
);

CREATE TABLE IF NOT EXISTS maestro.siga_techo_presupuesto (
    ano_eje             smallint NOT NULL,
    sec_ejec            integer NOT NULL,
    centro_costo        varchar(15) NOT NULL,
    fase_cuadro         smallint NOT NULL DEFAULT 5,
    origen              varchar(1) NOT NULL,
    fuente_financ       varchar(2) NOT NULL,
    sec_func            integer NOT NULL,
    clasificador        varchar(20) NOT NULL,
    categ_gasto         varchar(1),
    grupo_gasto         varchar(1),
    monto_techo_0       numeric(18,2) NOT NULL DEFAULT 0,
    monto_techo_1       numeric(18,2) NOT NULL DEFAULT 0,
    monto_techo_2       numeric(18,2) NOT NULL DEFAULT 0,
    monto_techo_3       numeric(18,2) NOT NULL DEFAULT 0,
    monto_usado_0       numeric(18,2) NOT NULL DEFAULT 0,
    monto_usado_1       numeric(18,2) NOT NULL DEFAULT 0,
    monto_usado_2       numeric(18,2) NOT NULL DEFAULT 0,
    monto_usado_3       numeric(18,2) NOT NULL DEFAULT 0,
    sincronizado_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload_origen      jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (ano_eje, sec_ejec, centro_costo, fase_cuadro,
                 origen, fuente_financ, sec_func, clasificador),
    CONSTRAINT ck_siga_techo_fase CHECK (fase_cuadro > 0),
    CONSTRAINT ck_siga_techo_montos CHECK (
        monto_techo_0 >= 0 AND monto_techo_1 >= 0 AND
        monto_techo_2 >= 0 AND monto_techo_3 >= 0 AND
        monto_usado_0 >= 0 AND monto_usado_1 >= 0 AND
        monto_usado_2 >= 0 AND monto_usado_3 >= 0
    )
);

/* Asociación programática observada en SIGA. Se conserva como cache de control. */
CREATE TABLE IF NOT EXISTS maestro.siga_meta_centro_rubro (
    ano_eje             smallint NOT NULL,
    sec_ejec            integer NOT NULL,
    centro_costo        varchar(15) NOT NULL,
    sec_func            integer NOT NULL,
    origen              varchar(1) NOT NULL,
    fuente_financ       varchar(2) NOT NULL,
    tipo_tarea          varchar(1),
    nivel_tarea         varchar(1),
    codigo_tarea        bigint,
    estado              char(1) NOT NULL DEFAULT 'A',
    sincronizado_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload_origen      jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (ano_eje, sec_ejec, centro_costo, sec_func, origen, fuente_financ),
    CONSTRAINT ck_siga_asociacion_estado CHECK (estado IN ('A','I'))
);

/* -------------------------------------------------------------------------- */
/* 3. Workflow configurable                                                    */
/* -------------------------------------------------------------------------- */

CREATE TABLE IF NOT EXISTS workflow.estado (
    codigo              varchar(50) PRIMARY KEY,
    modulo              varchar(30) NOT NULL,
    nombre              varchar(150) NOT NULL,
    orden               integer NOT NULL,
    es_final            boolean NOT NULL DEFAULT false,
    activo              boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS workflow.transicion (
    codigo              varchar(60) PRIMARY KEY,
    modulo              varchar(30) NOT NULL,
    estado_origen       varchar(50) NOT NULL REFERENCES workflow.estado(codigo),
    estado_destino      varchar(50) NOT NULL REFERENCES workflow.estado(codigo),
    nombre_accion       varchar(180) NOT NULL,
    roles_permitidos    text[] NOT NULL,
    requiere_comentario boolean NOT NULL DEFAULT false,
    activo              boolean NOT NULL DEFAULT true
);

INSERT INTO workflow.estado(codigo, modulo, nombre, orden, es_final) VALUES
('CMN_BORRADOR', 'CMN', 'Registrar Anexo 3', 10, false),
('CMN_PEND_FIRMA_A3', 'CMN', 'Por firmar Anexo 3', 20, false),
('CMN_A3_FIRMADO', 'CMN', 'Anexo 3 firmado', 30, false),
('CMN_EN_EVAL_OA', 'CMN', 'En evaluación OA', 40, false),
('CMN_EN_EVAL_UA', 'CMN', 'En evaluación Unidad de Abastecimiento', 50, false),
('CMN_OBSERVADO', 'CMN', 'Observado', 60, false),
('CMN_VALIDADO_UA', 'CMN', 'Validado por Unidad de Abastecimiento', 70, false),
('CMN_PEND_FIRMA_A4', 'CMN', 'Por firmar Anexo 4', 80, false),
('CMN_A4_FIRMADO', 'CMN', 'Anexo 4 firmado', 90, false),
('CMN_A4_ENVIADO', 'CMN', 'Anexo 4 enviado al Área usuaria', 100, false),
('CMN_FINALIZADO', 'CMN', 'Anexo 4 recepcionado - Fin', 110, true),
('CMN_ANULADO', 'CMN', 'Anulado', 999, true)
ON CONFLICT (codigo) DO UPDATE
SET nombre = EXCLUDED.nombre,
    orden = EXCLUDED.orden,
    es_final = EXCLUDED.es_final;

INSERT INTO workflow.transicion
(codigo, modulo, estado_origen, estado_destino, nombre_accion, roles_permitidos, requiere_comentario)
VALUES
('CMN_GENERAR_A3', 'CMN', 'CMN_BORRADOR', 'CMN_PEND_FIRMA_A3', 'Generar Anexo 3', ARRAY['AREA_ESPECIALISTA','AREA_JEFE'], false),
('CMN_FIRMAR_A3', 'CMN', 'CMN_PEND_FIRMA_A3', 'CMN_A3_FIRMADO', 'Firmar Anexo 3', ARRAY['AREA_JEFE'], false),
('CMN_ENVIAR_OA', 'CMN', 'CMN_A3_FIRMADO', 'CMN_EN_EVAL_OA', 'Enviar Anexo 3 a OA', ARRAY['AREA_JEFE'], false),
('CMN_OBSERVAR_OA', 'CMN', 'CMN_EN_EVAL_OA', 'CMN_OBSERVADO', 'Observar desde OA', ARRAY['OA'], true),
('CMN_DERIVAR_ABAST', 'CMN', 'CMN_EN_EVAL_OA', 'CMN_EN_EVAL_UA', 'Derivar a Unidad de Abastecimiento', ARRAY['OA'], false),
('CMN_OBSERVAR_ABAST', 'CMN', 'CMN_EN_EVAL_UA', 'CMN_OBSERVADO', 'Observar desde Abastecimiento', ARRAY['ABAST_ESPECIALISTA','ABAST_COORDINADOR'], true),
('CMN_VALIDAR_ABAST', 'CMN', 'CMN_EN_EVAL_UA', 'CMN_VALIDADO_UA', 'Validar Anexo 3', ARRAY['ABAST_ESPECIALISTA','ABAST_COORDINADOR'], false),
('CMN_SUBSANAR', 'CMN', 'CMN_OBSERVADO', 'CMN_BORRADOR', 'Abrir subsanación integral', ARRAY['AREA_ESPECIALISTA','AREA_JEFE'], true),
('CMN_GENERAR_A4', 'CMN', 'CMN_VALIDADO_UA', 'CMN_PEND_FIRMA_A4', 'Generar Anexo 4', ARRAY['ABAST_ESPECIALISTA','ABAST_COORDINADOR','ABAST_JEFE'], false),
('CMN_FIRMAR_A4', 'CMN', 'CMN_PEND_FIRMA_A4', 'CMN_A4_FIRMADO', 'Completar firmas del Anexo 4', ARRAY['ABAST_JEFE','MAX_AUT_ADMIN'], false),
('CMN_ENVIAR_A4', 'CMN', 'CMN_A4_FIRMADO', 'CMN_A4_ENVIADO', 'Enviar Anexo 4', ARRAY['ABAST_JEFE','ABAST_ESPECIALISTA'], false),
('CMN_RECEPCIONAR_A4', 'CMN', 'CMN_A4_ENVIADO', 'CMN_FINALIZADO', 'Recepcionar Anexo 4', ARRAY['AREA_JEFE'], false)
ON CONFLICT (codigo) DO UPDATE
SET estado_origen = EXCLUDED.estado_origen,
    estado_destino = EXCLUDED.estado_destino,
    nombre_accion = EXCLUDED.nombre_accion,
    roles_permitidos = EXCLUDED.roles_permitidos,
    requiere_comentario = EXCLUDED.requiere_comentario;

/* -------------------------------------------------------------------------- */
/* 4. Transacción CMN local                                                    */
/* -------------------------------------------------------------------------- */

CREATE SEQUENCE IF NOT EXISTS cmn.seq_codigo_solicitud START WITH 1;

CREATE TABLE IF NOT EXISTS cmn.solicitud (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo              varchar(40) NOT NULL UNIQUE,
    idempotencia_key    varchar(120) UNIQUE,
    tipo_operacion      varchar(20) NOT NULL DEFAULT 'ALTA_ORDINARIA',
    tipo_inclusion      varchar(15) NOT NULL DEFAULT 'ORDINARIA',
    estado_codigo       varchar(50) NOT NULL DEFAULT 'CMN_BORRADOR'
                        REFERENCES workflow.estado(codigo),
    version             integer NOT NULL DEFAULT 1,

    ano_eje             smallint NOT NULL,
    sec_ejec            integer NOT NULL,
    centro_costo        varchar(15) NOT NULL,
    fase_cuadro         smallint NOT NULL DEFAULT 5,
    secuencia_siga      bigint,

    tipo_tarea          varchar(1) NOT NULL,
    nivel_tarea         varchar(1) NOT NULL,
    codigo_tarea        bigint NOT NULL,
    sec_func            integer NOT NULL,
    sec_func_prop       integer,
    origen              varchar(1) NOT NULL DEFAULT '1',
    fuente_financ       varchar(2) NOT NULL DEFAULT '00',
    clasificador        varchar(20) NOT NULL,
    tipo_recurso        varchar(2) NOT NULL DEFAULT '1',
    tipo_ppto           smallint NOT NULL DEFAULT 1,
    tipo_uso            varchar(1) NOT NULL DEFAULT 'C',
    tipo_bien           varchar(1) NOT NULL,

    sustento            text NOT NULL,
    fecha_solicitud     date NOT NULL DEFAULT current_date,
    responsable_area    varchar(180) NOT NULL,
    cargo_responsable   varchar(180) NOT NULL,
    datos_adicionales   jsonb NOT NULL DEFAULT '{}'::jsonb,

    anulado             boolean NOT NULL DEFAULT false,
    motivo_anulacion    text,
    anulado_en          timestamptz,
    anulado_por         varchar(120),
    creado_por          varchar(120) NOT NULL,
    creado_en           timestamptz NOT NULL DEFAULT clock_timestamp(),
    actualizado_por     varchar(120) NOT NULL,
    actualizado_en      timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_cmn_tipo_operacion CHECK (tipo_operacion IN ('ALTA_ORDINARIA','MODIFICACION')),
    CONSTRAINT ck_cmn_tipo_inclusion CHECK (tipo_inclusion IN ('ORDINARIA','URGENTE')),
    CONSTRAINT ck_cmn_tipo_bien CHECK (tipo_bien IN ('B','S','O')),
    CONSTRAINT ck_cmn_fase_homologada CHECK (fase_cuadro = 5),
    CONSTRAINT ck_cmn_version CHECK (version > 0),
    FOREIGN KEY (ano_eje, sec_ejec, centro_costo)
        REFERENCES maestro.siga_centro_costo(ano_eje, sec_ejec, centro_costo),
    FOREIGN KEY (ano_eje, sec_ejec, sec_func)
        REFERENCES maestro.siga_meta(ano_eje, sec_ejec, sec_func),
    FOREIGN KEY (ano_eje, sec_ejec, origen, fuente_financ)
        REFERENCES maestro.siga_fuente_financiamiento(ano_eje, sec_ejec, origen, fuente_financ),
    FOREIGN KEY (ano_eje, sec_ejec, tipo_tarea, nivel_tarea, codigo_tarea)
        REFERENCES maestro.siga_actividad_tarea(ano_eje, sec_ejec, tipo_tarea, nivel_tarea, codigo_tarea)
);

CREATE TABLE IF NOT EXISTS cmn.item (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    solicitud_id        uuid NOT NULL REFERENCES cmn.solicitud(id) ON DELETE CASCADE,
    orden               integer NOT NULL,
    sec_ejec            integer NOT NULL,
    tipo_movimiento     varchar(12) NOT NULL DEFAULT 'INCLUSION',
    tipo_bien           varchar(1) NOT NULL,
    grupo_bien          varchar(2) NOT NULL,
    clase_bien          varchar(2) NOT NULL,
    familia_bien        varchar(4) NOT NULL,
    item_bien           varchar(4) NOT NULL,
    descripcion_servicio varchar(350),
    unidad_medida       integer NOT NULL,
    precio_unitario     numeric(16,6) NOT NULL,
    item_sec_siga       integer,
    estado_siga         varchar(2),
    creado_por          varchar(120) NOT NULL,
    creado_en           timestamptz NOT NULL DEFAULT clock_timestamp(),
    actualizado_por     varchar(120) NOT NULL,
    actualizado_en      timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (solicitud_id, orden),
    UNIQUE (solicitud_id, tipo_bien, grupo_bien, clase_bien, familia_bien, item_bien),
    CONSTRAINT ck_cmn_item_movimiento CHECK (tipo_movimiento IN ('INCLUSION','EXCLUSION')),
    CONSTRAINT ck_cmn_item_precio CHECK (precio_unitario > 0),
    CONSTRAINT fk_cmn_item_catalogo
    FOREIGN KEY (sec_ejec, tipo_bien, grupo_bien, clase_bien, familia_bien, item_bien)
        REFERENCES maestro.siga_catalogo_item(sec_ejec, tipo_bien, grupo_bien, clase_bien, familia_bien, item_bien)
);

CREATE TABLE IF NOT EXISTS cmn.item_periodo (
    item_id             uuid NOT NULL REFERENCES cmn.item(id) ON DELETE CASCADE,
    ano_offset          smallint NOT NULL,
    mes                 smallint NOT NULL,
    cantidad            numeric(14,2) NOT NULL DEFAULT 0,
    monto               numeric(18,2) NOT NULL DEFAULT 0,
    PRIMARY KEY (item_id, ano_offset, mes),
    CONSTRAINT ck_cmn_periodo_offset CHECK (ano_offset BETWEEN 0 AND 3),
    CONSTRAINT ck_cmn_periodo_mes CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT ck_cmn_periodo_valores CHECK (cantidad >= 0 AND monto >= 0)
);

CREATE TABLE IF NOT EXISTS cmn.documento (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo                varchar(10) NOT NULL,
    numero              varchar(80) NOT NULL,
    version             integer NOT NULL,
    consolidado         boolean NOT NULL DEFAULT false,
    estado              varchar(15) NOT NULL DEFAULT 'BORRADOR',
    payload             jsonb NOT NULL,
    firmas_requeridas   text[] NOT NULL,
    archivo_uri         text,
    archivo_hash        varchar(128),
    creado_por          varchar(120) NOT NULL,
    creado_en           timestamptz NOT NULL DEFAULT clock_timestamp(),
    firmado_en          timestamptz,
    anulado_en          timestamptz,
    CONSTRAINT ck_cmn_documento_tipo CHECK (tipo IN ('ANEXO_3','ANEXO_4')),
    CONSTRAINT ck_cmn_documento_estado CHECK (estado IN ('BORRADOR','FIRMADO','ANULADO')),
    CONSTRAINT ck_cmn_documento_version CHECK (version > 0),
    UNIQUE (tipo, numero, version)
);

CREATE TABLE IF NOT EXISTS cmn.documento_solicitud (
    documento_id        uuid NOT NULL REFERENCES cmn.documento(id) ON DELETE CASCADE,
    solicitud_id        uuid NOT NULL REFERENCES cmn.solicitud(id),
    PRIMARY KEY (documento_id, solicitud_id)
);

CREATE TABLE IF NOT EXISTS cmn.documento_firma (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    documento_id        uuid NOT NULL REFERENCES cmn.documento(id) ON DELETE CASCADE,
    rol_firma           varchar(40) NOT NULL REFERENCES seguridad.rol(codigo),
    firmante            varchar(180) NOT NULL,
    cargo               varchar(180) NOT NULL,
    certificado_serie   varchar(250),
    firma_hash          varchar(256) NOT NULL,
    firma_payload       jsonb NOT NULL DEFAULT '{}'::jsonb,
    firmado_en          timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (documento_id, rol_firma)
);

CREATE TABLE IF NOT EXISTS cmn.observacion (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    solicitud_id        uuid NOT NULL REFERENCES cmn.solicitud(id),
    origen_rol          varchar(40) NOT NULL REFERENCES seguridad.rol(codigo),
    destino_rol         varchar(40) NOT NULL REFERENCES seguridad.rol(codigo),
    motivo              text NOT NULL,
    estado              varchar(15) NOT NULL DEFAULT 'PENDIENTE',
    respuesta           text,
    creada_por          varchar(120) NOT NULL,
    creada_en           timestamptz NOT NULL DEFAULT clock_timestamp(),
    recepcionada_por    varchar(120),
    recepcionada_en     timestamptz,
    subsanada_por       varchar(120),
    subsanada_en        timestamptz,
    CONSTRAINT ck_cmn_observacion_estado CHECK
        (estado IN ('PENDIENTE','RECEPCIONADA','SUBSANADA','CERRADA'))
);

CREATE TABLE IF NOT EXISTS workflow.historial (
    id                  bigserial PRIMARY KEY,
    modulo              varchar(30) NOT NULL,
    entidad_id          uuid NOT NULL,
    estado_origen       varchar(50),
    estado_destino      varchar(50) NOT NULL,
    transicion_codigo   varchar(60),
    comentario          text,
    actor               varchar(120) NOT NULL,
    actor_rol           varchar(40) NOT NULL,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    ocurrido_en         timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS auditoria.evento (
    id                  bigserial PRIMARY KEY,
    correlacion_id      uuid NOT NULL DEFAULT gen_random_uuid(),
    modulo              varchar(30) NOT NULL,
    entidad             varchar(80) NOT NULL,
    entidad_id          uuid,
    accion              varchar(80) NOT NULL,
    actor               varchar(120) NOT NULL,
    actor_rol           varchar(40),
    datos_antes         jsonb,
    datos_despues       jsonb,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    ocurrido_en         timestamptz NOT NULL DEFAULT clock_timestamp()
);

/* -------------------------------------------------------------------------- */
/* 5. Outbox y conciliación SIGA                                               */
/* -------------------------------------------------------------------------- */

CREATE TABLE IF NOT EXISTS integracion.siga_operacion (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotencia_key    varchar(200) NOT NULL UNIQUE,
    solicitud_id        uuid NOT NULL REFERENCES cmn.solicitud(id),
    item_id             uuid NOT NULL REFERENCES cmn.item(id),
    procedimiento       varchar(128) NOT NULL DEFAULT 'dbo.usp_ext_registrar_item_cmn',
    estado              varchar(20) NOT NULL DEFAULT 'PENDIENTE',
    request_json        jsonb NOT NULL,
    response_json       jsonb,
    error_codigo        varchar(80),
    error_mensaje       text,
    intentos            integer NOT NULL DEFAULT 0,
    max_intentos        integer NOT NULL DEFAULT 5,
    proximo_intento_en  timestamptz NOT NULL DEFAULT clock_timestamp(),
    bloqueo_token       uuid,
    bloqueado_en        timestamptz,
    creado_en           timestamptz NOT NULL DEFAULT clock_timestamp(),
    actualizado_en      timestamptz NOT NULL DEFAULT clock_timestamp(),
    completado_en       timestamptz,
    CONSTRAINT ck_siga_operacion_estado CHECK
        (estado IN ('PENDIENTE','EN_PROCESO','REINTENTO','COMPLETADO','ERROR','ANULADO')),
    CONSTRAINT ck_siga_operacion_intentos CHECK (intentos >= 0 AND max_intentos > 0)
);

CREATE TABLE IF NOT EXISTS integracion.siga_item_mapeo (
    item_id             uuid PRIMARY KEY REFERENCES cmn.item(id),
    solicitud_id        uuid NOT NULL REFERENCES cmn.solicitud(id),
    ano_eje             smallint NOT NULL,
    sec_ejec            integer NOT NULL,
    centro_costo        varchar(15) NOT NULL,
    secuencia_siga      bigint NOT NULL,
    fase_cuadro         smallint NOT NULL,
    item_sec_siga       integer NOT NULL,
    estado_siga         varchar(2) NOT NULL,
    registrado_en_siga  timestamptz NOT NULL DEFAULT clock_timestamp(),
    ultima_conciliacion timestamptz,
    payload_respuesta   jsonb NOT NULL,
    UNIQUE (ano_eje, sec_ejec, centro_costo, secuencia_siga, fase_cuadro, item_sec_siga)
);

CREATE INDEX IF NOT EXISTS ix_cmn_solicitud_estado
    ON cmn.solicitud(estado_codigo, anulado, actualizado_en DESC);
CREATE INDEX IF NOT EXISTS ix_cmn_solicitud_area
    ON cmn.solicitud(ano_eje, sec_ejec, centro_costo);
CREATE INDEX IF NOT EXISTS ix_cmn_item_solicitud
    ON cmn.item(solicitud_id, orden);
CREATE INDEX IF NOT EXISTS ix_cmn_documento_solicitud
    ON cmn.documento_solicitud(solicitud_id, documento_id);
CREATE INDEX IF NOT EXISTS ix_wf_historial_entidad
    ON workflow.historial(modulo, entidad_id, ocurrido_en DESC);
CREATE INDEX IF NOT EXISTS ix_integracion_siga_pendiente
    ON integracion.siga_operacion(estado, proximo_intento_en, creado_en)
    WHERE estado IN ('PENDIENTE','REINTENTO');

/* -------------------------------------------------------------------------- */
/* 6. Vistas de consulta                                                       */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW cmn.v_item_resumen AS
SELECT
    i.id AS item_id,
    i.solicitud_id,
    i.orden,
    i.tipo_movimiento,
    i.tipo_bien,
    i.grupo_bien,
    i.clase_bien,
    i.familia_bien,
    i.item_bien,
    COALESCE(i.descripcion_servicio, c.descripcion) AS descripcion,
    i.unidad_medida,
    i.precio_unitario,
    SUM(p.cantidad) FILTER (WHERE p.ano_offset = 0) AS cantidad_0,
    SUM(p.cantidad) FILTER (WHERE p.ano_offset = 1) AS cantidad_1,
    SUM(p.cantidad) FILTER (WHERE p.ano_offset = 2) AS cantidad_2,
    SUM(p.cantidad) FILTER (WHERE p.ano_offset = 3) AS cantidad_3,
    SUM(p.monto) FILTER (WHERE p.ano_offset = 0) AS monto_0,
    SUM(p.monto) FILTER (WHERE p.ano_offset = 1) AS monto_1,
    SUM(p.monto) FILTER (WHERE p.ano_offset = 2) AS monto_2,
    SUM(p.monto) FILTER (WHERE p.ano_offset = 3) AS monto_3,
    SUM(p.cantidad) AS cantidad_total,
    SUM(p.monto) AS monto_total
FROM cmn.item i
JOIN maestro.siga_catalogo_item c
  ON c.sec_ejec = i.sec_ejec
 AND c.tipo_bien = i.tipo_bien
 AND c.grupo_bien = i.grupo_bien
 AND c.clase_bien = i.clase_bien
 AND c.familia_bien = i.familia_bien
 AND c.item_bien = i.item_bien
JOIN cmn.item_periodo p ON p.item_id = i.id
GROUP BY i.id, c.descripcion;

/* -------------------------------------------------------------------------- */
/* 7. Utilitarios JSON y auditoría                                             */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION api.ok(p_data jsonb DEFAULT '{}'::jsonb,
                                  p_meta jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT jsonb_build_object('ok', true, 'data', COALESCE(p_data, '{}'::jsonb),
                              'meta', COALESCE(p_meta, '{}'::jsonb));
$$;

CREATE OR REPLACE FUNCTION api.error(p_codigo text,
                                     p_mensaje text,
                                     p_detalle jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT jsonb_build_object('ok', false,
                              'error', jsonb_build_object(
                                  'codigo', COALESCE(p_codigo, 'ERROR'),
                                  'mensaje', COALESCE(p_mensaje, 'Error no especificado'),
                                  'detalle', COALESCE(p_detalle, '{}'::jsonb)
                              ));
$$;

CREATE OR REPLACE FUNCTION auditoria.registrar(
    p_modulo text,
    p_entidad text,
    p_entidad_id uuid,
    p_accion text,
    p_actor text,
    p_actor_rol text,
    p_antes jsonb DEFAULT NULL,
    p_despues jsonb DEFAULT NULL,
    p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SET search_path = auditoria, public
AS $$
BEGIN
    INSERT INTO auditoria.evento
    (modulo, entidad, entidad_id, accion, actor, actor_rol,
     datos_antes, datos_despues, metadata)
    VALUES
    (p_modulo, p_entidad, p_entidad_id, p_accion, p_actor, p_actor_rol,
     p_antes, p_despues, COALESCE(p_metadata, '{}'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION cmn.insertar_items(
    p_solicitud_id uuid,
    p_sec_ejec integer,
    p_items jsonb,
    p_actor text
) RETURNS void
LANGUAGE plpgsql
SET search_path = cmn, maestro, public
AS $$
DECLARE
    v_item_json        jsonb;
    v_item_id          uuid;
    v_orden            integer := 0;
    v_precio           numeric(16,6);
    v_tipo_bien        varchar(1);
    v_grupo            varchar(2);
    v_clase            varchar(2);
    v_familia          varchar(4);
    v_item              varchar(4);
    v_unidad           integer;
    v_cantidad         numeric(14,2);
    v_periodo          jsonb;
    v_total_cantidad   numeric(18,2);
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Debe registrar al menos un ítem CMN.';
    END IF;

    FOR v_item_json IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        v_orden := v_orden + 1;
        v_precio := (v_item_json->>'precio_unitario')::numeric;
        v_tipo_bien := upper(v_item_json->>'tipo_bien');
        v_grupo := v_item_json->>'grupo_bien';
        v_clase := v_item_json->>'clase_bien';
        v_familia := v_item_json->>'familia_bien';
        v_item := v_item_json->>'item_bien';

        IF v_precio IS NULL OR v_precio <= 0 THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = format('Ítem %s: el precio unitario debe ser mayor que cero.', v_orden);
        END IF;

        SELECT unidad_medida INTO v_unidad
        FROM maestro.siga_catalogo_item
        WHERE sec_ejec = p_sec_ejec
          AND tipo_bien = v_tipo_bien
          AND grupo_bien = v_grupo
          AND clase_bien = v_clase
          AND familia_bien = v_familia
          AND item_bien = v_item
          AND estado = 'A';

        IF v_unidad IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = '23503',
                MESSAGE = format('Ítem %s: no existe o está inactivo en el catálogo SIGA.', v_orden);
        END IF;

        v_item_id := gen_random_uuid();

        INSERT INTO cmn.item
        (id, solicitud_id, orden, tipo_movimiento, sec_ejec,
         tipo_bien, grupo_bien, clase_bien, familia_bien, item_bien,
         descripcion_servicio, unidad_medida, precio_unitario,
         creado_por, actualizado_por)
        VALUES
        (v_item_id, p_solicitud_id, COALESCE((v_item_json->>'orden')::integer, v_orden),
         COALESCE(upper(v_item_json->>'tipo_movimiento'), 'INCLUSION'), p_sec_ejec,
         v_tipo_bien, v_grupo, v_clase, v_familia, v_item,
         NULLIF(v_item_json->>'descripcion_servicio',''), v_unidad, v_precio,
         p_actor, p_actor);

        /* Siempre se materializan 48 filas: 12 meses por cuatro años. */
        INSERT INTO cmn.item_periodo(item_id, ano_offset, mes, cantidad, monto)
        SELECT
            v_item_id,
            a.ano_offset,
            m.mes,
            COALESCE((SELECT (x->>'cantidad')::numeric
                      FROM jsonb_array_elements(COALESCE(v_item_json->'periodos','[]'::jsonb)) x
                      WHERE (x->>'ano_offset')::integer = a.ano_offset
                        AND (x->>'mes')::integer = m.mes
                      LIMIT 1), 0),
            round(COALESCE((SELECT (x->>'cantidad')::numeric
                            FROM jsonb_array_elements(COALESCE(v_item_json->'periodos','[]'::jsonb)) x
                            WHERE (x->>'ano_offset')::integer = a.ano_offset
                              AND (x->>'mes')::integer = m.mes
                            LIMIT 1), 0) * v_precio, 2)
        FROM generate_series(0,3) AS a(ano_offset)
        CROSS JOIN generate_series(1,12) AS m(mes);

        IF EXISTS (
            SELECT 1 FROM cmn.item_periodo
            WHERE item_id = v_item_id AND cantidad < 0
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = format('Ítem %s: las cantidades no pueden ser negativas.', v_orden);
        END IF;

        SELECT SUM(cantidad) INTO v_total_cantidad
        FROM cmn.item_periodo WHERE item_id = v_item_id;

        IF COALESCE(v_total_cantidad,0) <= 0 THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = format('Ítem %s: debe programar al menos una cantidad mayor que cero.', v_orden);
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION cmn.validar_techo_solicitud(p_solicitud_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = cmn, maestro, public
AS $$
DECLARE
    v_solicitud cmn.solicitud%ROWTYPE;
    v_techo maestro.siga_techo_presupuesto%ROWTYPE;
    v_montos numeric[];
    v_i integer;
BEGIN
    SELECT * INTO STRICT v_solicitud FROM cmn.solicitud WHERE id = p_solicitud_id;

    SELECT * INTO v_techo
    FROM maestro.siga_techo_presupuesto
    WHERE ano_eje = v_solicitud.ano_eje
      AND sec_ejec = v_solicitud.sec_ejec
      AND centro_costo = v_solicitud.centro_costo
      AND fase_cuadro = v_solicitud.fase_cuadro
      AND origen = v_solicitud.origen
      AND fuente_financ = v_solicitud.fuente_financ
      AND sec_func = v_solicitud.sec_func
      AND clasificador = v_solicitud.clasificador;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503',
            MESSAGE = 'No existe techo presupuestal SIGA compatible con la solicitud.';
    END IF;

    SELECT ARRAY[
        COALESCE(SUM(p.monto) FILTER (WHERE p.ano_offset=0),0),
        COALESCE(SUM(p.monto) FILTER (WHERE p.ano_offset=1),0),
        COALESCE(SUM(p.monto) FILTER (WHERE p.ano_offset=2),0),
        COALESCE(SUM(p.monto) FILTER (WHERE p.ano_offset=3),0)
    ] INTO v_montos
    FROM cmn.item i
    JOIN cmn.item_periodo p ON p.item_id = i.id
    WHERE i.solicitud_id = p_solicitud_id
      AND i.tipo_movimiento = 'INCLUSION';

    IF v_montos[1] + v_techo.monto_usado_0 > v_techo.monto_techo_0 OR
       v_montos[2] + v_techo.monto_usado_1 > v_techo.monto_techo_1 OR
       v_montos[3] + v_techo.monto_usado_2 > v_techo.monto_techo_2 OR
       v_montos[4] + v_techo.monto_usado_3 > v_techo.monto_techo_3 THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'La solicitud excede el techo CMN cacheado en uno de los cuatro periodos.';
    END IF;
END;
$$;

/* -------------------------------------------------------------------------- */
/* 8. API de maestros                                                          */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION api.siga_sincronizar_maestros(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, maestro, public
AS $$
DECLARE
    r jsonb;
    v_conteos jsonb := '{}'::jsonb;
BEGIN
    FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'centros_costo','[]'::jsonb)) LOOP
        INSERT INTO maestro.siga_centro_costo
        (ano_eje,sec_ejec,centro_costo,descripcion,estado,sincronizado_en,payload_origen)
        VALUES ((r->>'ano_eje')::smallint,(r->>'sec_ejec')::integer,r->>'centro_costo',
                r->>'descripcion',COALESCE(r->>'estado','A'),clock_timestamp(),r)
        ON CONFLICT (ano_eje,sec_ejec,centro_costo) DO UPDATE
        SET descripcion=EXCLUDED.descripcion,estado=EXCLUDED.estado,
            sincronizado_en=EXCLUDED.sincronizado_en,payload_origen=EXCLUDED.payload_origen;
    END LOOP;

    FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'metas','[]'::jsonb)) LOOP
        INSERT INTO maestro.siga_meta
        (ano_eje,sec_ejec,sec_func,sec_func_prop,descripcion,estado,sincronizado_en,payload_origen)
        VALUES ((r->>'ano_eje')::smallint,(r->>'sec_ejec')::integer,(r->>'sec_func')::integer,
                NULLIF(r->>'sec_func_prop','')::integer,r->>'descripcion',
                COALESCE(r->>'estado','A'),clock_timestamp(),r)
        ON CONFLICT (ano_eje,sec_ejec,sec_func) DO UPDATE
        SET sec_func_prop=EXCLUDED.sec_func_prop,descripcion=EXCLUDED.descripcion,
            estado=EXCLUDED.estado,sincronizado_en=EXCLUDED.sincronizado_en,
            payload_origen=EXCLUDED.payload_origen;
    END LOOP;

    FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'fuentes','[]'::jsonb)) LOOP
        INSERT INTO maestro.siga_fuente_financiamiento
        (ano_eje,sec_ejec,origen,fuente_financ,descripcion,estado,sincronizado_en,payload_origen)
        VALUES ((r->>'ano_eje')::smallint,(r->>'sec_ejec')::integer,r->>'origen',r->>'fuente_financ',
                r->>'descripcion',COALESCE(r->>'estado','A'),clock_timestamp(),r)
        ON CONFLICT (ano_eje,sec_ejec,origen,fuente_financ) DO UPDATE
        SET descripcion=EXCLUDED.descripcion,estado=EXCLUDED.estado,
            sincronizado_en=EXCLUDED.sincronizado_en,payload_origen=EXCLUDED.payload_origen;
    END LOOP;

    FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'actividades','[]'::jsonb)) LOOP
        INSERT INTO maestro.siga_actividad_tarea
        (ano_eje,sec_ejec,tipo_tarea,nivel_tarea,codigo_tarea,descripcion,estado,sincronizado_en,payload_origen)
        VALUES ((r->>'ano_eje')::smallint,(r->>'sec_ejec')::integer,r->>'tipo_tarea',r->>'nivel_tarea',
                (r->>'codigo_tarea')::bigint,r->>'descripcion',COALESCE(r->>'estado','A'),clock_timestamp(),r)
        ON CONFLICT (ano_eje,sec_ejec,tipo_tarea,nivel_tarea,codigo_tarea) DO UPDATE
        SET descripcion=EXCLUDED.descripcion,estado=EXCLUDED.estado,
            sincronizado_en=EXCLUDED.sincronizado_en,payload_origen=EXCLUDED.payload_origen;
    END LOOP;

    FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'catalogo','[]'::jsonb)) LOOP
        INSERT INTO maestro.siga_catalogo_item
        (sec_ejec,tipo_bien,grupo_bien,clase_bien,familia_bien,item_bien,
         descripcion,unidad_medida,estado,sincronizado_en,payload_origen)
        VALUES ((r->>'sec_ejec')::integer,r->>'tipo_bien',r->>'grupo_bien',r->>'clase_bien',
                r->>'familia_bien',r->>'item_bien',r->>'descripcion',(r->>'unidad_medida')::integer,
                COALESCE(r->>'estado','A'),clock_timestamp(),r)
        ON CONFLICT (sec_ejec,tipo_bien,grupo_bien,clase_bien,familia_bien,item_bien) DO UPDATE
        SET descripcion=EXCLUDED.descripcion,unidad_medida=EXCLUDED.unidad_medida,
            estado=EXCLUDED.estado,sincronizado_en=EXCLUDED.sincronizado_en,
            payload_origen=EXCLUDED.payload_origen;
    END LOOP;

    FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'techos','[]'::jsonb)) LOOP
        INSERT INTO maestro.siga_techo_presupuesto
        (ano_eje,sec_ejec,centro_costo,fase_cuadro,origen,fuente_financ,sec_func,clasificador,
         categ_gasto,grupo_gasto,monto_techo_0,monto_techo_1,monto_techo_2,monto_techo_3,
         monto_usado_0,monto_usado_1,monto_usado_2,monto_usado_3,sincronizado_en,payload_origen)
        VALUES ((r->>'ano_eje')::smallint,(r->>'sec_ejec')::integer,r->>'centro_costo',
                COALESCE((r->>'fase_cuadro')::smallint,5),r->>'origen',r->>'fuente_financ',
                (r->>'sec_func')::integer,r->>'clasificador',r->>'categ_gasto',r->>'grupo_gasto',
                COALESCE((r->>'monto_techo_0')::numeric,0),COALESCE((r->>'monto_techo_1')::numeric,0),
                COALESCE((r->>'monto_techo_2')::numeric,0),COALESCE((r->>'monto_techo_3')::numeric,0),
                COALESCE((r->>'monto_usado_0')::numeric,0),COALESCE((r->>'monto_usado_1')::numeric,0),
                COALESCE((r->>'monto_usado_2')::numeric,0),COALESCE((r->>'monto_usado_3')::numeric,0),
                clock_timestamp(),r)
        ON CONFLICT (ano_eje,sec_ejec,centro_costo,fase_cuadro,origen,fuente_financ,sec_func,clasificador)
        DO UPDATE SET categ_gasto=EXCLUDED.categ_gasto,grupo_gasto=EXCLUDED.grupo_gasto,
            monto_techo_0=EXCLUDED.monto_techo_0,monto_techo_1=EXCLUDED.monto_techo_1,
            monto_techo_2=EXCLUDED.monto_techo_2,monto_techo_3=EXCLUDED.monto_techo_3,
            monto_usado_0=EXCLUDED.monto_usado_0,monto_usado_1=EXCLUDED.monto_usado_1,
            monto_usado_2=EXCLUDED.monto_usado_2,monto_usado_3=EXCLUDED.monto_usado_3,
            sincronizado_en=EXCLUDED.sincronizado_en,payload_origen=EXCLUDED.payload_origen;
    END LOOP;

    v_conteos := jsonb_build_object(
        'centros_costo', jsonb_array_length(COALESCE(p_payload->'centros_costo','[]'::jsonb)),
        'metas', jsonb_array_length(COALESCE(p_payload->'metas','[]'::jsonb)),
        'fuentes', jsonb_array_length(COALESCE(p_payload->'fuentes','[]'::jsonb)),
        'actividades', jsonb_array_length(COALESCE(p_payload->'actividades','[]'::jsonb)),
        'catalogo', jsonb_array_length(COALESCE(p_payload->'catalogo','[]'::jsonb)),
        'techos', jsonb_array_length(COALESCE(p_payload->'techos','[]'::jsonb))
    );
    RETURN api.ok(v_conteos);
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE, SQLERRM, jsonb_build_object('operacion','sincronizar_maestros'));
END;
$$;

/* -------------------------------------------------------------------------- */
/* 9. API CRUD CMN                                                             */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION api.cmn_registrar(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, cmn, workflow, auditoria, public
AS $$
DECLARE
    s                   jsonb := p_payload->'solicitud';
    a                   jsonb := COALESCE(p_payload->'actor','{}'::jsonb);
    v_id                uuid := COALESCE(NULLIF(s->>'id','')::uuid, gen_random_uuid());
    v_actor             text := NULLIF(a->>'usuario','');
    v_rol               text := NULLIF(a->>'rol','');
    v_codigo            text;
    v_ano               smallint;
    v_sec_ejec          integer;
    v_resultado         jsonb;
BEGIN
    IF s IS NULL OR jsonb_typeof(s) <> 'object' THEN
        RETURN api.error('PAYLOAD_INVALIDO','Debe enviar el objeto solicitud.');
    END IF;
    IF v_actor IS NULL OR v_rol IS NULL THEN
        RETURN api.error('ACTOR_REQUERIDO','El backend debe informar actor.usuario y actor.rol.');
    END IF;
    IF v_rol NOT IN ('AREA_ESPECIALISTA','AREA_JEFE','ADMIN_SISTEMA') THEN
        RETURN api.error('ROL_NO_AUTORIZADO','El rol no puede registrar una solicitud CMN.');
    END IF;

    v_ano := (s->>'ano_eje')::smallint;
    v_sec_ejec := (s->>'sec_ejec')::integer;
    v_codigo := COALESCE(NULLIF(s->>'codigo',''),
        format('CMN-%s-%s',v_ano,lpad(nextval('cmn.seq_codigo_solicitud')::text,6,'0')));

    INSERT INTO cmn.solicitud
    (id,codigo,idempotencia_key,tipo_operacion,tipo_inclusion,estado_codigo,
     ano_eje,sec_ejec,centro_costo,fase_cuadro,tipo_tarea,nivel_tarea,codigo_tarea,
     sec_func,sec_func_prop,origen,fuente_financ,clasificador,tipo_recurso,tipo_ppto,
     tipo_uso,tipo_bien,sustento,fecha_solicitud,responsable_area,cargo_responsable,
     datos_adicionales,creado_por,actualizado_por)
    VALUES
    (v_id,v_codigo,NULLIF(s->>'idempotencia_key',''),
     COALESCE(s->>'tipo_operacion','ALTA_ORDINARIA'),
     COALESCE(s->>'tipo_inclusion','ORDINARIA'),'CMN_BORRADOR',
     v_ano,v_sec_ejec,s->>'centro_costo',COALESCE((s->>'fase_cuadro')::smallint,5),
     s->>'tipo_tarea',s->>'nivel_tarea',(s->>'codigo_tarea')::bigint,
     (s->>'sec_func')::integer,NULLIF(s->>'sec_func_prop','')::integer,
     COALESCE(s->>'origen','1'),COALESCE(s->>'fuente_financ','00'),s->>'clasificador',
     COALESCE(s->>'tipo_recurso','1'),COALESCE((s->>'tipo_ppto')::smallint,1),
     COALESCE(s->>'tipo_uso','C'),upper(s->>'tipo_bien'),s->>'sustento',
     COALESCE((s->>'fecha_solicitud')::date,current_date),s->>'responsable_area',
     s->>'cargo_responsable',COALESCE(s->'datos_adicionales','{}'::jsonb),v_actor,v_actor);

    PERFORM cmn.insertar_items(v_id,v_sec_ejec,p_payload->'items',v_actor);
    PERFORM cmn.validar_techo_solicitud(v_id);

    INSERT INTO workflow.historial
    (modulo,entidad_id,estado_destino,transicion_codigo,comentario,actor,actor_rol,metadata)
    VALUES ('CMN',v_id,'CMN_BORRADOR','CMN_REGISTRAR','Solicitud CMN registrada',v_actor,v_rol,
            jsonb_build_object('codigo',v_codigo));

    PERFORM auditoria.registrar('CMN','cmn.solicitud',v_id,'REGISTRAR',v_actor,v_rol,NULL,
        jsonb_build_object('codigo',v_codigo,'version',1),COALESCE(a->'metadata','{}'::jsonb));

    SELECT jsonb_build_object('solicitud_id',id,'codigo',codigo,'estado',estado_codigo,'version',version)
    INTO v_resultado FROM cmn.solicitud WHERE id=v_id;
    RETURN api.ok(v_resultado);
EXCEPTION
    WHEN unique_violation THEN
        RETURN api.error('DUPLICADO',SQLERRM,jsonb_build_object('idempotencia_key',s->>'idempotencia_key'));
    WHEN foreign_key_violation THEN
        RETURN api.error('MAESTRO_SIGA_NO_VALIDO',SQLERRM);
    WHEN OTHERS THEN
        RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_registrar'));
END;
$$;

CREATE OR REPLACE FUNCTION api.cmn_listar(p_filtro jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = api, cmn, public
AS $$
DECLARE
    v_limite integer := LEAST(GREATEST(COALESCE((p_filtro->>'limite')::integer,20),1),100);
    v_offset integer := GREATEST(COALESCE((p_filtro->>'offset')::integer,0),0);
    v_total bigint;
    v_data jsonb;
BEGIN
    SELECT COUNT(*) INTO v_total
    FROM cmn.solicitud s
    WHERE (NULLIF(p_filtro->>'estado','') IS NULL OR s.estado_codigo=p_filtro->>'estado')
      AND (NULLIF(p_filtro->>'centro_costo','') IS NULL OR s.centro_costo=p_filtro->>'centro_costo')
      AND (NULLIF(p_filtro->>'ano_eje','') IS NULL OR s.ano_eje=(p_filtro->>'ano_eje')::smallint)
      AND (COALESCE((p_filtro->>'incluir_anulados')::boolean,false) OR NOT s.anulado)
      AND (NULLIF(p_filtro->>'texto','') IS NULL OR
           s.codigo ILIKE '%'||(p_filtro->>'texto')||'%' OR
           s.sustento ILIKE '%'||(p_filtro->>'texto')||'%');

    SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.actualizado_en DESC),'[]'::jsonb)
    INTO v_data
    FROM (
        SELECT s.id,s.codigo,s.tipo_operacion,s.tipo_inclusion,s.estado_codigo,
               s.ano_eje,s.sec_ejec,s.centro_costo,s.fecha_solicitud,s.version,
               s.secuencia_siga,s.anulado,s.actualizado_en,
               (SELECT COUNT(*) FROM cmn.item i WHERE i.solicitud_id=s.id) AS items,
               (SELECT COALESCE(SUM(r.monto_total),0) FROM cmn.v_item_resumen r
                WHERE r.solicitud_id=s.id AND r.tipo_movimiento='INCLUSION') AS monto_inclusion
        FROM cmn.solicitud s
        WHERE (NULLIF(p_filtro->>'estado','') IS NULL OR s.estado_codigo=p_filtro->>'estado')
          AND (NULLIF(p_filtro->>'centro_costo','') IS NULL OR s.centro_costo=p_filtro->>'centro_costo')
          AND (NULLIF(p_filtro->>'ano_eje','') IS NULL OR s.ano_eje=(p_filtro->>'ano_eje')::smallint)
          AND (COALESCE((p_filtro->>'incluir_anulados')::boolean,false) OR NOT s.anulado)
          AND (NULLIF(p_filtro->>'texto','') IS NULL OR
               s.codigo ILIKE '%'||(p_filtro->>'texto')||'%' OR
               s.sustento ILIKE '%'||(p_filtro->>'texto')||'%')
        ORDER BY s.actualizado_en DESC
        LIMIT v_limite OFFSET v_offset
    ) q;

    RETURN api.ok(v_data,jsonb_build_object('total',v_total,'limite',v_limite,'offset',v_offset));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_listar'));
END;
$$;

CREATE OR REPLACE FUNCTION api.cmn_obtener(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = api, cmn, workflow, integracion, public
AS $$
DECLARE
    v_id uuid := (p_payload->>'solicitud_id')::uuid;
    v_data jsonb;
BEGIN
    SELECT to_jsonb(s) || jsonb_build_object(
        'items', COALESCE((
            SELECT jsonb_agg(to_jsonb(r) || jsonb_build_object(
                'periodos',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.ano_offset,p.mes)
                            FROM cmn.item_periodo p WHERE p.item_id=r.item_id)
            ) ORDER BY r.orden)
            FROM cmn.v_item_resumen r WHERE r.solicitud_id=s.id
        ),'[]'::jsonb),
        'documentos', COALESCE((
            SELECT jsonb_agg(to_jsonb(d) || jsonb_build_object(
                'firmas',(SELECT COALESCE(jsonb_agg(to_jsonb(f) ORDER BY f.firmado_en),'[]'::jsonb)
                          FROM cmn.documento_firma f WHERE f.documento_id=d.id)
            ) ORDER BY d.creado_en)
            FROM cmn.documento d
            JOIN cmn.documento_solicitud ds ON ds.documento_id=d.id
            WHERE ds.solicitud_id=s.id
        ),'[]'::jsonb),
        'observaciones', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.creada_en)
                                   FROM cmn.observacion o WHERE o.solicitud_id=s.id),'[]'::jsonb),
        'historial', COALESCE((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.ocurrido_en)
                              FROM workflow.historial h WHERE h.modulo='CMN' AND h.entidad_id=s.id),'[]'::jsonb),
        'integracion_siga', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.creado_en)
                                     FROM integracion.siga_operacion x WHERE x.solicitud_id=s.id),'[]'::jsonb)
    ) INTO v_data
    FROM cmn.solicitud s WHERE s.id=v_id;

    IF v_data IS NULL THEN RETURN api.error('NO_ENCONTRADO','La solicitud CMN no existe.'); END IF;
    RETURN api.ok(v_data);
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_obtener'));
END;
$$;

CREATE OR REPLACE FUNCTION api.cmn_modificar(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, cmn, workflow, auditoria, public
AS $$
DECLARE
    s jsonb := p_payload->'solicitud';
    a jsonb := COALESCE(p_payload->'actor','{}'::jsonb);
    v_id uuid := (s->>'id')::uuid;
    v_version integer := (s->>'version')::integer;
    v_actor text := NULLIF(a->>'usuario','');
    v_rol text := NULLIF(a->>'rol','');
    v_actual cmn.solicitud%ROWTYPE;
BEGIN
    IF v_actor IS NULL OR v_rol IS NULL THEN
        RETURN api.error('ACTOR_REQUERIDO','El backend debe informar actor.usuario y actor.rol.');
    END IF;
    IF v_rol NOT IN ('AREA_ESPECIALISTA','AREA_JEFE','ADMIN_SISTEMA') THEN
        RETURN api.error('ROL_NO_AUTORIZADO','El rol no puede modificar una solicitud CMN.');
    END IF;
    SELECT * INTO v_actual FROM cmn.solicitud WHERE id=v_id FOR UPDATE;
    IF NOT FOUND THEN RETURN api.error('NO_ENCONTRADO','La solicitud CMN no existe.'); END IF;
    IF v_actual.anulado THEN RETURN api.error('SOLICITUD_ANULADA','No se puede modificar una solicitud anulada.'); END IF;
    IF v_actual.estado_codigo NOT IN ('CMN_BORRADOR','CMN_OBSERVADO') THEN
        RETURN api.error('ESTADO_NO_EDITABLE','La solicitud solo se modifica en borrador u observado.',
                         jsonb_build_object('estado',v_actual.estado_codigo));
    END IF;
    IF v_actual.version <> v_version THEN
        RETURN api.error('CONFLICTO_VERSION','La solicitud fue modificada por otro usuario.',
                         jsonb_build_object('version_actual',v_actual.version));
    END IF;
    IF EXISTS (SELECT 1 FROM integracion.siga_item_mapeo m WHERE m.solicitud_id=v_id) THEN
        RETURN api.error('YA_REGISTRADO_EN_SIGA','No se puede reemplazar ítems ya registrados en SIGA.');
    END IF;

    UPDATE cmn.solicitud SET
        tipo_operacion=COALESCE(s->>'tipo_operacion',tipo_operacion),
        tipo_inclusion=COALESCE(s->>'tipo_inclusion',tipo_inclusion),
        centro_costo=COALESCE(s->>'centro_costo',centro_costo),
        tipo_tarea=COALESCE(s->>'tipo_tarea',tipo_tarea),
        nivel_tarea=COALESCE(s->>'nivel_tarea',nivel_tarea),
        codigo_tarea=COALESCE((s->>'codigo_tarea')::bigint,codigo_tarea),
        sec_func=COALESCE((s->>'sec_func')::integer,sec_func),
        sec_func_prop=COALESCE(NULLIF(s->>'sec_func_prop','')::integer,sec_func_prop),
        origen=COALESCE(s->>'origen',origen),
        fuente_financ=COALESCE(s->>'fuente_financ',fuente_financ),
        clasificador=COALESCE(s->>'clasificador',clasificador),
        tipo_recurso=COALESCE(s->>'tipo_recurso',tipo_recurso),
        tipo_ppto=COALESCE((s->>'tipo_ppto')::smallint,tipo_ppto),
        tipo_uso=COALESCE(s->>'tipo_uso',tipo_uso),
        tipo_bien=COALESCE(upper(s->>'tipo_bien'),tipo_bien),
        sustento=COALESCE(s->>'sustento',sustento),
        responsable_area=COALESCE(s->>'responsable_area',responsable_area),
        cargo_responsable=COALESCE(s->>'cargo_responsable',cargo_responsable),
        datos_adicionales=COALESCE(s->'datos_adicionales',datos_adicionales),
        estado_codigo='CMN_BORRADOR',version=version+1,
        actualizado_por=v_actor,actualizado_en=clock_timestamp()
    WHERE id=v_id;

    IF p_payload ? 'items' THEN
        DELETE FROM cmn.item WHERE solicitud_id=v_id;
        PERFORM cmn.insertar_items(v_id,v_actual.sec_ejec,p_payload->'items',v_actor);
    END IF;
    PERFORM cmn.validar_techo_solicitud(v_id);

    INSERT INTO workflow.historial
    (modulo,entidad_id,estado_origen,estado_destino,transicion_codigo,comentario,actor,actor_rol)
    VALUES ('CMN',v_id,v_actual.estado_codigo,'CMN_BORRADOR','CMN_MODIFICAR',
            COALESCE(p_payload->>'comentario','Solicitud modificada'),v_actor,v_rol);
    PERFORM auditoria.registrar('CMN','cmn.solicitud',v_id,'MODIFICAR',v_actor,v_rol,to_jsonb(v_actual),
        jsonb_build_object('version',v_version+1),COALESCE(a->'metadata','{}'::jsonb));

    RETURN api.ok(jsonb_build_object('solicitud_id',v_id,'estado','CMN_BORRADOR','version',v_version+1));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_modificar'));
END;
$$;

CREATE OR REPLACE FUNCTION api.cmn_anular(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, cmn, workflow, integracion, auditoria, public
AS $$
DECLARE
    v_id uuid := (p_payload->>'solicitud_id')::uuid;
    a jsonb := COALESCE(p_payload->'actor','{}'::jsonb);
    v_actor text := NULLIF(a->>'usuario','');
    v_rol text := NULLIF(a->>'rol','');
    v_motivo text := NULLIF(p_payload->>'motivo','');
    v_actual cmn.solicitud%ROWTYPE;
BEGIN
    IF v_actor IS NULL OR v_rol IS NULL THEN
        RETURN api.error('ACTOR_REQUERIDO','El backend debe informar actor.usuario y actor.rol.');
    END IF;
    IF v_rol NOT IN ('AREA_ESPECIALISTA','AREA_JEFE','ADMIN_SISTEMA') THEN
        RETURN api.error('ROL_NO_AUTORIZADO','El rol no puede anular una solicitud CMN.');
    END IF;
    IF v_motivo IS NULL THEN RETURN api.error('MOTIVO_REQUERIDO','Debe informar el motivo de anulación.'); END IF;
    SELECT * INTO v_actual FROM cmn.solicitud WHERE id=v_id FOR UPDATE;
    IF NOT FOUND THEN RETURN api.error('NO_ENCONTRADO','La solicitud CMN no existe.'); END IF;
    IF EXISTS (SELECT 1 FROM integracion.siga_item_mapeo WHERE solicitud_id=v_id) THEN
        RETURN api.error('ANULACION_REQUIERE_SIGA',
            'La solicitud ya tiene ítems en SIGA. Debe ejecutarse el procedimiento de reversión homologado.');
    END IF;

    UPDATE cmn.solicitud SET anulado=true,motivo_anulacion=v_motivo,
        anulado_en=clock_timestamp(),anulado_por=v_actor,estado_codigo='CMN_ANULADO',
        version=version+1,actualizado_por=v_actor,actualizado_en=clock_timestamp()
    WHERE id=v_id;
    UPDATE integracion.siga_operacion SET estado='ANULADO',actualizado_en=clock_timestamp()
    WHERE solicitud_id=v_id AND estado IN ('PENDIENTE','REINTENTO');

    INSERT INTO workflow.historial
    (modulo,entidad_id,estado_origen,estado_destino,transicion_codigo,comentario,actor,actor_rol)
    VALUES ('CMN',v_id,v_actual.estado_codigo,'CMN_ANULADO','CMN_ANULAR',v_motivo,v_actor,v_rol);
    PERFORM auditoria.registrar('CMN','cmn.solicitud',v_id,'ANULAR',v_actor,v_rol,to_jsonb(v_actual),
        jsonb_build_object('motivo',v_motivo),COALESCE(a->'metadata','{}'::jsonb));
    RETURN api.ok(jsonb_build_object('solicitud_id',v_id,'estado','CMN_ANULADO'));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_anular'));
END;
$$;

/* -------------------------------------------------------------------------- */
/* 10. API de flujo, observaciones y documentos                                */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION api.cmn_cambiar_estado(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, cmn, workflow, auditoria, public
AS $$
DECLARE
    v_id uuid := (p_payload->>'solicitud_id')::uuid;
    v_accion text := p_payload->>'accion';
    a jsonb := COALESCE(p_payload->'actor','{}'::jsonb);
    v_actor text := NULLIF(a->>'usuario','');
    v_rol text := NULLIF(a->>'rol','');
    v_comentario text := NULLIF(p_payload->>'comentario','');
    v_actual cmn.solicitud%ROWTYPE;
    v_t workflow.transicion%ROWTYPE;
BEGIN
    IF v_actor IS NULL OR v_rol IS NULL THEN
        RETURN api.error('ACTOR_REQUERIDO','El backend debe informar actor.usuario y actor.rol.');
    END IF;
    SELECT * INTO v_actual FROM cmn.solicitud WHERE id=v_id FOR UPDATE;
    IF NOT FOUND THEN RETURN api.error('NO_ENCONTRADO','La solicitud CMN no existe.'); END IF;

    SELECT * INTO v_t FROM workflow.transicion
    WHERE codigo=v_accion AND modulo='CMN' AND estado_origen=v_actual.estado_codigo AND activo;
    IF NOT FOUND THEN
        RETURN api.error('TRANSICION_NO_VALIDA','La acción no está habilitada para el estado actual.',
            jsonb_build_object('estado',v_actual.estado_codigo,'accion',v_accion));
    END IF;
    IF NOT (v_rol = ANY(v_t.roles_permitidos)) THEN
        RETURN api.error('ROL_NO_AUTORIZADO','El rol no puede ejecutar esta transición.');
    END IF;
    IF v_t.requiere_comentario AND v_comentario IS NULL THEN
        RETURN api.error('COMENTARIO_REQUERIDO','La transición exige comentario o sustento.');
    END IF;

    UPDATE cmn.solicitud SET estado_codigo=v_t.estado_destino,version=version+1,
        actualizado_por=v_actor,actualizado_en=clock_timestamp() WHERE id=v_id;
    INSERT INTO workflow.historial
    (modulo,entidad_id,estado_origen,estado_destino,transicion_codigo,comentario,actor,actor_rol,metadata)
    VALUES ('CMN',v_id,v_actual.estado_codigo,v_t.estado_destino,v_t.codigo,v_comentario,v_actor,v_rol,
            COALESCE(p_payload->'metadata','{}'::jsonb));
    PERFORM auditoria.registrar('CMN','cmn.solicitud',v_id,v_accion,v_actor,v_rol,
        jsonb_build_object('estado',v_actual.estado_codigo),jsonb_build_object('estado',v_t.estado_destino),
        COALESCE(a->'metadata','{}'::jsonb));
    RETURN api.ok(jsonb_build_object('solicitud_id',v_id,'estado',v_t.estado_destino,
                                     'version',v_actual.version+1));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_cambiar_estado'));
END;
$$;

CREATE OR REPLACE FUNCTION api.cmn_registrar_observacion(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, cmn, public
AS $$
DECLARE
    v_id uuid := (p_payload->>'solicitud_id')::uuid;
    a jsonb := COALESCE(p_payload->'actor','{}'::jsonb);
    v_origen text := NULLIF(a->>'rol','');
    v_actor text := NULLIF(a->>'usuario','');
    v_destino text := COALESCE(p_payload->>'destino_rol','AREA_JEFE');
    v_motivo text := NULLIF(p_payload->>'motivo','');
    v_obs uuid;
    v_accion text;
    v_result jsonb;
BEGIN
    IF v_actor IS NULL OR v_origen IS NULL THEN
        RETURN api.error('ACTOR_REQUERIDO','El backend debe informar actor.usuario y actor.rol.');
    END IF;
    IF v_motivo IS NULL THEN RETURN api.error('MOTIVO_REQUERIDO','Debe detallar la observación.'); END IF;
    v_accion := CASE v_origen WHEN 'OA' THEN 'CMN_OBSERVAR_OA'
                              WHEN 'ABAST_ESPECIALISTA' THEN 'CMN_OBSERVAR_ABAST'
                              WHEN 'ABAST_COORDINADOR' THEN 'CMN_OBSERVAR_ABAST' END;
    IF v_accion IS NULL THEN RETURN api.error('ROL_NO_AUTORIZADO','El rol no puede observar el CMN.'); END IF;

    v_result := api.cmn_cambiar_estado(jsonb_build_object(
        'solicitud_id',v_id,'accion',v_accion,'comentario',v_motivo,'actor',a));
    IF NOT COALESCE((v_result->>'ok')::boolean,false) THEN RETURN v_result; END IF;

    INSERT INTO cmn.observacion
    (solicitud_id,origen_rol,destino_rol,motivo,creada_por)
    VALUES (v_id,v_origen,v_destino,v_motivo,v_actor) RETURNING id INTO v_obs;
    RETURN api.ok(jsonb_build_object('observacion_id',v_obs,'solicitud_id',v_id,'estado','PENDIENTE'));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_registrar_observacion'));
END;
$$;

CREATE OR REPLACE FUNCTION api.cmn_generar_anexo3(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, cmn, workflow, auditoria, public
AS $$
DECLARE
    v_id uuid := (p_payload->>'solicitud_id')::uuid;
    a jsonb := COALESCE(p_payload->'actor','{}'::jsonb);
    v_actor text := NULLIF(a->>'usuario','');
    v_rol text := NULLIF(a->>'rol','');
    v_s cmn.solicitud%ROWTYPE;
    v_doc_id uuid := gen_random_uuid();
    v_version integer;
    v_payload_doc jsonb;
BEGIN
    IF v_actor IS NULL OR v_rol IS NULL THEN
        RETURN api.error('ACTOR_REQUERIDO','El backend debe informar actor.usuario y actor.rol.');
    END IF;
    SELECT * INTO v_s FROM cmn.solicitud WHERE id=v_id FOR UPDATE;
    IF NOT FOUND THEN RETURN api.error('NO_ENCONTRADO','La solicitud CMN no existe.'); END IF;
    IF v_s.estado_codigo NOT IN ('CMN_BORRADOR','CMN_OBSERVADO') THEN
        RETURN api.error('ESTADO_NO_VALIDO','El Anexo 3 solo se genera desde borrador u observado.');
    END IF;
    IF v_rol NOT IN ('AREA_ESPECIALISTA','AREA_JEFE') THEN
        RETURN api.error('ROL_NO_AUTORIZADO','El rol no puede generar el Anexo 3.');
    END IF;

    SELECT COALESCE(MAX(d.version),0)+1 INTO v_version
    FROM cmn.documento d JOIN cmn.documento_solicitud ds ON ds.documento_id=d.id
    WHERE ds.solicitud_id=v_id AND d.tipo='ANEXO_3';

    SELECT jsonb_build_object(
        'tipo','ANEXO_3','version',v_version,'solicitud_id',v_s.id,
        'numero_solicitud',v_s.codigo,'area_usuaria',cc.descripcion,
        'centro_costo',v_s.centro_costo,'fecha',v_s.fecha_solicitud,
        'responsable_area',v_s.responsable_area,'cargo',v_s.cargo_responsable,
        'sustento',v_s.sustento,'tipo_inclusion',v_s.tipo_inclusion,
        'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'orden',r.orden,'movimiento',r.tipo_movimiento,
            'codigo',concat_ws('-',r.tipo_bien,r.grupo_bien,r.clase_bien,r.familia_bien,r.item_bien),
            'descripcion',r.descripcion,'unidad_medida',r.unidad_medida,
            'cantidad_total',r.cantidad_total,'valor_total',r.monto_total,
            'cantidad_ano_0',r.cantidad_0,'valor_ano_0',r.monto_0,
            'cantidad_ano_1',r.cantidad_1,'valor_ano_1',r.monto_1,
            'cantidad_ano_2',r.cantidad_2,'valor_ano_2',r.monto_2,
            'cantidad_ano_3',r.cantidad_3,'valor_ano_3',r.monto_3
        ) ORDER BY r.orden) FROM cmn.v_item_resumen r WHERE r.solicitud_id=v_id),'[]'::jsonb)
    ) INTO v_payload_doc
    FROM maestro.siga_centro_costo cc
    WHERE cc.ano_eje=v_s.ano_eje AND cc.sec_ejec=v_s.sec_ejec AND cc.centro_costo=v_s.centro_costo;

    INSERT INTO cmn.documento
    (id,tipo,numero,version,consolidado,estado,payload,firmas_requeridas,creado_por)
    VALUES (v_doc_id,'ANEXO_3',v_s.codigo,v_version,false,'BORRADOR',v_payload_doc,
            ARRAY['AREA_JEFE'],v_actor);
    INSERT INTO cmn.documento_solicitud(documento_id,solicitud_id) VALUES(v_doc_id,v_id);
    UPDATE cmn.solicitud SET estado_codigo='CMN_PEND_FIRMA_A3',version=version+1,
        actualizado_por=v_actor,actualizado_en=clock_timestamp() WHERE id=v_id;
    INSERT INTO workflow.historial
    (modulo,entidad_id,estado_origen,estado_destino,transicion_codigo,comentario,actor,actor_rol)
    VALUES ('CMN',v_id,v_s.estado_codigo,'CMN_PEND_FIRMA_A3','CMN_GENERAR_A3',
            format('Anexo 3 versión %s generado',v_version),v_actor,v_rol);
    RETURN api.ok(jsonb_build_object('documento_id',v_doc_id,'tipo','ANEXO_3',
                                     'version',v_version,'estado','BORRADOR','payload',v_payload_doc));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_generar_anexo3'));
END;
$$;

CREATE OR REPLACE FUNCTION api.cmn_generar_anexo4(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, cmn, workflow, auditoria, public
AS $$
DECLARE
    a jsonb := COALESCE(p_payload->'actor','{}'::jsonb);
    v_actor text := NULLIF(a->>'usuario','');
    v_rol text := NULLIF(a->>'rol','');
    v_ids uuid[];
    v_doc_id uuid := gen_random_uuid();
    v_numero text;
    v_version integer;
    v_payload_doc jsonb;
    v_count integer;
BEGIN
    IF v_actor IS NULL OR v_rol IS NULL THEN
        RETURN api.error('ACTOR_REQUERIDO','El backend debe informar actor.usuario y actor.rol.');
    END IF;
    SELECT array_agg(value::text::uuid) INTO v_ids
    FROM jsonb_array_elements_text(COALESCE(p_payload->'solicitud_ids','[]'::jsonb));
    v_count := COALESCE(array_length(v_ids,1),0);
    IF v_count=0 THEN RETURN api.error('SOLICITUDES_REQUERIDAS','Informe una o más solicitudes.'); END IF;
    IF v_rol NOT IN ('ABAST_ESPECIALISTA','ABAST_COORDINADOR','ABAST_JEFE') THEN
        RETURN api.error('ROL_NO_AUTORIZADO','El rol no puede generar el Anexo 4.');
    END IF;
    IF (SELECT COUNT(*) FROM cmn.solicitud WHERE id=ANY(v_ids) AND estado_codigo='CMN_VALIDADO_UA' AND NOT anulado) <> v_count THEN
        RETURN api.error('ESTADO_NO_VALIDO','Todas las solicitudes deben estar validadas por Abastecimiento.');
    END IF;

    v_numero := COALESCE(NULLIF(p_payload->>'numero',''),
        format('A4-%s-%s',to_char(current_date,'YYYYMMDD'),substr(v_doc_id::text,1,8)));
    SELECT COALESCE(MAX(version),0)+1 INTO v_version FROM cmn.documento
    WHERE tipo='ANEXO_4' AND numero=v_numero;

    SELECT jsonb_build_object(
        'tipo','ANEXO_4','numero',v_numero,'version',v_version,
        'consolidado',v_count>1,'fecha',current_date,
        'entidad','Autoridad Nacional de Infraestructura','identificacion','ANIN',
        'solicitudes',jsonb_agg(jsonb_build_object(
            'solicitud_id',s.id,'numero_solicitud',s.codigo,'fecha_solicitud',s.fecha_solicitud,
            'centro_costo',s.centro_costo,'area_usuaria',cc.descripcion,
            'items',(SELECT jsonb_agg(jsonb_build_object(
                'orden',r.orden,'movimiento',r.tipo_movimiento,
                'codigo',concat_ws('-',r.tipo_bien,r.grupo_bien,r.clase_bien,r.familia_bien,r.item_bien),
                'descripcion',r.descripcion,'unidad_medida',r.unidad_medida,
                'cantidad_total',r.cantidad_total,'valor_total',r.monto_total
            ) ORDER BY r.orden) FROM cmn.v_item_resumen r WHERE r.solicitud_id=s.id)
        ) ORDER BY s.codigo)
    ) INTO v_payload_doc
    FROM cmn.solicitud s
    JOIN maestro.siga_centro_costo cc
      ON cc.ano_eje=s.ano_eje AND cc.sec_ejec=s.sec_ejec AND cc.centro_costo=s.centro_costo
    WHERE s.id=ANY(v_ids);

    INSERT INTO cmn.documento
    (id,tipo,numero,version,consolidado,estado,payload,firmas_requeridas,creado_por)
    VALUES (v_doc_id,'ANEXO_4',v_numero,v_version,v_count>1,'BORRADOR',v_payload_doc,
            ARRAY['ABAST_JEFE','MAX_AUT_ADMIN'],v_actor);
    INSERT INTO cmn.documento_solicitud(documento_id,solicitud_id)
    SELECT v_doc_id,unnest(v_ids);
    UPDATE cmn.solicitud SET estado_codigo='CMN_PEND_FIRMA_A4',version=version+1,
        actualizado_por=v_actor,actualizado_en=clock_timestamp() WHERE id=ANY(v_ids);
    INSERT INTO workflow.historial
    (modulo,entidad_id,estado_origen,estado_destino,transicion_codigo,comentario,actor,actor_rol,metadata)
    SELECT 'CMN',id,'CMN_VALIDADO_UA','CMN_PEND_FIRMA_A4','CMN_GENERAR_A4',
           format('Anexo 4 %s generado',v_numero),v_actor,v_rol,jsonb_build_object('documento_id',v_doc_id)
    FROM cmn.solicitud WHERE id=ANY(v_ids);

    RETURN api.ok(jsonb_build_object('documento_id',v_doc_id,'tipo','ANEXO_4',
        'numero',v_numero,'version',v_version,'consolidado',v_count>1,
        'solicitudes',v_count,'estado','BORRADOR','payload',v_payload_doc));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_generar_anexo4'));
END;
$$;

CREATE OR REPLACE FUNCTION api.cmn_firmar_documento(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, cmn, workflow, auditoria, public
AS $$
DECLARE
    v_doc_id uuid := (p_payload->>'documento_id')::uuid;
    a jsonb := COALESCE(p_payload->'actor','{}'::jsonb);
    v_actor text := NULLIF(a->>'usuario','');
    v_rol text := NULLIF(a->>'rol','');
    v_doc cmn.documento%ROWTYPE;
    v_completo boolean;
    v_estado_destino text;
BEGIN
    IF v_actor IS NULL OR v_rol IS NULL THEN
        RETURN api.error('ACTOR_REQUERIDO','El backend debe informar actor.usuario y actor.rol.');
    END IF;
    SELECT * INTO v_doc FROM cmn.documento WHERE id=v_doc_id FOR UPDATE;
    IF NOT FOUND THEN RETURN api.error('NO_ENCONTRADO','El documento no existe.'); END IF;
    IF v_doc.estado <> 'BORRADOR' THEN RETURN api.error('ESTADO_NO_VALIDO','El documento no admite una nueva firma.'); END IF;
    IF NOT (v_rol = ANY(v_doc.firmas_requeridas)) THEN
        RETURN api.error('ROL_FIRMA_NO_VALIDO','El rol no está configurado como firmante del documento.');
    END IF;

    INSERT INTO cmn.documento_firma
    (documento_id,rol_firma,firmante,cargo,certificado_serie,firma_hash,firma_payload)
    VALUES (v_doc_id,v_rol,COALESCE(p_payload->>'firmante',v_actor),p_payload->>'cargo',
            p_payload->>'certificado_serie',p_payload->>'firma_hash',
            COALESCE(p_payload->'firma_payload','{}'::jsonb));

    SELECT NOT EXISTS (
        SELECT 1 FROM unnest(v_doc.firmas_requeridas) r
        WHERE NOT EXISTS (SELECT 1 FROM cmn.documento_firma f
                          WHERE f.documento_id=v_doc_id AND f.rol_firma=r)
    ) INTO v_completo;

    IF v_completo THEN
        UPDATE cmn.documento SET estado='FIRMADO',firmado_en=clock_timestamp() WHERE id=v_doc_id;
        v_estado_destino := CASE v_doc.tipo WHEN 'ANEXO_3' THEN 'CMN_A3_FIRMADO' ELSE 'CMN_A4_FIRMADO' END;
        UPDATE cmn.solicitud s SET estado_codigo=v_estado_destino,version=version+1,
            actualizado_por=v_actor,actualizado_en=clock_timestamp()
        FROM cmn.documento_solicitud ds
        WHERE ds.documento_id=v_doc_id AND ds.solicitud_id=s.id;
        INSERT INTO workflow.historial
        (modulo,entidad_id,estado_origen,estado_destino,transicion_codigo,comentario,actor,actor_rol,metadata)
        SELECT 'CMN',ds.solicitud_id,
               CASE v_doc.tipo WHEN 'ANEXO_3' THEN 'CMN_PEND_FIRMA_A3' ELSE 'CMN_PEND_FIRMA_A4' END,
               v_estado_destino,CASE v_doc.tipo WHEN 'ANEXO_3' THEN 'CMN_FIRMAR_A3' ELSE 'CMN_FIRMAR_A4' END,
               format('%s completó sus firmas',v_doc.tipo),v_actor,v_rol,jsonb_build_object('documento_id',v_doc_id)
        FROM cmn.documento_solicitud ds WHERE ds.documento_id=v_doc_id;
    END IF;

    RETURN api.ok(jsonb_build_object('documento_id',v_doc_id,'firma_registrada',true,
        'firmas_completas',v_completo,'estado',CASE WHEN v_completo THEN 'FIRMADO' ELSE 'BORRADOR' END));
EXCEPTION
    WHEN unique_violation THEN RETURN api.error('FIRMA_DUPLICADA','El rol ya firmó este documento.');
    WHEN OTHERS THEN RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_firmar_documento'));
END;
$$;

/* -------------------------------------------------------------------------- */
/* 11. Preparación e intercambio con el backend puente                         */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION integracion.periodos_xml(p_item_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = integracion, cmn, public
AS $$
SELECT '<Periodos>' || string_agg(
    format('<Periodo codigo="%s" c01="%s" c02="%s" c03="%s" c04="%s" c05="%s" c06="%s" c07="%s" c08="%s" c09="%s" c10="%s" c11="%s" c12="%s" />',
        ano_offset,
        c01,c02,c03,c04,c05,c06,c07,c08,c09,c10,c11,c12
    ), '' ORDER BY ano_offset) || '</Periodos>'
FROM (
    SELECT ano_offset,
        max(cantidad) FILTER(WHERE mes=1) AS c01,
        max(cantidad) FILTER(WHERE mes=2) AS c02,
        max(cantidad) FILTER(WHERE mes=3) AS c03,
        max(cantidad) FILTER(WHERE mes=4) AS c04,
        max(cantidad) FILTER(WHERE mes=5) AS c05,
        max(cantidad) FILTER(WHERE mes=6) AS c06,
        max(cantidad) FILTER(WHERE mes=7) AS c07,
        max(cantidad) FILTER(WHERE mes=8) AS c08,
        max(cantidad) FILTER(WHERE mes=9) AS c09,
        max(cantidad) FILTER(WHERE mes=10) AS c10,
        max(cantidad) FILTER(WHERE mes=11) AS c11,
        max(cantidad) FILTER(WHERE mes=12) AS c12
    FROM cmn.item_periodo
    WHERE item_id=p_item_id
    GROUP BY ano_offset
) periodos;
$$;

CREATE OR REPLACE FUNCTION api.cmn_preparar_sincronizacion_siga(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, cmn, integracion, public
AS $$
DECLARE
    v_id uuid := (p_payload->>'solicitud_id')::uuid;
    a jsonb := COALESCE(p_payload->'actor','{}'::jsonb);
    v_actor text := NULLIF(a->>'usuario','');
    v_rol text := NULLIF(a->>'rol','');
    v_s cmn.solicitud%ROWTYPE;
    v_i cmn.item%ROWTYPE;
    v_request jsonb;
    v_op uuid;
    v_count integer := 0;
BEGIN
    IF v_actor IS NULL OR v_rol IS NULL THEN
        RETURN api.error('ACTOR_REQUERIDO','El backend debe informar actor.usuario y actor.rol.');
    END IF;
    IF v_rol NOT IN ('INTEGRACION_SIGA','ADMIN_SISTEMA') THEN
        RETURN api.error('ROL_NO_AUTORIZADO','Solo el servicio de integración puede preparar el envío a SIGA.');
    END IF;
    SELECT * INTO v_s FROM cmn.solicitud WHERE id=v_id FOR UPDATE;
    IF NOT FOUND THEN RETURN api.error('NO_ENCONTRADO','La solicitud CMN no existe.'); END IF;
    IF v_s.estado_codigo NOT IN ('CMN_A4_FIRMADO','CMN_A4_ENVIADO','CMN_FINALIZADO') THEN
        RETURN api.error('ESTADO_NO_VALIDO','La sincronización requiere el Anexo 4 firmado.');
    END IF;
    IF v_s.tipo_operacion <> 'ALTA_ORDINARIA' THEN
        RETURN api.error('SIGA_SP_NO_HOMOLOGADO',
            'El SP disponible no registra modificaciones del CMN ni SIG_CUADRO_MODIFICADO_CMN.');
    END IF;
    IF EXISTS (SELECT 1 FROM cmn.item WHERE solicitud_id=v_id AND tipo_movimiento='EXCLUSION') THEN
        RETURN api.error('SIGA_SP_NO_HOMOLOGADO','El SP disponible no procesa exclusiones.');
    END IF;

    FOR v_i IN SELECT * FROM cmn.item WHERE solicitud_id=v_id ORDER BY orden
    LOOP
        v_request := jsonb_build_object(
            'procedimiento','dbo.usp_ext_registrar_item_cmn',
            'parametros',jsonb_build_object(
                'AnoEje',v_s.ano_eje,'SecEjec',v_s.sec_ejec,'CentroCosto',v_s.centro_costo,
                'FaseCuadro',v_s.fase_cuadro,'Secuencia',v_s.secuencia_siga,
                'TipoTarea',v_s.tipo_tarea,'NivelTarea',v_s.nivel_tarea,'CodigoTarea',v_s.codigo_tarea,
                'SecFunc',v_s.sec_func,'SecFuncProp',v_s.sec_func_prop,'Origen',v_s.origen,
                'FuenteFinanc',v_s.fuente_financ,'Clasificador',v_s.clasificador,
                'TipoRecurso',v_s.tipo_recurso,'TipoPpto',v_s.tipo_ppto,'TipoUso',v_s.tipo_uso,
                'TipoBien',v_i.tipo_bien,'GrupoBien',v_i.grupo_bien,'ClaseBien',v_i.clase_bien,
                'FamiliaBien',v_i.familia_bien,'ItemBien',v_i.item_bien,
                'UnidadMedida',v_i.unidad_medida,'PrecioUnit',v_i.precio_unitario,
                'DescripcionServicio',v_i.descripcion_servicio,
                'PeriodosXml',integracion.periodos_xml(v_i.id),
                'Usuario',left(v_actor,30),'Equipo','SIGCM_BRIDGE'
            ),
            'contexto',jsonb_build_object('solicitud_id',v_s.id,'item_id',v_i.id,
                                          'codigo_solicitud',v_s.codigo,'version',v_s.version)
        );

        INSERT INTO integracion.siga_operacion
        (idempotencia_key,solicitud_id,item_id,request_json)
        VALUES (format('SIGA-CMN:%s:%s:v%s',v_s.id,v_i.id,v_s.version),v_s.id,v_i.id,v_request)
        ON CONFLICT (idempotencia_key) DO NOTHING
        RETURNING id INTO v_op;
        IF v_op IS NOT NULL THEN v_count := v_count+1; END IF;
        v_op := NULL;
    END LOOP;

    RETURN api.ok(jsonb_build_object('solicitud_id',v_id,'operaciones_encoladas',v_count,
        'procedimiento','dbo.usp_ext_registrar_item_cmn'));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','cmn_preparar_sincronizacion_siga'));
END;
$$;

CREATE OR REPLACE FUNCTION api.integracion_siga_tomar_pendientes(p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, integracion, public
AS $$
DECLARE
    v_limite integer := LEAST(GREATEST(COALESCE((p_payload->>'limite')::integer,10),1),50);
    v_token uuid := gen_random_uuid();
    v_data jsonb;
BEGIN
    WITH elegidos AS (
        SELECT id FROM integracion.siga_operacion
        WHERE estado IN ('PENDIENTE','REINTENTO')
          AND proximo_intento_en <= clock_timestamp()
          AND intentos < max_intentos
        ORDER BY creado_en
        FOR UPDATE SKIP LOCKED
        LIMIT v_limite
    ), actualizados AS (
        UPDATE integracion.siga_operacion o
        SET estado='EN_PROCESO',intentos=intentos+1,bloqueo_token=v_token,
            bloqueado_en=clock_timestamp(),actualizado_en=clock_timestamp()
        FROM elegidos e WHERE o.id=e.id
        RETURNING o.id,o.idempotencia_key,o.procedimiento,o.request_json,o.intentos,o.bloqueo_token
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(actualizados)),'[]'::jsonb) INTO v_data FROM actualizados;
    RETURN api.ok(v_data,jsonb_build_object('bloqueo_token',v_token,'cantidad',jsonb_array_length(v_data)));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','integracion_siga_tomar_pendientes'));
END;
$$;

CREATE OR REPLACE FUNCTION api.integracion_siga_registrar_resultado(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = api, integracion, cmn, public
AS $$
DECLARE
    v_op_id uuid := (p_payload->>'operacion_id')::uuid;
    v_token uuid := (p_payload->>'bloqueo_token')::uuid;
    v_ok boolean := COALESCE((p_payload->>'ok')::boolean,false);
    v_resp jsonb := COALESCE(p_payload->'respuesta','{}'::jsonb);
    v_op integracion.siga_operacion%ROWTYPE;
    v_estado text;
BEGIN
    SELECT * INTO v_op FROM integracion.siga_operacion WHERE id=v_op_id FOR UPDATE;
    IF NOT FOUND THEN RETURN api.error('NO_ENCONTRADO','La operación de integración no existe.'); END IF;
    IF v_op.estado <> 'EN_PROCESO' OR v_op.bloqueo_token IS DISTINCT FROM v_token THEN
        RETURN api.error('BLOQUEO_INVALIDO','La operación no pertenece al lote o ya fue procesada.');
    END IF;

    IF v_ok THEN
        IF NULLIF(v_resp->>'SECUENCIA','') IS NULL OR NULLIF(v_resp->>'ITEM_SEC','') IS NULL THEN
            RETURN api.error('RESPUESTA_SIGA_INVALIDA','SIGA no devolvió SECUENCIA e ITEM_SEC.');
        END IF;
        UPDATE integracion.siga_operacion SET estado='COMPLETADO',response_json=v_resp,
            error_codigo=NULL,error_mensaje=NULL,completado_en=clock_timestamp(),
            actualizado_en=clock_timestamp(),bloqueo_token=NULL
        WHERE id=v_op_id;

        INSERT INTO integracion.siga_item_mapeo
        (item_id,solicitud_id,ano_eje,sec_ejec,centro_costo,secuencia_siga,
         fase_cuadro,item_sec_siga,estado_siga,payload_respuesta)
        VALUES (v_op.item_id,v_op.solicitud_id,(v_resp->>'ANO_EJE')::smallint,
                (v_resp->>'SEC_EJEC')::integer,v_resp->>'CENTRO_COSTO',
                (v_resp->>'SECUENCIA')::bigint,(v_resp->>'FASE_CUADRO')::smallint,
                (v_resp->>'ITEM_SEC')::integer,COALESCE(v_resp->>'ESTADO','5'),v_resp)
        ON CONFLICT (item_id) DO UPDATE
        SET secuencia_siga=EXCLUDED.secuencia_siga,item_sec_siga=EXCLUDED.item_sec_siga,
            estado_siga=EXCLUDED.estado_siga,payload_respuesta=EXCLUDED.payload_respuesta,
            registrado_en_siga=clock_timestamp();

        UPDATE cmn.item SET item_sec_siga=(v_resp->>'ITEM_SEC')::integer,
            estado_siga=COALESCE(v_resp->>'ESTADO','5'),actualizado_en=clock_timestamp()
        WHERE id=v_op.item_id;
        UPDATE cmn.solicitud SET secuencia_siga=(v_resp->>'SECUENCIA')::bigint,
            actualizado_en=clock_timestamp() WHERE id=v_op.solicitud_id;
        v_estado := 'COMPLETADO';
    ELSE
        v_estado := CASE WHEN v_op.intentos < v_op.max_intentos THEN 'REINTENTO' ELSE 'ERROR' END;
        UPDATE integracion.siga_operacion SET estado=v_estado,response_json=v_resp,
            error_codigo=COALESCE(p_payload->>'error_codigo','SIGA_ERROR'),
            error_mensaje=COALESCE(p_payload->>'error_mensaje','Error reportado por SIGA'),
            proximo_intento_en=clock_timestamp()+make_interval(secs=>LEAST(3600,30*power(2,intentos)::integer)),
            actualizado_en=clock_timestamp(),bloqueo_token=NULL
        WHERE id=v_op_id;
    END IF;
    RETURN api.ok(jsonb_build_object('operacion_id',v_op_id,'estado',v_estado,'intentos',v_op.intentos));
EXCEPTION WHEN OTHERS THEN
    RETURN api.error(SQLSTATE,SQLERRM,jsonb_build_object('operacion','integracion_siga_registrar_resultado'));
END;
$$;

/* -------------------------------------------------------------------------- */
/* 12. Contratos JSON de ejemplo                                               */
/* -------------------------------------------------------------------------- */

/*
-- 1) Antes del registro se sincronizan los maestros consultados desde SIGA.
SELECT api.siga_sincronizar_maestros($json$
{
  "centros_costo":[{"ano_eje":2026,"sec_ejec":1750,"centro_costo":"010101","descripcion":"Unidad de Sistemas","estado":"A"}],
  "metas":[{"ano_eje":2026,"sec_ejec":1750,"sec_func":86,"sec_func_prop":86,"descripcion":"Meta 0086","estado":"A"}],
  "fuentes":[{"ano_eje":2026,"sec_ejec":1750,"origen":"1","fuente_financ":"00","descripcion":"Recursos ordinarios","estado":"A"}],
  "actividades":[{"ano_eje":2026,"sec_ejec":1750,"tipo_tarea":"1","nivel_tarea":"C","codigo_tarea":999,"descripcion":"Actividad operativa","estado":"A"}],
  "catalogo":[{"sec_ejec":1750,"tipo_bien":"S","grupo_bien":"09","clase_bien":"11","familia_bien":"0007","item_bien":"0041","descripcion":"Servicio especializado","unidad_medida":36,"estado":"A"}],
  "techos":[{"ano_eje":2026,"sec_ejec":1750,"centro_costo":"010101","fase_cuadro":5,"origen":"1","fuente_financ":"00","sec_func":86,"clasificador":"2.3.2.7.11.99","monto_techo_0":50000,"monto_techo_1":50000,"monto_techo_2":50000,"monto_techo_3":50000}]
}
$json$::jsonb);

-- 2) Registro local. Los periodos no enviados se materializan con cantidad 0.
SELECT api.cmn_registrar($json$
{
  "actor":{"usuario":"cmendoza","rol":"AREA_ESPECIALISTA","metadata":{"ip":"10.0.0.10"}},
  "solicitud":{
    "idempotencia_key":"WEB-CMN-2026-000001",
    "tipo_operacion":"ALTA_ORDINARIA",
    "tipo_inclusion":"ORDINARIA",
    "ano_eje":2026,"sec_ejec":1750,"centro_costo":"010101","fase_cuadro":5,
    "tipo_tarea":"1","nivel_tarea":"C","codigo_tarea":999,
    "sec_func":86,"sec_func_prop":86,"origen":"1","fuente_financ":"00",
    "clasificador":"2.3.2.7.11.99","tipo_recurso":"1","tipo_ppto":1,"tipo_uso":"C","tipo_bien":"S",
    "sustento":"Necesidad multianual del área usuaria.",
    "responsable_area":"Carlos Mendoza","cargo_responsable":"Especialista"
  },
  "items":[{
    "orden":1,"tipo_movimiento":"INCLUSION","tipo_bien":"S",
    "grupo_bien":"09","clase_bien":"11","familia_bien":"0007","item_bien":"0041",
    "descripcion_servicio":"Servicio especializado","precio_unitario":1000,
    "periodos":[
      {"ano_offset":0,"mes":1,"cantidad":1},
      {"ano_offset":1,"mes":1,"cantidad":1},
      {"ano_offset":2,"mes":1,"cantidad":1},
      {"ano_offset":3,"mes":1,"cantidad":1}
    ]
  }]
}
$json$::jsonb);

-- 3) Generación del Anexo 3.
SELECT api.cmn_generar_anexo3(jsonb_build_object(
  'solicitud_id','REEMPLAZAR_UUID','actor',jsonb_build_object('usuario','cmendoza','rol','AREA_ESPECIALISTA')));

-- 4) El Jefe firma el Anexo 3; luego el flujo continúa mediante api.cmn_cambiar_estado.
SELECT api.cmn_firmar_documento($json$
{"documento_id":"REEMPLAZAR_UUID","actor":{"usuario":"mtorres","rol":"AREA_JEFE"},
 "firmante":"María Torres","cargo":"Jefe del Área usuaria","firma_hash":"SHA256..."}
$json$::jsonb);

-- 5) Generación de Anexo 4 individual o consolidado.
SELECT api.cmn_generar_anexo4($json$
{"solicitud_ids":["REEMPLAZAR_UUID_1","REEMPLAZAR_UUID_2"],
 "actor":{"usuario":"lparedes","rol":"ABAST_COORDINADOR"}}
$json$::jsonb);

-- 6) Tras completar las firmas del Anexo 4, se prepara el outbox SIGA.
SELECT api.cmn_preparar_sincronizacion_siga($json$
{"solicitud_id":"REEMPLAZAR_UUID","actor":{"usuario":"svc_sigcm","rol":"INTEGRACION_SIGA"}}
$json$::jsonb);

-- 7) Worker: toma operaciones, ejecuta SQL Server y registra cada resultado.
SELECT api.integracion_siga_tomar_pendientes('{"limite":10}'::jsonb);
SELECT api.integracion_siga_registrar_resultado($json$
{"operacion_id":"REEMPLAZAR_UUID","bloqueo_token":"REEMPLAZAR_TOKEN","ok":true,
 "respuesta":{"ANO_EJE":2026,"SEC_EJEC":1750,"CENTRO_COSTO":"010101",
 "SECUENCIA":123,"FASE_CUADRO":5,"ITEM_SEC":1,"ESTADO":"5","REGISTRADO":"CABECERA_E_ITEM"}}
$json$::jsonb);
*/

COMMIT;

/*
 Despliegue recomendado
 ----------------------
 1. Ejecutar en una base PostgreSQL vacía de desarrollo.
 2. Crear roles físicos de base separados para API, worker y migraciones.
 3. Revocar acceso directo a tablas a la cuenta API y otorgar solo EXECUTE
    sobre funciones api.* necesarias.
 4. Homologar la carga de maestros contra SIGA_1750.
 5. Ejecutar pruebas de duplicidad, edición concurrente, techo insuficiente,
    firmas incompletas, reintentos y conciliación pantalla/base.
 6. No habilitar MODIFICACION/EXCLUSION hacia SIGA hasta contar con un SP
    específico validado por el DBA y el responsable funcional SIGA.
*/
