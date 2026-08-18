/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paRegistrarAuditoria
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 3. sigcm.paRegistrarAuditoria                                             */
/* ========================================================================== */

/*
  Bitacora de acciones. Es OTRA COSA que el cuarteto de auditoria de cada tabla:
  ese registra quien toco una fila; esta registra que se intento hacer, con que
  resultado y bajo que correlacion, incluidos los intentos DENEGADOS que nunca
  llegan a modificar ninguna fila.

  Prohibido pasar contrasenias, certificados o datos personales sensibles en
  @DatosAntes, @DatosDespues o @Metadata.
*/
CREATE   PROCEDURE sigcm.paRegistrarAuditoria
    @CorrelacionId uniqueidentifier,
    @CodigoModulo  varchar(30),
    @Entidad       varchar(80),
    @IdEntidad     uniqueidentifier = NULL,
    @Accion        varchar(80),
    @Resultado     varchar(15)      = 'OK',
    @IdActor       uniqueidentifier = NULL,
    @ActorCuenta   varchar(120),
    @ActorRol      varchar(40)      = NULL,
    @IdActorUnidad uniqueidentifier = NULL,
    @OrigenIp      varchar(45)      = NULL,
    @Equipo        varchar(50)      = NULL,
    @Programa      varchar(50)      = NULL,
    @DatosAntes    nvarchar(max)    = NULL,
    @DatosDespues  nvarchar(max)    = NULL,
    @Metadata      nvarchar(max)    = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO sigcm.EventoAuditoria
        (CorrelacionId, CodigoModulo, Entidad, IdEntidad, Accion, Resultado,
         IdActor, ActorCuenta, ActorRol, IdActorUnidad, OrigenIp, Equipo, Programa,
         DatosAntes, DatosDespues, Metadata)
    VALUES
        (@CorrelacionId, @CodigoModulo, @Entidad, @IdEntidad, @Accion, @Resultado,
         @IdActor, @ActorCuenta, @ActorRol, @IdActorUnidad, @OrigenIp, @Equipo, @Programa,
         CASE WHEN sigcm.fnEsJson(@DatosAntes)   = 1 THEN @DatosAntes   END,
         CASE WHEN sigcm.fnEsJson(@DatosDespues) = 1 THEN @DatosDespues END,
         CASE WHEN sigcm.fnEsJson(@Metadata)     = 1 THEN @Metadata ELSE N'{}' END);
END
GO
