/*
===============================================================================
  SIGCM - S041 : Visto bueno del especialista Abast sin firma digital (A3)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Observacion CMN (validacion 16/09/2026) / ticket T2:
  El especialista de Abastecimiento valida tecnicamente el Anexo 3 con un click
  (visto bueno operativo). No usa certificado/token. La firma digital del A3
  queda para el Jefe de Abastecimiento (escritura SIGA / ITEMS_ANEXO_3).

  - CMN_ABAST_ESP_FIRMAR_A3: RequiereFirma = 0
  - Se retira ABAST_ESPECIALISTA de TipoDocumentoFirma del Anexo 3
  - ABAST_JEFE queda como 2.o firmante digital del A3 (despues de AREA_JEFE)

  Idempotente. Va despues de S001 / S009 / S010.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

UPDATE sigcm.Transicion
   SET RequiereFirma     = 0,
       RolFirmaRequerida = NULL,
       DocumentoRequerido = 'CMN_ANEXO_3_SOLICITUD_MODIFICACION',
       NombreAccion      = 'Validar el Anexo 3 y elevar al Jefe',
       Activo            = 1
 WHERE CodigoTransicion = 'CMN_ABAST_ESP_FIRMAR_A3';

/* El especialista ya no es firmante digital del Anexo 3. Si quedara en la
   tabla, la firma del jefe no podria cerrar la version (F003 espera todas). */
DELETE FROM sigcm.TipoDocumentoFirma
 WHERE CodigoTipoDocumento = 'CMN_ANEXO_3_SOLICITUD_MODIFICACION'
   AND CodigoRol = 'ABAST_ESPECIALISTA';

UPDATE sigcm.TipoDocumentoFirma
   SET OrdenFirma = 2
 WHERE CodigoTipoDocumento = 'CMN_ANEXO_3_SOLICITUD_MODIFICACION'
   AND CodigoRol = 'ABAST_JEFE';

PRINT 'S041 aplicada: especialista Abast valida A3 sin firma digital; firma el jefe.';
GO
