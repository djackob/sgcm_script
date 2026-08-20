/*
===============================================================================
  Captura del SQL que envia el aplicativo SIGA
  Instancia: localhost\SQLSERVER25

  PARA QUE
  --------
  SIGA es PowerBuilder y arma su SQL en el cliente. Cuando una pantalla se
  niega a abrir ("El Area Usuaria debe estar en estado Consolidacion y
  Aprobacion") o muestra items que no esperabamos, la unica forma de saber que
  esta preguntando es mirar lo que manda al motor.

  El plan cache no sirve: SIGA usa DB-Library y sus consultas ad hoc no quedan
  retenidas. Extended Events si las ve.

  COMO SE USA
  -----------
  1. Ejecutar la seccion 1 (crear e iniciar).
  2. Hacer en el aplicativo SOLO la accion que interesa. Cuantos menos clics,
     mas legible queda la captura.
  3. Ejecutar la seccion 2 (leer).
  4. Ejecutar la seccion 3 (detener y borrar) al terminar. No dejarla corriendo.

  Filtra por el usuario admin_siga, que es con el que se conecta el aplicativo,
  para no capturar lo que hace el SIGCM ni sqlcmd.
===============================================================================
*/

/* -------------------------------------------------------------------------- */
/* 1. Crear e iniciar                                                          */
/* -------------------------------------------------------------------------- */

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'captura_siga')
BEGIN
    ALTER EVENT SESSION captura_siga ON SERVER STATE = STOP;
    DROP EVENT SESSION captura_siga ON SERVER;
END
GO

CREATE EVENT SESSION captura_siga ON SERVER
ADD EVENT sqlserver.sql_batch_completed (
    ACTION (sqlserver.session_id, sqlserver.username, sqlserver.database_name)
    WHERE sqlserver.username = N'admin_siga'
),
ADD EVENT sqlserver.rpc_completed (
    ACTION (sqlserver.session_id, sqlserver.username, sqlserver.database_name)
    WHERE sqlserver.username = N'admin_siga'
)
ADD TARGET package0.ring_buffer (SET max_events_limit = 2000, max_memory = 20480)
WITH (MAX_DISPATCH_LATENCY = 5 SECONDS, TRACK_CAUSALITY = ON);
GO

ALTER EVENT SESSION captura_siga ON SERVER STATE = START;
GO

PRINT 'Captura iniciada. Haz la accion en el aplicativo y luego corre la seccion 2.';
GO


/* -------------------------------------------------------------------------- */
/* 2. Leer lo capturado                                                        */
/* -------------------------------------------------------------------------- */
/*
SET NOCOUNT ON;

WITH datos AS (
    SELECT x = CONVERT(xml, t.target_data)
      FROM sys.dm_xe_session_targets AS t
      JOIN sys.dm_xe_sessions AS s ON s.address = t.event_session_address
     WHERE s.name = 'captura_siga' AND t.target_name = 'ring_buffer'
),
eventos AS (
    SELECT momento = e.value('@timestamp', 'datetime2'),
           evento  = e.value('@name', 'varchar(50)'),
           sesion  = e.value('(action[@name="session_id"]/value)[1]', 'int'),
           consulta = ISNULL(e.value('(data[@name="batch_text"]/value)[1]', 'nvarchar(max)'),
                             e.value('(data[@name="statement"]/value)[1]', 'nvarchar(max)'))
      FROM datos
     CROSS APPLY x.nodes('//event') AS n(e)
)
SELECT momento, evento, sesion, consulta
  FROM eventos
 WHERE consulta IS NOT NULL
   AND consulta NOT LIKE '%sp_reset_connection%'
 ORDER BY momento;
*/

/* Solo las que tocan el CMN, que suele ser lo que se busca:

   ... AND (consulta LIKE '%CUADRO%' OR consulta LIKE '%DEMANDA%')
*/


/* -------------------------------------------------------------------------- */
/* 3. Detener y borrar                                                         */
/* -------------------------------------------------------------------------- */
/*
ALTER EVENT SESSION captura_siga ON SERVER STATE = STOP;
DROP EVENT SESSION captura_siga ON SERVER;
*/
