/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paListarTransicionDisponible
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 1. sigcm.paListarTransicionDisponible                                     */
/* ========================================================================== */

/* Lo que el frontend necesita para pintar los botones de accion: que puede hacer
   ESTE actor con ESTE expediente ahora mismo. Calcularlo en el cliente seria
   duplicar la maquina de estados en TypeScript y que las dos se desincronicen. */
CREATE   PROCEDURE sigcm.paListarTransicionDisponible
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
            RAISERROR('VALIDACION_PAYLOAD: falta IdExpediente o no es un identificador valido.', 16, 1);

        DECLARE @CodigoEstado varchar(60), @CodigoModulo varchar(30), @Version int;
        SELECT @CodigoEstado = CodigoEstado, @CodigoModulo = CodigoModulo, @Version = Version
          FROM sigcm.Expediente
         WHERE IdExpediente = @IdExpediente AND Anulado = 0 AND Activo = 1;

        IF @CodigoEstado IS NULL
            RAISERROR('NO_ENCONTRADO: el expediente no existe o esta anulado.', 16, 1);

        DECLARE @Transiciones nvarchar(max);
        SET @Transiciones = N'[' + ISNULL(STUFF((
            SELECT N',' + N'{'
                + N'"CodigoTransicion":' + sigcm.fnJsonValorTexto(t.CodigoTransicion)
                + N',"NombreAccion":' + sigcm.fnJsonValorTexto(t.NombreAccion)
                + N',"CodigoEstadoDestino":' + sigcm.fnJsonValorTexto(t.CodigoEstadoDestino)
                + N',"EstadoDestino":' + sigcm.fnJsonValorTexto(d.Nombre)
                + N',"RequiereComentario":' + CASE WHEN t.RequiereComentario = 1 THEN N'true' ELSE N'false' END
                + N',"RequiereFirma":' + CASE WHEN t.RequiereFirma = 1 THEN N'true' ELSE N'false' END
                + N',"DocumentoRequerido":' + sigcm.fnJsonValorTexto(t.DocumentoRequerido)
                + N',"EncolaIntegracion":' + CASE WHEN t.EncolaIntegracion = 1 THEN N'true' ELSE N'false' END
                + N',"GeneraObservacion":' + CASE WHEN t.GeneraObservacion = 1 THEN N'true' ELSE N'false' END
                + N'}'
              FROM sigcm.Transicion AS t
              JOIN sigcm.Estado     AS d ON d.CodigoEstado = t.CodigoEstadoDestino
             WHERE t.CodigoModulo = @CodigoModulo
               AND t.CodigoEstadoOrigen = @CodigoEstado
               AND t.Activo = 1
               AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS r
                            WHERE r.CodigoTransicion = t.CodigoTransicion
                              AND r.CodigoRol = @CodigoRol)
             ORDER BY t.CodigoTransicion
               FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        SET @resultado = N'{"estado":1'
            + N',"IdExpediente":' + sigcm.fnJsonValorTexto(CONVERT(varchar(36), @IdExpediente))
            + N',"CodigoEstadoActual":' + sigcm.fnJsonValorTexto(@CodigoEstado)
            + N',"Version":' + CONVERT(nvarchar(20), @Version)
            + N',"Transiciones":' + @Transiciones
            + N',"mensaje":"OK"}';

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N',"Transiciones":[]}';
        SELECT @resultado;
    END CATCH
END
GO
