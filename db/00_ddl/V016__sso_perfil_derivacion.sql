/*
===============================================================================
  SIGCM - Migracion V016 : Padron del SSO y arbol de derivacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  QUE RESUELVE
  ------------
  La identidad la certifica el SSO institucional (base PostgreSQL saa_, esquema
  login). De ahi sale, por la funcion
  login.fn_listar_login_usuario_perfil_sistema_sgcm, el padron de quienes tienen
  acceso al SGCM: persona, cod_perfil y centro_costo.

  Faltan dos cosas que el SSO no puede darnos y que son configuracion nuestra:

    1. LA TRADUCCION cod_perfil -> CodigoRol.  El SSO nombra los perfiles como
       PE082 / JEFE UA; el flujo del SIGCM razona con ABAST_JEFE. Sin esta tabla
       el padron no se puede aterrizar en sigcm.UsuarioRol.

    2. EL ARBOL DE DERIVACION jefe -> coordinador -> especialista.  En el SSO NO
       EXISTE: login.tm_login_usuario.id_padre esta en NULL en las 1748 filas.
       Verificado el 2026-08-27.

  QUE ES EL CENTRO DE COSTO
  -------------------------
  No identifica a una persona: identifica al AREA. Es el codigo presupuestal con
  el que SIGA nombra a la unidad organica (01.07.03.01 = Unidad de
  Abastecimiento), y en el SSO vive en login.tm_login_dependencia.centro_costo.
  El jefe, el coordinador y el especialista de Abastecimiento COMPARTEN el mismo.

  De ahi la unidad de razonamiento del arbol:

      PUESTO = (cod_perfil, centro_costo)

  Un puesto puede estar ocupado por varias personas -hoy ESPECIALISTA UA en
  01.07.03.01 son dos-. Por eso la derivacion se CONFIGURA por perfil y se
  RESUELVE a persona en el momento de derivar, consultando quien ocupa el puesto
  destino. Nunca se guarda un nombre en la configuracion: la rotacion de personal
  la absorbe el padron, no el arbol.

  POR QUE NO UN ARBOL PERSONA -> PERSONA
  --------------------------------------
  Porque habria que mantenerlo a mano en cada rotacion y el SSO no puede
  alimentarlo. Con el arbol por perfil, cambiar de especialista es dar de baja
  uno y de alta otro en el SSO: la siguiente sincronizacion lo refleja y la
  pantalla de derivacion deja de ofrecer al que se fue. Ver F008.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Anclaje del padron: los identificadores del SSO                         */
/* -------------------------------------------------------------------------- */

/*
  La identidad se ancla en login.tm_login_usuario.id_usuario, no en el DNI ni en
  el nombre. Es el entero estable del SSO: si a alguien le corrigen el documento
  o el apellido, sigue siendo la misma persona y su historial no se parte.

  Nulo para las cuentas que no vienen del SSO: los usuarios ficticios de S900 y
  las cuentas tecnicas de integracion. Ese nulo es el que protege a esas cuentas
  de la reconciliacion (F008): lo que el SSO no gobierna, el SSO no da de baja.
*/
IF COL_LENGTH(N'sigcm.Usuario', N'IdUsuarioSso') IS NULL
    ALTER TABLE sigcm.Usuario ADD IdUsuarioSso int NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_sigcm_Usuario_IdSso' AND object_id = OBJECT_ID(N'sigcm.Usuario'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_sigcm_Usuario_IdSso
    ON sigcm.Usuario(IdUsuarioSso)
    WHERE IdUsuarioSso IS NOT NULL;
GO

/* El id de dependencia del SSO cumple el mismo papel para la unidad organica, y
   ademas permite reconstruir el arbol de areas: login.tm_login_dependencia trae
   id_padre poblado en 52 de sus 70 filas. */
IF COL_LENGTH(N'sigcm.Unidad', N'IdDependenciaSso') IS NULL
    ALTER TABLE sigcm.Unidad ADD IdDependenciaSso int NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_sigcm_Unidad_IdSso' AND object_id = OBJECT_ID(N'sigcm.Unidad'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_sigcm_Unidad_IdSso
    ON sigcm.Unidad(IdDependenciaSso)
    WHERE IdDependenciaSso IS NOT NULL;
GO

/* -------------------------------------------------------------------------- */
/* 2. sigcm.PerfilSso : la traduccion cod_perfil -> CodigoRol                  */
/* -------------------------------------------------------------------------- */

/*
  Tabla de MANTENIMIENTO. Se siembra en S005 con la equivalencia vigente y se
  edita cuando el SSO agrega un perfil.

  Un cod_perfil sin fila aqui NO ENTRA al sistema: es lo correcto. Darle un rol
  del flujo por descarte seria inventarle una autorizacion a alguien. Hoy el
  unico en esa situacion es PE019 EXTERNO, a proposito.

  Varios cod_perfil pueden apuntar al mismo CodigoRol -PE091 JEFE DE UNIDAD y
  PE079 JEFE OFICINA son los dos AREA_JEFE-, y por eso la clave primaria es el
  codigo del SSO y no el rol.
*/
IF OBJECT_ID(N'sigcm.PerfilSso', N'U') IS NULL
CREATE TABLE sigcm.PerfilSso (
    CodigoPerfilSso varchar(20)  NOT NULL CONSTRAINT PK_sigcm_PerfilSso PRIMARY KEY,
    NombreSso       varchar(150) NOT NULL,
    CodigoRol       varchar(40)  NOT NULL
                    CONSTRAINT FK_sigcm_PerfilSso_Rol REFERENCES sigcm.Rol(CodigoRol),
    /* Comentario de mantenimiento: por que este perfil se mapea asi. */
    Observacion     nvarchar(400) NULL,
    Activo          bit NOT NULL CONSTRAINT DF_sigcm_PerfilSso_Activo DEFAULT (1)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_PerfilSso_Rol' AND object_id = OBJECT_ID(N'sigcm.PerfilSso'))
CREATE NONCLUSTERED INDEX IX_sigcm_PerfilSso_Rol ON sigcm.PerfilSso(CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 3. sigcm.RolDerivacion : el arbol de perfiles                               */
/* -------------------------------------------------------------------------- */

/*
  Una fila por ARISTA del arbol: un CodigoRolOrigen puede derivar a un
  CodigoRolDestino, en este modulo.

  EL MODULO ES COLUMNA, y eso resuelve por dato la regla que pidio el negocio:

    CMN            el area usuaria NO pasa por el coordinador. Simplemente no
                   existe la fila AREA_JEFE -> AREA_COORDINADOR.
    REQUERIMIENTO  si pasa por los tres, y esa fila si existe.

  Agregar o quitar un escalon de un flujo vuelve a ser agregar o quitar filas, no
  desplegar codigo, que es el corolario de CONTEXTO.md seccion 3.

  EL SALTO DIRECTO ES OTRA ARISTA, no una excepcion: el jefe puede derivar al
  coordinador (Orden 1) o directamente al especialista (Orden 2). Las dos son
  destinos validos y Orden solo gobierna como se presentan.

  ALCANCE : donde se busca a quien ocupa el puesto destino.
    MISMA_UNIDAD  en la unidad del actor. Es el caso de todo el arbol interno de
                  un area: el jefe de UA deriva a SU coordinador, no al de otra.
    UNIDAD_PADRE  en la unidad padre segun sigcm.Unidad.IdUnidadPadre, que se
                  sincroniza del arbol de dependencias del SSO.
    ENTIDAD       en cualquier unidad. Para roles unicos en la entidad -OA,
                  Abastecimiento- donde no hay ambiguedad que resolver.

  ESTA TABLA NO SUSTITUYE A LA MAQUINA DE ESTADOS. sigcm.Transicion sigue
  decidiendo QUE puede hacerse y a que estado va el expediente; esto decide, una
  vez que la transicion es una derivacion, A QUIEN se le puede pasar dentro del
  rol que el estado destino ya declaro. Son preguntas distintas y por eso son
  tablas distintas.
*/
IF OBJECT_ID(N'sigcm.RolDerivacion', N'U') IS NULL
CREATE TABLE sigcm.RolDerivacion (
    IdRolDerivacion   int IDENTITY(1,1) NOT NULL
                      CONSTRAINT PK_sigcm_RolDerivacion PRIMARY KEY,
    CodigoModulo      varchar(30) NOT NULL
                      CONSTRAINT FK_sigcm_RolDeriv_Modulo REFERENCES sigcm.Modulo(CodigoModulo),
    CodigoRolOrigen   varchar(40) NOT NULL
                      CONSTRAINT FK_sigcm_RolDeriv_Origen REFERENCES sigcm.Rol(CodigoRol),
    CodigoRolDestino  varchar(40) NOT NULL
                      CONSTRAINT FK_sigcm_RolDeriv_Destino REFERENCES sigcm.Rol(CodigoRol),
    Alcance           varchar(20) NOT NULL
                      CONSTRAINT DF_sigcm_RolDeriv_Alcance DEFAULT ('MISMA_UNIDAD'),
    Orden             int NOT NULL CONSTRAINT DF_sigcm_RolDeriv_Orden DEFAULT (1),
    Descripcion       nvarchar(400) NULL,
    Activo            bit NOT NULL CONSTRAINT DF_sigcm_RolDeriv_Activo DEFAULT (1),

    CONSTRAINT CK_sigcm_RolDeriv_Alcance
        CHECK (Alcance IN ('MISMA_UNIDAD','UNIDAD_PADRE','ENTIDAD')),
    /* Un rol que se deriva a si mismo es un ciclo de un paso: no hay escalon. */
    CONSTRAINT CK_sigcm_RolDeriv_NoReflexiva
        CHECK (CodigoRolOrigen <> CodigoRolDestino)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_sigcm_RolDerivacion_Arista' AND object_id = OBJECT_ID(N'sigcm.RolDerivacion'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_sigcm_RolDerivacion_Arista
    ON sigcm.RolDerivacion(CodigoModulo, CodigoRolOrigen, CodigoRolDestino);
GO

/* -------------------------------------------------------------------------- */
/* 3b. sigcm.UnidadTramitadora : las areas que tramitan y no originan          */
/* -------------------------------------------------------------------------- */

/*
  sigcm.Unidad.EsAreaUsuaria distingue a quien ORIGINA un CMN de quien lo
  TRAMITA. El SSO no conoce esa distincion -para el, Abastecimiento es una
  dependencia como cualquier otra-, asi que es configuracion nuestra.

  POR QUE ES UNA TABLA Y NO UN UPDATE EN LA SEMILLA
  Porque las unidades no existen cuando la semilla corre: las crea la primera
  sincronizacion con el SSO, que ocurre despues. Un UPDATE en S005 no encuentra
  nada que corregir y deja a Abastecimiento marcado como area usuaria hasta que
  alguien lo note. Siendo tabla, F008 la consulta cada vez que da de alta una
  unidad y la regla se aplica sola, venga la unidad de donde venga y en el orden
  que sea.

  Se indexa por CENTRO DE COSTO y no por nombre: el nombre de una oficina cambia
  con cada reorganizacion y el codigo presupuestal no.
*/
IF OBJECT_ID(N'sigcm.UnidadTramitadora', N'U') IS NULL
CREATE TABLE sigcm.UnidadTramitadora (
    CentroCosto varchar(15)   NOT NULL CONSTRAINT PK_sigcm_UnidadTramitadora PRIMARY KEY,
    Motivo      nvarchar(300)     NULL,
    Activo      bit NOT NULL CONSTRAINT DF_sigcm_UnidadTram_Activo DEFAULT (1)
);
GO

/* -------------------------------------------------------------------------- */
/* 4. sigcm.SincronizacionSso : bitacora de cada reconciliacion               */
/* -------------------------------------------------------------------------- */

/*
  Una fila por corrida de F008. No es adorno: la sincronizacion DA DE BAJA
  asignaciones por diferencia de conjuntos, y una baja que nadie puede explicar
  es peor que no tener la funcionalidad.

  Si manana alguien pregunta por que el especialista Fulano dejo de ver su
  bandeja, la respuesta esta aqui con fecha, cantidades y el detalle de lo que
  cambio.
*/
IF OBJECT_ID(N'sigcm.SincronizacionSso', N'U') IS NULL
CREATE TABLE sigcm.SincronizacionSso (
    IdSincronizacion  bigint IDENTITY(1,1) NOT NULL
                      CONSTRAINT PK_sigcm_SincronizacionSso PRIMARY KEY,
    Fecha             datetime     NOT NULL CONSTRAINT DF_sigcm_SincSso_Fecha DEFAULT (GETDATE()),
    Disparador        varchar(30)  NOT NULL,   /* INGRESO | MANTENIMIENTO */
    CuentaDisparo     varchar(120)     NULL,
    PadronRecibido    int          NOT NULL CONSTRAINT DF_sigcm_SincSso_Recibido DEFAULT (0),
    UnidadesAlta      int          NOT NULL CONSTRAINT DF_sigcm_SincSso_UniAlta  DEFAULT (0),
    UsuariosAlta      int          NOT NULL CONSTRAINT DF_sigcm_SincSso_UsuAlta  DEFAULT (0),
    AsignacionesAlta  int          NOT NULL CONSTRAINT DF_sigcm_SincSso_AsigAlta DEFAULT (0),
    AsignacionesBaja  int          NOT NULL CONSTRAINT DF_sigcm_SincSso_AsigBaja DEFAULT (0),
    /* Perfiles y centros de costo que llegaron y no se pudieron aterrizar. */
    Descartes         nvarchar(max)    NULL,
    Detalle           nvarchar(max)    NULL,

    CONSTRAINT CK_sigcm_SincSso_Descartes CHECK (Descartes IS NULL OR ISJSON(Descartes) = 1),
    CONSTRAINT CK_sigcm_SincSso_Detalle   CHECK (Detalle   IS NULL OR ISJSON(Detalle)   = 1)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_SincSso_Fecha' AND object_id = OBJECT_ID(N'sigcm.SincronizacionSso'))
CREATE NONCLUSTERED INDEX IX_sigcm_SincSso_Fecha ON sigcm.SincronizacionSso(Fecha DESC);
GO

PRINT 'V016 aplicada: padron del SSO y arbol de derivacion.';
GO
