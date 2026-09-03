/*
===============================================================================
  SIGCM - Migracion V020 : Resultado PID y catalogo de idoneidad (7.2.1.10)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  SUNAT y RNP vuelven a estar activos: son el bloque de formalidad, aparte de
  la matriz de cinco filtros. RPS_TCP (OSCE) y DEBIDA_DILIGENCIA completan
  esa matriz. ResultadoPid guarda lo que devolvio (o no) la interoperabilidad,
  distinto del check del especialista (Resultado).
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF COL_LENGTH('requerimiento.FiltroIdoneidad', 'ResultadoPid') IS NULL
    ALTER TABLE requerimiento.FiltroIdoneidad
        ADD ResultadoPid varchar(20) NULL
            CONSTRAINT DF_req_FiltroIdoneidad_Pid DEFAULT ('PENDIENTE');
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
     WHERE name = N'CK_req_FiltroIdoneidad_Pid'
       AND parent_object_id = OBJECT_ID(N'requerimiento.FiltroIdoneidad')
)
    ALTER TABLE requerimiento.FiltroIdoneidad
        ADD CONSTRAINT CK_req_FiltroIdoneidad_Pid
            CHECK (ResultadoPid IS NULL
                OR ResultadoPid IN ('PENDIENTE','APTO','ALERTA','SIN_SERVICIO'));
GO

MERGE requerimiento.FiltroTipo AS d
USING (VALUES
    ('SUNAT_HABIDO',     N'Condicion de Activo y Habido en la SUNAT', 10),
    ('RNP',              N'Inscripcion vigente en el Registro Nacional de Proveedores (RNP)', 20),
    ('RNSSC',            N'Registro Nacional de Sanciones Contra Servidores Civiles (RNSSC)', 30),
    ('REDAM',            N'Registro de Deudores Alimentarios Morosos (REDAM)', 40),
    ('RPS_TCP',          N'Relacion de Proveedores Sancionados por el OSCE (sancion vigente)', 50),
    ('REDJUM',           N'Registro de Deudores Judiciales Morosos (REDJUM)', 60),
    ('DEBIDA_DILIGENCIA',N'Plataforma de Debida Diligencia del Sector Publico', 70)
) AS s(CodigoFiltro, Nombre, Orden)
ON d.CodigoFiltro = s.CodigoFiltro
WHEN MATCHED THEN
    UPDATE SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Activo = 1
WHEN NOT MATCHED THEN
    INSERT (CodigoFiltro, Nombre, Orden, Activo)
    VALUES (s.CodigoFiltro, s.Nombre, s.Orden, 1);
GO

PRINT 'V020 aplicada: ResultadoPid y catalogo SUNAT/RNP + cinco filtros.';
GO
