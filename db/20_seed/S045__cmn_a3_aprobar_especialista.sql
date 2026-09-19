/*
===============================================================================
  SIGCM - S045 : Aprobacion Anexo 3 por especialista (sin ida y vuelta)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Problema:
    El especialista solo daba V.B. y elevaba a CMN_A3_FIRMA_JEFE; el jefe
    volvia a confirmar y recien ahi se escribia SIGA (ITEMS_ANEXO_3). Ida y
    vuelta redundante.

  Solucion:
    1. CMN_ABAST_ESP_FIRMAR_A3 aprueba y encola ITEMS_ANEXO_3 → CMN_A3_APROBADO
       (sin firma digital; el V.B. operativo ya es la decision).
    2. CMN_ABAST_ESP_ELEVAR_JEFE (opcional) eleva al jefe sin escribir SIGA,
       para los casos en que el especialista prefiere que decida la jefatura.
    3. CMN_ABAST_JEFE_FIRMAR_A3 se mantiene para expedientes ya elevados o
       legacy en CMN_A3_FIRMA_JEFE.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* 1. Especialista: aprobar = V.B. + escritura SIGA */
UPDATE sigcm.Transicion
   SET CodigoEstadoDestino   = 'CMN_A3_APROBADO',
       NombreAccion          = 'Aprobar el Anexo 3 y registrarlo en SIGA',
       RequiereComentario    = 0,
       RequiereFirma         = 0,
       RolFirmaRequerida     = NULL,
       DocumentoRequerido    = 'CMN_ANEXO_3_SOLICITUD_MODIFICACION',
       EncolaIntegracion     = 1,
       OperacionIntegracion  = 'ITEMS_ANEXO_3',
       GeneraObservacion     = 0,
       Activo                = 1
 WHERE CodigoTransicion = 'CMN_ABAST_ESP_FIRMAR_A3';
GO

/* 2. Elevacion opcional al jefe (sin tocar SIGA) */
IF NOT EXISTS (SELECT 1 FROM sigcm.Transicion WHERE CodigoTransicion = 'CMN_ABAST_ESP_ELEVAR_JEFE')
    INSERT INTO sigcm.Transicion (
        CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
        NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
        EncolaIntegracion, OperacionIntegracion, GeneraObservacion,
        RolFirmaRequerida, Activo)
    VALUES (
        'CMN_ABAST_ESP_ELEVAR_JEFE', 'CMN',
        'CMN_EN_ABAST_ESP', 'CMN_A3_FIRMA_JEFE',
        'Elevar al Jefe para decision', 0, 0, NULL,
        0, NULL, 0, NULL, 1);
ELSE
    UPDATE sigcm.Transicion
       SET CodigoEstadoOrigen    = 'CMN_EN_ABAST_ESP',
           CodigoEstadoDestino   = 'CMN_A3_FIRMA_JEFE',
           NombreAccion          = 'Elevar al Jefe para decision',
           RequiereComentario    = 0,
           RequiereFirma         = 0,
           DocumentoRequerido    = NULL,
           EncolaIntegracion     = 0,
           OperacionIntegracion  = NULL,
           GeneraObservacion     = 0,
           RolFirmaRequerida     = NULL,
           Activo                = 1
     WHERE CodigoTransicion = 'CMN_ABAST_ESP_ELEVAR_JEFE';
GO

DELETE FROM sigcm.TransicionRol WHERE CodigoTransicion = 'CMN_ABAST_ESP_ELEVAR_JEFE';
INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
VALUES ('CMN_ABAST_ESP_ELEVAR_JEFE', 'ABAST_ESPECIALISTA');
GO

IF NOT EXISTS (
    SELECT 1 FROM sigcm.TransicionRol
     WHERE CodigoTransicion = 'CMN_ABAST_ESP_FIRMAR_A3'
       AND CodigoRol = 'ABAST_ESPECIALISTA')
    INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
    VALUES ('CMN_ABAST_ESP_FIRMAR_A3', 'ABAST_ESPECIALISTA');
GO

PRINT 'S045: especialista puede aprobar A3 y escribir SIGA; elevacion al jefe queda opcional.';
GO
