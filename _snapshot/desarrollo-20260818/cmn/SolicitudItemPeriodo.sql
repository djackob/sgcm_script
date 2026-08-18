/*
  Base    : DBSIGCM
  Esquema : cmn
  Objeto  : cmn.SolicitudItemPeriodo
  Tipo    : TABLE
  Extraido: 2026-08-18 12:00:38
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [cmn].[SolicitudItemPeriodo] (
    [IdSolicitudItem] uniqueidentifier NOT NULL,
    [AnoOffset] smallint NOT NULL,
    [Mes] smallint NOT NULL,
    [Cantidad] decimal(18,2) NOT NULL CONSTRAINT [DF_SolicitudItemPeriodo_Cantidad] DEFAULT ((0)),
    [Monto] decimal(18,2) NOT NULL CONSTRAINT [DF_SolicitudItemPeriodo_Monto] DEFAULT ((0)),
    CONSTRAINT [PK_cmn_SolicitudItemPeriodo] PRIMARY KEY ([IdSolicitudItem] ASC, [AnoOffset] ASC, [Mes] ASC),
    CONSTRAINT [FK_cmn_Periodo_Item] FOREIGN KEY ([IdSolicitudItem]) REFERENCES [cmn].[SolicitudItem] ([IdSolicitudItem])
);
GO
