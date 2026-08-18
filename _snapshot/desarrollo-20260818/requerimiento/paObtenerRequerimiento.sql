/*
  Base    : DBSIGCM
  Esquema : requerimiento
  Objeto  : requerimiento.paObtenerRequerimiento
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 2. requerimiento.paObtenerRequerimiento                                   */
/* ========================================================================== */

/* Requerimiento completo: cabecera, pedidos e items. Es lo que consume el visor
   y el formulario cuando esta editable (REQ-11).

   Entrada: { "Actor": {...}, "IdRequerimiento": "..." } */
CREATE   PROCEDURE requerimiento.paObtenerRequerimiento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF sigcm.fnEsJson(@parametro) <> 1
            RAISERROR('JSON incorrecto.', 16, 1);

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
            sigcm.fnTryGuid(sigcm.fnJsonTexto(@parametro, 'IdRequerimiento'));

        IF @IdRequerimiento IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta IdRequerimiento o no es un identificador valido.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM requerimiento.Requerimiento
                        WHERE IdRequerimiento = @IdRequerimiento AND Activo = 1)
            RAISERROR('NO_ENCONTRADO: el requerimiento no existe.', 16, 1);

        DECLARE @PedidosJson nvarchar(max);
        DECLARE @ItemsJson nvarchar(max);

        SET @PedidosJson = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"IdRequerimientoPedido":' + sigcm.fnJsonValorTexto(CONVERT(nvarchar(36), p.IdRequerimientoPedido))
                + N',"AnoEje":'      + CASE WHEN p.AnoEje IS NULL THEN N'null' ELSE CONVERT(nvarchar(10), p.AnoEje) END
                + N',"SecEjec":'     + CASE WHEN p.SecEjec IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), p.SecEjec) END
                + N',"NumeroPedido":' + sigcm.fnJsonValorTexto(p.NumeroPedido)
                + N',"SecPedido":'   + CASE WHEN p.SecPedido IS NULL THEN N'null' ELSE CONVERT(nvarchar(30), p.SecPedido) END
                + N',"FechaPedido":' + CASE WHEN p.FechaPedido IS NULL THEN N'null' ELSE sigcm.fnJsonValorTexto(CONVERT(varchar(10), p.FechaPedido, 23)) END
                + N',"CentroCosto":' + sigcm.fnJsonValorTexto(p.CentroCosto)
                + N',"SecFunc":'     + CASE WHEN p.SecFunc IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), p.SecFunc) END
                + N',"Origen":'      + sigcm.fnJsonValorTexto(p.Origen)
                + N',"FuenteFinanc":'+ sigcm.fnJsonValorTexto(p.FuenteFinanc)
                + N',"Clasificador":'+ sigcm.fnJsonValorTexto(p.Clasificador)
                + N',"Verificado":'  + CASE WHEN p.Verificado IS NULL THEN N'null' WHEN p.Verificado = 1 THEN N'true' ELSE N'false' END
                + N'}'
              FROM requerimiento.RequerimientoPedido AS p
             WHERE p.IdRequerimiento = @IdRequerimiento AND p.Activo = 1
             ORDER BY p.NumeroPedido
               FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SET @ItemsJson = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"IdRequerimientoItem":' + sigcm.fnJsonValorTexto(CONVERT(nvarchar(36), i.IdRequerimientoItem))
                + N',"Orden":'            + CASE WHEN i.Orden IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), i.Orden) END
                + N',"CodigoItem":'       + sigcm.fnJsonValorTexto(sigcm.fnCodigoItemSiga(i.TipoBien, i.GrupoBien, i.ClaseBien, i.FamiliaBien, i.ItemBien))
                + N',"TipoBien":'         + sigcm.fnJsonValorTexto(i.TipoBien)
                + N',"GrupoBien":'        + sigcm.fnJsonValorTexto(i.GrupoBien)
                + N',"ClaseBien":'        + sigcm.fnJsonValorTexto(i.ClaseBien)
                + N',"FamiliaBien":'      + sigcm.fnJsonValorTexto(i.FamiliaBien)
                + N',"ItemBien":'         + sigcm.fnJsonValorTexto(i.ItemBien)
                + N',"DescripcionServicio":' + sigcm.fnJsonValorTexto(i.DescripcionServicio)
                + N',"UnidadMedida":'     + CASE WHEN i.UnidadMedida IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), i.UnidadMedida) END
                + N',"UnidadAbreviatura":'+ sigcm.fnJsonValorTexto(um.Abreviatura)
                + N',"Descripcion":'      + sigcm.fnJsonValorTexto(ISNULL(cat.Descripcion, i.DescripcionServicio))
                + N',"Cantidad":'         + CASE WHEN i.Cantidad IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), i.Cantidad) END
                + N',"PrecioUnitario":'   + CASE WHEN i.PrecioUnitario IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), i.PrecioUnitario) END
                + N',"Monto":'            + CASE WHEN i.Monto IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), i.Monto) END
                + N',"NumeroPedido":'     + sigcm.fnJsonValorTexto((
                       SELECT TOP 1 p2.NumeroPedido
                         FROM requerimiento.RequerimientoPedido AS p2
                        WHERE p2.IdRequerimientoPedido = i.IdRequerimientoPedido))
                + N'}'
              FROM requerimiento.RequerimientoItem AS i
              JOIN requerimiento.Requerimiento AS r0 ON r0.IdRequerimiento = i.IdRequerimiento
              LEFT JOIN siga.vwUnidadMedida AS um ON um.UnidadMedida = i.UnidadMedida
              LEFT JOIN siga.vwCatalogoItem AS cat
                     ON cat.SecEjec = r0.SecEjec
                    AND cat.TipoBien = i.TipoBien AND cat.GrupoBien = i.GrupoBien
                    AND cat.ClaseBien = i.ClaseBien AND cat.FamiliaBien = i.FamiliaBien
                    AND cat.ItemBien = i.ItemBien
             WHERE i.IdRequerimiento = @IdRequerimiento AND i.Activo = 1
             ORDER BY i.Orden
               FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SELECT @resultado = N'{"estado":1'
            + N',"IdRequerimiento":' + sigcm.fnJsonValorTexto(CONVERT(nvarchar(36), r.IdRequerimiento))
            + N',"Codigo":' + sigcm.fnJsonValorTexto(r.Codigo)
            + N',"AnoEje":' + CASE WHEN r.AnoEje IS NULL THEN N'null' ELSE CONVERT(nvarchar(10), r.AnoEje) END
            + N',"SecEjec":' + CASE WHEN r.SecEjec IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), r.SecEjec) END
            + N',"CentroCosto":' + sigcm.fnJsonValorTexto(r.CentroCosto)
            + N',"Denominacion":' + sigcm.fnJsonValorTexto(r.Denominacion)
            + N',"CodigoTipoContratacion":' + sigcm.fnJsonValorTexto(r.CodigoTipoContratacion)
            + N',"TipoContratacion":' + sigcm.fnJsonValorTexto(tc.Nombre)
            + N',"CodigoDec":' + sigcm.fnJsonValorTexto(r.CodigoDec)
            + N',"CondicionCmn":' + sigcm.fnJsonValorTexto(r.CondicionCmn)
            + N',"IdSolicitudCmn":' + CASE WHEN r.IdSolicitudCmn IS NULL THEN N'null'
                                           ELSE sigcm.fnJsonValorTexto(CONVERT(nvarchar(36), r.IdSolicitudCmn)) END
            + N',"GeneradoDocumentoCmn":' + sigcm.fnJsonValorTexto(r.GeneradoDocumentoCmn)
            + N',"NombreDocumentoCmn":' + sigcm.fnJsonValorTexto(r.NombreDocumentoCmn)
            + N',"Monto":' + CASE WHEN r.Monto IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), r.Monto) END
            + N',"PlazoDias":' + CASE WHEN r.PlazoDias IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), r.PlazoDias) END
            + N',"FechaInicioPrevisto":' + CASE WHEN r.FechaInicioPrevisto IS NULL THEN N'null'
                                                ELSE sigcm.fnJsonValorTexto(CONVERT(varchar(10), r.FechaInicioPrevisto, 23)) END
            + N',"Ate":' + sigcm.fnJsonValorTexto(r.Ate)
            + N',"RucSugerido":' + sigcm.fnJsonValorTexto(r.RucSugerido)
            + N',"TieneDisponibilidad":' + CASE WHEN r.TieneDisponibilidad IS NULL THEN N'null'
                                                WHEN r.TieneDisponibilidad = 1 THEN N'true' ELSE N'false' END
            + N',"GeneradoDocumentoDisponibilidad":' + sigcm.fnJsonValorTexto(r.GeneradoDocumentoDisponibilidad)
            + N',"NombreDocumentoDisponibilidad":' + sigcm.fnJsonValorTexto(r.NombreDocumentoDisponibilidad)
            + N',"Sustento":' + sigcm.fnJsonValorTexto(r.Sustento)
            + N',"DatosAdicionales":' + CASE WHEN sigcm.fnEsJson(r.DatosAdicionales) = 1
                                             THEN r.DatosAdicionales
                                             ELSE ISNULL(sigcm.fnJsonValorTexto(r.DatosAdicionales), N'{}') END
            + N',"IdExpediente":' + sigcm.fnJsonValorTexto(CONVERT(nvarchar(36), e.IdExpediente))
            + N',"CodigoEstado":' + sigcm.fnJsonValorTexto(e.CodigoEstado)
            + N',"Version":' + CASE WHEN e.Version IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), e.Version) END
            + N',"Anulado":' + CASE WHEN e.Anulado IS NULL THEN N'null' WHEN e.Anulado = 1 THEN N'true' ELSE N'false' END
            + N',"Estado":' + sigcm.fnJsonValorTexto(w.Nombre)
            + N',"Responsable":' + sigcm.fnJsonValorTexto(LTRIM(RTRIM(ISNULL(u.Nombres, '') + N' ' + ISNULL(u.Apellidos, ''))))
            + N',"CentroCostoNombre":' + sigcm.fnJsonValorTexto(cc.NombreDepend)
            /* Si se apoya en una modificacion del CMN, se devuelve su
               codigo: el visor la muestra sin una segunda consulta. */
            + N',"SolicitudCmn":' + sigcm.fnJsonValorTexto((SELECT TOP 1 s.Codigo FROM cmn.Solicitud AS s
                                                             WHERE s.IdSolicitud = r.IdSolicitudCmn))
            + N',"Pedidos":' + @PedidosJson
            + N',"Items":' + @ItemsJson
            + N',"mensaje":"OK"}'
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
          JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
          JOIN sigcm.Usuario    AS u ON u.IdUsuario    = r.IdResponsable
          JOIN sigcm.TipoContratacion AS tc ON tc.CodigoTipoContratacion = r.CodigoTipoContratacion
          LEFT JOIN siga.vwCentroCosto AS cc
                 ON cc.AnoEje = r.AnoEje AND cc.SecEjec = r.SecEjec
                AND cc.CentroCosto = r.CentroCosto
         WHERE r.IdRequerimiento = @IdRequerimiento;

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N'}';
        SELECT @resultado;
    END CATCH
END
GO
