/*
  Base    : DBSIGCM
  Esquema : requerimiento
  Objeto  : requerimiento.RequerimientoItem
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [requerimiento].[RequerimientoItem] (
    [IdRequerimientoItem] uniqueidentifier NOT NULL CONSTRAINT [DF_RequerimientoItem_IdRequerimientoItem] DEFAULT (newsequentialid()),
    [IdRequerimiento] uniqueidentifier NOT NULL,
    [IdRequerimientoPedido] uniqueidentifier,
    [Orden] int NOT NULL,
    [TipoBien] char(1),
    [GrupoBien] varchar(2),
    [ClaseBien] varchar(2),
    [FamiliaBien] varchar(4),
    [ItemBien] varchar(4),
    [DescripcionServicio] varchar(350),
    [UnidadMedida] int,
    [Cantidad] decimal(18,2) NOT NULL,
    [PrecioUnitario] decimal(16,6) NOT NULL,
    [Monto] decimal(18,2),
    [Activo] bit NOT NULL CONSTRAINT [DF_RequerimientoItem_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_RequerimientoItem_FechaCreacionAuditoria] DEFAULT (getdate()),
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
    CONSTRAINT [UQ_req_Item_Orden] UNIQUE ([IdRequerimiento] ASC, [Orden] ASC),
    CONSTRAINT [PK_req_Item] PRIMARY KEY ([IdRequerimientoItem] ASC),
    CONSTRAINT [FK_req_Item_Pedido] FOREIGN KEY ([IdRequerimientoPedido]) REFERENCES [requerimiento].[RequerimientoPedido] ([IdRequerimientoPedido]),
    CONSTRAINT [FK_req_Item_Requerimiento] FOREIGN KEY ([IdRequerimiento]) REFERENCES [requerimiento].[Requerimiento] ([IdRequerimiento])
);
GO
