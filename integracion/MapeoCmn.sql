/*
  Base    : DBSIGCM
  Esquema : integracion
  Objeto  : integracion.MapeoCmn
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [integracion].[MapeoCmn] (
    [IdSolicitudItem] uniqueidentifier NOT NULL,
    [IdSolicitud] uniqueidentifier NOT NULL,
    [AnoEje] smallint NOT NULL,
    [SecEjec] int NOT NULL,
    [CentroCosto] varchar(15) NOT NULL,
    [SecCuadro] bigint NOT NULL,
    [SecItem] bigint NOT NULL,
    [SecCuaModSal] bigint,
    [EstadoSiga] varchar(2) NOT NULL,
    [MotivoSolicitud] varchar(1),
    [IdempotenciaKey] varchar(200) NOT NULL,
    [RegistradoEnSiga] datetime NOT NULL CONSTRAINT [DF_MapeoCmn_RegistradoEnSiga] DEFAULT (getdate()),
    [UltimaConciliacion] datetime,
    [ConciliacionOk] bit,
    [PayloadRespuesta] nvarchar(max) NOT NULL,
    [UsuarioCreacionAuditoria] varchar(30),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    CONSTRAINT [UQ_integracion_MapeoCmn_Natural] UNIQUE ([AnoEje] ASC, [SecEjec] ASC, [CentroCosto] ASC, [SecCuadro] ASC, [SecItem] ASC),
    CONSTRAINT [PK_integracion_MapeoCmn] PRIMARY KEY ([IdSolicitudItem] ASC),
    CONSTRAINT [FK_integracion_MapeoCmn_Item] FOREIGN KEY ([IdSolicitudItem]) REFERENCES [cmn].[SolicitudItem] ([IdSolicitudItem]),
    CONSTRAINT [FK_integracion_MapeoCmn_Solicitud] FOREIGN KEY ([IdSolicitud]) REFERENCES [cmn].[Solicitud] ([IdSolicitud])
);
GO
