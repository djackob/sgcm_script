/*
  Base    : DBSIGCM
  Esquema : requerimiento
  Objeto  : requerimiento.ParametroAnio
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [requerimiento].[ParametroAnio] (
    [AnoEje] smallint NOT NULL,
    [ValorUit] decimal(18,2) NOT NULL,
    [TopeUit] decimal(9,2) NOT NULL CONSTRAINT [DF_ParametroAnio_TopeUit] DEFAULT ((8)),
    [MontoTope] decimal(28,4),
    [Activo] bit NOT NULL CONSTRAINT [DF_ParametroAnio_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_ParametroAnio_FechaCreacionAuditoria] DEFAULT (getdate()),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    [UsuarioModificacionAuditoria] varchar(30),
    [FechaModificacionAuditoria] datetime,
    [EquipoModificacionAuditoria] varchar(50),
    [ProgramaModificacionAuditoria] varchar(50),
    [UsuarioEliminacionAuditoria] varchar(30),
    [FechaEliminacionAuditoria] datetime,
    [EquipoEliminacionAuditoria] varchar(50),
    [ProgramaEliminacionAuditoria] varchar(50),
    CONSTRAINT [PK_req_ParametroAnio] PRIMARY KEY ([AnoEje] ASC)
);
GO
