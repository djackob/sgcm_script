/*
===============================================================================
  SIGCM - V028 : Notificacion del Anexo 4 al area usuaria
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Al firmar el Jefe de Abastecimiento el Anexo 4, la modificacion queda aprobada
  en SIGA y el expediente vuelve al area usuaria: la transicion
  CMN_ABAST_JEFE_FIRMAR_A4 lleva a CMN_A4_ENVIADO, cuyo rol responsable es
  AREA_JEFE, y el enrutamiento de F004 devuelve el expediente a su unidad de
  origen. Esa parte -la derivacion en el sistema- ya funcionaba.

  Lo que faltaba es el aviso. El area usuaria pidio que ademas de aparecerle en
  la bandeja le llegue un correo diciendo que su modificacion del CMN ya se
  hizo, porque nadie mira una bandeja que la mayor parte del tiempo esta quieta.

  Esta tabla lleva la constancia del envio, uno por SOLICITUD y no por paquete:
  un Anexo 4 puede agrupar los Anexos 3 de varias areas usuarias, y cada una
  recibe su propio correo. Es el mismo patron de
  requerimiento.InvitacionCotizacion (V025): el correo no se envia desde SQL
  -SMTP no corre en el motor-, la rutina arma el sobre, el backend lo envia y
  vuelve a marcar aqui el resultado.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'cmn.NotificacionAnexo4', N'U') IS NULL
CREATE TABLE cmn.NotificacionAnexo4 (
    IdNotificacion   uniqueidentifier NOT NULL
                     CONSTRAINT DF_cmn_NotifA4_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_cmn_NotificacionAnexo4 PRIMARY KEY,

    IdSolicitud      uniqueidentifier NOT NULL
                     CONSTRAINT FK_cmn_NotifA4_Solicitud REFERENCES cmn.Solicitud(IdSolicitud),
    IdPaquete        uniqueidentifier     NULL
                     CONSTRAINT FK_cmn_NotifA4_Paquete REFERENCES cmn.Paquete(IdPaquete),

    /* A quien se aviso. Se guarda el texto enviado y no solo el id del usuario:
       si manana esa persona cambia de correo, la constancia debe seguir
       diciendo a donde se mando. */
    Destinatario     varchar(400)     NOT NULL,
    Copia            varchar(400)         NULL,

    EnviadaEn        datetime             NULL,
    ResultadoCorreo  nvarchar(400)        NULL,
    CorreoEnviado    bit              NOT NULL CONSTRAINT DF_cmn_NotifA4_Enviado DEFAULT (0),

    /* El PDF del Anexo 4 que se adjunto, por si despues hay que probar que se
       envio el documento y no solo el aviso. */
    Anexo4Documento  nvarchar(200)        NULL,

    Activo           bit NOT NULL CONSTRAINT DF_cmn_NotifA4_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_cmn_NotifA4_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL
);
GO

/* Una notificacion viva por solicitud. El reintento tras un fallo de SMTP
   actualiza la fila; no crea una segunda. */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
     WHERE name = N'UQ_cmn_NotifA4_Solicitud'
       AND object_id = OBJECT_ID(N'cmn.NotificacionAnexo4'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_cmn_NotifA4_Solicitud
    ON cmn.NotificacionAnexo4(IdSolicitud)
    WHERE Activo = 1;
GO

PRINT 'V028 aplicada: cmn.NotificacionAnexo4.';
GO
