/*
===============================================================================
  SIGCM - F004 : Motor de transiciones de estado y encolado hacia SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51200-51299

  Este archivo NO existia en la version PostgreSQL: estaba declarado como
  pendiente. Sin el, el outbox queda inerte —tablas creadas, nadie encolando— que
  es exactamente como quedo la implementacion anterior.

  ---------------------------------------------------------------------------
  UN SOLO MOTOR PARA TODOS LOS MODULOS
  ---------------------------------------------------------------------------
  sigcm.paEjecutarTransicion no sabe nada de CMN ni de Requerimiento. Lee que
  transiciones existen, quien puede ejecutarlas y que exigen desde sigcm.Estado,
  sigcm.Transicion y sigcm.TransicionRol. Incorporar un modulo nuevo es agregar
  filas en esas tablas, no escribir codigo.

  Lo unico especifico por modulo es la EXPANSION del encolado, en la seccion 2:
  traducir la marca de la transicion a operaciones concretas de integracion.Operacion.

  ---------------------------------------------------------------------------
  CONCURRENCIA OPTIMISTA
  ---------------------------------------------------------------------------
  El cliente manda la Version que leyo. Si otro usuario movio el expediente entre
  la lectura y el envio, el UPDATE no encuentra fila y se responde CONFLICTO_
  VERSION. Sin esto, dos revisores simultaneos se pisan y el segundo cree que su
  accion se aplico.

  ---------------------------------------------------------------------------
  ENTRADA
  ---------------------------------------------------------------------------
  {
    "Actor": { ... },
    "IdExpediente": "...",
    "CodigoTransicion": "CMN_VALIDAR_UA",
    "Version": 3,
    "Comentario": "...",
    "IdUnidadDestino": null,        // opcional; ver seccion de enrutamiento
    "Datos": { }                    // opcional, se guarda en el historial
  }
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. sigcm.paListarTransicionDisponible                                     */
/* ========================================================================== */

/* Lo que el frontend necesita para pintar los botones de accion: que puede hacer
   ESTE actor con ESTE expediente ahora mismo. Calcularlo en el cliente seria
   duplicar la maquina de estados en TypeScript y que las dos se desincronicen. */
CREATE OR ALTER PROCEDURE sigcm.paListarTransicionDisponible
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51200, 'JSON incorrecto.', 1;

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
            THROW 51201, 'VALIDACION_PAYLOAD: falta IdExpediente o no es un identificador valido.', 1;

        DECLARE @CodigoEstado varchar(60), @CodigoModulo varchar(30), @Version int;
        SELECT @CodigoEstado = CodigoEstado, @CodigoModulo = CodigoModulo, @Version = Version
          FROM sigcm.Expediente
         WHERE IdExpediente = @IdExpediente AND Anulado = 0 AND Activo = 1;

        IF @CodigoEstado IS NULL
            THROW 51202, 'NO_ENCONTRADO: el expediente no existe o esta anulado.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente AS IdExpediente,
                   @CodigoEstado AS CodigoEstadoActual,
                   @Version      AS Version,
                   Transiciones = JSON_QUERY(COALESCE((
                       SELECT t.CodigoTransicion, t.NombreAccion, t.CodigoEstadoDestino,
                              EstadoDestino = d.Nombre,
                              t.RequiereComentario, t.RequiereFirma, t.DocumentoRequerido,
                              t.EncolaIntegracion, t.GeneraObservacion
                         FROM sigcm.Transicion AS t
                         JOIN sigcm.Estado     AS d ON d.CodigoEstado = t.CodigoEstadoDestino
                        WHERE t.CodigoModulo = @CodigoModulo
                          AND t.CodigoEstadoOrigen = @CodigoEstado
                          AND t.Activo = 1
                          AND EXISTS (SELECT 1 FROM sigcm.TransicionRol AS r
                                       WHERE r.CodigoTransicion = t.CodigoTransicion
                                         AND r.CodigoRol = @CodigoRol)
                        ORDER BY t.CodigoTransicion
                          FOR JSON PATH), '[]')),
                   'OK' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo,
                   JSON_QUERY('[]') AS Transiciones
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

/* ========================================================================== */
/* 2. sigcm.paEjecutarTransicion                                             */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE sigcm.paEjecutarTransicion
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
            THROW 51210, 'JSON incorrecto.', 1;

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

        SELECT @IdExpediente     = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @CodigoTransicion = CodigoTransicion,
               @VersionCliente   = Version,
               @Comentario       = Comentario,
               @IdUnidadDestino  = TRY_CONVERT(uniqueidentifier, IdUnidadDestino),
               @Datos            = Datos
        FROM OPENJSON(@parametro)
        WITH (
            IdExpediente     varchar(50),
            CodigoTransicion varchar(70),
            Version          int,
            Comentario       nvarchar(max),
            IdUnidadDestino  varchar(50),
            Datos            nvarchar(max) AS JSON
        );

        IF @IdExpediente IS NULL
            THROW 51211, 'VALIDACION_PAYLOAD: falta IdExpediente o no es un identificador valido.', 1;
        IF NULLIF(LTRIM(RTRIM(@CodigoTransicion)), '') IS NULL
            THROW 51212, 'VALIDACION_PAYLOAD: falta CodigoTransicion.', 1;

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
            THROW 51213, 'NO_ENCONTRADO: el expediente no existe o esta anulado.', 1;

        IF @VersionCliente IS NOT NULL AND @VersionCliente <> @VersionActual
        BEGIN
            DECLARE @errVer nvarchar(400) = CONCAT(
                'CONFLICTO_VERSION: el expediente va por la version ', @VersionActual,
                ' y usted trabajo sobre la ', @VersionCliente,
                '. Vuelva a cargarlo: otra persona lo movio mientras tanto.');
            THROW 51214, @errVer, 1;
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
            DECLARE @errTr nvarchar(500) = CONCAT(
                'CONFLICTO_TRANSICION: "', @CodigoTransicion,
                '" no es una transicion valida desde el estado ', @EstadoActual, '.');
            THROW 51215, @errTr, 1;
        END

        /* El rol se comprueba contra la tabla, no contra una lista en codigo. */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol
                        WHERE CodigoTransicion = @CodigoTransicion AND CodigoRol = @CodigoRol)
        BEGIN
            DECLARE @errRol nvarchar(500) = CONCAT(
                'NO_AUTORIZADO: el rol ', @CodigoRol, ' no puede ejecutar "', @NombreAccion, '".');
            THROW 51216, @errRol, 1;
        END

        IF @RequiereComentario = 1 AND NULLIF(LTRIM(RTRIM(@Comentario)), '') IS NULL
        BEGIN
            DECLARE @errCom nvarchar(400) = CONCAT(
                'VALIDACION_COMENTARIO: "', @NombreAccion, '" exige registrar el motivo.');
            THROW 51217, @errCom, 1;
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
                DECLARE @errDoc nvarchar(500) = CONCAT(
                    'CONFLICTO_DOCUMENTO: "', @NombreAccion, '" exige el documento ',
                    @DocumentoRequerido, ' en su version vigente y firmado.');
                THROW 51218, @errDoc, 1;
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
            THROW 51219, 'CONFLICTO_VERSION: otra persona movio el expediente en este instante. Vuelva a cargarlo.', 1;

        INSERT INTO sigcm.Historial
            (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
             Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (@IdExpediente, @EstadoActual, @EstadoDestino, @CodigoTransicion,
             @Comentario, @IdUsuario, @CodigoRol, @IdUnidad,
             CASE WHEN ISJSON(@Datos) = 1 THEN @Datos ELSE N'{}' END,
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
                THROW 51220, 'CONFLICTO_OBSERVACION: el expediente ya tiene una observacion abierta.', 1;

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
                    CONCAT(CONVERT(varchar(36), s.IdSolicitud), ':',
                           CONVERT(varchar(36), i.IdSolicitudItem), ':',
                           CONVERT(varchar(10), @VersionNueva), ':',
                           CASE i.TipoMovimiento
                                WHEN 'INCLUSION'    THEN 'INCLUIR_ITEM'
                                WHEN 'EXCLUSION'    THEN 'EXCLUIR_ITEM'
                                ELSE 'MODIFICAR_CANTIDADES' END),
                    @IdExpediente, s.IdSolicitud, i.IdSolicitudItem,
                    CASE i.TipoMovimiento
                         WHEN 'INCLUSION' THEN 'INCLUIR_ITEM'
                         WHEN 'EXCLUSION' THEN 'EXCLUIR_ITEM'
                         ELSE 'MODIFICAR_CANTIDADES' END,
                    'integracion.paEscribirCuadroModificado',
                    i.Orden,
                    'PENDIENTE',
                    (SELECT s.AnoEje, s.SecEjec, s.CentroCosto,
                            i.TipoMovimiento, i.RefSecCuadro, i.RefSecItem,
                            i.TipoTarea, i.NivelTarea, i.CodigoTarea, i.SecFunc, i.SecFuncProp,
                            i.Origen, i.FuenteFinanc, i.Clasificador, i.TipoRecurso,
                            i.TipoPpto, i.TipoUso,
                            i.TipoBien, i.GrupoBien, i.ClaseBien, i.FamiliaBien, i.ItemBien,
                            i.UnidadMedida, i.PrecioUnitario,
                            Periodos = JSON_QUERY((
                                SELECT p.AnoOffset, p.Mes, p.Cantidad, p.Monto
                                  FROM cmn.SolicitudItemPeriodo AS p
                                 WHERE p.IdSolicitudItem = i.IdSolicitudItem
                                 ORDER BY p.AnoOffset, p.Mes
                                   FOR JSON PATH))
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
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
                    CONCAT(CONVERT(varchar(36), s.IdSolicitud), '::',
                           CONVERT(varchar(10), @VersionNueva), ':CONSOLIDAR_CMN'),
                    @IdExpediente, s.IdSolicitud, NULL,
                    'CONSOLIDAR_CMN', 'integracion.paEscribirCuadroModificado', 1, 'PENDIENTE',
                    (SELECT s.AnoEje, s.SecEjec, s.CentroCosto, s.Codigo,
                            Items = (SELECT COUNT(*) FROM cmn.SolicitudItem AS i2
                                      WHERE i2.IdSolicitud = s.IdSolicitud AND i2.Activo = 1)
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                    @Cuenta, @Ahora, @Equipo, @Programa
                  FROM cmn.Solicitud AS s
                 WHERE s.IdExpediente = @IdExpediente AND s.Activo = 1;

                SET @Encoladas = @@ROWCOUNT;
            END
            ELSE
            BEGIN
                DECLARE @errOp nvarchar(400) = CONCAT(
                    'CONFLICTO_CONFIGURACION: la transicion declara EncolaIntegracion pero "',
                    @OperacionIntegracion, '" no tiene expansion definida en F004.');
                THROW 51221, @errOp, 1;
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

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente     AS IdExpediente,
                   @CodigoExpediente AS Codigo,
                   @EstadoActual     AS CodigoEstadoAnterior,
                   @EstadoDestino    AS CodigoEstado,
                   @VersionNueva     AS Version,
                   @Encoladas        AS OperacionesEncoladas,
                   @IdObservacion    AS IdObservacion,
                   N'Se registro la accion satisfactoriamente.' AS mensaje
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

/* ========================================================================== */
/* 3. sigcm.paObtenerTrazabilidad                                            */
/* ========================================================================== */

/* Historial, observaciones y cola de integracion de un expediente, que es lo que
   pide la pestania de trazabilidad del mockup. */
CREATE OR ALTER PROCEDURE sigcm.paObtenerTrazabilidad
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51230, 'JSON incorrecto.', 1;

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
            THROW 51231, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Historial = JSON_QUERY(COALESCE((
                       SELECT h.IdHistorial, h.CodigoEstadoOrigen, h.CodigoEstadoDestino,
                              h.CodigoTransicion, h.Comentario, h.ActorRol, h.OcurridoEn,
                              Actor = CONCAT_WS(' ', u.Nombres, u.Apellidos),
                              Unidad = n.Nombre
                         FROM sigcm.Historial AS h
                         JOIN sigcm.Usuario   AS u ON u.IdUsuario = h.IdActor
                         LEFT JOIN sigcm.Unidad AS n ON n.IdUnidad = h.IdActorUnidad
                        WHERE h.IdExpediente = @IdExpediente
                        ORDER BY h.IdHistorial
                          FOR JSON PATH), '[]')),
                   Observaciones = JSON_QUERY(COALESCE((
                       SELECT o.IdObservacion, o.CodigoRolOrigen, o.CodigoEstadoRetorno,
                              o.Motivo, o.Estado, o.Respuesta,
                              o.FechaCreacionAuditoria, o.RecepcionadaEn, o.SubsanadaEn, o.CerradaEn
                         FROM sigcm.Observacion AS o
                        WHERE o.IdExpediente = @IdExpediente AND o.Activo = 1
                        ORDER BY o.FechaCreacionAuditoria
                          FOR JSON PATH), '[]')),
                   Integracion = JSON_QUERY(COALESCE((
                       SELECT g.IdOperacion, g.Operacion, g.Estado, g.Secuencia,
                              g.Intentos, g.MaxIntentos, g.ModoEjecucion,
                              g.ErrorCodigo, g.ErrorMensaje,
                              g.FechaCreacionAuditoria, g.CompletadoEn
                         FROM integracion.Operacion AS g
                        WHERE g.IdExpediente = @IdExpediente
                        ORDER BY g.Secuencia, g.FechaCreacionAuditoria
                          FOR JSON PATH), '[]')),
                   'OK' AS mensaje
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

PRINT 'F004 aplicada: motor de transiciones y encolado.';
GO
