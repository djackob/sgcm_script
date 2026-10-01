/*
===============================================================================
  SIGCM - F028 : Visto bueno previo a la firma del Acta (Anexo 11)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 52800-52849

  Con el acta por firmar, el Jefe o la Secretaria del area usuaria derivan el
  expediente a una persona por cada fila del 8.1 del Anexo 3. Las personas
  responden una por una. El jefe firma el Anexo 11 y envia a Administracion
  solo con la ronda completa (pago.fnAccionVistoBuenoFirma, F012).

    pago.paListarCandidatoVistoBueno  filas del 8.1 con las personas que
                                      ejercen ese perfil en esa unidad
    pago.paDerivarVistoBuenoFirma     abre una ronda y la envia al primer paso
    pago.paResponderVistoBuenoFirma   el paso pendiente otorga u observa
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. pago.paListarCandidatoVistoBueno                                       */
/* ========================================================================== */

/*
  Entrada: { "Actor":{...}, "IdExpediente":"..." }
  Salida : { "estado":1, "Pasos":[ { Orden, NombreUnidad, NombreRol,
             IdUsuarioSugerido, Personas:[ { IdUsuario, NombreCompleto, Cargo } ] } ] }

  IdUsuarioSugerido es quien atendio ese paso en la ronda anterior, para que
  una nueva derivacion tras una observacion no obligue a elegir de nuevo.
*/
CREATE OR ALTER PROCEDURE pago.paListarCandidatoVistoBueno
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52800, 'JSON incorrecto.', 1;

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
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        IF @IdExpediente IS NULL
            THROW 52801, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @IdPago uniqueidentifier;
        SELECT @IdPago = p.IdExpedientePago
          FROM pago.ExpedientePago AS p
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;
        IF @IdPago IS NULL
            THROW 52802, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        DECLARE @Hoy date = CONVERT(date, GETDATE());
        DECLARE @RondaPrevia smallint =
            (SELECT MAX(v.Ronda) FROM pago.VistoBuenoFirma AS v WHERE v.IdExpedientePago = @IdPago);

        SELECT (
            SELECT 1 AS estado,
                   Pasos = JSON_QUERY(COALESCE((
                       SELECT rv.Orden, rv.IdUnidad, rv.CodigoRol, rv.NombreUnidad, rv.NombreRol,
                              IdUsuarioSugerido = (SELECT v.IdUsuarioDestino
                                                     FROM pago.VistoBuenoFirma AS v
                                                    WHERE v.IdExpedientePago = @IdPago
                                                      AND v.Ronda = @RondaPrevia
                                                      AND v.Orden = rv.Orden),
                              Personas = JSON_QUERY(COALESCE((
                                  SELECT IdUsuario = u.IdUsuario,
                                         NombreCompleto = CONCAT_WS(' ', u.Nombres, u.Apellidos),
                                         u.Cargo, ur.EsTitular
                                    FROM sigcm.UsuarioRol AS ur
                                    JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
                                   WHERE ur.IdUnidad = rv.IdUnidad
                                     AND ur.CodigoRol = rv.CodigoRol
                                     AND ur.Activo = 1 AND u.Activo = 1
                                     AND ur.VigenteDesde <= @Hoy
                                     AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @Hoy)
                                   ORDER BY ur.EsTitular DESC, u.Nombres, u.Apellidos
                                     FOR JSON PATH), N'[]'))
                         FROM pago.RutaInformePrevio AS rv
                        WHERE rv.IdExpedientePago = @IdPago
                        ORDER BY rv.Orden
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 2. pago.paDerivarVistoBuenoFirma                                          */
/* ========================================================================== */

/*
  Entrada: { "Actor":{...}, "IdExpediente":"...", "Version":n, "Comentario":"...",
             "Destinatarios":[ { "Orden":1, "IdUsuario":"..." } ] }

  Exige una persona por cada fila del 8.1 que ejerza ese perfil en esa unidad.
  Abre la ronda siguiente y deja el expediente en la unidad y a nombre de la
  persona del primer paso.
*/
CREATE OR ALTER PROCEDURE pago.paDerivarVistoBuenoFirma
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52810, 'JSON incorrecto.', 1;

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
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        IF @IdExpediente IS NULL
            THROW 52811, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        IF @CodigoRol NOT IN ('AREA_JEFE', 'AREA_SECRETARIA')
            THROW 52812, 'NO_AUTORIZADO: solo el Jefe o la Secretaria del area usuaria derivan para visto bueno.', 1;

        DECLARE @IdPago uniqueidentifier, @Estado varchar(60), @Version int,
                @IdUnidadActual uniqueidentifier;
        SELECT @IdPago = p.IdExpedientePago, @Estado = e.CodigoEstado, @Version = e.Version,
               @IdUnidadActual = e.IdUnidadActual
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 52813, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;
        IF @Estado <> 'PAG_CONFORMIDAD_PEND_FIRMA'
            THROW 52814, 'CONFLICTO_ESTADO: el expediente no esta con el acta por firmar.', 1;
        IF @IdUnidadActual <> @IdUnidad
            THROW 52815, 'NO_AUTORIZADO: el expediente esta en otra unidad.', 1;
        IF pago.fnAccionVistoBuenoFirma(@IdPago, 'PAG_DERIVAR_VB_FIRMA', @IdUsuario, @CodigoRol, @IdUnidad) = 0
            THROW 52816, 'CONFLICTO_RUTA: el expediente no tiene vistos buenos pendientes de derivar.', 1;

        DECLARE @Hoy date = CONVERT(date, GETDATE());
        DECLARE @Dest TABLE (Orden smallint PRIMARY KEY, IdUsuario uniqueidentifier NULL);
        INSERT INTO @Dest (Orden, IdUsuario)
        SELECT d.Orden, MAX(TRY_CONVERT(uniqueidentifier, d.IdUsuario))
          FROM OPENJSON(@parametro, '$.Destinatarios')
               WITH (Orden smallint, IdUsuario varchar(50)) AS d
         WHERE d.Orden IS NOT NULL
         GROUP BY d.Orden;

        DECLARE @Falta nvarchar(400);
        SELECT TOP 1 @Falta = CONCAT(rv.NombreUnidad, CASE WHEN rv.NombreRol IS NOT NULL
                                                        THEN CONCAT(N' - ', rv.NombreRol) END)
          FROM pago.RutaInformePrevio AS rv
          LEFT JOIN @Dest AS d ON d.Orden = rv.Orden
         WHERE rv.IdExpedientePago = @IdPago
           AND NOT EXISTS (SELECT 1
                             FROM sigcm.UsuarioRol AS ur
                             JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
                            WHERE ur.IdUsuario = d.IdUsuario
                              AND ur.IdUnidad = rv.IdUnidad
                              AND ur.CodigoRol = rv.CodigoRol
                              AND ur.Activo = 1 AND u.Activo = 1
                              AND ur.VigenteDesde <= @Hoy
                              AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @Hoy))
         ORDER BY rv.Orden;

        IF @Falta IS NOT NULL
        BEGIN
            DECLARE @errFalta nvarchar(500) = CONCAT(
                N'VALIDACION_PAYLOAD: seleccione la persona que otorga el visto bueno en ', @Falta, N'.');
            THROW 52817, @errFalta, 1;
        END

        DECLARE @Ronda smallint = 1 + ISNULL(
            (SELECT MAX(v.Ronda) FROM pago.VistoBuenoFirma AS v WHERE v.IdExpedientePago = @IdPago), 0);

        DECLARE @IdUnidadPrimera uniqueidentifier, @IdUsuarioPrimero uniqueidentifier;
        SELECT TOP 1 @IdUnidadPrimera = rv.IdUnidad, @IdUsuarioPrimero = d.IdUsuario
          FROM pago.RutaInformePrevio AS rv
          JOIN @Dest AS d ON d.Orden = rv.Orden
         WHERE rv.IdExpedientePago = @IdPago
         ORDER BY rv.Orden;

        BEGIN TRANSACTION;

        UPDATE pago.VistoBuenoFirma
           SET Estado = 'ANULADO'
         WHERE IdExpedientePago = @IdPago AND Estado = 'PENDIENTE';

        INSERT INTO pago.VistoBuenoFirma
              (IdExpedientePago, Ronda, Orden, IdUnidad, CodigoRol, NombreUnidad, NombreRol,
               IdUsuarioDestino, NombreUsuarioDestino, IdUsuarioDeriva)
        SELECT @IdPago, @Ronda, rv.Orden, rv.IdUnidad, rv.CodigoRol, rv.NombreUnidad, rv.NombreRol,
               d.IdUsuario, CONCAT_WS(' ', u.Nombres, u.Apellidos), @IdUsuario
          FROM pago.RutaInformePrevio AS rv
          JOIN @Dest AS d ON d.Orden = rv.Orden
          JOIN sigcm.Usuario AS u ON u.IdUsuario = d.IdUsuario
         WHERE rv.IdExpedientePago = @IdPago;

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'PAG_DERIVAR_VB_FIRMA');
        SET @parametro = JSON_MODIFY(@parametro, '$.IdUnidadDestino', CONVERT(varchar(36), @IdUnidadPrimera));
        SET @parametro = JSON_MODIFY(@parametro, '$.IdResponsableDestino', NULL);
        SET @parametro = JSON_MODIFY(@parametro, '$.Destinatarios', NULL);
        IF NULLIF(JSON_VALUE(@parametro, '$.Comentario'), N'') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Comentario',
                CONCAT(N'Derivado para visto bueno previo a la firma del Acta (ronda ', @Ronda, N').'));
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;

        IF (SELECT e.Version FROM sigcm.Expediente AS e WHERE e.IdExpediente = @IdExpediente) = @Version + 1
        BEGIN
            /* paEjecutarTransicion solo acepta responsables del arbol de
               derivacion; la persona del 8.1 se fija aqui. */
            UPDATE sigcm.Expediente
               SET IdResponsableActual = @IdUsuarioPrimero
             WHERE IdExpediente = @IdExpediente;

            IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
        END
        ELSE IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 3. pago.paResponderVistoBuenoFirma                                        */
/* ========================================================================== */

/*
  Entrada: { "Actor":{...}, "IdExpediente":"...", "Version":n,
             "Respuesta":"OTORGAR" | "OBSERVAR", "Comentario":"...",
             "GeneradoDocumento":"...", "NombreDocumento":"..." }

  OTORGAR con pasos pendientes: el estado no cambia (sigcm.Transicion no admite
  origen = destino); pasa la unidad y la persona del siguiente paso.
  OTORGAR en el ultimo paso, u OBSERVAR en cualquiera: el acta vuelve al jefe
  del area usuaria. La observacion cierra la ronda.
*/
CREATE OR ALTER PROCEDURE pago.paResponderVistoBuenoFirma
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52830, 'JSON incorrecto.', 1;

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
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @Respuesta varchar(10) = UPPER(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Respuesta'))));
        DECLARE @Comentario nvarchar(2000) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Comentario'))), N'');
        DECLARE @Documento nvarchar(200) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.GeneradoDocumento'))), N'');
        DECLARE @NombreDoc nvarchar(260) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.NombreDocumento'))), N'');

        IF @IdExpediente IS NULL
            THROW 52831, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @Respuesta IS NULL OR @Respuesta NOT IN ('OTORGAR', 'OBSERVAR')
            THROW 52832, 'VALIDACION_PAYLOAD: indique si otorga u observa.', 1;
        IF @Respuesta = 'OBSERVAR' AND @Comentario IS NULL
            THROW 52833, 'VALIDACION_PAYLOAD: registre las observaciones.', 1;

        DECLARE @IdPago uniqueidentifier, @Estado varchar(60), @Version int,
                @IdUnidadOrigen uniqueidentifier;
        SELECT @IdPago = p.IdExpedientePago, @Estado = e.CodigoEstado, @Version = e.Version,
               @IdUnidadOrigen = e.IdUnidadOrigen
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 52834, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;
        IF @Estado <> 'PAG_VB_PREVIO_FIRMA'
            THROW 52835, 'CONFLICTO_ESTADO: el expediente no esta pendiente de visto bueno previo a la firma.', 1;

        DECLARE @Ronda smallint =
            (SELECT MAX(v.Ronda) FROM pago.VistoBuenoFirma AS v WHERE v.IdExpedientePago = @IdPago);

        DECLARE @IdVb uniqueidentifier, @Orden smallint, @NombreDestino nvarchar(250);
        SELECT TOP 1 @IdVb = v.IdVistoBueno, @Orden = v.Orden, @NombreDestino = v.NombreUsuarioDestino
          FROM pago.VistoBuenoFirma AS v
         WHERE v.IdExpedientePago = @IdPago AND v.Ronda = @Ronda AND v.Estado = 'PENDIENTE'
         ORDER BY v.Orden;

        IF @IdVb IS NULL
            THROW 52836, 'CONFLICTO_RUTA: este expediente no tiene un visto bueno pendiente.', 1;

        IF pago.fnAccionVistoBuenoFirma(@IdPago, 'PAG_OTORGAR_VB_FIRMA', @IdUsuario, @CodigoRol, @IdUnidad) = 0
        BEGIN
            DECLARE @errDest nvarchar(500) = CONCAT(
                N'NO_AUTORIZADO: el visto bueno pendiente le corresponde a ', @NombreDestino, N'.');
            THROW 52837, @errDest, 1;
        END

        DECLARE @IdUnidadSig uniqueidentifier, @IdUsuarioSig uniqueidentifier;
        IF @Respuesta = 'OTORGAR'
            SELECT TOP 1 @IdUnidadSig = v.IdUnidad, @IdUsuarioSig = v.IdUsuarioDestino
              FROM pago.VistoBuenoFirma AS v
             WHERE v.IdExpedientePago = @IdPago AND v.Ronda = @Ronda
               AND v.Estado = 'PENDIENTE' AND v.Orden > @Orden
             ORDER BY v.Orden;

        DECLARE @VersionCliente int = TRY_CONVERT(int, JSON_VALUE(@parametro, '$.Version'));
        IF @VersionCliente IS NOT NULL AND @VersionCliente <> @Version
            THROW 52838, 'CONFLICTO_VERSION: el expediente cambio mientras lo revisaba. Vuelva a abrirlo.', 1;

        BEGIN TRANSACTION;

        UPDATE pago.VistoBuenoFirma
           SET Estado = CASE WHEN @Respuesta = 'OTORGAR' THEN 'OTORGADO' ELSE 'OBSERVADO' END,
               Comentario = @Comentario,
               GeneradoDocumento = @Documento,
               NombreDocumento = CASE WHEN @Documento IS NOT NULL THEN @NombreDoc END,
               RespondidoEn = GETDATE()
         WHERE IdVistoBueno = @IdVb AND Estado = 'PENDIENTE';

        IF @@ROWCOUNT <> 1
            THROW 52839, 'CONFLICTO_RUTA: el paso ya fue respondido.', 1;

        IF @Respuesta = 'OBSERVAR'
            UPDATE pago.VistoBuenoFirma
               SET Estado = 'ANULADO'
             WHERE IdExpedientePago = @IdPago AND Ronda = @Ronda AND Estado = 'PENDIENTE';

        IF @IdUnidadSig IS NOT NULL
        BEGIN
            UPDATE sigcm.Expediente
               SET IdUnidadActual = @IdUnidadSig,
                   IdResponsableActual = @IdUsuarioSig,
                   Version = @Version + 1,
                   UsuarioModificacionAuditoria = LEFT(@Cuenta, 30),
                   FechaModificacionAuditoria = GETDATE(),
                   EquipoModificacionAuditoria = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdExpediente = @IdExpediente AND Version = @Version;

            IF @@ROWCOUNT <> 1
                THROW 52838, 'CONFLICTO_VERSION: el expediente cambio mientras lo revisaba. Vuelva a abrirlo.', 1;

            INSERT INTO sigcm.Historial
                (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
                 Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
                 UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdExpediente, @Estado, @Estado, NULL,
                 COALESCE(@Comentario,
                          CONCAT(N'Visto bueno previo a la firma otorgado (paso ', @Orden, N'). Pasa al siguiente perfil.')),
                 @IdUsuario, @CodigoRol, @IdUnidad,
                 (SELECT @Ronda AS Ronda, @Orden AS PasoOtorgado, @IdUnidadSig AS IdUnidadSiguiente,
                         @Documento AS GeneradoDocumento
                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                 LEFT(@Cuenta, 30), @Equipo, @Programa);

            COMMIT TRANSACTION;

            SELECT (SELECT 1 AS estado,
                           N'Visto bueno otorgado. El expediente pasa al siguiente perfil.' AS mensaje,
                           @Version + 1 AS Version
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            RETURN;
        END

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion',
            CASE WHEN @Respuesta = 'OTORGAR' THEN 'PAG_OTORGAR_VB_FIRMA' ELSE 'PAG_OBSERVAR_VB_FIRMA' END);
        SET @parametro = JSON_MODIFY(@parametro, '$.IdUnidadDestino', CONVERT(varchar(36), @IdUnidadOrigen));
        SET @parametro = JSON_MODIFY(@parametro, '$.IdResponsableDestino', NULL);
        IF @Comentario IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Comentario',
                N'Vistos buenos previos completos. El acta vuelve al Jefe del area usuaria para su firma.');
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;

        IF (SELECT e.Version FROM sigcm.Expediente AS e WHERE e.IdExpediente = @IdExpediente) = @Version + 1
        BEGIN
            IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
        END
        ELSE IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F028 aplicada: visto bueno previo a la firma del Acta (Anexo 11).';
GO
