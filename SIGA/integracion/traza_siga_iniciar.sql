/*
===============================================================================
  Traza de diagnostico: capturar lo que hace el cliente SIGA contra SIGA_1750
  Ambito: instancia (Extended Events)   SOLO desarrollo / homologacion

  Objetivo:
    Registrar las sentencias que el cliente SIGA 26.01.00 envia al generar un
    cuadro de adquisicion desde un pedido de requerimiento, para poder disenar
    la operacion de integracion de SGCM sobre el comportamiento real y no
    sobre una reconstruccion.

  Notas:
    - El archivo .xel se escribe en el directorio Log de la instancia porque
      la cuenta del servicio (NT Service\MSSQLSERVER) tiene permiso ahi.
    - Se excluye sqlcmd para no capturar las consultas de diagnostico propias.
    - Al terminar, ejecutar traza_siga_detener.sql para no dejarla corriendo.

    sqlcmd -S localhost -E -b -i traza_siga_iniciar.sql
===============================================================================
*/
USE master;
GO

SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'captura_cuadro')
BEGIN
    ALTER EVENT SESSION captura_cuadro ON SERVER STATE = STOP;
    DROP EVENT SESSION captura_cuadro ON SERVER;
    PRINT 'Sesion previa eliminada.';
END;
GO

DECLARE @ruta nvarchar(400) =
    N'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\Log\captura_cuadro.xel';

DECLARE @sql nvarchar(max) = N'
CREATE EVENT SESSION captura_cuadro ON SERVER
ADD EVENT sqlserver.sql_batch_completed
(
    ACTION (sqlserver.sql_text, sqlserver.client_app_name, sqlserver.client_hostname,
            sqlserver.username, sqlserver.database_name, sqlserver.session_id,
            package0.event_sequence)
    WHERE (sqlserver.database_name = N''SIGA_1750''
           AND sqlserver.client_app_name <> N''SQLCMD'')
),
ADD EVENT sqlserver.rpc_completed
(
    ACTION (sqlserver.sql_text, sqlserver.client_app_name, sqlserver.client_hostname,
            sqlserver.username, sqlserver.database_name, sqlserver.session_id,
            package0.event_sequence)
    WHERE (sqlserver.database_name = N''SIGA_1750''
           AND sqlserver.client_app_name <> N''SQLCMD'')
)
ADD TARGET package0.event_file
(
    SET filename = N''' + @ruta + N''',
        max_file_size = 64,
        max_rollover_files = 4
)
WITH (MAX_MEMORY = 16 MB,
      EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
      MAX_DISPATCH_LATENCY = 5 SECONDS,
      STARTUP_STATE = OFF);';

EXEC sys.sp_executesql @sql;
PRINT 'Sesion captura_cuadro creada.';
GO

ALTER EVENT SESSION captura_cuadro ON SERVER STATE = START;
PRINT 'Sesion captura_cuadro INICIADA. Realice la accion en SIGA y luego analice.';
GO

SELECT Sesion = s.name, Estado = CASE WHEN r.name IS NULL THEN 'detenida' ELSE 'corriendo' END
  FROM sys.server_event_sessions AS s
  LEFT JOIN sys.dm_xe_sessions AS r ON r.name = s.name
 WHERE s.name = 'captura_cuadro';
GO
