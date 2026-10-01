/*
  V041 - Alertas de la campana ya vistas por cada usuario.

  La campana calcula sus alertas en cada consulta (F024); esta tabla solo
  recuerda cual abrio el usuario. Una alerta deja de ser nueva mientras el
  expediente siga en la misma Version y la alerta sea del mismo Tipo: si el
  expediente se mueve o el plazo pasa de POR_VENCER a VENCIDO, vuelve a ser
  nueva.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'sigcm.AlertaVista', N'U') IS NULL
BEGIN
    CREATE TABLE sigcm.AlertaVista (
        IdUsuario         uniqueidentifier NOT NULL,
        IdExpediente      uniqueidentifier NOT NULL,
        Tipo              varchar(20)      NOT NULL,
        VersionExpediente int              NOT NULL,
        FechaVista        datetime         NOT NULL CONSTRAINT DF_sigcm_AlertaVista_FechaVista DEFAULT (GETDATE()),
        CONSTRAINT PK_sigcm_AlertaVista PRIMARY KEY (IdUsuario, IdExpediente),
        CONSTRAINT CK_sigcm_AlertaVista_Tipo CHECK (Tipo IN ('VENCIDO', 'POR_VENCER', 'PENDIENTE'))
    );
END
GO

PRINT 'V041 aplicada: sigcm.AlertaVista.';
GO
