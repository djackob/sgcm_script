/*
===============================================================================
  SIGCM - Migracion V007 : Ruta de navegacion por modulo
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Autoridad : SIGCM

  POR QUE ESTA COLUMNA EXISTE
  ---------------------------
  El menu lateral del frontend se arma con lo que devuelve la sesion, y el guard
  de rutas compara cada entrada del menu contra el path de Angular. Si la
  correspondencia modulo -> ruta viviera en TypeScript, habria dos matrices de
  acceso: la de sigcm.RolModulo, que decide quien entra, y un CASE en el cliente,
  que decide adonde. Se desincronizan el dia que alguien renombra una ruta.

  La matriz de acceso ya es dato configurable (V001, seccion 4). La ruta es la
  otra mitad del mismo dato y va en la misma tabla.

  Los cinco modulos sin pantalla todavia llevan Ruta NULL: la sesion no los
  incluye en el menu hasta que exista el componente que los atiende.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'sigcm.Modulo', N'Ruta') IS NULL
    ALTER TABLE sigcm.Modulo ADD Ruta varchar(100) NULL;
GO

IF COL_LENGTH(N'sigcm.Modulo', N'Icono') IS NULL
    ALTER TABLE sigcm.Modulo ADD Icono varchar(60) NULL;
GO

/* Solo CMN tiene pantalla en la v1. El resto queda declarado sin ruta. */
UPDATE sigcm.Modulo SET Ruta = 'gestion-cmn', Icono = 'mdi mdi-clipboard-list-outline'
 WHERE CodigoModulo = 'CMN';
GO

PRINT 'V007 aplicada: ruta e icono por modulo.';
GO
