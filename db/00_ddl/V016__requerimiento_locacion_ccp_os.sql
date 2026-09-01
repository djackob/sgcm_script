/*
===============================================================================
  SIGCM - Migracion V016 : Locacion — filtros de idoneidad, CCP y orden
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Autoridad : SIGCM

  Segunda mitad del flujo de locacion de servicios (contratos menores <= 8 UIT),
  segun la Especificacion de Requisitos Funcionales:

    4. Filtros de idoneidad (RNSSC, REDAM, RPS_TCP, REDJUM, debida diligencia).
       El especialista registra conformidad manual con opcion Si / No.
    5. Certificacion de Credito Presupuestario (CCP) y memorando a UP.
    6. Orden de servicio y datos para notificar al locador y al area usuaria.

  La indagacion competitiva (Anexo 8) no entra: la locacion por invitacion
  directa usa una sola cotizacion (Anexo 6) y la declaracion jurada (Anexo 7).
  Esos tipos de documento se siembran en S004; aqui solo el modelo de datos
  que el circuito posterior a REQ_CONFORME necesita persistir.

  SIGA y SIAF se leen, no se escriben desde estas tablas. El numero de O/S
  y el de la CCP se registran como dato informado por Abastecimiento.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Catalogo de filtros de idoneidad                                        */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'requerimiento.FiltroTipo', N'U') IS NULL
CREATE TABLE requerimiento.FiltroTipo (
    CodigoFiltro varchar(30)  NOT NULL CONSTRAINT PK_req_FiltroTipo PRIMARY KEY,
    Nombre       varchar(200) NOT NULL,
    Orden        smallint     NOT NULL,
    Activo       bit          NOT NULL CONSTRAINT DF_req_FiltroTipo_Activo DEFAULT (1)
);
GO

MERGE requerimiento.FiltroTipo AS d
USING (VALUES
    ('RNSSC', N'Registro Nacional de Sanciones Contra Servidores Civiles (RNSSC)', 1),
    ('REDAM', N'Registro de Deudores Alimentarios Morosos (REDAM)', 2),
    ('RPS_TCP', N'Relación de Proveedores Sancionados por el OSCE (sanción vigente)', 3),
    ('REDJUM', N'Registro de Deudores Judiciales Morosos (REDJUM)', 4),
    ('DEBIDA_DILIGENCIA', N'Plataforma de Debida Diligencia del Sector Público (salvo en contrataciones bajo la modalidad de Acuerdo Marco)', 5)
) AS s(CodigoFiltro, Nombre, Orden)
ON d.CodigoFiltro = s.CodigoFiltro
WHEN MATCHED THEN
    UPDATE SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Activo = 1
WHEN NOT MATCHED THEN
    INSERT (CodigoFiltro, Nombre, Orden, Activo)
    VALUES (s.CodigoFiltro, s.Nombre, s.Orden, 1);
GO

/* Instalaciones nuevas: RNP y SUNAT ya no aplican en este tramo. */
UPDATE requerimiento.FiltroTipo
   SET Activo = 0
 WHERE CodigoFiltro IN ('RNP', 'SUNAT_HABIDO');
GO

/* -------------------------------------------------------------------------- */
/* 2. Resultado de cada filtro por requerimiento                              */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'requerimiento.FiltroIdoneidad', N'U') IS NULL
CREATE TABLE requerimiento.FiltroIdoneidad (
    IdFiltro         uniqueidentifier NOT NULL
                     CONSTRAINT DF_req_FiltroIdoneidad_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_req_FiltroIdoneidad PRIMARY KEY,
    IdRequerimiento  uniqueidentifier NOT NULL
                     CONSTRAINT FK_req_FiltroIdoneidad_Req REFERENCES requerimiento.Requerimiento(IdRequerimiento),
    CodigoFiltro     varchar(30) NOT NULL
                     CONSTRAINT FK_req_FiltroIdoneidad_Tipo REFERENCES requerimiento.FiltroTipo(CodigoFiltro),

    /* PENDIENTE | CONFORME | NO_CONFORME | NO_APLICA */
    Resultado        varchar(20) NOT NULL CONSTRAINT DF_req_FiltroIdoneidad_Res DEFAULT ('PENDIENTE'),
    /* PID cuando haya interoperabilidad; MANUAL mientras no. */
    Origen           varchar(20) NOT NULL CONSTRAINT DF_req_FiltroIdoneidad_Ori DEFAULT ('MANUAL'),
    Observacion      nvarchar(500) NULL,
    FechaVerificacion datetime NULL,

    Activo           bit NOT NULL CONSTRAINT DF_req_FiltroIdoneidad_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_req_FiltroIdoneidad_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,
    UsuarioEliminacionAuditoria   varchar(30)  NULL,
    FechaEliminacionAuditoria     datetime     NULL,
    EquipoEliminacionAuditoria    varchar(50)  NULL,
    ProgramaEliminacionAuditoria  varchar(50)  NULL,

    CONSTRAINT UQ_req_FiltroIdoneidad UNIQUE (IdRequerimiento, CodigoFiltro),
    CONSTRAINT CK_req_FiltroIdoneidad_Res
        CHECK (Resultado IN ('PENDIENTE','CONFORME','NO_CONFORME','NO_APLICA')),
    CONSTRAINT CK_req_FiltroIdoneidad_Ori
        CHECK (Origen IN ('PID','MANUAL'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_req_FiltroIdoneidad_Req' AND object_id = OBJECT_ID(N'requerimiento.FiltroIdoneidad'))
CREATE NONCLUSTERED INDEX IX_req_FiltroIdoneidad_Req
    ON requerimiento.FiltroIdoneidad(IdRequerimiento);
GO

/* -------------------------------------------------------------------------- */
/* 3. Certificacion de credito presupuestario                                 */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'requerimiento.CertificacionCcp', N'U') IS NULL
CREATE TABLE requerimiento.CertificacionCcp (
    IdCcp            uniqueidentifier NOT NULL
                     CONSTRAINT DF_req_Ccp_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_req_Ccp PRIMARY KEY,
    IdRequerimiento  uniqueidentifier NOT NULL
                     CONSTRAINT UQ_req_Ccp_Req UNIQUE
                     CONSTRAINT FK_req_Ccp_Req REFERENCES requerimiento.Requerimiento(IdRequerimiento),

    NumeroCcp        varchar(40)  NULL,
    FechaSolicitud   datetime     NULL,
    FechaEmision     date         NULL,

    GeneradoDocumentoCcp nvarchar(1000) NULL,
    NombreDocumentoCcp   nvarchar(1000) NULL,
    GeneradoDocumentoMemo nvarchar(1000) NULL,
    NombreDocumentoMemo   nvarchar(1000) NULL,

    Observacion      nvarchar(500) NULL,

    Activo           bit NOT NULL CONSTRAINT DF_req_Ccp_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_req_Ccp_FecCre DEFAULT (GETDATE()),
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

/* -------------------------------------------------------------------------- */
/* 4. Orden de servicio                                                       */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'requerimiento.OrdenServicio', N'U') IS NULL
CREATE TABLE requerimiento.OrdenServicio (
    IdOrdenServicio  uniqueidentifier NOT NULL
                     CONSTRAINT DF_req_Os_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_req_Os PRIMARY KEY,
    IdRequerimiento  uniqueidentifier NOT NULL
                     CONSTRAINT UQ_req_Os_Req UNIQUE
                     CONSTRAINT FK_req_Os_Req REFERENCES requerimiento.Requerimiento(IdRequerimiento),

    NumeroOrden      varchar(40)  NULL,
    FechaEmision     datetime     NULL,

    CorreoLocador      varchar(200) NULL,
    CorreoAreaUsuaria  varchar(200) NULL,
    NotificadoEn       datetime     NULL,
    ResultadoNotificacion nvarchar(300) NULL,

    GeneradoDocumento nvarchar(1000) NULL,
    NombreDocumento   nvarchar(1000) NULL,

    Activo           bit NOT NULL CONSTRAINT DF_req_Os_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_req_Os_FecCre DEFAULT (GETDATE()),
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

PRINT 'V016 aplicada: filtros de idoneidad, CCP y orden de servicio.';
GO
