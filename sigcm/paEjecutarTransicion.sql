/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paEjecutarTransicion
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 2. sigcm.paEjecutarTransicion                                             */
/* ========================================================================== */

CREATE   PROCEDURE sigcm.paEjecutarTransicion
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

        /* ---- Actor ---------------------------------------------------- */
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

        /* ---- Payload -------------------------------------------------- */
        DECLARE @IdExpediente    uniqueidentifier,
                @CodigoTransicion varchar(70),
                @VersionCliente  int,
                @Comentario      nvarchar(max),
                @IdUnidadDestino uniqueidentifier,
                @Datos           nvarchar(max);

        SET @IdExpediente     = sigcm.fnTryGuid(sigcm.fnJsonTexto(@parametro, 'IdExpediente'));
        SET @CodigoTransicion = sigcm.fnJsonTexto(@parametro, 'CodigoTransicion');
        SET @VersionCliente   = sigcm.fnJsonEntero(@parametro, 'Version');
        SET @Comentario       = sigcm.fnJsonTexto(@parametro, 'Comentario');
        SET @IdUnidadDestino  = sigcm.fnTryGuid(sigcm.fnJsonTexto(@parametro, 'IdUnidadDestino'));
        SET @Datos            = sigcm.fnJsonTexto(@parametro, 'Datos');

        IF @IdExpediente IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta IdExpediente o no es un identificador valido.', 16, 1);
        IF NULLIF(LTRIM(RTRIM(@CodigoTransicion)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta CodigoTransicion.', 16, 1);

        /* ---- Expediente ----------------------------------------------- */
        DECLARE @EstadoActual varchar(60), @CodigoModulo varchar(30),
                @VersionActual int, @CodigoExpediente varchar(40);

        SELECT @EstadoActual     = CodigoEstado,
               @CodigoModulo     = CodigoModulo,
               @VersionActual    = Version,
               @CodigoExpediente = Codigo
          FROM sigcm.Expediente
         WHERE IdExpediente = @IdExpediente AND Anulado = 0 AND Activo = 1;

        IF @EstadoActual IS NULL
            RAISERROR('NO_ENCONTRADO: el expediente no existe o esta anulado.', 16, 1);

        IF @VersionCliente IS NOT NULL AND @VersionCliente <> @VersionActual
        BEGIN
            DECLARE @errVer nvarchar(400);
            SET @errVer = 'CONFLICTO_VERSION: el expediente va por la version '
                + ISNULL(CONVERT(varchar(11), @VersionActual), '')
                + ' y usted trabajo sobre la '
                + ISNULL(CONVERT(varchar(11), @VersionCliente), '')
                + '. Vuelva a cargarlo: otra persona lo movio mientras tanto.';
            RAISERROR(@errVer, 16, 1);
        END

        /* ---- Transicion ----------------------------------------------- */
        DECLARE @EstadoDestino varchar(60), @NombreAccion varchar(180),
                @RequiereComentario bit, @RequiereFirma bit,
                @DocumentoRequerido varchar(60), @EncolaIntegracion bit,
                @OperacionIntegracion varchar(30), @GeneraObservacion bit;

        SELECT @EstadoDestino        = CodigoEstadoDestino,
               @NombreAccion         = NombreAccion,
               @RequiereComentario   = RequiereComentario,
               @RequiereFirma        = RequiereFirma,
               @DocumentoRequerido   = DocumentoRequerido,
               @EncolaIntegracion    = EncolaIntegracion,
               @OperacionIntegracion = OperacionIntegracion,
               @GeneraObservacion    = GeneraObservacion
          FROM sigcm.Transicion
         WHERE CodigoTransicion   = @CodigoTransicion
           AND CodigoModulo       = @CodigoModulo
           AND CodigoEstadoOrigen = @EstadoActual
           AND Activo = 1;

        IF @EstadoDestino IS NULL
        BEGIN
            DECLARE @errTr nvarchar(500);
            SET @errTr = 'CONFLICTO_TRANSICION: "' + ISNULL(@CodigoTransicion, '')
                + '" no es una transicion valida desde el estado ' + ISNULL(@EstadoActual, '') + '.';
            RAISERROR(@errTr, 16, 1);
        END

        /* El rol se comprueba contra la tabla, no contra una lista en codigo. */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol
                        WHERE CodigoTransicion = @CodigoTransicion AND CodigoRol = @CodigoRol)
        BEGIN
            DECLARE @errRol nvarchar(500);
            SET @errRol = 'NO_AUTORIZADO: el rol ' + ISNULL(@CodigoRol, '')
                + ' no puede ejecutar "' + ISNULL(@NombreAccion, '') + '".';
            RAISERROR(@errRol, 16, 1);
        END

        IF @RequiereComentario = 1 AND NULLIF(LTRIM(RTRIM(@Comentario)), '') IS NULL
        BEGIN
            DECLARE @errCom nvarchar(400);
            SET @errCom = 'VALIDACION_COMENTARIO: "' + ISNULL(@NombreAccion, '')
                + '" exige registrar el motivo.';
            RAISERROR(@errCom, 16, 1);
        END

        /* El documento debe existir, estar vigente y FIRMADO. Que exista un
           borrador no basta: es justamente lo que la firma pretende impedir. */
        IF @DocumentoRequerido IS NOT NULL
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                  FROM sigcm.DocumentoExpediente AS de
                  JOIN sigcm.Documento           AS d  ON d.IdDocumento = de.IdDocumento
                  JOIN sigcm.DocumentoVersion    AS dv ON dv.IdDocumento = d.IdDocumento
                                                      AND dv.Version = d.VersionVigente
                 WHERE de.IdExpediente = @IdExpediente
                   AND d.CodigoTipoDocumento = @DocumentoRequerido
                   AND d.Anulado = 0 AND d.Activo = 1
                   AND dv.Estado = 'FIRMADO')
            BEGIN
                DECLARE @errDoc nvarchar(500);
                SET @errDoc = 'CONFLICTO_DOCUMENTO: "' + ISNULL(@NombreAccion, '')
                    + '" exige el documento ' + ISNULL(@DocumentoRequerido, '')
                    + ' en su version vigente y firmado.';
                RAISERROR(@errDoc, 16, 1);
            END
        END

        /* ---- Enrutamiento: a que unidad y a quien queda ---------------- */
        /*
          El estado destino declara el ROL responsable. La UNIDAD no se puede
          deducir del rol en general: dos areas usuarias distintas tienen ambas un
          AREA_JEFE. Por eso:

            1. Si el cliente manda IdUnidadDestino, manda eso.
            2. Si no, y exactamente una unidad tiene asignado hoy ese rol, se usa
               esa. Es el caso de OA y Abastecimiento, que son unicas.
            3. Si no, se conserva la unidad actual. Es el caso de las
               transiciones internas del area usuaria (especialista -> jefe).
        */
        DECLARE @RolDestino varchar(40), @IdUnidadActualExp uniqueidentifier;
        SELECT @RolDestino = RolResponsable FROM sigcm.Estado WHERE CodigoEstado = @EstadoDestino;
        SELECT @IdUnidadActualExp = IdUnidadActual FROM sigcm.Expediente WHERE IdExpediente = @IdExpediente;

        IF @IdUnidadDestino IS NULL AND @RolDestino IS NOT NULL
        BEGIN
            DECLARE @Candidatas int;
            SELECT @Candidatas = COUNT(DISTINCT ur.IdUnidad)
              FROM sigcm.UsuarioRol AS ur
             WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1
               AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()));

            IF @Candidatas = 1
                SELECT @IdUnidadDestino = MIN(ur.IdUnidad)
                  FROM sigcm.UsuarioRol AS ur
                 WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1
                   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()));
        END

        SET @IdUnidadDestino = ISNULL(@IdUnidadDestino, @IdUnidadActualExp);

        /* El responsable concreto se deja sin fijar: la bandeja se resuelve por
           rol y unidad, y asignar a una persona en una unidad con varios titulares
           seria inventar una regla que la Directiva no establece. */
        DECLARE @IdResponsable uniqueidentifier = NULL;

        /* ---- Escritura ------------------------------------------------ */
        DECLARE @Ahora datetime = GETDATE();
        DECLARE @VersionNueva int = @VersionActual + 1;
        DECLARE @Encoladas int = 0;
        DECLARE @IdObservacion uniqueidentifier = NULL;

        BEGIN TRANSACTION;

        /* La condicion sobre Version es el candado de concurrencia optimista:
           si otro proceso avanzo el expediente entre la lectura y este UPDATE,
           no se afecta ninguna fila. */
        UPDATE sigcm.Expediente
           SET CodigoEstado                  = @EstadoDestino,
               Version                       = @VersionNueva,
               IdUnidadActual                = @IdUnidadDestino,
               IdResponsableActual           = @IdResponsable,
               CerradoEn                     = CASE WHEN EXISTS (SELECT 1 FROM sigcm.Estado
                                                                  WHERE CodigoEstado = @EstadoDestino
                                                                    AND EsFinal = 1)
                                                    THEN @Ahora ELSE CerradoEn END,
               UsuarioModificacionAuditoria  = @Cuenta,
               FechaModificacionAuditoria    = @Ahora,
               EquipoModificacionAuditoria   = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdExpediente = @IdExpediente
           AND Version      = @VersionActual;

        IF @@ROWCOUNT = 0
            RAISERROR('CONFLICTO_VERSION: otra persona movio el expediente en este instante. Vuelva a cargarlo.', 16, 1);

        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
             Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExpediente, @EstadoActual, @EstadoDestino, @CodigoTransicion,
             @Comentario, @IdUsuario, @CodigoRol, @IdUnidad,
             CASE WHEN sigcm.fnEsJson(@Datos) = 1 THEN @Datos ELSE N'{}' END,
             @Cuenta, @Equipo, @Programa);

        /* ---- Observacion ---------------------------------------------- */
        /*
          CodigoEstadoRetorno se toma del estado en que ESTABA el expediente al
          observarse. Ahi vive la regla del mockup: lo que observa OA vuelve a OA,
          lo que observa Abastecimiento vuelve a Abastecimiento. Es dato, no un
          condicional por unidad.
        */
        IF @GeneraObservacion = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM sigcm.Observacion
                        WHERE IdExpediente = @IdExpediente
                          AND Estado IN ('PENDIENTE','RECEPCIONADA') AND Activo = 1)
                RAISERROR('CONFLICTO_OBSERVACION: el expediente ya tiene una observacion abierta.', 16, 1);

            DECLARE @UnidadOrigenExp uniqueidentifier;
            SELECT @UnidadOrigenExp = IdUnidadOrigen FROM sigcm.Expediente WHERE IdExpediente = @IdExpediente;

            DECLARE @Obs TABLE (IdObservacion uniqueidentifier);

            INSERT INTO sigcm.Observacion
                (IdExpediente, IdUnidadOrigen, CodigoRolOrigen, IdUnidadDestino,
                 CodigoEstadoRetorno, Motivo, Estado,
                 UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                 EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            OUTPUT inserted.IdObservacion INTO @Obs
            VALUES
                (@IdExpediente, @IdUnidad, @CodigoRol, @UnidadOrigenExp,
                 @EstadoActual, @Comentario, 'PENDIENTE',
                 @Cuenta, @Ahora, @Equipo, @Programa);

            SELECT @IdObservacion = IdObservacion FROM @Obs;
        END

        /* ---- Encolado hacia SIGA -------------------------------------- */
        /*
          Aqui, y solo aqui, el motor generico se vuelve especifico del modulo.

          La clave de idempotencia es determinista: {solicitud}:{item}:{version}:
          {operacion}. Un reintento con la misma clave choca contra el indice
          unico y no puede duplicar el registro en SIGA. Es la unica garantia real
          contra el doble registro, y por eso el outbox se conserva aunque ambas
          bases compartan instancia.
        */
        IF @EncolaIntegracion = 1
        BEGIN
            IF @OperacionIntegracion = 'ITEMS_ANEXO_3'
            BEGIN
                /* Anexo 3 validado: una operacion por item, derivando el verbo de
                   su TipoMovimiento. Escriben en SIG_CUADRO_MODIFICADO_DET y
                   _SALDO. */
                INSERT INTO integracion.Operacion
                    (IdempotenciaKey, IdExpediente, IdSolicitud, IdSolicitudItem,
                     Operacion, Procedimiento, Secuencia, Estado, RequestJson,
                     UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                     EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                SELECT
                    ISNULL(CONVERT(varchar(36), s.IdSolicitud), '') + ':'
                        + ISNULL(CONVERT(varchar(36), i.IdSolicitudItem), '') + ':'
                        + ISNULL(CONVERT(varchar(10), @VersionNueva), '') + ':'
                        + CASE i.TipoMovimiento
                               WHEN 'INCLUSION'    THEN 'INCLUIR_ITEM'
                               WHEN 'EXCLUSION'    THEN 'EXCLUIR_ITEM'
                               ELSE 'MODIFICAR_CANTIDADES' END,
                    @IdExpediente, s.IdSolicitud, i.IdSolicitudItem,
                    CASE i.TipoMovimiento
                         WHEN 'INCLUSION' THEN 'INCLUIR_ITEM'
                         WHEN 'EXCLUSION' THEN 'EXCLUIR_ITEM'
                         ELSE 'MODIFICAR_CANTIDADES' END,
                    'integracion.paEscribirCuadroModificado',
                    i.Orden,
                    'PENDIENTE',
                    N'{'
                        + N'"AnoEje":' + CONVERT(nvarchar(20), s.AnoEje)
                        + N',"SecEjec":' + CONVERT(nvarchar(20), s.SecEjec)
                        + N',"CentroCosto":' + sigcm.fnJsonValorTexto(s.CentroCosto)
                        + N',"TipoMovimiento":' + sigcm.fnJsonValorTexto(i.TipoMovimiento)
                        + N',"RefSecCuadro":' + CASE WHEN i.RefSecCuadro IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), i.RefSecCuadro) END
                        + N',"RefSecItem":' + CASE WHEN i.RefSecItem IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), i.RefSecItem) END
                        + N',"TipoTarea":' + sigcm.fnJsonValorTexto(i.TipoTarea)
                        + N',"NivelTarea":' + sigcm.fnJsonValorTexto(i.NivelTarea)
                        + N',"CodigoTarea":' + CONVERT(nvarchar(40), i.CodigoTarea)
                        + N',"SecFunc":' + CONVERT(nvarchar(20), i.SecFunc)
                        + N',"SecFuncProp":' + CASE WHEN i.SecFuncProp IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), i.SecFuncProp) END
                        + N',"Origen":' + sigcm.fnJsonValorTexto(i.Origen)
                        + N',"FuenteFinanc":' + sigcm.fnJsonValorTexto(i.FuenteFinanc)
                        + N',"Clasificador":' + sigcm.fnJsonValorTexto(i.Clasificador)
                        + N',"TipoRecurso":' + sigcm.fnJsonValorTexto(i.TipoRecurso)
                        + N',"TipoPpto":' + CONVERT(nvarchar(20), i.TipoPpto)
                        + N',"TipoUso":' + sigcm.fnJsonValorTexto(i.TipoUso)
                        + N',"TipoBien":' + sigcm.fnJsonValorTexto(i.TipoBien)
                        + N',"GrupoBien":' + sigcm.fnJsonValorTexto(i.GrupoBien)
                        + N',"ClaseBien":' + sigcm.fnJsonValorTexto(i.ClaseBien)
                        + N',"FamiliaBien":' + sigcm.fnJsonValorTexto(i.FamiliaBien)
                        + N',"ItemBien":' + sigcm.fnJsonValorTexto(i.ItemBien)
                        + N',"UnidadMedida":' + CONVERT(nvarchar(20), i.UnidadMedida)
                        + N',"PrecioUnitario":' + CONVERT(nvarchar(40), i.PrecioUnitario)
                        + N',"Periodos":' + N'[' + ISNULL(STUFF((
                            SELECT N',' + N'{'
                                + N'"AnoOffset":' + CONVERT(nvarchar(20), p.AnoOffset)
                                + N',"Mes":' + CONVERT(nvarchar(20), p.Mes)
                                + N',"Cantidad":' + CONVERT(nvarchar(40), p.Cantidad)
                                + N',"Monto":' + CONVERT(nvarchar(40), p.Monto)
                                + N'}'
                              FROM cmn.SolicitudItemPeriodo AS p
                             WHERE p.IdSolicitudItem = i.IdSolicitudItem
                             ORDER BY p.AnoOffset, p.Mes
                               FOR XML PATH(N''), TYPE
                          ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']'
                        + N'}',
                    @Cuenta, @Ahora, @Equipo, @Programa
                  FROM cmn.Solicitud     AS s
                  JOIN cmn.SolicitudItem AS i ON i.IdSolicitud = s.IdSolicitud AND i.Activo = 1
                 WHERE s.IdExpediente = @IdExpediente AND s.Activo = 1;

                SET @Encoladas = @@ROWCOUNT;
            END
            ELSE IF @OperacionIntegracion = 'CONSOLIDAR_CMN'
            BEGIN
                /* Anexo 4 firmado: una sola operacion por solicitud. Escribe en
                   SIG_CUADRO_MODIFICADO_CMN, que segun los datos de 2026 no se
                   puebla hasta la consolidacion. */
                INSERT INTO integracion.Operacion
                    (IdempotenciaKey, IdExpediente, IdSolicitud, IdSolicitudItem,
                     Operacion, Procedimiento, Secuencia, Estado, RequestJson,
                     UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                     EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                SELECT
                    ISNULL(CONVERT(varchar(36), s.IdSolicitud), '') + '::'
                        + ISNULL(CONVERT(varchar(10), @VersionNueva), '') + ':CONSOLIDAR_CMN',
                    @IdExpediente, s.IdSolicitud, NULL,
                    'CONSOLIDAR_CMN', 'integracion.paEscribirCuadroModificado', 1, 'PENDIENTE',
                    N'{'
                        + N'"AnoEje":' + CONVERT(nvarchar(20), s.AnoEje)
                        + N',"SecEjec":' + CONVERT(nvarchar(20), s.SecEjec)
                        + N',"CentroCosto":' + sigcm.fnJsonValorTexto(s.CentroCosto)
                        + N',"Codigo":' + sigcm.fnJsonValorTexto(s.Codigo)
                        + N',"Items":' + CONVERT(nvarchar(20), (
                              SELECT COUNT(*) FROM cmn.SolicitudItem AS i2
                               WHERE i2.IdSolicitud = s.IdSolicitud AND i2.Activo = 1))
                        + N'}',
                    @Cuenta, @Ahora, @Equipo, @Programa
                  FROM cmn.Solicitud AS s
                 WHERE s.IdExpediente = @IdExpediente AND s.Activo = 1;

                SET @Encoladas = @@ROWCOUNT;
            END
            ELSE
            BEGIN
                DECLARE @errOp nvarchar(400);
                SET @errOp = 'CONFLICTO_CONFIGURACION: la transicion declara EncolaIntegracion pero "'
                    + ISNULL(@OperacionIntegracion, '')
                    + '" no tiene expansion definida en F004.';
                RAISERROR(@errOp, 16, 1);
            END
        END

        COMMIT TRANSACTION;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = @CodigoModulo,
             @Entidad = 'sigcm.Expediente', @IdEntidad = @IdExpediente,
             @Accion = @CodigoTransicion, @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta,
             @ActorRol = @CodigoRol, @IdActorUnidad = @IdUnidad,
             @OrigenIp = @Ip, @Equipo = @Equipo, @Programa = @Programa;

        SET @resultado = N'{"estado":1'
            + N',"IdExpediente":' + sigcm.fnJsonValorTexto(CONVERT(varchar(36), @IdExpediente))
            + N',"Codigo":' + sigcm.fnJsonValorTexto(@CodigoExpediente)
            + N',"CodigoEstadoAnterior":' + sigcm.fnJsonValorTexto(@EstadoActual)
            + N',"CodigoEstado":' + sigcm.fnJsonValorTexto(@EstadoDestino)
            + N',"Version":' + CONVERT(nvarchar(20), @VersionNueva)
            + N',"OperacionesEncoladas":' + CONVERT(nvarchar(20), @Encoladas)
            + N',"IdObservacion":' + CASE WHEN @IdObservacion IS NULL THEN N'null'
                                          ELSE sigcm.fnJsonValorTexto(CONVERT(varchar(36), @IdObservacion)) END
            + N',"mensaje":' + sigcm.fnJsonValorTexto(N'Se registro la accion satisfactoriamente.')
            + N'}';

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
