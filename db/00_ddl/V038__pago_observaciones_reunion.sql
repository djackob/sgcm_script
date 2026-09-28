/*
===============================================================================
  SIGCM - V038 : Observaciones de la reunion del 27-09-2026 (modulo PAGO)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  1. pago.ExpedientePago.NumeroContrato y TipoOrden: el Anexo 11 lleva el
     numero de contrato cuando la contratacion cruza el ejercicio fiscal, y
     el tipo de orden (O/S u O/C) forma parte del codigo del expediente.
  2. pago.DocumentoAdicional: "otros documentos" del pago, N por expediente.
     sigcm.Documento versiona por tipo, asi que no sirve para N archivos
     del mismo tipo.
  3. sigcm.CorreoEnviado: evidencia de cada correo que sale del sistema,
     reconstruible como HTML/PDF.
  4. Item CCI_SIAF del checklist (Anexo 9).

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'pago.ExpedientePago', N'NumeroContrato') IS NULL
    ALTER TABLE pago.ExpedientePago ADD NumeroContrato varchar(60) NULL;
GO

IF COL_LENGTH(N'pago.ExpedientePago', N'TipoOrden') IS NULL
    ALTER TABLE pago.ExpedientePago
      ADD TipoOrden char(2) NOT NULL
          CONSTRAINT DF_pago_ExpPago_TipoOrden DEFAULT ('OS');
GO

/* -------------------------------------------------------------------------- */
/* Otros documentos del pago                                                  */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'pago.DocumentoAdicional', N'U') IS NULL
CREATE TABLE pago.DocumentoAdicional (
    IdDocumentoAdicional uniqueidentifier NOT NULL
                         CONSTRAINT DF_pago_DocAdic_Id DEFAULT (NEWSEQUENTIALID())
                         CONSTRAINT PK_pago_DocumentoAdicional PRIMARY KEY,
    IdExpedientePago     uniqueidentifier NOT NULL
                         CONSTRAINT FK_pago_DocAdic_Pago REFERENCES pago.ExpedientePago(IdExpedientePago),
    GeneradoDocumento    nvarchar(200) NOT NULL,
    NombreDocumento      nvarchar(300) NOT NULL,
    Descripcion          nvarchar(500) NULL,
    IdUsuario            uniqueidentifier NULL,
    NombreUsuario        nvarchar(250) NULL,
    CodigoRol            varchar(40) NULL,
    Activo               bit NOT NULL CONSTRAINT DF_pago_DocAdic_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_pago_DocAdic_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pago_DocAdic_Pago'
                AND object_id = OBJECT_ID(N'pago.DocumentoAdicional'))
CREATE NONCLUSTERED INDEX IX_pago_DocAdic_Pago
    ON pago.DocumentoAdicional(IdExpedientePago)
    WHERE Activo = 1;
GO

/* -------------------------------------------------------------------------- */
/* Evidencia de correos                                                       */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'sigcm.CorreoEnviado', N'U') IS NULL
CREATE TABLE sigcm.CorreoEnviado (
    IdCorreo         uniqueidentifier NOT NULL
                     CONSTRAINT DF_sigcm_Correo_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_sigcm_CorreoEnviado PRIMARY KEY,
    IdExpediente     uniqueidentifier NULL
                     CONSTRAINT FK_sigcm_Correo_Exp REFERENCES sigcm.Expediente(IdExpediente),
    Origen           varchar(80)   NOT NULL,
    Destinatario     nvarchar(1000) NOT NULL,
    Copia            nvarchar(1000) NULL,
    Asunto           nvarchar(500) NOT NULL,
    Cuerpo           nvarchar(max) NOT NULL,
    Adjuntos         nvarchar(max) NULL,
    Enviado          bit           NOT NULL,
    Resultado        nvarchar(1000) NULL,
    Referencia       nvarchar(max) NULL,
    IdUsuario        uniqueidentifier NULL,
    CodigoRol        varchar(40)   NULL,
    EnviadoEn        datetime      NOT NULL CONSTRAINT DF_sigcm_Correo_Fecha DEFAULT (GETDATE()),
    UsuarioCreacionAuditoria  varchar(30) NULL,
    EquipoCreacionAuditoria   varchar(50) NULL,
    ProgramaCreacionAuditoria varchar(50) NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sigcm_Correo_Exp'
                AND object_id = OBJECT_ID(N'sigcm.CorreoEnviado'))
CREATE NONCLUSTERED INDEX IX_sigcm_Correo_Exp
    ON sigcm.CorreoEnviado(IdExpediente, EnviadoEn DESC);
GO

/* -------------------------------------------------------------------------- */
/* Checklist: CCI en SIAF Web contra Anexo 6                                  */
/* -------------------------------------------------------------------------- */

MERGE pago.ChecklistItem AS d
USING (VALUES
    ('CCI_SIAF', N'CCI registrado en SIAF Web coincide con el Anexo 6 o con la actualizacion de CCI presentada por el proveedor', 85, 1)
) AS s(CodigoItem, Nombre, Orden, Obligatorio)
ON d.CodigoItem = s.CodigoItem
WHEN MATCHED THEN
    UPDATE SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Obligatorio = s.Obligatorio, d.Activo = 1
WHEN NOT MATCHED THEN
    INSERT (CodigoItem, Nombre, Orden, Obligatorio, Activo)
    VALUES (s.CodigoItem, s.Nombre, s.Orden, s.Obligatorio, 1);
GO

PRINT 'V038 aplicada: NumeroContrato/TipoOrden, pago.DocumentoAdicional, sigcm.CorreoEnviado, item CCI_SIAF.';
GO
