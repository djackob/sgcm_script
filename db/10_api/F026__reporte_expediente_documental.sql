/*
  F026 - Reporte: expediente documental por orden de compra o de servicio.

  Abastecimiento busca la orden (OC / OS) y obtiene el expediente de esa
  contratacion: el CMN de origen, el requerimiento, el contrato con sus
  entregas, modificaciones / ampliaciones y resolucion, y los pagos de la
  orden. Solo entran las contrataciones que ya tienen orden.

  Documentos: los registrados en sigcm.Documento (version vigente) y los que
  cada modulo guarda en columnas propias (guias, PECOSA, cartas, CCP, notas de
  pago, otros documentos, constancia de prestacion). Se deduplican por el id
  del archivo en el file server.

  reporte.fnCadenaOrden               expedientes de la contratacion de una orden.
  reporte.paBuscarOrden               ordenes por numero (coincidencia parcial).
  reporte.paObtenerExpedienteDocumental ficha, cadena, documentos y trazabilidad.

  Solo perfiles de Abastecimiento.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DROP PROCEDURE IF EXISTS reporte.paListarExpedienteDocumental;
DROP FUNCTION IF EXISTS reporte.fnCadenaExpediente;
GO

/*
  Requerimiento y CMN de la orden, y todo lo que cuelga del requerimiento
  (IdExpedientePadre), salvo contratos y pagos de otra orden del mismo
  requerimiento y lo que cuelga de ellos.
*/
CREATE OR ALTER FUNCTION reporte.fnCadenaOrden (@IdOrdenServicio uniqueidentifier)
RETURNS TABLE
AS
RETURN (
    WITH Semilla AS (
        SELECT r.IdExpediente
          FROM requerimiento.OrdenServicio AS os
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = os.IdRequerimiento
         WHERE os.IdOrdenServicio = @IdOrdenServicio
    ), Arbol AS (
        SELECT IdExpediente, 0 AS Nivel FROM Semilla
        UNION ALL
        SELECT h.IdExpediente, a.Nivel + 1
          FROM sigcm.Expediente AS h
          JOIN Arbol AS a ON h.IdExpedientePadre = a.IdExpediente
         WHERE a.Nivel < 6
           AND NOT EXISTS (SELECT 1 FROM ejecucion.Contrato AS c
                            WHERE c.IdExpediente = h.IdExpediente AND c.IdOrdenServicio <> @IdOrdenServicio)
           AND NOT EXISTS (SELECT 1 FROM pago.ExpedientePago AS p
                            WHERE p.IdExpediente = h.IdExpediente AND p.IdOrdenServicio <> @IdOrdenServicio)
    ), Todo AS (
        SELECT IdExpediente FROM Arbol
        UNION
        SELECT s.IdExpediente
          FROM requerimiento.OrdenServicio AS os
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = os.IdRequerimiento
          JOIN cmn.Solicitud AS s ON s.IdSolicitud = r.IdSolicitudCmn
         WHERE os.IdOrdenServicio = @IdOrdenServicio
    )
    SELECT DISTINCT t.IdExpediente
      FROM Todo AS t
      JOIN sigcm.Expediente AS e ON e.IdExpediente = t.IdExpediente
     WHERE e.Anulado = 0
);
GO

CREATE OR ALTER PROCEDURE reporte.paBuscarOrden
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET LOCK_TIMEOUT 8000;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52601, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120),
                @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier,
                @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50),
                @CorrelacionId uniqueidentifier;

        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        IF @CodigoRol NOT LIKE 'ABAST[_]%'
            THROW 52602, 'NO_AUTORIZADO: los reportes son de los perfiles de Abastecimiento.', 1;

        DECLARE @Texto varchar(60), @TipoOrden char(2), @AnoEje smallint, @Limite int;
        SELECT @Texto = NULLIF(LTRIM(RTRIM(Texto)), ''), @TipoOrden = NULLIF(TipoOrden, ''),
               @AnoEje = AnoEje, @Limite = Limite
          FROM OPENJSON(@parametro, '$.Filtro')
          WITH (Texto varchar(60), TipoOrden char(2), AnoEje smallint, Limite int);
        SET @Limite = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 15 WHEN @Limite > 50 THEN 50 ELSE @Limite END;

        CREATE TABLE #Orden (
            IdOrdenServicio uniqueidentifier PRIMARY KEY, NumeroOrden varchar(60), TipoOrden char(2),
            FechaOrden datetime, IdExpediente uniqueidentifier, CodigoRequerimiento varchar(40),
            Denominacion nvarchar(600), AnoEje smallint, IdUnidad uniqueidentifier, CodigoEstado varchar(60),
            Proveedor nvarchar(250), RucProveedor varchar(20), Monto decimal(18, 2),
            Entregables int, EntregablesPagados int);

        INSERT INTO #Orden
        SELECT os.IdOrdenServicio,
               COALESCE(NULLIF(os.NumeroOrden, ''), ct.NumeroOrdenSiga, pg.NumeroOrdenSiga),
               COALESCE(pg.TipoOrden, CASE WHEN r.CodigoTipoContratacion = 'BIEN' THEN 'OC' ELSE 'OS' END),
               COALESCE(os.FechaEmision, os.FechaCreacionAuditoria),
               r.IdExpediente, r.Codigo, r.Denominacion, r.AnoEje, er.IdUnidadOrigen,
               COALESCE(ec.CodigoEstado, er.CodigoEstado),
               COALESCE(ct.NombreProveedor, pg.NombreLocador),
               COALESCE(ct.RucProveedor, ct.DniProveedor, pg.RucLocador, pg.DniLocador),
               COALESCE(ct.MontoContrato, pg.MontoContrato, r.Monto),
               pg.Entregables, pg.Pagados
          FROM requerimiento.OrdenServicio AS os
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = os.IdRequerimiento
          JOIN sigcm.Expediente AS er ON er.IdExpediente = r.IdExpediente
          OUTER APPLY (SELECT TOP 1 c.NumeroOrdenSiga, c.NombreProveedor, c.RucProveedor, c.DniProveedor,
                              c.MontoContrato, c.IdExpediente
                         FROM ejecucion.Contrato AS c
                        WHERE c.IdOrdenServicio = os.IdOrdenServicio AND c.Activo = 1
                        ORDER BY c.FechaCreacionAuditoria DESC) AS ct
          LEFT JOIN sigcm.Expediente AS ec ON ec.IdExpediente = ct.IdExpediente
          OUTER APPLY (SELECT NumeroOrdenSiga = MAX(NULLIF(p.NumeroOrdenSiga, '')), TipoOrden = MAX(p.TipoOrden),
                              NombreLocador = MAX(p.NombreLocador), RucLocador = MAX(p.RucLocador),
                              DniLocador = MAX(p.DniLocador), MontoContrato = MAX(p.MontoContrato),
                              Entregables = COUNT(*),
                              Pagados = SUM(CASE WHEN p.FechaAbono IS NOT NULL THEN 1 ELSE 0 END)
                         FROM pago.ExpedientePago AS p
                         JOIN sigcm.Expediente AS ep ON ep.IdExpediente = p.IdExpediente
                        WHERE p.IdOrdenServicio = os.IdOrdenServicio AND p.Activo = 1 AND ep.Anulado = 0) AS pg
         WHERE os.Activo = 1 AND r.Activo = 1 AND er.Anulado = 0;

        DELETE FROM #Orden
         WHERE (@TipoOrden IS NOT NULL AND TipoOrden <> @TipoOrden)
            OR (@AnoEje IS NOT NULL AND AnoEje <> @AnoEje)
            OR (@Texto IS NOT NULL AND ISNULL(NumeroOrden, '') NOT LIKE '%' + @Texto + '%'
                                   AND CodigoRequerimiento NOT LIKE '%' + @Texto + '%');

        DECLARE @Total int = (SELECT COUNT(*) FROM #Orden);

        SELECT @resultado = (
            SELECT 1 AS estado, @Total AS total, @Limite AS limite,
                   Ordenes = JSON_QUERY(COALESCE((
                       SELECT TOP (@Limite) o.IdOrdenServicio, o.NumeroOrden, o.TipoOrden, o.FechaOrden,
                              o.CodigoRequerimiento, o.Denominacion, o.AnoEje,
                              Unidad = u.Nombre, UnidadSigla = u.Sigla, Estado = w.Nombre,
                              o.Proveedor, o.RucProveedor, o.Monto,
                              Entregables = ISNULL(o.Entregables, 0), EntregablesPagados = ISNULL(o.EntregablesPagados, 0)
                         FROM #Orden AS o
                         LEFT JOIN sigcm.Unidad AS u ON u.IdUnidad = o.IdUnidad
                         LEFT JOIN sigcm.Estado AS w ON w.CodigoEstado = o.CodigoEstado
                        ORDER BY CASE WHEN o.NumeroOrden = @Texto THEN 0 ELSE 1 END, o.FechaOrden DESC
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        DROP TABLE #Orden;
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE reporte.paObtenerExpedienteDocumental
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET LOCK_TIMEOUT 8000;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52611, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120),
                @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier,
                @CentroCostoActor varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50),
                @CorrelacionId uniqueidentifier;

        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCostoActor OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        IF @CodigoRol NOT LIKE 'ABAST[_]%'
            THROW 52612, 'NO_AUTORIZADO: los reportes son de los perfiles de Abastecimiento.', 1;

        DECLARE @IdOrden uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdOrdenServicio'));
        IF @IdOrden IS NULL
            THROW 52613, 'VALIDACION_PAYLOAD: falta IdOrdenServicio.', 1;
        IF NOT EXISTS (SELECT 1 FROM requerimiento.OrdenServicio WHERE IdOrdenServicio = @IdOrden AND Activo = 1)
            THROW 52614, 'NO_ENCONTRADO: la orden no existe o fue anulada.', 1;

        CREATE TABLE #Cadena (
            IdExpediente uniqueidentifier PRIMARY KEY, CodigoModulo varchar(30), Codigo varchar(40),
            OrdenModulo int, Modulo varchar(150), Carpeta varchar(30));
        INSERT INTO #Cadena
        SELECT e.IdExpediente, e.CodigoModulo, e.Codigo, m.Orden, m.Nombre,
               CASE e.CodigoModulo WHEN 'CMN' THEN 'cmn' WHEN 'REQUERIMIENTO' THEN 'requerimiento'
                                   WHEN 'EJECUCION' THEN 'ejecucion' WHEN 'MODIFICACION' THEN 'modificacion'
                                   WHEN 'RESOLUCION' THEN 'resolucion' WHEN 'PAGO' THEN 'pago' ELSE 'sigcm' END
          FROM reporte.fnCadenaOrden(@IdOrden) AS k
          JOIN sigcm.Expediente AS e ON e.IdExpediente = k.IdExpediente
          JOIN sigcm.Modulo AS m ON m.CodigoModulo = e.CodigoModulo;

        CREATE TABLE #Doc (
            IdExpediente uniqueidentifier, Documento nvarchar(300), Numero varchar(60),
            GeneradoDocumento nvarchar(400), NombreDocumento nvarchar(300), Fecha datetime,
            Origen varchar(10), Prioridad int);

        /* 1. Registrados en el nucleo documental. */
        INSERT INTO #Doc
        SELECT c.IdExpediente, td.Nombre, d.Numero, dv.GeneradoDocumento, dv.NombreDocumento,
               COALESCE(dv.FirmadoEn, dv.FechaCreacionAuditoria), 'REGISTRO', 1
          FROM #Cadena AS c
          JOIN sigcm.DocumentoExpediente AS de ON de.IdExpediente = c.IdExpediente
          JOIN sigcm.Documento AS d ON d.IdDocumento = de.IdDocumento
          JOIN sigcm.TipoDocumento AS td ON td.CodigoTipoDocumento = d.CodigoTipoDocumento
          JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumento = d.IdDocumento AND dv.Version = d.VersionVigente
         WHERE d.Anulado = 0 AND d.Activo = 1 AND NULLIF(dv.GeneradoDocumento, '') IS NOT NULL;

        /* 2. Guardados en columnas de cada modulo. */
        INSERT INTO #Doc
        SELECT r.IdExpediente, v.Documento, NULL, v.Doc, v.Nombre, r.FechaCreacionAuditoria, 'MODULO', 2
          FROM requerimiento.Requerimiento AS r
          JOIN #Cadena AS c ON c.IdExpediente = r.IdExpediente
          CROSS APPLY (VALUES (r.GeneradoDocumentoCmn, N'Documento CMN del requerimiento', r.NombreDocumentoCmn),
                              (r.GeneradoDocumentoDisponibilidad, N'Disponibilidad presupuestal', r.NombreDocumentoDisponibilidad)
                      ) AS v(Doc, Documento, Nombre)
         WHERE NULLIF(v.Doc, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT r.IdExpediente, v.Documento, NULL, v.Doc, NULL, x.FechaCreacionAuditoria, 'MODULO', 2
          FROM requerimiento.CertificacionCcp AS x
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = x.IdRequerimiento
          JOIN #Cadena AS c ON c.IdExpediente = r.IdExpediente
          CROSS APPLY (VALUES (x.GeneradoDocumentoMemo, N'Memorando de solicitud de CCP'),
                              (x.GeneradoDocumentoMemoUp, N'Memorando de la Unidad de Presupuesto'),
                              (x.GeneradoDocumentoPrevision, N'Prevision presupuestal'),
                              (x.GeneradoDocumentoCcp, N'Certificacion de credito presupuestario')) AS v(Doc, Documento)
         WHERE x.Activo = 1 AND NULLIF(v.Doc, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT r.IdExpediente, N'Evidencia del filtro de idoneidad', NULL, x.GeneradoDocumentoEvidencia, NULL,
               x.FechaCreacionAuditoria, 'MODULO', 2
          FROM requerimiento.FiltroIdoneidad AS x
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = x.IdRequerimiento
          JOIN #Cadena AS c ON c.IdExpediente = r.IdExpediente
         WHERE x.Activo = 1 AND NULLIF(x.GeneradoDocumentoEvidencia, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT r.IdExpediente, v.Documento, NULL, v.Doc, NULL, x.FechaCreacionAuditoria, 'MODULO', 2
          FROM requerimiento.InvitacionCotizacion AS x
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = x.IdRequerimiento
          JOIN #Cadena AS c ON c.IdExpediente = r.IdExpediente
          CROSS APPLY (VALUES (x.Anexo3Documento, N'Invitacion - Anexo 3'),
                              (x.Anexo6Documento, N'Cotizacion - Anexo 6'),
                              (x.Anexo7Documento, N'Declaracion jurada - Anexo 7'),
                              (x.IntegridadDocumento, N'Paquete de integridad')) AS v(Doc, Documento)
         WHERE x.Activo = 1 AND NULLIF(v.Doc, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT r.IdExpediente, N'Orden de servicio / compra', os.NumeroOrden, os.GeneradoDocumento, os.NombreDocumento,
               COALESCE(os.FechaEmision, os.FechaCreacionAuditoria), 'MODULO', 2
          FROM requerimiento.OrdenServicio AS os
          JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = os.IdRequerimiento
          JOIN #Cadena AS c ON c.IdExpediente = r.IdExpediente
         WHERE os.IdOrdenServicio = @IdOrden AND NULLIF(os.GeneradoDocumento, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT s.IdExpediente, N'Anexo 4 notificado', NULL, x.Anexo4Documento, NULL, x.FechaCreacionAuditoria, 'MODULO', 2
          FROM cmn.NotificacionAnexo4 AS x
          JOIN cmn.Solicitud AS s ON s.IdSolicitud = x.IdSolicitud
          JOIN #Cadena AS c ON c.IdExpediente = s.IdExpediente
         WHERE x.Activo = 1 AND NULLIF(x.Anexo4Documento, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT COALESCE(ce.IdExpediente, ct.IdExpediente), CONCAT(v.Documento, N' - entrega ', x.NumeroEntrega), NULL,
               v.Doc, NULL, x.FechaCreacionAuditoria, 'MODULO', 2
          FROM ejecucion.Entrega AS x
          JOIN ejecucion.Contrato AS ct ON ct.IdContrato = x.IdContrato
          JOIN #Cadena AS c ON c.IdExpediente = ct.IdExpediente
          LEFT JOIN #Cadena AS ce ON ce.IdExpediente = x.IdExpediente
          CROSS APPLY (VALUES (x.GuiaDocumento, N'Guia de remision'),
                              (x.GuiaSuscritaDocumento, N'Guia de remision suscrita'),
                              (x.PecosaDocumento, N'PECOSA'),
                              (x.ActaIncumplimientoDocumento, N'Acta de incumplimiento')) AS v(Doc, Documento)
         WHERE x.Activo = 1 AND NULLIF(v.Doc, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT ct.IdExpediente, CONCAT(N'Informe de ', LOWER(x.Tipo)), NULL, x.InformeDocumento, NULL,
               x.FechaCreacionAuditoria, 'MODULO', 2
          FROM ejecucion.Incidencia AS x
          JOIN ejecucion.Contrato AS ct ON ct.IdContrato = x.IdContrato
          JOIN #Cadena AS c ON c.IdExpediente = ct.IdExpediente
         WHERE x.Activo = 1 AND NULLIF(x.InformeDocumento, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT x.IdExpediente, v.Documento, NULL, v.Doc, NULL, x.FechaCreacionAuditoria, 'MODULO', 2
          FROM ampliacion.Solicitud AS x
          JOIN #Cadena AS c ON c.IdExpediente = x.IdExpediente
          CROSS APPLY (VALUES (x.SolicitudDocumento, N'Solicitud'),
                              (x.InformeAuDocumento, N'Informe del area usuaria'),
                              (x.InformeDecDocumento, N'Informe de la DEC'),
                              (x.ActaDocumento, N'Acta de modificacion'),
                              (x.CartaDocumento, N'Carta de respuesta')) AS v(Doc, Documento)
         WHERE x.Activo = 1 AND NULLIF(v.Doc, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT x.IdExpediente, v.Documento, NULL, v.Doc, NULL, x.FechaCreacionAuditoria, 'MODULO', 2
          FROM resolucion.Procedimiento AS x
          JOIN #Cadena AS c ON c.IdExpediente = x.IdExpediente
          CROSS APPLY (VALUES (x.SolicitudDocumento, N'Solicitud de resolucion'),
                              (x.InformeAuDocumento, N'Informe del area usuaria'),
                              (x.RespuestaDocumento, N'Respuesta del proveedor'),
                              (x.CartaApercibimientoDocumento, N'Carta de apercibimiento'),
                              (x.CartaDocumento, N'Carta de resolucion')) AS v(Doc, Documento)
         WHERE x.Activo = 1 AND NULLIF(v.Doc, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT x.IdExpediente, v.Documento, NULL, v.Doc, NULL, COALESCE(v.Fecha, x.FechaCreacionAuditoria), 'MODULO', 2
          FROM pago.ExpedientePago AS x
          JOIN #Cadena AS c ON c.IdExpediente = x.IdExpediente
          CROSS APPLY (VALUES (x.InformeDocumento, N'Informe del entregable', x.FechaPresentacion),
                              (x.RhePdfDocumento, N'Recibo por honorarios electronico (PDF)', x.FechaPresentacion),
                              (x.RheXmlDocumento, N'Recibo por honorarios electronico (XML)', x.FechaPresentacion),
                              (x.Suspension4taDocumento, N'Suspension de retencion de 4ta categoria', x.FechaPresentacion),
                              (x.NotaPagoDocumento, N'Nota de pago SIAF', x.FechaAbono),
                              (x.ConstanciaDocumento, N'Constancia de transferencia', x.FechaAbono),
                              (x.PapeletaPenalidadDocumento, N'Papeleta de deposito de penalidad', x.FechaAbono)
                      ) AS v(Doc, Documento, Fecha)
         WHERE x.Activo = 1 AND NULLIF(v.Doc, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT p.IdExpediente, CONCAT(N'Otro documento', CASE WHEN a.Descripcion IS NOT NULL THEN N': ' + a.Descripcion ELSE N'' END),
               NULL, a.GeneradoDocumento, a.NombreDocumento, a.FechaCreacionAuditoria, 'MODULO', 2
          FROM pago.DocumentoAdicional AS a
          JOIN pago.ExpedientePago AS p ON p.IdExpedientePago = a.IdExpedientePago
          JOIN #Cadena AS c ON c.IdExpediente = p.IdExpediente
         WHERE a.Activo = 1 AND NULLIF(a.GeneradoDocumento, '') IS NOT NULL;

        INSERT INTO #Doc
        SELECT x.IdExpediente, N'Constancia de prestacion', x.Numero, x.GeneradoDocumento, x.NombreDocumento,
               x.FechaEmision, 'MODULO', 2
          FROM pago.ConstanciaPrestacion AS x
          JOIN #Cadena AS c ON c.IdExpediente = x.IdExpediente
         WHERE x.Activo = 1 AND NULLIF(x.GeneradoDocumento, '') IS NOT NULL;

        /* Un archivo, una fila: manda el registro del nucleo. */
        ;WITH Clave AS (
            SELECT d.*, Archivo = LOWER(RIGHT(n.s, CHARINDEX('/', REVERSE(n.s) + '/') - 1))
              FROM #Doc AS d
              CROSS APPLY (SELECT REPLACE(d.GeneradoDocumento, '\', '/') AS s) AS n
        ), Unico AS (
            SELECT *, Fila = ROW_NUMBER() OVER (PARTITION BY Archivo ORDER BY Prioridad, Fecha)
              FROM Clave
        )
        DELETE FROM Unico WHERE Fila > 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Cabecera = JSON_QUERY((
                       SELECT os.IdOrdenServicio,
                              NumeroOrden = COALESCE(NULLIF(os.NumeroOrden, ''), ct.NumeroOrdenSiga, pg.NumeroOrdenSiga),
                              TipoOrden = COALESCE(pg.TipoOrden, CASE WHEN r.CodigoTipoContratacion = 'BIEN' THEN 'OC' ELSE 'OS' END),
                              FechaOrden = COALESCE(os.FechaEmision, os.FechaCreacionAuditoria),
                              CodigoRequerimiento = r.Codigo, r.Denominacion, r.CodigoTipoContratacion,
                              CodigoCmn = ecm.Codigo, Unidad = u.Nombre, UnidadSigla = u.Sigla,
                              EstadoRequerimiento = wr.Nombre,
                              CodigoContrato = ec.Codigo, EstadoContrato = wc.Nombre,
                              ct.FechaInicio, FechaFin = COALESCE(ct.FechaFinReal, ct.FechaFinPrevista), ct.PlazoDias,
                              Monto = COALESCE(ct.MontoContrato, pg.MontoContrato, r.Monto),
                              Proveedor = COALESCE(ct.NombreProveedor, pg.NombreLocador),
                              RucProveedor = COALESCE(ct.RucProveedor, ct.DniProveedor, pg.RucLocador, pg.DniLocador),
                              Entregables = ISNULL(pg.Entregables, 0), EntregablesPagados = ISNULL(pg.Pagados, 0),
                              MontoPagado = ISNULL(pg.MontoPagado, 0),
                              Constancia = (SELECT TOP 1 cp.Numero FROM pago.ConstanciaPrestacion AS cp
                                             WHERE cp.IdRequerimiento = r.IdRequerimiento AND cp.Activo = 1)
                         FROM requerimiento.OrdenServicio AS os
                         JOIN requerimiento.Requerimiento AS r ON r.IdRequerimiento = os.IdRequerimiento
                         JOIN sigcm.Expediente AS er ON er.IdExpediente = r.IdExpediente
                         LEFT JOIN sigcm.Estado AS wr ON wr.CodigoEstado = er.CodigoEstado
                         LEFT JOIN cmn.Solicitud AS scm ON scm.IdSolicitud = r.IdSolicitudCmn
                         LEFT JOIN sigcm.Expediente AS ecm ON ecm.IdExpediente = scm.IdExpediente
                         LEFT JOIN sigcm.Unidad AS u ON u.IdUnidad = er.IdUnidadOrigen
                         OUTER APPLY (SELECT TOP 1 c.* FROM ejecucion.Contrato AS c
                                       WHERE c.IdOrdenServicio = os.IdOrdenServicio AND c.Activo = 1
                                       ORDER BY c.FechaCreacionAuditoria DESC) AS ct
                         LEFT JOIN sigcm.Expediente AS ec ON ec.IdExpediente = ct.IdExpediente
                         LEFT JOIN sigcm.Estado AS wc ON wc.CodigoEstado = ec.CodigoEstado
                         OUTER APPLY (SELECT NumeroOrdenSiga = MAX(NULLIF(p.NumeroOrdenSiga, '')), TipoOrden = MAX(p.TipoOrden),
                                             NombreLocador = MAX(p.NombreLocador), RucLocador = MAX(p.RucLocador),
                                             DniLocador = MAX(p.DniLocador), MontoContrato = MAX(p.MontoContrato),
                                             Entregables = COUNT(*),
                                             Pagados = SUM(CASE WHEN p.FechaAbono IS NOT NULL THEN 1 ELSE 0 END),
                                             MontoPagado = SUM(CASE WHEN p.FechaAbono IS NOT NULL THEN p.MontoEntregable ELSE 0 END)
                                        FROM pago.ExpedientePago AS p
                                        JOIN sigcm.Expediente AS ep ON ep.IdExpediente = p.IdExpediente
                                       WHERE p.IdOrdenServicio = os.IdOrdenServicio AND p.Activo = 1 AND ep.Anulado = 0) AS pg
                        WHERE os.IdOrdenServicio = @IdOrden
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                   Expedientes = JSON_QUERY(COALESCE((
                       SELECT c.IdExpediente, c.CodigoModulo, c.Modulo, c.Codigo, Estado = w.Nombre, w.EsFinal,
                              Padre = p.Codigo, Creado = e.FechaCreacionAuditoria,
                              Documentos = (SELECT COUNT(*) FROM #Doc AS d WHERE d.IdExpediente = c.IdExpediente)
                         FROM #Cadena AS c
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
                         JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
                         LEFT JOIN sigcm.Expediente AS p ON p.IdExpediente = e.IdExpedientePadre
                        ORDER BY c.OrdenModulo, c.Codigo
                          FOR JSON PATH), N'[]')),
                   Documentos = JSON_QUERY(COALESCE((
                       SELECT c.CodigoModulo, c.Modulo, CodigoExpediente = c.Codigo, c.Carpeta,
                              d.Documento, d.Numero, d.GeneradoDocumento, d.NombreDocumento, d.Fecha, d.Origen
                         FROM #Doc AS d
                         JOIN #Cadena AS c ON c.IdExpediente = d.IdExpediente
                        ORDER BY c.OrdenModulo, c.Codigo, d.Fecha, d.Documento
                          FOR JSON PATH), N'[]')),
                   Historial = JSON_QUERY(COALESCE((
                       SELECT c.Modulo, CodigoExpediente = c.Codigo, h.OcurridoEn,
                              EstadoOrigen = wo.Nombre, EstadoDestino = wd.Nombre, h.Comentario, h.ActorRol,
                              Actor = CONCAT_WS(' ', u.Nombres, u.Apellidos), Unidad = n.Nombre
                         FROM sigcm.Historial AS h
                         JOIN #Cadena AS c ON c.IdExpediente = h.IdExpediente
                         LEFT JOIN sigcm.Estado AS wo ON wo.CodigoEstado = h.CodigoEstadoOrigen
                         LEFT JOIN sigcm.Estado AS wd ON wd.CodigoEstado = h.CodigoEstadoDestino
                         LEFT JOIN sigcm.Usuario AS u ON u.IdUsuario = h.IdActor
                         LEFT JOIN sigcm.Unidad AS n ON n.IdUnidad = h.IdActorUnidad
                        ORDER BY h.OcurridoEn, h.IdHistorial
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        DROP TABLE #Doc;
        DROP TABLE #Cadena;
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F026 aplicada: reporte de expediente documental por orden.';
GO
