/*
===============================================================================
  SIGCM - S043 : Firmantes del Anexo 4 (config inicial + menu admin)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  T5: config vigente = solo ABAST_JEFE. Modulo ADMIN_CMN_FIRMANTES para
  ADMIN_SISTEMA. Idempotente. Requiere V035 + F019.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'cmn.ConfigFirmanteAnexo4', N'U') IS NULL
BEGIN
    RAISERROR('S043 requiere V035 (cmn.ConfigFirmanteAnexo4).', 16, 1);
    RETURN;
END
GO

/* Config por defecto: un firmante = jefe Abast. */
IF NOT EXISTS (SELECT 1 FROM cmn.ConfigFirmanteAnexo4)
BEGIN
    INSERT INTO cmn.ConfigFirmanteAnexo4
        (CodigoRol, OrdenFirma, EtiquetaCargo, Activo,
         UsuarioCreacionAuditoria, FechaCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES
        ('ABAST_JEFE', 1, N'Jefe de la Unidad de Abastecimiento', 1,
         'seed', SYSUTCDATETIME(), 'S043');
END
GO

/* Alinear catalogo global del Anexo 4 con la config. */
DELETE FROM sigcm.TipoDocumentoFirma
 WHERE CodigoTipoDocumento = 'CMN_ANEXO_4_APROBACION_MODIFICACION';

INSERT INTO sigcm.TipoDocumentoFirma (CodigoTipoDocumento, CodigoRol, OrdenFirma)
SELECT 'CMN_ANEXO_4_APROBACION_MODIFICACION', c.CodigoRol, c.OrdenFirma
  FROM cmn.ConfigFirmanteAnexo4 AS c
 WHERE c.Activo = 1;
GO

/* Modulo de mantenimiento. */
DECLARE @Modulo TABLE (CodigoModulo varchar(30), Nombre varchar(150), Orden int,
                       Activo bit, Ruta varchar(100), Icono varchar(60));
INSERT INTO @Modulo VALUES
  ('ADMIN_CMN_FIRMANTES', 'Firmantes Anexo 4 (CMN)', 91, 1,
   'mantenimiento-firmantes-a4', 'mdi mdi-draw-pen');

UPDATE d SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Activo = s.Activo,
             d.Ruta = s.Ruta, d.Icono = s.Icono
  FROM sigcm.Modulo AS d JOIN @Modulo AS s ON s.CodigoModulo = d.CodigoModulo;

INSERT INTO sigcm.Modulo (CodigoModulo, Nombre, Orden, Activo, Ruta, Icono)
SELECT s.CodigoModulo, s.Nombre, s.Orden, s.Activo, s.Ruta, s.Icono
  FROM @Modulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Modulo AS d WHERE d.CodigoModulo = s.CodigoModulo);

IF NOT EXISTS (
    SELECT 1 FROM sigcm.RolModulo
     WHERE CodigoRol = 'ADMIN_SISTEMA' AND CodigoModulo = 'ADMIN_CMN_FIRMANTES'
)
    INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
    VALUES ('ADMIN_SISTEMA', 'ADMIN_CMN_FIRMANTES');
GO

PRINT 'S043 aplicada: firmantes A4 (ABAST_JEFE) + menu ADMIN_CMN_FIRMANTES.';
GO
