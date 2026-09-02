/*
===============================================================================
  SIGCM - V025 : Invitacion de cotizacion al locador (indagacion de mercado)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  En locacion el envio al locador propuesto (Anexo 5) se dispara al entrar a
  Indagacion de Mercado: uno a uno, con Anexo 3, 6, 7 y el paquete de
  integridad. El locador tiene 3 dias habiles para devolver A6 y A7 firmados.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'requerimiento.InvitacionCotizacion', N'U') IS NULL
CREATE TABLE requerimiento.InvitacionCotizacion (
    IdInvitacion        uniqueidentifier NOT NULL
                        CONSTRAINT DF_req_Invitacion_Id DEFAULT (NEWSEQUENTIALID())
                        CONSTRAINT PK_req_InvitacionCotizacion PRIMARY KEY,
    IdRequerimiento     uniqueidentifier NOT NULL
                        CONSTRAINT FK_req_Invitacion_Req REFERENCES requerimiento.Requerimiento(IdRequerimiento),
    Destinatario        varchar(200)  NOT NULL,
    EnviadaEn           datetime          NULL,
    PlazoHasta          date              NULL,
    ResultadoCorreo     nvarchar(400)     NULL,
    CorreoEnviado       bit           NOT NULL CONSTRAINT DF_req_Invitacion_Enviado DEFAULT (0),
    Anexo3Documento     nvarchar(200)     NULL,
    Anexo6Documento     nvarchar(200)     NULL,
    Anexo7Documento     nvarchar(200)     NULL,
    IntegridadDocumento nvarchar(200)     NULL,
    Activo              bit           NOT NULL CONSTRAINT DF_req_Invitacion_Activo DEFAULT (1),
    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_req_Invitacion_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL
);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
     WHERE name = N'UQ_req_Invitacion_Req'
       AND object_id = OBJECT_ID(N'requerimiento.InvitacionCotizacion'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_req_Invitacion_Req
    ON requerimiento.InvitacionCotizacion(IdRequerimiento)
    WHERE Activo = 1;
GO

PRINT 'V025 aplicada: requerimiento.InvitacionCotizacion.';
GO
