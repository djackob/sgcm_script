/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paObtenerTrazabilidad
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 3. sigcm.paObtenerTrazabilidad                                            */
/* ========================================================================== */

/* Historial, observaciones y cola de integracion de un expediente, que es lo que
   pide la pestania de trazabilidad del mockup. */
CREATE   PROCEDURE sigcm.paObtenerTrazabilidad
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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

        DECLARE @IdExpediente uniqueidentifier =
            sigcm.fnTryGuid(sigcm.fnJsonTexto(@parametro, 'IdExpediente'));

        IF @IdExpediente IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta IdExpediente.', 16, 1);

        DECLARE @Historial nvarchar(max), @Observaciones nvarchar(max), @Integracion nvarchar(max);

        SET @Historial = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"IdHistorial":' + CONVERT(nvarchar(20), h.IdHistorial)
                + N',"CodigoEstadoOrigen":' + sigcm.fnJsonValorTexto(h.CodigoEstadoOrigen)
                + N',"CodigoEstadoDestino":' + sigcm.fnJsonValorTexto(h.CodigoEstadoDestino)
                + N',"CodigoTransicion":' + sigcm.fnJsonValorTexto(h.CodigoTransicion)
                + N',"Comentario":' + sigcm.fnJsonValorTexto(h.Comentario)
                + N',"ActorRol":' + sigcm.fnJsonValorTexto(h.ActorRol)
                + N',"OcurridoEn":' + N'"' + CONVERT(varchar(23), h.OcurridoEn, 126) + N'"'
                + N',"Actor":' + sigcm.fnJsonValorTexto(LTRIM(RTRIM(ISNULL(u.Nombres, '') + ' ' + ISNULL(u.Apellidos, ''))))
                + N',"Unidad":' + sigcm.fnJsonValorTexto(n.Nombre)
                + N'}'
              FROM sigcm.Historial AS h
              JOIN sigcm.Usuario   AS u ON u.IdUsuario = h.IdActor
              LEFT JOIN sigcm.Unidad AS n ON n.IdUnidad = h.IdActorUnidad
             WHERE h.IdExpediente = @IdExpediente
             ORDER BY h.IdHistorial
               FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SET @Observaciones = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"IdObservacion":' + sigcm.fnJsonValorTexto(CONVERT(varchar(36), o.IdObservacion))
                + N',"CodigoRolOrigen":' + sigcm.fnJsonValorTexto(o.CodigoRolOrigen)
                + N',"CodigoEstadoRetorno":' + sigcm.fnJsonValorTexto(o.CodigoEstadoRetorno)
                + N',"Motivo":' + sigcm.fnJsonValorTexto(o.Motivo)
                + N',"Estado":' + sigcm.fnJsonValorTexto(o.Estado)
                + N',"Respuesta":' + sigcm.fnJsonValorTexto(o.Respuesta)
                + N',"FechaCreacionAuditoria":' + CASE WHEN o.FechaCreacionAuditoria IS NULL THEN N'null'
                                                       ELSE N'"' + CONVERT(varchar(23), o.FechaCreacionAuditoria, 126) + N'"' END
                + N',"RecepcionadaEn":' + CASE WHEN o.RecepcionadaEn IS NULL THEN N'null'
                                               ELSE N'"' + CONVERT(varchar(23), o.RecepcionadaEn, 126) + N'"' END
                + N',"SubsanadaEn":' + CASE WHEN o.SubsanadaEn IS NULL THEN N'null'
                                            ELSE N'"' + CONVERT(varchar(23), o.SubsanadaEn, 126) + N'"' END
                + N',"CerradaEn":' + CASE WHEN o.CerradaEn IS NULL THEN N'null'
                                          ELSE N'"' + CONVERT(varchar(23), o.CerradaEn, 126) + N'"' END
                + N'}'
              FROM sigcm.Observacion AS o
             WHERE o.IdExpediente = @IdExpediente AND o.Activo = 1
             ORDER BY o.FechaCreacionAuditoria
               FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SET @Integracion = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"IdOperacion":' + sigcm.fnJsonValorTexto(CONVERT(varchar(36), g.IdOperacion))
                + N',"Operacion":' + sigcm.fnJsonValorTexto(g.Operacion)
                + N',"Estado":' + sigcm.fnJsonValorTexto(g.Estado)
                + N',"Secuencia":' + CONVERT(nvarchar(20), g.Secuencia)
                + N',"Intentos":' + CONVERT(nvarchar(20), g.Intentos)
                + N',"MaxIntentos":' + CONVERT(nvarchar(20), g.MaxIntentos)
                + N',"ModoEjecucion":' + sigcm.fnJsonValorTexto(g.ModoEjecucion)
                + N',"ErrorCodigo":' + sigcm.fnJsonValorTexto(g.ErrorCodigo)
                + N',"ErrorMensaje":' + sigcm.fnJsonValorTexto(g.ErrorMensaje)
                + N',"FechaCreacionAuditoria":' + CASE WHEN g.FechaCreacionAuditoria IS NULL THEN N'null'
                                                       ELSE N'"' + CONVERT(varchar(23), g.FechaCreacionAuditoria, 126) + N'"' END
                + N',"CompletadoEn":' + CASE WHEN g.CompletadoEn IS NULL THEN N'null'
                                             ELSE N'"' + CONVERT(varchar(23), g.CompletadoEn, 126) + N'"' END
                + N'}'
              FROM integracion.Operacion AS g
             WHERE g.IdExpediente = @IdExpediente
             ORDER BY g.Secuencia, g.FechaCreacionAuditoria
               FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SET @resultado = N'{"estado":1'
            + N',"Historial":' + @Historial
            + N',"Observaciones":' + @Observaciones
            + N',"Integracion":' + @Integracion
            + N',"mensaje":"OK"}';

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
