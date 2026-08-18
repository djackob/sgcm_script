/*
===============================================================================
  SIGCM - Migracion V008 : Columnas de archivo en la version del documento
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Autoridad : SIGCM

  QUE CAMBIA Y POR QUE
  --------------------
  sigcm.DocumentoVersion ya guardaba ArchivoUri y ArchivoHash. El nombre
  ArchivoUri es correcto pero no es el que usan los demas sistemas de la ANIN,
  donde el par de columnas de archivo se llama GeneradoDocumento (la URL con la
  que se descarga) y NombreDocumento (el nombre visible para el usuario).

  Tener dos vocabularios para el mismo dato obliga a traducir en cada pantalla y
  a recordar cual sistema usa cual. Se adopta el de la casa:

      ArchivoUri  ->  GeneradoDocumento
      (nueva)     ->  NombreDocumento

  ArchivoHash se conserva con su nombre: no tiene equivalente en la convencion y
  describe exactamente lo que guarda.

  El componente app-input-archivos del frontend descubre estas dos columnas POR
  SU NOMBRE, buscando propiedades que empiecen o terminen en "GeneradoDocumento"
  y "NombreDocumento". Con cualquier otro nombre no encontraria el archivo.

  Idempotente: comprueba antes de renombrar y antes de agregar.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Renombrado. sp_rename avisa que las referencias no se actualizan solas; las
   unicas que existen estan en F003 y F004, que se despliegan despues. */
IF COL_LENGTH(N'sigcm.DocumentoVersion', N'ArchivoUri') IS NOT NULL
   AND COL_LENGTH(N'sigcm.DocumentoVersion', N'GeneradoDocumento') IS NULL
BEGIN
    EXEC sys.sp_rename N'sigcm.DocumentoVersion.ArchivoUri', N'GeneradoDocumento', N'COLUMN';
    PRINT 'V008: ArchivoUri renombrada a GeneradoDocumento.';
END
GO

/* Si la base es nueva y nunca tuvo ArchivoUri, la columna se crea directamente. */
IF COL_LENGTH(N'sigcm.DocumentoVersion', N'GeneradoDocumento') IS NULL
    ALTER TABLE sigcm.DocumentoVersion ADD GeneradoDocumento nvarchar(1000) NULL;
GO

IF COL_LENGTH(N'sigcm.DocumentoVersion', N'NombreDocumento') IS NULL
    ALTER TABLE sigcm.DocumentoVersion ADD NombreDocumento nvarchar(1000) NULL;
GO

PRINT 'V008 aplicada: columnas de archivo del documento.';
GO
