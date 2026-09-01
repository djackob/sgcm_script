/*
  Analiza la traza captura_cuadro: muestra lo que el cliente SIGA envio a la
  base, en orden cronologico, separando las escrituras sobre las tablas del
  cuadro de adquisicion y del pedido.

  Nota: los metodos XML exigen QUOTED_IDENTIFIER ON y sqlcmd lo deja apagado,
  por eso se fija explicitamente al inicio.

    sqlcmd -S localhost -E -b -i traza_siga_analizar.sql -o traza_cuadro.txt -y 0 -Y 0
*/
USE master;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID('tempdb..#eventos') IS NOT NULL DROP TABLE #eventos;
GO

SELECT
    Momento = x.value('(event/@timestamp)[1]', 'datetime2(3)'),
    Evento  = x.value('(event/@name)[1]', 'varchar(60)'),
    Usuario = x.value('(event/action[@name="username"]/value)[1]', 'varchar(120)'),
    App     = x.value('(event/action[@name="client_app_name"]/value)[1]', 'varchar(160)'),
    Equipo  = x.value('(event/action[@name="client_hostname"]/value)[1]', 'varchar(120)'),
    Sesion  = x.value('(event/action[@name="session_id"]/value)[1]', 'int'),
    Texto   = COALESCE(
                  x.value('(event/data[@name="batch_text"]/value)[1]', 'nvarchar(max)'),
                  x.value('(event/data[@name="statement"]/value)[1]', 'nvarchar(max)'),
                  x.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)'))
  INTO #eventos
  FROM (SELECT CONVERT(xml, event_data) AS x
          FROM sys.fn_xe_file_target_read_file(
               'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\Log\captura_cuadro*.xel',
               NULL, NULL, NULL)) AS e;
GO

PRINT '=== Resumen: eventos capturados por aplicacion y usuario ===';
SELECT App, Usuario, Equipo, Sesion, Eventos = COUNT(*),
       Desde = MIN(Momento), Hasta = MAX(Momento)
  FROM #eventos
 GROUP BY App, Usuario, Equipo, Sesion
 ORDER BY COUNT(*) DESC;
GO

PRINT '';
PRINT '=== ESCRITURAS sobre tablas de pedido y cuadro ===';
SELECT Momento, Evento, Usuario, Texto
  FROM #eventos
 WHERE (Texto LIKE '%SIG_CUADRO_ADQUISICION%'
     OR Texto LIKE '%SIG_DETALLE_BSERV_CUADRO%'
     OR Texto LIKE '%SIG_DETALLE_METAS_CUADRO%'
     OR Texto LIKE '%SIG_DETALLE_PEDIDO_CUADRO%'
     OR Texto LIKE '%SIG_DETALLE_PEDIDOS%'
     OR Texto LIKE '%SIG_PEDIDOS%')
   AND (Texto LIKE '%INSERT %' OR Texto LIKE '%UPDATE %' OR Texto LIKE '%DELETE %')
 ORDER BY Momento;
GO

PRINT '';
PRINT '=== CONSULTAS de la pantalla Pedido Consolidado (por que sale vacia) ===';
SELECT Momento, Texto
  FROM #eventos
 WHERE Texto LIKE '%NRO_REQUER%'
    OR Texto LIKE '%CONSOLIDA%'
 ORDER BY Momento;
GO

PRINT '';
PRINT '=== Secuencia completa ===';
SELECT Momento, Evento, Usuario, Texto
  FROM #eventos
 ORDER BY Momento;
GO
