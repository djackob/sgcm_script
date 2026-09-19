/*
===============================================================================
  SIGCM - V035 : Configuracion de firmantes del Anexo 4 (CMN)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  T5 / observacion CMN 16/09/2026:
  - cmn.ConfigFirmanteAnexo4: config vigente editable por ADMIN_SISTEMA
  - cmn.PaqueteFirmante: snapshot inmutable al generar el Anexo 4

  Idempotente.
===============================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'cmn.ConfigFirmanteAnexo4', N'U') IS NULL
CREATE TABLE cmn.ConfigFirmanteAnexo4 (
    IdConfigFirmante             uniqueidentifier NOT NULL
        CONSTRAINT DF_cmn_ConfigFirmanteA4_Id DEFAULT (NEWSEQUENTIALID())
        CONSTRAINT PK_cmn_ConfigFirmanteAnexo4 PRIMARY KEY,
    CodigoRol                    varchar(40)  NOT NULL
        CONSTRAINT FK_cmn_ConfigFirmanteA4_Rol REFERENCES sigcm.Rol (CodigoRol),
    OrdenFirma                   smallint     NOT NULL,
    EtiquetaCargo                nvarchar(200) NULL,
    Activo                       bit          NOT NULL
        CONSTRAINT DF_cmn_ConfigFirmanteA4_Activo DEFAULT (1),
    UsuarioCreacionAuditoria     varchar(120) NOT NULL,
    FechaCreacionAuditoria       datetime2(3) NOT NULL
        CONSTRAINT DF_cmn_ConfigFirmanteA4_Fec DEFAULT (SYSUTCDATETIME()),
    EquipoCreacionAuditoria      varchar(50)  NULL,
    ProgramaCreacionAuditoria    varchar(50)  NULL,
    UsuarioModificacionAuditoria varchar(120) NULL,
    FechaModificacionAuditoria   datetime2(3) NULL,
    EquipoModificacionAuditoria  varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,
    CONSTRAINT UQ_cmn_ConfigFirmanteA4_Orden UNIQUE (OrdenFirma),
    CONSTRAINT UQ_cmn_ConfigFirmanteA4_Rol UNIQUE (CodigoRol),
    CONSTRAINT CK_cmn_ConfigFirmanteA4_Orden CHECK (OrdenFirma BETWEEN 1 AND 2)
);
GO

IF OBJECT_ID(N'cmn.PaqueteFirmante', N'U') IS NULL
CREATE TABLE cmn.PaqueteFirmante (
    IdPaquete       uniqueidentifier NOT NULL
        CONSTRAINT FK_cmn_PaqueteFirmante_Paquete REFERENCES cmn.Paquete (IdPaquete),
    CodigoRol       varchar(40)  NOT NULL
        CONSTRAINT FK_cmn_PaqueteFirmante_Rol REFERENCES sigcm.Rol (CodigoRol),
    OrdenFirma      smallint     NOT NULL,
    EtiquetaCargo   nvarchar(200) NULL,
    CONSTRAINT PK_cmn_PaqueteFirmante PRIMARY KEY (IdPaquete, CodigoRol),
    CONSTRAINT UQ_cmn_PaqueteFirmante_Orden UNIQUE (IdPaquete, OrdenFirma),
    CONSTRAINT CK_cmn_PaqueteFirmante_Orden CHECK (OrdenFirma BETWEEN 1 AND 2)
);
GO

PRINT 'V035 aplicada: cmn.ConfigFirmanteAnexo4 + cmn.PaqueteFirmante.';
GO
