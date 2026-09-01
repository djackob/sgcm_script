/*
  Detiene y elimina la traza captura_cuadro. Ejecutar siempre al terminar el
  diagnostico: una sesion de Extended Events olvidada sigue escribiendo a disco.

    sqlcmd -S localhost -E -b -i traza_siga_detener.sql
*/
USE master;
GO

SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.dm_xe_sessions WHERE name = 'captura_cuadro')
BEGIN
    ALTER EVENT SESSION captura_cuadro ON SERVER STATE = STOP;
    PRINT 'Sesion detenida.';
END;

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'captura_cuadro')
BEGIN
    DROP EVENT SESSION captura_cuadro ON SERVER;
    PRINT 'Sesion eliminada.';
END
ELSE
    PRINT 'No habia sesion captura_cuadro.';
GO
