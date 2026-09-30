/*
  S054 - Semilla del reporte de expediente por orden. Solo QA.

  Completa los documentos de la contratacion de prueba PRU-OC-0001
  (REQ-PRU-EJEC-0001, integracion SIMULADO) segun el estado real de cada etapa:
    - Requerimiento: EETT y CCP (registrados en sigcm.Documento), disponibilidad
      presupuestal y la orden de compra (columnas del modulo).
    - Ejecucion: sus guias, PECOSA y acta ya estaban referenciadas; los archivos
      los crea S054__semilla_reporte_orden.archivos.mjs.
    - Ampliacion MOD-2026-000004 (en decision de la DEC): carta de solicitud e
      informe del area usuaria.
    - Pagos: pendientes, sin documentos.
  No cambia estados. Solo llena columnas vacias y registra cada documento una vez.
  Antes de ejecutar, generar los PDFs con el .mjs.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IdOrden uniqueidentifier = (SELECT IdOrdenServicio FROM requerimiento.OrdenServicio
                                      WHERE NumeroOrden = 'PRU-OC-0001' AND EstadoIntegracion = 'SIMULADO');
IF @IdOrden IS NULL
BEGIN
    PRINT 'S054 omitida: no existe la orden de prueba PRU-OC-0001 (SIMULADO).';
    RETURN;
END

DECLARE @IdRequerimiento uniqueidentifier, @IdExpReq uniqueidentifier;
SELECT @IdRequerimiento = r.IdRequerimiento, @IdExpReq = r.IdExpediente
  FROM requerimiento.OrdenServicio AS os
  JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = os.IdRequerimiento
 WHERE os.IdOrdenServicio = @IdOrden;

UPDATE requerimiento.OrdenServicio
   SET GeneradoDocumento = 'QA-SEMILLA-PRU-OC-0001-ORDEN-COMPRA.pdf',
       NombreDocumento = 'Orden de compra PRU-OC-0001.pdf'
 WHERE IdOrdenServicio = @IdOrden AND GeneradoDocumento IS NULL;

UPDATE requerimiento.Requerimiento
   SET GeneradoDocumentoDisponibilidad = 'QA-SEMILLA-PRU-OC-0001-DISPONIBILIDAD.pdf',
       NombreDocumentoDisponibilidad = 'Disponibilidad presupuestal REQ-PRU-EJEC-0001.pdf'
 WHERE IdRequerimiento = @IdRequerimiento AND GeneradoDocumentoDisponibilidad IS NULL;

UPDATE a
   SET SolicitudDocumento = COALESCE(a.SolicitudDocumento, 'QA-SEMILLA-PRU-OC-0001-AMP-SOLICITUD.pdf'),
       InformeAuDocumento = COALESCE(a.InformeAuDocumento, 'QA-SEMILLA-PRU-OC-0001-AMP-INFORME-AU.pdf')
  FROM ampliacion.Solicitud AS a
  JOIN ejecucion.Contrato AS c ON c.IdContrato = a.IdContrato
 WHERE c.IdOrdenServicio = @IdOrden AND a.Activo = 1;

/* EETT y CCP por el registro documental, como en el flujo. */
DECLARE @Cuenta varchar(120), @Unidad varchar(30);
SELECT TOP 1 @Cuenta = u.Cuenta, @Unidad = COALESCE(n.CentroCostoSiga, n.Codigo)
  FROM sigcm.UsuarioRol AS ur
  JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
  JOIN sigcm.Unidad AS n ON n.IdUnidad = ur.IdUnidad
 WHERE ur.CodigoRol = 'ABAST_ESPECIALISTA' AND ur.Activo = 1 AND u.Activo = 1
 ORDER BY n.CentroCostoSiga DESC;

DECLARE @Doc TABLE (Tipo varchar(60), Archivo varchar(200), Nombre nvarchar(200));
INSERT INTO @Doc VALUES
    ('REQ_EETT_BIEN', 'QA-SEMILLA-PRU-OC-0001-EETT.pdf', N'Especificaciones tecnicas REQ-PRU-EJEC-0001.pdf'),
    ('REQ_CCP',       'QA-SEMILLA-PRU-OC-0001-CCP.pdf',  N'CCP REQ-PRU-EJEC-0001.pdf');

DECLARE @Tipo varchar(60), @Archivo varchar(200), @Nombre nvarchar(200), @p nvarchar(max);
DECLARE @r TABLE (j nvarchar(max));
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT Tipo, Archivo, Nombre FROM @Doc;
OPEN cur;
FETCH cur INTO @Tipo, @Archivo, @Nombre;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sigcm.DocumentoExpediente AS de
                     JOIN sigcm.Documento AS d ON d.IdDocumento = de.IdDocumento
                    WHERE de.IdExpediente = @IdExpReq AND d.CodigoTipoDocumento = @Tipo AND d.Anulado = 0)
    BEGIN
        SET @p = (SELECT Actor = JSON_QUERY((SELECT Usuario = @Cuenta, Rol = 'ABAST_ESPECIALISTA', Unidad = @Unidad
                                              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                         IdExpediente = @IdExpReq, CodigoTipoDocumento = @Tipo,
                         GeneradoDocumento = @Archivo, NombreDocumento = @Nombre
                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DELETE FROM @r;
        INSERT INTO @r EXEC sigcm.paRegistrarDocumento @p;
        IF (SELECT JSON_VALUE(j, '$.estado') FROM @r) <> '1'
        BEGIN
            DECLARE @msg nvarchar(2000) = CONCAT('S054: no se registro ', @Tipo, ': ', (SELECT JSON_VALUE(j, '$.mensaje') FROM @r));
            THROW 59054, @msg, 1;
        END
    END
    FETCH cur INTO @Tipo, @Archivo, @Nombre;
END
CLOSE cur;
DEALLOCATE cur;

PRINT 'S054 aplicada: documentos de la orden de prueba PRU-OC-0001.';
GO
