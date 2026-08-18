/*
===============================================================================
  SIGCM - Semilla S000 : Tabla de numeros
  Motor  : SQL Server 2016 (compat 130) o superior
  Ambito : [DBSIGCM]

  POR QUE EXISTE
  --------------
  PostgreSQL resolvia la materializacion de los 48 periodos con

      generate_series(0,3) CROSS JOIN generate_series(1,12)

  SQL Server tiene GENERATE_SERIES, pero es de la version 2022 y exige nivel de
  compatibilidad 160. La linea base del proyecto es SQL Server 2016 / compat 130,
  porque del servidor de produccion del ANIN no se conoce la version. Una tabla
  de numeros funciona desde SQL Server 2005 y no cuesta nada.

  Se siembra 0..1023: suficiente para los 4 anios, los 12 meses y cualquier
  desglose futuro, y cabe en una sola pagina de datos.

  Idempotente: solo inserta lo que falta.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Numero', N'U') IS NULL
CREATE TABLE dbo.Numero (
    n int NOT NULL CONSTRAINT pk_dbo_numero PRIMARY KEY CLUSTERED
);
GO

/* CTE de duplicacion binaria. b3 ya ofrece 256 filas y b4 llega a 65 536, de
   sobra para recortar con TOP a las 1024 que se quieren. */
WITH b0 AS (SELECT 0 AS z UNION ALL SELECT 0),
     b1 AS (SELECT 0 AS z FROM b0 AS a CROSS JOIN b0 AS b),
     b2 AS (SELECT 0 AS z FROM b1 AS a CROSS JOIN b1 AS b),
     b3 AS (SELECT 0 AS z FROM b2 AS a CROSS JOIN b2 AS b),
     b4 AS (SELECT 0 AS z FROM b3 AS a CROSS JOIN b3 AS b),
     serie AS (
         SELECT TOP (1024) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
           FROM b4
     )
INSERT INTO dbo.Numero (n)
SELECT s.n
  FROM serie AS s
 WHERE NOT EXISTS (SELECT 1 FROM dbo.Numero AS d WHERE d.n = s.n);
GO

/* El script es la autoridad sobre el contenido de la tabla: si una ejecucion
   anterior dejo filas de mas, se retiran. Asi reejecutar converge siempre al
   mismo estado, que es lo que se entiende por idempotente. */
DELETE FROM dbo.Numero WHERE n < 0 OR n > 1023;
GO

DECLARE @filas int = (SELECT COUNT(*) FROM dbo.Numero);
IF @filas <> 1024
    RAISERROR(N'dbo.Numero incorrecta: se esperaban exactamente 1024 filas.', 16, 1);
PRINT 'S000 aplicada: dbo.Numero con ' + CONVERT(varchar(10), @filas) + ' filas (0..1023).';
GO
