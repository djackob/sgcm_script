/*
===============================================================================
  SIGCM - V030 : Punto focal en UsuarioRol
  Ambito : [DBSIGCM]

  Marca especialistas/coordinadores como "punto focal" del area para avisos
  (p. ej. Anexo 4 aprobado). Idempotente.
===============================================================================
*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF COL_LENGTH(N'sigcm.UsuarioRol', N'EsPuntoFocal') IS NULL
BEGIN
    ALTER TABLE sigcm.UsuarioRol
      ADD EsPuntoFocal bit NOT NULL
          CONSTRAINT DF_sigcm_UsuarioRol_PuntoFocal DEFAULT (0);
END
GO

PRINT 'V030: sigcm.UsuarioRol.EsPuntoFocal disponible.';
GO
