/*
===============================================================================
  SIGCM - V036 : FirmaObligatoria en sigcm.TipoDocumentoFirma
  Motor  : SQL Server 2022 (compat 160)

  Distingue una firma que cierra el documento de una que puede omitirse.
  El valor por defecto es 1: CMN y el resto del flujo no cambian.
  En Requerimiento, S047 deja en 0 la firma del especialista AU.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF COL_LENGTH(N'sigcm.TipoDocumentoFirma', N'FirmaObligatoria') IS NULL
BEGIN
    ALTER TABLE sigcm.TipoDocumentoFirma
        ADD FirmaObligatoria bit NOT NULL
            CONSTRAINT DF_sigcm_TipoDocFirma_Obligatoria DEFAULT (1);
END
GO
