/*
===============================================================================
  SIGCM - S024 : Jefe AU no actua mientras el expediente esta con Especialista
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  En REQ_BORRADOR / REQ_DOC_PENDIENTE el RolResponsable es AREA_ESPECIALISTA.
  El Jefe no debe ver ni ejecutar:

    - Anular (REQ_ANULAR_BORRADOR, REQ_ANULAR_DOC_PEND)
    - Derivar al Jefe para firma (REQ_DERIVAR_JEFE)

  El camino vigente es Firma especialista (REQ_DERIVAR_COORD) → Coordinador
  → Derivar al Jefe (REQ_OTORGAR_VB). El Jefe actua en REQ_PEND_FIRMA_AU.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DELETE FROM sigcm.TransicionRol
 WHERE CodigoRol = 'AREA_JEFE'
   AND CodigoTransicion IN (
       'REQ_ANULAR_BORRADOR',
       'REQ_ANULAR_DOC_PEND',
       'REQ_DERIVAR_JEFE'
   );

/* Anular en documento pendiente: solo quien elabora (Especialista). */
IF NOT EXISTS (
    SELECT 1 FROM sigcm.TransicionRol
     WHERE CodigoTransicion = 'REQ_ANULAR_DOC_PEND'
       AND CodigoRol = 'AREA_ESPECIALISTA'
)
    INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
    VALUES ('REQ_ANULAR_DOC_PEND', 'AREA_ESPECIALISTA');

/* Atajo Especialista → Jefe (salta Coordinador): fuera del flujo AU. */
UPDATE sigcm.Transicion
   SET Activo = 0
 WHERE CodigoTransicion = 'REQ_DERIVAR_JEFE'
   AND Activo = 1;

PRINT 'S024 aplicada: Jefe AU sin Anular/Derivar mientras el expediente esta con el Especialista.';
GO
