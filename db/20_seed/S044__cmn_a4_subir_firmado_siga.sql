/*
===============================================================================
  SIGCM - S044 : Anexo 4 — aprobar SIGA sin firma SGCM + subir PDF firmado
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Flujo (observacion CMN / T6 manual):
  1. El SGCM sigue generando el PDF auxiliar (pdfmake). Ya NO se firma en SGCM.
  2. El jefe Abast aprueba en SIGA (CONSOLIDAR_CMN) sin certificado sobre ese PDF.
  3. Estado nuevo CMN_A4_PEND_DOC_SIGA: el jefe o la secretaria de Abastecimiento
     sube el Anexo 4 descargado del SIGA ya firmado digitalmente (reemplaza el
     auxiliar). El especialista no ve esta accion.
  4. Al guardar esa accion: correo (F013) + CMN_FINALIZADO.

  Idempotente. Va despues de S020 / S043 / F019.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Estado pendiente de documento oficial SIGA                              */
/* -------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sigcm.Estado WHERE CodigoEstado = 'CMN_A4_PEND_DOC_SIGA')
    INSERT INTO sigcm.Estado
        (CodigoEstado, CodigoModulo, Nombre, Orden, EsInicial, EsFinal, RolResponsable)
    VALUES
        ('CMN_A4_PEND_DOC_SIGA', 'CMN',
         'Anexo 4 aprobado en SIGA - pendiente documento firmado',
         95, 0, 0, 'ABAST_JEFE');
ELSE
    UPDATE sigcm.Estado
       SET Nombre = 'Anexo 4 aprobado en SIGA - pendiente documento firmado',
           Orden = 95,
           EsFinal = 0,
           RolResponsable = 'ABAST_JEFE'
     WHERE CodigoEstado = 'CMN_A4_PEND_DOC_SIGA';
GO

UPDATE sigcm.Estado
   SET Nombre = 'Anexo 4 por aprobar en SIGA (sin firma digital SGCM)'
 WHERE CodigoEstado = 'CMN_A4_FIRMA_JEFE';

UPDATE sigcm.Estado
   SET Nombre = 'Anexo 4 cerrado con documento firmado del SIGA'
 WHERE CodigoEstado = 'CMN_FINALIZADO';
GO

/* -------------------------------------------------------------------------- */
/* 2. Aprobar en SIGA sin firma digital del PDF del SGCM                      */
/* -------------------------------------------------------------------------- */

UPDATE sigcm.Transicion
   SET CodigoEstadoOrigen   = 'CMN_A4_FIRMA_JEFE',
       CodigoEstadoDestino  = 'CMN_A4_PEND_DOC_SIGA',
       NombreAccion         = 'Aprobar en SIGA y esperar documento firmado',
       RequiereComentario   = 0,
       RequiereFirma        = 0,
       DocumentoRequerido   = 'CMN_ANEXO_4_APROBACION_MODIFICACION',
       EncolaIntegracion    = 1,
       OperacionIntegracion = 'CONSOLIDAR_CMN',
       GeneraObservacion    = 0,
       RolFirmaRequerida    = NULL,
       Activo               = 1
 WHERE CodigoTransicion = 'CMN_ABAST_JEFE_FIRMAR_A4';

DELETE FROM sigcm.TransicionRol WHERE CodigoTransicion = 'CMN_ABAST_JEFE_FIRMAR_A4';
INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
VALUES ('CMN_ABAST_JEFE_FIRMAR_A4', 'ABAST_JEFE');
GO

/* Paso intermedio de firma digital A4 (T5) ya no aplica: no se firma en SGCM. */
UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion = 'CMN_ABAST_COORD_FIRMAR_A4';

DELETE FROM sigcm.TransicionRol
 WHERE CodigoTransicion = 'CMN_ABAST_COORD_FIRMAR_A4';
GO

/* -------------------------------------------------------------------------- */
/* 3. Subir PDF firmado del SIGA y finalizar                                  */
/* -------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sigcm.Transicion WHERE CodigoTransicion = 'CMN_ABAST_SUBIR_A4_SIGA')
    INSERT INTO sigcm.Transicion
        (CodigoTransicion, CodigoModulo, CodigoEstadoOrigen, CodigoEstadoDestino,
         NombreAccion, RequiereComentario, RequiereFirma, DocumentoRequerido,
         EncolaIntegracion, OperacionIntegracion, GeneraObservacion,
         RolFirmaRequerida, Activo)
    VALUES
        ('CMN_ABAST_SUBIR_A4_SIGA', 'CMN',
         'CMN_A4_PEND_DOC_SIGA', 'CMN_FINALIZADO',
         'Registrar Anexo 4 firmado del SIGA y finalizar',
         0, 0, 'CMN_ANEXO_4_APROBACION_MODIFICACION',
         0, NULL, 0, NULL, 1);
ELSE
    UPDATE sigcm.Transicion
       SET CodigoEstadoOrigen   = 'CMN_A4_PEND_DOC_SIGA',
           CodigoEstadoDestino  = 'CMN_FINALIZADO',
           NombreAccion         = 'Registrar Anexo 4 firmado del SIGA y finalizar',
           RequiereComentario   = 0,
           RequiereFirma        = 0,
           DocumentoRequerido   = 'CMN_ANEXO_4_APROBACION_MODIFICACION',
           EncolaIntegracion    = 0,
           OperacionIntegracion = NULL,
           GeneraObservacion    = 0,
           RolFirmaRequerida    = NULL,
           Activo               = 1
     WHERE CodigoTransicion = 'CMN_ABAST_SUBIR_A4_SIGA';

DELETE FROM sigcm.TransicionRol WHERE CodigoTransicion = 'CMN_ABAST_SUBIR_A4_SIGA';
INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol) VALUES
  ('CMN_ABAST_SUBIR_A4_SIGA', 'ABAST_JEFE'),
  ('CMN_ABAST_SUBIR_A4_SIGA', 'ABAST_SECRETARIA');
GO

/* Generar A4 sigue yendo al jefe (destino unico activo). */
UPDATE sigcm.Transicion
   SET CodigoEstadoDestino = 'CMN_A4_FIRMA_JEFE',
       NombreAccion = 'Generar Anexo 4 y remitir al Jefe',
       RequiereFirma = 0,
       Activo = 1
 WHERE CodigoTransicion = 'CMN_GENERAR_A4';
GO

PRINT 'S044 aplicada: A4 sin firma SGCM → SIGA → subir PDF (jefe/secretaria Abast) → finalizar + correo.';
GO
