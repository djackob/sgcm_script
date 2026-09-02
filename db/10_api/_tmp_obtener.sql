CREATE OR ALTER PROCEDURE requerimiento.paObtenerRequerimiento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51440, 'JSON incorrecto.', 1;

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

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        IF @IdRequerimiento IS NULL
            THROW 51441, 'VALIDACION_PAYLOAD: falta IdRequerimiento o no es un identificador valido.', 1;

        IF NOT EXISTS (SELECT 1 FROM requerimiento.Requerimiento
                        WHERE IdRequerimiento = @IdRequerimiento AND Activo = 1)
            THROW 51442, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   r.IdRequerimiento, r.Codigo, r.AnoEje, r.SecEjec, r.CentroCosto,
                   r.Denominacion, r.CodigoTipoContratacion,
                   TipoContratacion = tc.Nombre,
                   r.CodigoDec, r.CondicionCmn, r.IdSolicitudCmn,
                   r.GeneradoDocumentoCmn, r.NombreDocumentoCmn,
                   r.Monto, r.PlazoDias, r.FechaInicioPrevisto,
                   r.Ate, r.RucSugerido,
                   r.TieneDisponibilidad,
                   r.GeneradoDocumentoDisponibilidad, r.NombreDocumentoDisponibilidad,
                   r.Sustento, r.DatosAdicionales,
                   e.IdExpediente, e.CodigoEstado, e.Version, e.Anulado,
                   Estado = w.Nombre,
                   Responsable = CONCAT_WS(' ', u.Nombres, u.Apellidos),
                   CentroCostoNombre = ISNULL(un.Nombre, r.CentroCosto),
                   /* Si se apoya en una modificacion del CMN, se devuelve su
                      codigo: el visor la muestra sin una segunda consulta. */
                   SolicitudCmn = (SELECT TOP 1 s.Codigo FROM cmn.Solicitud AS s
                                    WHERE s.IdSolicitud = r.IdSolicitudCmn),
                   Pedidos = JSON_QUERY(COALESCE((
                       SELECT p.IdRequerimientoPedido, p.AnoEje, p.SecEjec, p.NumeroPedido,
                              p.SecPedido, p.FechaPedido, p.CentroCosto, p.SecFunc,
                              p.Origen, p.FuenteFinanc, p.Clasificador, p.Verificado
                         FROM requerimiento.RequerimientoPedido AS p
                        WHERE p.IdRequerimiento = r.IdRequerimiento AND p.Activo = 1
                        ORDER BY p.NumeroPedido
                          FOR JSON PATH), '[]')),
                   Items = JSON_QUERY(COALESCE((
                       SELECT i.IdRequerimientoItem, i.Orden,
                              CodigoItem = CONCAT_WS('.', i.TipoBien, i.GrupoBien,
                                                     i.ClaseBien, i.FamiliaBien, i.ItemBien),
                              i.TipoBien, i.GrupoBien, i.ClaseBien, i.FamiliaBien, i.ItemBien,
                              i.DescripcionServicio, i.UnidadMedida,
                              UnidadAbreviatura = CONVERT(varchar(20), NULL),
                              Descripcion = ISNULL(i.DescripcionServicio, CONVERT(varchar(350), N'')),
                              i.Cantidad, i.PrecioUnitario, i.Monto,
                              NumeroPedido = (SELECT TOP 1 p2.NumeroPedido
                                                FROM requerimiento.RequerimientoPedido AS p2
                                               WHERE p2.IdRequerimientoPedido = i.IdRequerimientoPedido)
                         FROM requerimiento.RequerimientoItem AS i
                        WHERE i.IdRequerimiento = r.IdRequerimiento AND i.Activo = 1
                        ORDER BY i.Orden
                          FOR JSON PATH), '[]')),
                   Filtros = JSON_QUERY(COALESCE((
                       SELECT f.IdFiltro, f.CodigoFiltro, Tipo = ft.Nombre, ft.Orden,
                              f.Resultado, f.Origen, f.Observacion, f.FechaVerificacion,
                              f.GeneradoDocumentoEvidencia, f.NombreDocumentoEvidencia
                         FROM requerimiento.FiltroIdoneidad AS f
                         JOIN requerimiento.FiltroTipo AS ft ON ft.CodigoFiltro = f.CodigoFiltro
                        WHERE f.IdRequerimiento = r.IdRequerimiento AND f.Activo = 1
                          AND ft.Activo = 1
                        ORDER BY ft.Orden
                          FOR JSON PATH), '[]')),
                   Ccp = JSON_QUERY((
                       SELECT TOP 1 c.IdCcp, c.NumeroCcp, c.NumeroExpedienteSiaf, c.MontoCertificado,
                              c.FechaSolicitud, c.FechaEmision,
                              c.GeneradoDocumentoCcp, c.NombreDocumentoCcp,
                              c.GeneradoDocumentoMemo, c.NombreDocumentoMemo,
                              c.GeneradoDocumentoMemoUp, c.NombreDocumentoMemoUp,
                              c.GeneradoDocumentoPrevision, c.NombreDocumentoPrevision,
                              c.CuerpoMemorando, c.Observacion, c.NumeroMemorando
                         FROM requerimiento.CertificacionCcp AS c
                        WHERE c.IdRequerimiento = r.IdRequerimiento AND c.Activo = 1
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                   OrdenServicio = JSON_QUERY((
                       SELECT TOP 1 o.IdOrdenServicio, o.NumeroOrden, o.FechaEmision,
                              o.CorreoLocador, o.CorreoAreaUsuaria, o.NotificadoEn,
                              o.EstadoIntegracion, o.SecCuadroSiga, o.ProveedorSiga,
                              o.ErrorIntegracion,
                              o.GeneradoDocumento, o.NombreDocumento
                         FROM requerimiento.OrdenServicio AS o
                        WHERE o.IdRequerimiento = r.IdRequerimiento AND o.Activo = 1
                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                   'OK' AS mensaje
              FROM requerimiento.Requerimiento AS r
              JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
              JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
              JOIN sigcm.Usuario    AS u ON u.IdUsuario    = r.IdResponsable
              JOIN sigcm.TipoContratacion AS tc ON tc.CodigoTipoContratacion = r.CodigoTipoContratacion
              LEFT JOIN sigcm.Unidad AS un
                     ON un.CentroCostoSiga = r.CentroCosto AND un.Activo = 1
             WHERE r.IdRequerimiento = @IdRequerimiento
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO
