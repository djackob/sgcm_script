/*
===============================================================================
  SIGCM - Migracion V018 : Catalogo de filtros de idoneidad (Abastecimiento)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Ajusta los registros que verifica el especialista de Administracion /
  Abastecimiento en la etapa REQ_FILTROS. RNP y SUNAT quedan inactivos; entran
  RPS_TCP (sanciones OSCE) y DEBIDA_DILIGENCIA (plataforma de debida diligencia).

  OPP y OA: sin jerarquia coord/esp por ahora; tramites entre oficinas solo con jefes.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

UPDATE requerimiento.FiltroTipo
   SET Activo = 0
 WHERE CodigoFiltro IN ('RNP', 'SUNAT_HABIDO');
GO

MERGE requerimiento.FiltroTipo AS d
USING (VALUES
    ('RNSSC', N'Registro Nacional de Sanciones Contra Servidores Civiles (RNSSC)', 1),
    ('REDAM', N'Registro de Deudores Alimentarios Morosos (REDAM)', 2),
    ('RPS_TCP', N'Relación de Proveedores Sancionados por el OSCE (sanción vigente)', 3),
    ('REDJUM', N'Registro de Deudores Judiciales Morosos (REDJUM)', 4),
    ('DEBIDA_DILIGENCIA', N'Plataforma de Debida Diligencia del Sector Público (salvo en contrataciones bajo la modalidad de Acuerdo Marco)', 5)
) AS s(CodigoFiltro, Nombre, Orden)
ON d.CodigoFiltro = s.CodigoFiltro
WHEN MATCHED THEN
    UPDATE SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Activo = 1
WHEN NOT MATCHED THEN
    INSERT (CodigoFiltro, Nombre, Orden, Activo)
    VALUES (s.CodigoFiltro, s.Nombre, s.Orden, 1);
GO

PRINT 'V018 aplicada: catalogo de filtros de idoneidad actualizado.';
GO
