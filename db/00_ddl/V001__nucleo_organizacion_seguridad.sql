/*
===============================================================================
  SIGCM - Migracion V001 : Organizacion, seguridad y catalogos base
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Autoridad : SIGCM (dato propio, no replicado de SIGA)

  Port de SIGCM/db/00_ddl/V001__nucleo_seguridad_org.sql (PostgreSQL 14).

  ESQUEMAS
  --------
  La version PostgreSQL usaba trece esquemas de tres letras (org, seg, cat, exp,
  wf, doc, obs, plz, aud, mst, itg, api) con una o dos tablas cada uno. Eso no
  organiza: fragmenta, y obliga a un diccionario para leer el modelo. Aqui se
  consolidan segun la unica division que si es real, la de AUTORIDAD SOBRE EL
  DATO, mas un esquema por modulo del sistema:

    sigcm         Nucleo transversal, propiedad del SIGCM: organizacion,
                  seguridad, catalogos, expediente, maquina de estados,
                  documentos, firmas, observaciones, plazos y auditoria.
    integracion   La cola hacia SIGA: outbox, mapeo de identificadores y
                  conciliacion. Autoridad compartida.
    siga          Frontera de lectura: sinonimos (C003) y vistas (V004) sobre la
                  base SIGA. Autoridad de SIGA; aqui no se escribe nunca.

    cmn           Gestion CMN                    <- unico con objetos en la v1
    requerimiento Requerimiento a Notificacion
    ejecucion     Ejecucion
    pago          Pago
    ampliacion    Modificacion-Ampliacion
    resolucion    Resolucion

  Diferencia con la version PostgreSQL: alli los maestros eran ocho tablas espejo
  con su proceso de sincronizacion. Aqui son vistas dentro de [siga], porque
  ambas bases comparten instancia. Ver V004.

  CONVENCIONES DE LA ANIN
  -----------------------
  Esquemas en minuscula; tablas y columnas en PascalCase; clave primaria
  Id<Entidad>. Rutinas esquema.paVerboEntidad y vistas esquema.vwEntidad.

  Toda tabla transaccional lleva Activo bit para el borrado logico y el cuarteto
  de auditoria por operacion: Usuario / Fecha / Equipo / Programa, con sufijo
  CreacionAuditoria, ModificacionAuditoria y EliminacionAuditoria.

  El usuario de auditoria se guarda como texto (la cuenta), no como clave foranea
  a sigcm.Usuario: la auditoria debe sobrevivir a la baja de una persona.

  Los catalogos puros (Modulo, TipoContratacion, Rol, Estado) no llevan el
  cuarteto: son configuracion que se despliega con la semilla, no dato capturado
  por un usuario. Si llevan Activo.

  Sobre los comentarios
  ---------------------
  La version PostgreSQL guardaba la justificacion de disenio en COMMENT ON. Aqui
  se conservan como comentarios del script: el equivalente exacto exigiria unas
  doscientas lineas de sp_addextendedproperty. El texto es el mismo.

  Linea base: SQL Server 2022. Unica construccion prohibida, el tipo json nativo
  (es de 2025 y produccion no lo tiene). Ver docs/entornos.md.

  Idempotente.
===============================================================================
*/

/* QUOTED_IDENTIFIER y ANSI_NULLS deben ir en ON y se fijan aqui en vez de
   confiar en el cliente: los indices filtrados los exigen tanto para crearse
   como para cualquier DML posterior sobre la tabla, y sqlcmd los deja en OFF
   salvo que se invoque con -I. SqlClient ya los manda en ON. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 0. Esquemas                                                                */
/* -------------------------------------------------------------------------- */

/* Nucleo transversal y frontera con SIGA */
IF SCHEMA_ID(N'sigcm')       IS NULL EXEC(N'CREATE SCHEMA sigcm       AUTHORIZATION dbo;');
IF SCHEMA_ID(N'integracion') IS NULL EXEC(N'CREATE SCHEMA integracion AUTHORIZATION dbo;');
IF SCHEMA_ID(N'siga')        IS NULL EXEC(N'CREATE SCHEMA siga        AUTHORIZATION dbo;');

/* Un esquema por modulo del sistema. Solo cmn tiene objetos en la v1; los otros
   cinco se crean vacios a proposito, para que la estructura del sistema este
   declarada desde el principio y cada modulo aterrice en su sitio sin discusion.
   Corresponden uno a uno con las filas de sigcm.Modulo que siembra S001. */
IF SCHEMA_ID(N'cmn')           IS NULL EXEC(N'CREATE SCHEMA cmn           AUTHORIZATION dbo;');
IF SCHEMA_ID(N'requerimiento') IS NULL EXEC(N'CREATE SCHEMA requerimiento AUTHORIZATION dbo;');
IF SCHEMA_ID(N'ejecucion')     IS NULL EXEC(N'CREATE SCHEMA ejecucion     AUTHORIZATION dbo;');
IF SCHEMA_ID(N'pago')          IS NULL EXEC(N'CREATE SCHEMA pago          AUTHORIZATION dbo;');
IF SCHEMA_ID(N'ampliacion')    IS NULL EXEC(N'CREATE SCHEMA ampliacion    AUTHORIZATION dbo;');
IF SCHEMA_ID(N'resolucion')    IS NULL EXEC(N'CREATE SCHEMA resolucion    AUTHORIZATION dbo;');
GO

/* -------------------------------------------------------------------------- */
/* 1. Catalogos base                                                          */
/* -------------------------------------------------------------------------- */

/* Modulos de proceso del SIGCM. La v1 implementa CMN; el resto queda declarado
   para que la matriz de acceso y la maquina de estados no cambien de forma al
   incorporarlos. */
IF OBJECT_ID(N'sigcm.Modulo', N'U') IS NULL
CREATE TABLE sigcm.Modulo (
    CodigoModulo varchar(30)  NOT NULL CONSTRAINT PK_sigcm_Modulo PRIMARY KEY,
    Nombre       varchar(150) NOT NULL,
    Orden        int          NOT NULL,
    Activo       bit          NOT NULL CONSTRAINT DF_sigcm_Modulo_Activo DEFAULT (1)
);
GO

/* TipoBienSiga es la correspondencia con TIPO_BIEN de SIGA. Locacion y
   Consultoria son servicios para SIGA (S) pero rutas documentales distintas para
   la ANIN: por eso el tipo de contratacion es catalogo propio y no se deriva de
   TIPO_BIEN. */
IF OBJECT_ID(N'sigcm.TipoContratacion', N'U') IS NULL
CREATE TABLE sigcm.TipoContratacion (
    CodigoTipoContratacion varchar(20)  NOT NULL CONSTRAINT PK_sigcm_TipoContratacion PRIMARY KEY,
    Nombre                 varchar(120) NOT NULL,
    TipoBienSiga           char(1)      NOT NULL,
    RutaEntregables        bit          NOT NULL CONSTRAINT DF_sigcm_TipoCon_Entregables DEFAULT (0),
    RutaRecepcionFisica    bit          NOT NULL CONSTRAINT DF_sigcm_TipoCon_Fisica      DEFAULT (0),
    Activo                 bit          NOT NULL CONSTRAINT DF_sigcm_TipoCon_Activo      DEFAULT (1),
    CONSTRAINT CK_sigcm_TipoCon_Bien CHECK (TipoBienSiga IN ('B','S','O'))
);
GO

/* -------------------------------------------------------------------------- */
/* 2. Organizacion                                                            */
/* -------------------------------------------------------------------------- */

/* CentroCostoSiga guarda el CENTRO_COSTO de SIG_CENTRO_COSTO. Deliberadamente
   sin clave foranea contra mst: en PostgreSQL era porque el espejo se recargaba;
   aqui porque mst son vistas y SQL Server no admite claves foraneas contra
   vistas ni contra otra base. La validacion la hace la rutina de negocio contra
   siga.vwCentroCosto, y de nuevo SIGA al escribir. */
IF OBJECT_ID(N'sigcm.Unidad', N'U') IS NULL
CREATE TABLE sigcm.Unidad (
    IdUnidad        uniqueidentifier NOT NULL
                    CONSTRAINT DF_sigcm_Unidad_Id DEFAULT (NEWSEQUENTIALID())
                    CONSTRAINT PK_sigcm_Unidad PRIMARY KEY,
    Codigo          varchar(30)  NOT NULL CONSTRAINT UQ_sigcm_Unidad_Codigo UNIQUE,
    Nombre          varchar(200) NOT NULL,
    Sigla           varchar(30)      NULL,
    IdUnidadPadre   uniqueidentifier NULL
                    CONSTRAINT FK_sigcm_Unidad_Padre REFERENCES sigcm.Unidad(IdUnidad),
    CentroCostoSiga varchar(15)      NULL,
    EsAreaUsuaria   bit NOT NULL CONSTRAINT DF_sigcm_Unidad_Area   DEFAULT (0),
    Activo          bit NOT NULL CONSTRAINT DF_sigcm_Unidad_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_sigcm_Unidad_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,
    UsuarioEliminacionAuditoria   varchar(30)  NULL,
    FechaEliminacionAuditoria     datetime     NULL,
    EquipoEliminacionAuditoria    varchar(50)  NULL,
    ProgramaEliminacionAuditoria  varchar(50)  NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Unidad_CentroCosto' AND object_id = OBJECT_ID(N'sigcm.Unidad'))
CREATE NONCLUSTERED INDEX IX_sigcm_Unidad_CentroCosto
    ON sigcm.Unidad(CentroCostoSiga)
    WHERE CentroCostoSiga IS NOT NULL;
GO

/* -------------------------------------------------------------------------- */
/* 3. Seguridad                                                               */
/* -------------------------------------------------------------------------- */

/* Identidad institucional. La autenticacion la resuelve el SSO; esta tabla
   guarda el perfil autorizado y es la referencia de los actores del flujo.
   Nunca almacena contrasenias. */
IF OBJECT_ID(N'sigcm.Usuario', N'U') IS NULL
CREATE TABLE sigcm.Usuario (
    IdUsuario          uniqueidentifier NOT NULL
                       CONSTRAINT DF_sigcm_Usuario_Id DEFAULT (NEWSEQUENTIALID())
                       CONSTRAINT PK_sigcm_Usuario PRIMARY KEY,
    Cuenta             varchar(120) NOT NULL CONSTRAINT UQ_sigcm_Usuario_Cuenta UNIQUE,
    DocumentoIdentidad varchar(20)      NULL,
    Nombres            varchar(120) NOT NULL,
    Apellidos          varchar(120) NOT NULL,
    Correo             varchar(200)     NULL,
    Cargo              varchar(180)     NULL,
    Activo             bit NOT NULL CONSTRAINT DF_sigcm_Usuario_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_sigcm_Usuario_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,
    UsuarioEliminacionAuditoria   varchar(30)  NULL,
    FechaEliminacionAuditoria     datetime     NULL,
    EquipoEliminacionAuditoria    varchar(50)  NULL,
    ProgramaEliminacionAuditoria  varchar(50)  NULL
);
GO

/* EsTecnico = 1 para cuentas de servicio (integracion, conciliacion). Nunca se
   asignan a personas ni pueden ejecutar transiciones del flujo institucional. */
IF OBJECT_ID(N'sigcm.Rol', N'U') IS NULL
CREATE TABLE sigcm.Rol (
    CodigoRol   varchar(40)  NOT NULL CONSTRAINT PK_sigcm_Rol PRIMARY KEY,
    Nombre      varchar(150) NOT NULL,
    Descripcion nvarchar(max)    NULL,
    EsTecnico   bit NOT NULL CONSTRAINT DF_sigcm_Rol_Tecnico DEFAULT (0),
    Activo      bit NOT NULL CONSTRAINT DF_sigcm_Rol_Activo  DEFAULT (1)
);
GO

/* Un usuario ejerce un rol dentro de una unidad concreta. La unidad es parte de
   la clave: el mismo especialista puede atender dos areas usuarias.
   EsTitular marca al firmante autorizado de la unidad; el control de firma se
   apoya en este campo, no en el nombre del cargo. */
IF OBJECT_ID(N'sigcm.UsuarioRol', N'U') IS NULL
CREATE TABLE sigcm.UsuarioRol (
    IdUsuarioRol  uniqueidentifier NOT NULL
                  CONSTRAINT DF_sigcm_UsuarioRol_Id DEFAULT (NEWSEQUENTIALID())
                  CONSTRAINT PK_sigcm_UsuarioRol PRIMARY KEY,
    IdUsuario     uniqueidentifier NOT NULL
                  CONSTRAINT FK_sigcm_UsuarioRol_Usuario REFERENCES sigcm.Usuario(IdUsuario) ON DELETE CASCADE,
    CodigoRol     varchar(40) NOT NULL
                  CONSTRAINT FK_sigcm_UsuarioRol_Rol REFERENCES sigcm.Rol(CodigoRol),
    IdUnidad      uniqueidentifier NOT NULL
                  CONSTRAINT FK_sigcm_UsuarioRol_Unidad REFERENCES sigcm.Unidad(IdUnidad),
    EsTitular     bit  NOT NULL CONSTRAINT DF_sigcm_UsuarioRol_Titular DEFAULT (0),
    VigenteDesde  date NOT NULL CONSTRAINT DF_sigcm_UsuarioRol_Desde   DEFAULT (CONVERT(date, GETDATE())),
    VigenteHasta  date     NULL,
    Activo        bit  NOT NULL CONSTRAINT DF_sigcm_UsuarioRol_Activo  DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_sigcm_UsuarioRol_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,
    UsuarioEliminacionAuditoria   varchar(30) NULL,
    FechaEliminacionAuditoria     datetime    NULL,
    EquipoEliminacionAuditoria    varchar(50) NULL,
    ProgramaEliminacionAuditoria  varchar(50) NULL,

    CONSTRAINT CK_sigcm_UsuarioRol_Vigencia
        CHECK (VigenteHasta IS NULL OR VigenteHasta >= VigenteDesde)
);
GO

/* Una asignacion vigente no puede duplicarse; las historicas si conviven. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_sigcm_UsuarioRol_Vigente' AND object_id = OBJECT_ID(N'sigcm.UsuarioRol'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_sigcm_UsuarioRol_Vigente
    ON sigcm.UsuarioRol(IdUsuario, CodigoRol, IdUnidad)
    WHERE VigenteHasta IS NULL AND Activo = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_UsuarioRol_Unidad' AND object_id = OBJECT_ID(N'sigcm.UsuarioRol'))
CREATE NONCLUSTERED INDEX IX_sigcm_UsuarioRol_Unidad
    ON sigcm.UsuarioRol(IdUnidad, CodigoRol);
GO

/* Matriz de acceso modulo <-> rol, tal como la define el mockup. Es dato
   configurable, no codigo. */
IF OBJECT_ID(N'sigcm.RolModulo', N'U') IS NULL
CREATE TABLE sigcm.RolModulo (
    CodigoRol    varchar(40) NOT NULL
                 CONSTRAINT FK_sigcm_RolModulo_Rol REFERENCES sigcm.Rol(CodigoRol) ON DELETE CASCADE,
    CodigoModulo varchar(30) NOT NULL
                 CONSTRAINT FK_sigcm_RolModulo_Modulo REFERENCES sigcm.Modulo(CodigoModulo) ON DELETE CASCADE,
    Activo       bit NOT NULL CONSTRAINT DF_sigcm_RolModulo_Activo DEFAULT (1),
    CONSTRAINT PK_sigcm_RolModulo PRIMARY KEY (CodigoRol, CodigoModulo)
);
GO

PRINT 'V001 aplicada.';
GO
