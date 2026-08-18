/*
  Base    : DBSIGCM
  Esquema : integracion
  Objeto  : integracion.Operacion
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [integracion].[Operacion] (
    [IdOperacion] uniqueidentifier NOT NULL CONSTRAINT [DF_Operacion_IdOperacion] DEFAULT (newsequentialid()),
    [IdempotenciaKey] varchar(200) NOT NULL,
    [IdExpediente] uniqueidentifier NOT NULL,
    [IdSolicitud] uniqueidentifier NOT NULL,
    [IdSolicitudItem] uniqueidentifier,
    [Operacion] varchar(30) NOT NULL,
    [Procedimiento] varchar(128) NOT NULL,
    [Secuencia] int NOT NULL CONSTRAINT [DF_Operacion_Secuencia] DEFAULT ((1)),
    [Estado] varchar(20) NOT NULL CONSTRAINT [DF_Operacion_Estado] DEFAULT ('PENDIENTE'),
    [RequestJson] nvarchar(max) NOT NULL,
    [ResponseJson] nvarchar(max),
    [ErrorCodigo] varchar(80),
    [ErrorMensaje] nvarchar(max),
    [Intentos] int NOT NULL CONSTRAINT [DF_Operacion_Intentos] DEFAULT ((0)),
    [MaxIntentos] int NOT NULL CONSTRAINT [DF_Operacion_MaxIntentos] DEFAULT ((5)),
    [ProximoIntentoEn] datetime NOT NULL CONSTRAINT [DF_Operacion_ProximoIntentoEn] DEFAULT (getdate()),
    [BloqueoToken] uniqueidentifier,
    [BloqueadoEn] datetime,
    [BloqueadoPor] varchar(80),
    [ModoEjecucion] varchar(15),
    [CompletadoEn] datetime,
    [Activo] bit NOT NULL CONSTRAINT [DF_Operacion_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_Operacion_FechaCreacionAuditoria] DEFAULT (getdate()),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    [UsuarioModificacionAuditoria] varchar(30),
    [FechaModificacionAuditoria] datetime,
    [EquipoModificacionAuditoria] varchar(50),
    [ProgramaModificacionAuditoria] varchar(50),
    CONSTRAINT [UQ_integracion_Operacion_Idempotencia] UNIQUE ([IdempotenciaKey] ASC),
    CONSTRAINT [PK_integracion_Operacion] PRIMARY KEY ([IdOperacion] ASC),
    CONSTRAINT [FK_integracion_Operacion_Expediente] FOREIGN KEY ([IdExpediente]) REFERENCES [sigcm].[Expediente] ([IdExpediente]),
    CONSTRAINT [FK_integracion_Operacion_Item] FOREIGN KEY ([IdSolicitudItem]) REFERENCES [cmn].[SolicitudItem] ([IdSolicitudItem]),
    CONSTRAINT [FK_integracion_Operacion_Solicitud] FOREIGN KEY ([IdSolicitud]) REFERENCES [cmn].[Solicitud] ([IdSolicitud])
);

CREATE INDEX [IX_integracion_Operacion_Atencion] ON [integracion].[Operacion] ([Estado] ASC, [FechaModificacionAuditoria] DESC);
GO
CREATE INDEX [IX_integracion_Operacion_Pendiente] ON [integracion].[Operacion] ([ProximoIntentoEn] ASC, [Secuencia] ASC, [FechaCreacionAuditoria] ASC);
GO
CREATE INDEX [IX_integracion_Operacion_Solicitud] ON [integracion].[Operacion] ([IdSolicitud] ASC, [Secuencia] ASC);
GO
