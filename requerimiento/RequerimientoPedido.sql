/*
  Base    : DBSIGCM
  Esquema : requerimiento
  Objeto  : requerimiento.RequerimientoPedido
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [requerimiento].[RequerimientoPedido] (
    [IdRequerimientoPedido] uniqueidentifier NOT NULL CONSTRAINT [DF_RequerimientoPedido_IdRequerimientoPedido] DEFAULT (newsequentialid()),
    [IdRequerimiento] uniqueidentifier NOT NULL,
    [AnoEje] smallint NOT NULL,
    [SecEjec] int NOT NULL,
    [NumeroPedido] varchar(20) NOT NULL,
    [SecPedido] bigint,
    [FechaPedido] date,
    [CentroCosto] varchar(15),
    [SecFunc] int,
    [Origen] varchar(1),
    [FuenteFinanc] varchar(2),
    [Clasificador] varchar(20),
    [Verificado] bit NOT NULL CONSTRAINT [DF_RequerimientoPedido_Verificado] DEFAULT ((0)),
    [Activo] bit NOT NULL CONSTRAINT [DF_RequerimientoPedido_Activo] DEFAULT ((1)),
    [UsuarioCreacionAuditoria] varchar(30),
    [FechaCreacionAuditoria] datetime CONSTRAINT [DF_RequerimientoPedido_FechaCreacionAuditoria] DEFAULT (getdate()),
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
    CONSTRAINT [UQ_req_Pedido_Numero] UNIQUE ([IdRequerimiento] ASC, [AnoEje] ASC, [NumeroPedido] ASC),
    CONSTRAINT [PK_req_Pedido] PRIMARY KEY ([IdRequerimientoPedido] ASC),
    CONSTRAINT [FK_req_Pedido_Requerimiento] FOREIGN KEY ([IdRequerimiento]) REFERENCES [requerimiento].[Requerimiento] ([IdRequerimiento])
);
GO
