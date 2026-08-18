/*
  Base    : DBSIGCM
  Esquema : cmn
  Objeto  : cmn.SolicitudItem
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [cmn].[SolicitudItem] (
    [IdSolicitudItem] uniqueidentifier NOT NULL CONSTRAINT [DF_SolicitudItem_IdSolicitudItem] DEFAULT (newsequentialid()),
    [IdSolicitud] uniqueidentifier NOT NULL,
    [Orden] int NOT NULL,
    [TipoMovimiento] varchar(15) NOT NULL,
    [TipoTarea] char(1) NOT NULL,
    [NivelTarea] char(1) NOT NULL,
    [CodigoTarea] bigint NOT NULL,
    [SecFunc] int NOT NULL,
    [SecFuncProp] int,
    [Origen] varchar(1) NOT NULL CONSTRAINT [DF_SolicitudItem_Origen] DEFAULT ('1'),
    [FuenteFinanc] varchar(2) NOT NULL CONSTRAINT [DF_SolicitudItem_FuenteFinanc] DEFAULT ('00'),
    [Clasificador] varchar(20) NOT NULL,
    [TipoRecurso] varchar(2) NOT NULL CONSTRAINT [DF_SolicitudItem_TipoRecurso] DEFAULT ('1'),
    [TipoPpto] smallint NOT NULL CONSTRAINT [DF_SolicitudItem_TipoPpto] DEFAULT ((1)),
    [TipoUso] varchar(1) NOT NULL CONSTRAINT [DF_SolicitudItem_TipoUso] DEFAULT ('C'),
    [TipoBien] char(1) NOT NULL,
    [GrupoBien] varchar(2) NOT NULL,
    [ClaseBien] varchar(2) NOT NULL,
    [FamiliaBien] varchar(4) NOT NULL,
    [ItemBien] varchar(4) NOT NULL,
    [DescripcionServicio] varchar(350),
    [UnidadMedida] int NOT NULL,
    [PrecioUnitario] decimal(16,6) NOT NULL,
    [RefSecCuadro] bigint,
    [RefSecItem] bigint,
    [Activo] bit NOT NULL CONSTRAINT [DF_SolicitudItem_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_SolicitudItem_FechaCreacionAuditoria] DEFAULT (getdate()),
    [EquipoCreacionAuditoria] varchar(50),
    [ProgramaCreacionAuditoria] varchar(50),
    [UsuarioModificacionAuditoria] varchar(30),
    [FechaModificacionAuditoria] datetime,
    [EquipoModificacionAuditoria] varchar(50),
    [ProgramaModificacionAuditoria] varchar(50),
    CONSTRAINT [UQ_cmn_SolItem_Orden] UNIQUE ([IdSolicitud] ASC, [Orden] ASC),
    CONSTRAINT [PK_cmn_SolicitudItem] PRIMARY KEY ([IdSolicitudItem] ASC),
    CONSTRAINT [FK_cmn_SolicitudItem_Solicitud] FOREIGN KEY ([IdSolicitud]) REFERENCES [cmn].[Solicitud] ([IdSolicitud])
);

CREATE INDEX [IX_cmn_SolItem_Solicitud] ON [cmn].[SolicitudItem] ([IdSolicitud] ASC, [Orden] ASC);
GO
CREATE UNIQUE INDEX [UQ_cmn_SolItem_Unico] ON [cmn].[SolicitudItem] ([IdSolicitud] ASC, [TipoTarea] ASC, [NivelTarea] ASC, [CodigoTarea] ASC, [SecFunc] ASC, [Origen] ASC, [FuenteFinanc] ASC, [Clasificador] ASC, [TipoUso] ASC, [TipoBien] ASC, [GrupoBien] ASC, [ClaseBien] ASC, [FamiliaBien] ASC, [ItemBien] ASC);
GO
