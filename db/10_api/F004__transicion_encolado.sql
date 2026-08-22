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
  UNA TRANSICION SOBRE VARIOS EXPEDIENTES A LA VEZ
  ---------------------------------------------------------------------------
  El Anexo 4 agrupa varios Anexos 3 de areas usuarias distintas, y cada Anexo 3
  es un expediente. Cuando el coordinador firma ese Anexo 4, los N expedientes
  tienen que avanzar juntos.

  Por eso la rutina acepta IdExpedientes ademas de IdExpediente, y los mueve
  TODOS EN LA MISMA TRANSACCION. No es una comodidad de la pantalla: un Anexo 4
  con tres expedientes movidos y dos sin mover no corresponde a ningun estado
  del tramite, y no habria forma de repararlo desde la interfaz, porque la
  accion que quedo a medias ya no esta disponible para los que si avanzaron.

  La firma del jefe encola una operacion hacia SIGA POR EXPEDIENTE. Un Anexo 4
  con cinco Anexos 3 produce cinco aprobaciones en SIGA, una por area usuaria:
  es el registro multiple de aprobaciones que pide el flujo.

  ---------------------------------------------------------------------------
  ENTRADA
  ---------------------------------------------------------------------------
  {
    "Actor": { ... },
    "IdExpediente": "...",          uno solo
    "Version": 3,                   su version, para el control de concurrencia
    "IdExpedientes": [              o varios, cada uno con la suya
        { "IdExpediente": "...", "Version": 3 },
        { "IdExpediente": "...", "Version": 7 }
    ],
    "CodigoTransicion": "CMN_ABAST_COORD_FIRMAR_A4",
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
    DECLARE @TranPropia bit = 0;

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

        /* El destino de CMN_SUBS_JEFE_ENVIAR no esta cableado: lo que observa OA
           vuelve a OA; lo que observa Abastecimiento entra por el jefe de
           Abastecimiento, sin pasar por Administracion. Se lee de la observacion
           abierta (CodigoEstadoRetorno). */
        DECLARE @RetornoObs varchar(60);
        SELECT TOP 1 @RetornoObs = o.CodigoEstadoRetorno
          FROM sigcm.Observacion AS o
         WHERE o.IdExpediente = @IdExpediente AND o.Activo = 1
           AND o.Estado IN ('PENDIENTE','RECEPCIONADA','SUBSANADA')
         ORDER BY o.FechaCreacionAuditoria DESC;

        DECLARE @DestinoSubs varchar(60) =
            CASE
                WHEN @RetornoObs = 'CMN_EN_EVAL_OA' THEN 'CMN_EN_EVAL_OA'
                WHEN @RetornoObs LIKE 'CMN_EN_ABAST%' THEN 'CMN_EN_ABAST_JEFE'
                ELSE NULL
            END;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente AS IdExpediente,
                   @CodigoEstado AS CodigoEstadoActual,
                   @Version      AS Version,
                   Transiciones = JSON_QUERY(COALESCE((
                       SELECT t.CodigoTransicion,
                              NombreAccion = CASE
                                  WHEN t.CodigoTransicion = 'CMN_SUBS_JEFE_ENVIAR'
                                       AND @DestinoSubs = 'CMN_EN_EVAL_OA'
                                      THEN 'Firmar y remitir subsanado a OA'
                                  ELSE t.NombreAccion
                              END,
                              CodigoEstadoDestino = CASE
                                  WHEN t.CodigoTransicion = 'CMN_SUBS_JEFE_ENVIAR'
                                       AND @DestinoSubs IS NOT NULL
                                      THEN @DestinoSubs
                                  ELSE t.CodigoEstadoDestino
                              END,
                              EstadoDestino = d.Nombre,
                              t.RequiereComentario, t.RequiereFirma, t.DocumentoRequerido,
                              t.EncolaIntegracion, t.GeneraObservacion
                         FROM sigcm.Transicion AS t
                         JOIN sigcm.Estado     AS d ON d.CodigoEstado =
                              CASE
                                  WHEN t.CodigoTransicion = 'CMN_SUBS_JEFE_ENVIAR'
                                       AND @DestinoSubs IS NOT NULL
                                      THEN @DestinoSubs
                                  ELSE t.CodigoEstadoDestino
                              END
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
        /* Solo se deshace la transaccion que ESTA rutina abrio.

           Antes decia "IF @@TRANCOUNT > 0 ROLLBACK", y eso deshacia tambien la
           transaccion de quien llama. Casi todos los errores de aqui son de
           validacion y ocurren ANTES de abrir nada: con la version anterior, un
           "falta IdExpediente" bastaba para tirar abajo el trabajo del llamador,
           que ni siquiera sabria por que. Ademas, bajo INSERT ... EXEC el motor
           prohibe el ROLLBACK y el error real quedaba tapado por un 3915. */
        IF @TranPropia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
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
    DECLARE @TranPropia bit = 0;

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

        IF NULLIF(LTRIM(RTRIM(@CodigoTransicion)), '') IS NULL
            THROW 51212, 'VALIDACION_PAYLOAD: falta CodigoTransicion.', 1;

        /* ---- El lote de expedientes que se mueve ---------------------- */
        /*
          IdExpedientes admite dos formas para no obligar al llamador a cambiar
          de estructura cuando pasa de uno a varios:
            ["guid", "guid"]                        sin control de concurrencia
            [{"IdExpediente":"guid","Version":3}]   con el
          El tipo 5 de OPENJSON es "objeto"; cualquier otro se lee como escalar.
        */
        DECLARE @Lote TABLE (
            IdExpediente   uniqueidentifier PRIMARY KEY,
            VersionCliente int NULL,
            Orden          int IDENTITY(1,1)
        );

        INSERT INTO @Lote (IdExpediente, VersionCliente)
        SELECT DISTINCT
               CASE WHEN j.type = 5
                    THEN TRY_CONVERT(uniqueidentifier, JSON_VALUE(j.value, '$.IdExpediente'))
                    ELSE TRY_CONVERT(uniqueidentifier, j.value) END,
               CASE WHEN j.type = 5
                    THEN TRY_CONVERT(int, JSON_VALUE(j.value, '$.Version')) END
          FROM OPENJSON(@parametro, '$.IdExpedientes') AS j
         WHERE CASE WHEN j.type = 5
                    THEN TRY_CONVERT(uniqueidentifier, JSON_VALUE(j.value, '$.IdExpediente'))
                    ELSE TRY_CONVERT(uniqueidentifier, j.value) END IS NOT NULL;

        IF @IdExpediente IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM @Lote WHERE IdExpediente = @IdExpediente)
            INSERT INTO @Lote (IdExpediente, VersionCliente) VALUES (@IdExpediente, @VersionCliente);

        IF NOT EXISTS (SELECT 1 FROM @Lote)
            THROW 51211, 'VALIDACION_PAYLOAD: falta IdExpediente o IdExpedientes.', 1;

        DECLARE @CantidadLote int = (SELECT COUNT(*) FROM @Lote);

        /* ---- Expediente de referencia --------------------------------- */
        /*
          La transicion se resuelve una sola vez, contra el estado del lote. Que
          el estado sea el mismo para todos no es un supuesto: se comprueba
          abajo. Si no lo fuera, una misma accion significaria cosas distintas
          para cada expediente y no habria una transicion que ejecutar.
        */
        DECLARE @EstadoActual varchar(60), @CodigoModulo varchar(30),
                @VersionActual int, @CodigoExpediente varchar(40);

        SELECT TOP 1 @EstadoActual     = e.CodigoEstado,
                     @CodigoModulo     = e.CodigoModulo,
                     @VersionActual    = e.Version,
                     @CodigoExpediente = e.Codigo,
                     @IdExpediente     = e.IdExpediente
          FROM sigcm.Expediente AS e
          JOIN @Lote AS l ON l.IdExpediente = e.IdExpediente
         WHERE e.Anulado = 0 AND e.Activo = 1
         ORDER BY l.Orden;

        IF @EstadoActual IS NULL
            THROW 51213, 'NO_ENCONTRADO: el expediente no existe o esta anulado.', 1;

        IF EXISTS (SELECT 1 FROM @Lote AS l
                    WHERE NOT EXISTS (SELECT 1 FROM sigcm.Expediente AS e
                                       WHERE e.IdExpediente = l.IdExpediente
                                         AND e.Anulado = 0 AND e.Activo = 1))
            THROW 51222, 'NO_ENCONTRADO: algun expediente del lote no existe o esta anulado.', 1;

        IF EXISTS (SELECT 1 FROM sigcm.Expediente AS e
                     JOIN @Lote AS l ON l.IdExpediente = e.IdExpediente
                    WHERE e.CodigoEstado <> @EstadoActual OR e.CodigoModulo <> @CodigoModulo)
        BEGIN
            DECLARE @errLote nvarchar(500) = CONCAT(
                'CONFLICTO_LOTE: los expedientes seleccionados no estan todos en el estado ',
                @EstadoActual, '. Vuelva a cargar la bandeja: alguno se movio mientras tanto.');
            THROW 51223, @errLote, 1;
        END

        /* Concurrencia optimista, expediente por expediente. Se comprueba antes
           de abrir la transaccion para responder el conflicto sin haber tocado
           nada, y se vuelve a comprobar en el UPDATE, que es donde realmente
           cierra la ventana. */
        DECLARE @ExpDesfasado varchar(40) =
            (SELECT TOP 1 e.Codigo
               FROM sigcm.Expediente AS e
               JOIN @Lote AS l ON l.IdExpediente = e.IdExpediente
              WHERE l.VersionCliente IS NOT NULL AND l.VersionCliente <> e.Version);

        IF @ExpDesfasado IS NOT NULL
        BEGIN
            DECLARE @errVer nvarchar(400) = CONCAT(
                'CONFLICTO_VERSION: el expediente ', @ExpDesfasado,
                ' cambio mientras usted trabajaba. Vuelva a cargarlo: otra persona lo movio.');
            THROW 51214, @errVer, 1;
        END

        /* ---- Transicion ----------------------------------------------- */
        DECLARE @EstadoDestino varchar(60), @NombreAccion varchar(180),
                @RequiereComentario bit, @RequiereFirma bit,
                @DocumentoRequerido varchar(60), @EncolaIntegracion bit,
                @OperacionIntegracion varchar(30), @GeneraObservacion bit,
                @RolFirmaRequerida varchar(40);

        SELECT @EstadoDestino        = CodigoEstadoDestino,
               @NombreAccion         = NombreAccion,
               @RequiereComentario   = RequiereComentario,
               @RequiereFirma        = RequiereFirma,
               @DocumentoRequerido   = DocumentoRequerido,
               @EncolaIntegracion    = EncolaIntegracion,
               @OperacionIntegracion = OperacionIntegracion,
               @GeneraObservacion    = GeneraObservacion,
               @RolFirmaRequerida    = RolFirmaRequerida
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

        /*
          El documento debe existir en su version vigente y traer la firma que
          respalda ESTE paso. Que exista un borrador no basta: es justamente lo
          que la firma pretende impedir.

          RolFirmaRequerida (V011) precisa cual firma:
            NULL  -> la version tiene que estar FIRMADO, es decir con todas las
                     firmas declaradas. Es lo que exige la recepcion del Anexo 4.
            <rol> -> alcanza con la firma vigente de ese rol. Es lo que exige
                     cada escalon de la cadena, porque a esa altura el documento
                     todavia tiene firmas pendientes por diseno.

          Se comprueba expediente por expediente: en un Anexo 4 consolidado el
          documento es uno solo y esta enlazado a todos, pero el enlace podria
          faltar para alguno y ese es exactamente el caso que hay que detener.
        */
        IF @DocumentoRequerido IS NOT NULL
        BEGIN
            DECLARE @ExpSinDoc varchar(40) =
                (SELECT TOP 1 e.Codigo
                   FROM sigcm.Expediente AS e
                   JOIN @Lote AS l ON l.IdExpediente = e.IdExpediente
                  WHERE NOT EXISTS (
                        SELECT 1
                          FROM sigcm.DocumentoExpediente AS de
                          JOIN sigcm.Documento        AS d  ON d.IdDocumento = de.IdDocumento
                          JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumento = d.IdDocumento
                                                           AND dv.Version = d.VersionVigente
                         WHERE de.IdExpediente = e.IdExpediente
                           AND d.CodigoTipoDocumento = @DocumentoRequerido
                           AND d.Anulado = 0 AND d.Activo = 1
                           AND (
                                (@RolFirmaRequerida IS NULL AND dv.Estado = 'FIRMADO')
                             OR (@RolFirmaRequerida IS NOT NULL
                                 AND dv.Estado IN ('PARCIAL','FIRMADO')
                                 AND EXISTS (SELECT 1 FROM sigcm.Firma AS f
                                              WHERE f.IdDocumentoVersion = dv.IdDocumentoVersion
                                                AND f.CodigoRol = @RolFirmaRequerida
                                                AND f.Estado = 'FIRMADA'))
                           )));

            IF @ExpSinDoc IS NOT NULL
            BEGIN
                DECLARE @errDoc nvarchar(600) = CONCAT(
                    'CONFLICTO_DOCUMENTO: "', @NombreAccion, '" exige el documento ',
                    @DocumentoRequerido,
                    CASE WHEN @RolFirmaRequerida IS NULL
                         THEN ' firmado por todos sus firmantes'
                         ELSE CONCAT(' con la firma vigente de ', @RolFirmaRequerida) END,
                    ', y el expediente ', @ExpSinDoc, ' no lo tiene asi.');
                THROW 51218, @errDoc, 1;
            END
        END

        /* ---- Enrutamiento: a que unidad queda cada expediente ---------- */
        /*
          El estado destino declara el ROL responsable. La UNIDAD no se deduce del
          rol: dos areas usuarias distintas tienen ambas un AREA_JEFE. El orden de
          resolucion, por expediente, es:

            1. Si el cliente manda IdUnidadDestino, manda eso.
            2. Si la UNIDAD DE ORIGEN del expediente tiene a alguien con el rol
               destino, va ahi. Es lo que devuelve cada expediente a SU area
               usuaria, y es imprescindible desde que el Anexo 4 cubre varias:
               al remitirlo, cada Anexo 3 tiene que volver a la oficina que lo
               pidio, no a una sola para todos.
            3. Si exactamente una unidad tiene ese rol, se usa esa. Es el caso de
               OA y de Abastecimiento, que son unicas en la entidad.
            4. Si no, se conserva la unidad actual.

          La regla 2 va antes que la 3 y no al reves: cuando el rol destino es
          unico en la entidad —OA, Abastecimiento— ninguna area usuaria lo tiene
          asignado, asi que la regla 2 no se activa y la 3 decide igual que antes.
        */
        DECLARE @RolDestino varchar(40);
        SELECT @RolDestino = RolResponsable FROM sigcm.Estado WHERE CodigoEstado = @EstadoDestino;

        DECLARE @UnidadUnicaRol uniqueidentifier = NULL;

        IF @IdUnidadDestino IS NULL AND @RolDestino IS NOT NULL
        BEGIN
            DECLARE @Candidatas int;
            SELECT @Candidatas = COUNT(DISTINCT ur.IdUnidad)
              FROM sigcm.UsuarioRol AS ur
             WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1
               AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()));

            IF @Candidatas = 1
                SELECT @UnidadUnicaRol = MIN(ur.IdUnidad)
                  FROM sigcm.UsuarioRol AS ur
                 WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1
                   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()));
        END

        /* ---- Escritura ------------------------------------------------ */
        DECLARE @Ahora datetime = GETDATE();
        DECLARE @Encoladas int = 0;
        DECLARE @IdObservacion uniqueidentifier = NULL;
        DECLARE @EsFinalDestino bit =
            CASE WHEN EXISTS (SELECT 1 FROM sigcm.Estado
                               WHERE CodigoEstado = @EstadoDestino AND EsFinal = 1)
                 THEN 1 ELSE 0 END;

        BEGIN TRANSACTION; SET @TranPropia = 1;

        /*
          El recorrido es expediente por expediente y todo dentro de UNA
          transaccion. Con un solo expediente se comporta exactamente como antes;
          con varios, o avanzan todos o no avanza ninguno.

          No se resuelve con un UPDATE de conjunto porque cada expediente tiene su
          propia version que verificar, su propia unidad de destino y su propia
          fila de historial, y porque el encolado de integracion necesita saber a
          que expediente pertenece cada operacion.
        */
        DECLARE @Idx int = 1, @IdExpLoop uniqueidentifier,
                @VersionExp int, @VersionNuevaExp int,
                @UnidadOrigenExp uniqueidentifier, @UnidadActualExp uniqueidentifier,
                @IdUnidadDestinoExp uniqueidentifier, @CodigoExpLoop varchar(40),
                @VersionNueva int = @VersionActual + 1,
                @EstadoDestinoExp varchar(60), @RetornoObsExp varchar(60),
                @CandidatasExp int;

        WHILE @Idx <= @CantidadLote
        BEGIN
            SELECT @IdExpLoop = l.IdExpediente FROM @Lote AS l WHERE l.Orden = @Idx;

            SELECT @VersionExp     = e.Version,
                   @UnidadOrigenExp = e.IdUnidadOrigen,
                   @UnidadActualExp = e.IdUnidadActual,
                   @CodigoExpLoop  = e.Codigo
              FROM sigcm.Expediente AS e
             WHERE e.IdExpediente = @IdExpLoop;

            SET @VersionNuevaExp = @VersionExp + 1;

            /* Destino por defecto de la transicion. En el retorno de una
               subsanacion se sustituye por CodigoEstadoRetorno: OA vuelve a OA;
               Abastecimiento entra por el jefe y no pasa por Administracion. */
            SET @EstadoDestinoExp = @EstadoDestino;
            SET @RetornoObsExp = NULL;

            IF @CodigoTransicion = 'CMN_SUBS_JEFE_ENVIAR'
            BEGIN
                SELECT TOP 1 @RetornoObsExp = o.CodigoEstadoRetorno
                  FROM sigcm.Observacion AS o
                 WHERE o.IdExpediente = @IdExpLoop AND o.Activo = 1
                   AND o.Estado IN ('PENDIENTE','RECEPCIONADA','SUBSANADA')
                 ORDER BY o.FechaCreacionAuditoria DESC;

                SET @EstadoDestinoExp =
                    CASE
                        WHEN @RetornoObsExp = 'CMN_EN_EVAL_OA' THEN 'CMN_EN_EVAL_OA'
                        ELSE 'CMN_EN_ABAST_JEFE'
                    END;

                UPDATE o
                   SET o.Estado = 'CERRADA',
                       o.CerradaEn = @Ahora,
                       o.RecepcionadaEn = COALESCE(o.RecepcionadaEn, o.SubsanadaEn, @Ahora),
                       o.IdRecepcionadaPor = COALESCE(o.IdRecepcionadaPor, o.IdSubsanadaPor, @IdUsuario),
                       o.SubsanadaEn = COALESCE(o.SubsanadaEn, @Ahora),
                       o.IdSubsanadaPor = COALESCE(o.IdSubsanadaPor, @IdUsuario),
                       o.UsuarioModificacionAuditoria = @Cuenta,
                       o.FechaModificacionAuditoria = @Ahora,
                       o.EquipoModificacionAuditoria = @Equipo,
                       o.ProgramaModificacionAuditoria = @Programa
                  FROM sigcm.Observacion AS o
                 WHERE o.IdExpediente = @IdExpLoop AND o.Activo = 1
                   AND o.Estado IN ('PENDIENTE','RECEPCIONADA','SUBSANADA');
            END

            /* No hay un paso aparte de recepcion en AU: el especialista levanta
               la observacion sobre el mismo expediente. CK_Observacion_Recepcion
               exige RecepcionadaEn en cuanto el estado deja de ser PENDIENTE. */
            IF @CodigoTransicion = 'CMN_SUBSANAR'
            BEGIN
                UPDATE o
                   SET o.Estado = 'SUBSANADA',
                       o.RecepcionadaEn = COALESCE(o.RecepcionadaEn, @Ahora),
                       o.IdRecepcionadaPor = COALESCE(o.IdRecepcionadaPor, @IdUsuario),
                       o.SubsanadaEn = @Ahora,
                       o.IdSubsanadaPor = @IdUsuario,
                       o.Respuesta = COALESCE(NULLIF(LTRIM(RTRIM(@Comentario)), ''), o.Respuesta),
                       o.UsuarioModificacionAuditoria = @Cuenta,
                       o.FechaModificacionAuditoria = @Ahora,
                       o.EquipoModificacionAuditoria = @Equipo,
                       o.ProgramaModificacionAuditoria = @Programa
                  FROM sigcm.Observacion AS o
                 WHERE o.IdExpediente = @IdExpLoop AND o.Activo = 1
                   AND o.Estado IN ('PENDIENTE','RECEPCIONADA');
            END

            SELECT @RolDestino = RolResponsable
              FROM sigcm.Estado
             WHERE CodigoEstado = @EstadoDestinoExp;

            SET @UnidadUnicaRol = NULL;
            IF @IdUnidadDestino IS NULL AND @RolDestino IS NOT NULL
            BEGIN
                SELECT @CandidatasExp = COUNT(DISTINCT ur.IdUnidad)
                  FROM sigcm.UsuarioRol AS ur
                 WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1
                   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()));

                IF @CandidatasExp = 1
                    SELECT @UnidadUnicaRol = MIN(ur.IdUnidad)
                      FROM sigcm.UsuarioRol AS ur
                     WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1
                       AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()));
            END

            /* Regla 2 del enrutamiento, evaluada con la unidad de ESTE expediente. */
            SET @IdUnidadDestinoExp = @IdUnidadDestino;

            IF @IdUnidadDestinoExp IS NULL AND @RolDestino IS NOT NULL
               AND EXISTS (SELECT 1 FROM sigcm.UsuarioRol AS ur
                            WHERE ur.CodigoRol = @RolDestino
                              AND ur.IdUnidad = @UnidadOrigenExp
                              AND ur.Activo = 1
                              AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE())))
                SET @IdUnidadDestinoExp = @UnidadOrigenExp;

            SET @IdUnidadDestinoExp = COALESCE(@IdUnidadDestinoExp, @UnidadUnicaRol, @UnidadActualExp);

            /* La condicion sobre Version es el candado de concurrencia optimista:
               si otro proceso avanzo el expediente entre la lectura y este UPDATE,
               no se afecta ninguna fila. */
            UPDATE sigcm.Expediente
               SET CodigoEstado                  = @EstadoDestinoExp,
                   Version                       = @VersionNuevaExp,
                   IdUnidadActual                = @IdUnidadDestinoExp,
                   /* El responsable concreto se deja sin fijar: la bandeja se
                      resuelve por rol y unidad, y asignar a una persona en una
                      unidad con varios titulares seria inventar una regla que la
                      Directiva no establece. */
                   IdResponsableActual           = NULL,
                   CerradoEn                     = CASE WHEN @EsFinalDestino = 1
                                                        THEN @Ahora ELSE CerradoEn END,
                   UsuarioModificacionAuditoria  = @Cuenta,
                   FechaModificacionAuditoria    = @Ahora,
                   EquipoModificacionAuditoria   = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdExpediente = @IdExpLoop
               AND Version      = @VersionExp;

            IF @@ROWCOUNT = 0
            BEGIN
                DECLARE @errCarrera nvarchar(400) = CONCAT(
                    'CONFLICTO_VERSION: otra persona movio el expediente ', @CodigoExpLoop,
                    ' en este instante. Vuelva a cargarlo.');
                THROW 51219, @errCarrera, 1;
            END

            INSERT INTO sigcm.Historial
                (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
                 Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
                 UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdExpLoop, @EstadoActual, @EstadoDestinoExp, @CodigoTransicion,
                 @Comentario, @IdUsuario, @CodigoRol, @IdUnidad,
                 CASE WHEN ISJSON(@Datos) = 1 THEN @Datos ELSE N'{}' END,
                 @Cuenta, @Equipo, @Programa);

            /* ---- Observacion ------------------------------------------ */
            /*
              CodigoEstadoRetorno se toma del estado en que ESTABA el expediente
              al observarse. Ahi vive la regla del mockup: lo que observa OA
              vuelve a OA, lo que observa Abastecimiento vuelve a Abastecimiento.
              Es dato, no un condicional por unidad.

              Un Anexo 3 puede observarse N veces en la misma instancia. La
              observacion previa se cierra y se abre una nueva; no se rechaza.
            */
            IF @GeneraObservacion = 1
            BEGIN
                UPDATE o
                   SET o.Estado = 'CERRADA',
                       o.CerradaEn = COALESCE(o.CerradaEn, @Ahora),
                       o.RecepcionadaEn = COALESCE(o.RecepcionadaEn, o.SubsanadaEn, @Ahora),
                       o.IdRecepcionadaPor = COALESCE(o.IdRecepcionadaPor, o.IdSubsanadaPor, @IdUsuario),
                       o.UsuarioModificacionAuditoria = @Cuenta,
                       o.FechaModificacionAuditoria = @Ahora,
                       o.EquipoModificacionAuditoria = @Equipo,
                       o.ProgramaModificacionAuditoria = @Programa
                  FROM sigcm.Observacion AS o
                 WHERE o.IdExpediente = @IdExpLoop AND o.Activo = 1
                   AND o.Estado IN ('PENDIENTE','RECEPCIONADA','SUBSANADA');

                DECLARE @Obs TABLE (IdObservacion uniqueidentifier);
                DELETE FROM @Obs;

                INSERT INTO sigcm.Observacion
                    (IdExpediente, IdUnidadOrigen, CodigoRolOrigen, IdUnidadDestino,
                     CodigoEstadoRetorno, Motivo, Estado,
                     UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                     EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                OUTPUT inserted.IdObservacion INTO @Obs
                VALUES
                    (@IdExpLoop, @IdUnidad, @CodigoRol, @UnidadOrigenExp,
                     @EstadoActual, @Comentario, 'PENDIENTE',
                     @Cuenta, @Ahora, @Equipo, @Programa);

                SELECT @IdObservacion = IdObservacion FROM @Obs;
            END

            SET @EstadoDestino = @EstadoDestinoExp;
            SET @Idx = @Idx + 1;
        END

        /* A partir de aqui el encolado trabaja sobre todo el lote de una vez. */
        SET @IdExpediente = (SELECT TOP 1 IdExpediente FROM @Lote ORDER BY Orden);

        /* ---- Dato del modulo que la accion trae consigo ---------------- */
        /*
          TipoInclusion es la decision del paso 6 del flujo: al conformar el
          Anexo 3, el especialista de Abastecimiento declara si la modificacion
          es ordinaria o urgente. De esa marca depende despues la regla del
          viernes al generar el Anexo 4.

          Viaja en el mismo POST que la transicion y no en una rutina aparte
          porque es parte de la misma decision: no existe conformar sin decidir
          el tipo. La columna es de cmn.Solicitud desde V005 y hasta ahora
          ninguna rutina la escribia; el frontend ya la mandaba y se perdia.
        */
        DECLARE @TipoInclusion varchar(15) =
            NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.TipoInclusion'))), '');

        IF @TipoInclusion IS NOT NULL
        BEGIN
            IF @TipoInclusion NOT IN ('ORDINARIA','URGENTE')
                THROW 51224, 'VALIDACION_PAYLOAD: TipoInclusion debe ser ORDINARIA o URGENTE.', 1;

            UPDATE s
               SET s.TipoInclusion = @TipoInclusion,
                   s.UsuarioModificacionAuditoria = @Cuenta,
                   s.FechaModificacionAuditoria   = @Ahora,
                   s.EquipoModificacionAuditoria  = @Equipo,
                   s.ProgramaModificacionAuditoria = @Programa
              FROM cmn.Solicitud AS s
              JOIN @Lote AS l ON l.IdExpediente = s.IdExpediente
             WHERE s.Activo = 1;
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
                           CONVERT(varchar(10), e.Version), ':',
                           CASE i.TipoMovimiento
                                WHEN 'INCLUSION'    THEN 'INCLUIR_ITEM'
                                WHEN 'EXCLUSION'    THEN 'EXCLUIR_ITEM'
                                ELSE 'MODIFICAR_CANTIDADES' END),
                    e.IdExpediente, s.IdSolicitud, i.IdSolicitudItem,
                    CASE i.TipoMovimiento
                         WHEN 'INCLUSION' THEN 'INCLUIR_ITEM'
                         WHEN 'EXCLUSION' THEN 'EXCLUIR_ITEM'
                         ELSE 'MODIFICAR_CANTIDADES' END,
                    'integracion.paEscribirCuadroModificado',
                    i.Orden,
                    'PENDIENTE',
                    (SELECT s.AnoEje, s.SecEjec, s.CentroCosto,
                            Comentario = @Comentario,
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
                  FROM @Lote             AS l
                  JOIN sigcm.Expediente  AS e ON e.IdExpediente = l.IdExpediente
                  JOIN cmn.Solicitud     AS s ON s.IdExpediente = e.IdExpediente AND s.Activo = 1
                  JOIN cmn.SolicitudItem AS i ON i.IdSolicitud = s.IdSolicitud AND i.Activo = 1;

                SET @Encoladas = @@ROWCOUNT;
            END
            ELSE IF @OperacionIntegracion = 'CONSOLIDAR_CMN'
            BEGIN
                /* Anexo 4 firmado: una operacion POR SOLICITUD, es decir una por
                   area usuaria del paquete. Es el registro multiple de
                   aprobaciones: un Anexo 4 que agrupa cinco Anexos 3 aprueba
                   cinco solicitudes en SIGA, cada una con su centro de costo.
                   Escribe en SIG_CUADRO_MODIFICADO_CMN, que segun los datos de
                   2026 no se puebla hasta la consolidacion. */
                INSERT INTO integracion.Operacion
                    (IdempotenciaKey, IdExpediente, IdSolicitud, IdSolicitudItem,
                     Operacion, Procedimiento, Secuencia, Estado, RequestJson,
                     UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                     EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                SELECT
                    CONCAT(CONVERT(varchar(36), s.IdSolicitud), '::',
                           CONVERT(varchar(10), e.Version), ':CONSOLIDAR_CMN'),
                    e.IdExpediente, s.IdSolicitud, NULL,
                    'CONSOLIDAR_CMN', 'integracion.paEscribirCuadroModificado', 1, 'PENDIENTE',
                    (SELECT s.AnoEje, s.SecEjec, s.CentroCosto, s.Codigo,
                            Comentario = @Comentario,
                            /* El paquete viaja en el request para que el error de
                               SIGA, si lo hay, se pueda leer contra el Anexo 4
                               concreto y no solo contra la solicitud. */
                            Anexo4 = (SELECT TOP 1 p.Codigo
                                        FROM cmn.PaqueteSolicitud AS ps
                                        JOIN cmn.Paquete AS p ON p.IdPaquete = ps.IdPaquete
                                       WHERE ps.IdSolicitud = s.IdSolicitud
                                         AND ps.Activo = 1 AND p.Anulado = 0),
                            Items = (SELECT COUNT(*) FROM cmn.SolicitudItem AS i2
                                      WHERE i2.IdSolicitud = s.IdSolicitud AND i2.Activo = 1)
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                    @Cuenta, @Ahora, @Equipo, @Programa
                  FROM @Lote            AS l
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = l.IdExpediente
                  JOIN cmn.Solicitud    AS s ON s.IdExpediente = e.IdExpediente AND s.Activo = 1;

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

        COMMIT TRANSACTION; SET @TranPropia = 0;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = @CodigoModulo,
             @Entidad = 'sigcm.Expediente', @IdEntidad = @IdExpediente,
             @Accion = @CodigoTransicion, @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta,
             @ActorRol = @CodigoRol, @IdActorUnidad = @IdUnidad,
             @OrigenIp = @Ip, @Equipo = @Equipo, @Programa = @Programa;

        /* Version del expediente de referencia, para que el llamador de un solo
           expediente siga leyendo el mismo campo que antes. Con lote, cada uno
           trae la suya en Expedientes. */
        SET @VersionNueva = (SELECT Version FROM sigcm.Expediente WHERE IdExpediente = @IdExpediente);

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente     AS IdExpediente,
                   @CodigoExpediente AS Codigo,
                   @EstadoActual     AS CodigoEstadoAnterior,
                   @EstadoDestino    AS CodigoEstado,
                   @VersionNueva     AS Version,
                   @CantidadLote     AS ExpedientesMovidos,
                   @Encoladas        AS OperacionesEncoladas,
                   @IdObservacion    AS IdObservacion,
                   Expedientes = JSON_QUERY(COALESCE((
                       SELECT e.IdExpediente, e.Codigo, e.Version, e.CodigoEstado
                         FROM @Lote AS l
                         JOIN sigcm.Expediente AS e ON e.IdExpediente = l.IdExpediente
                        ORDER BY l.Orden
                          FOR JSON PATH), '[]')),
                   CASE WHEN @CantidadLote = 1
                        THEN N'Se registro la accion satisfactoriamente.'
                        ELSE CONCAT(N'Se registro la accion sobre ', @CantidadLote,
                                    N' expedientes.') END AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        /* Solo se deshace la transaccion que ESTA rutina abrio.

           Antes decia "IF @@TRANCOUNT > 0 ROLLBACK", y eso deshacia tambien la
           transaccion de quien llama. Casi todos los errores de aqui son de
           validacion y ocurren ANTES de abrir nada: con la version anterior, un
           "falta IdExpediente" bastaba para tirar abajo el trabajo del llamador,
           que ni siquiera sabria por que. Ademas, bajo INSERT ... EXEC el motor
           prohibe el ROLLBACK y el error real quedaba tapado por un 3915. */
        IF @TranPropia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
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
    DECLARE @TranPropia bit = 0;

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
        /* Solo se deshace la transaccion que ESTA rutina abrio.

           Antes decia "IF @@TRANCOUNT > 0 ROLLBACK", y eso deshacia tambien la
           transaccion de quien llama. Casi todos los errores de aqui son de
           validacion y ocurren ANTES de abrir nada: con la version anterior, un
           "falta IdExpediente" bastaba para tirar abajo el trabajo del llamador,
           que ni siquiera sabria por que. Ademas, bajo INSERT ... EXEC el motor
           prohibe el ROLLBACK y el error real quedaba tapado por un 3915. */
        IF @TranPropia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

PRINT 'F004 aplicada: motor de transiciones y encolado.';
GO
