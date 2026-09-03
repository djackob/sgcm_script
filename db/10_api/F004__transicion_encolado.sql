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

  El destino tampoco se escribe aqui. Casi siempre es el de la tabla, pero lo
  subsanado vuelve a quien observo, y eso depende del expediente. Ese calculo
  vive en sigcm.fnEstadoDestinoTransicion (F001) y lo llaman por igual el motor,
  la lista de acciones de la seccion 1 y las bandejas de F002 y F005: una sola
  definicion, para que el boton no anuncie un destino y la ejecucion haga otro.

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
    "IdResponsableDestino": null,   // opcional; a que PERSONA se deriva (F008)
    "Datos": { }                    // opcional, se guarda en el historial
  }

  ---------------------------------------------------------------------------
  DERIVAR A UNA PERSONA
  ---------------------------------------------------------------------------
  IdResponsableDestino permite que el jefe elija a quien le pasa el expediente
  dentro del rol que el estado destino ya declaro: a un coordinador concreto, o
  directo a un especialista. Los destinos legitimos los define el arbol de
  sigcm.RolDerivacion y los resuelve sigcm.fnDestinatarioDerivacion (F008), la
  MISMA funcion con la que la pantalla arma su lista. Una sola definicion: si la
  pantalla lo ofrece, aqui se acepta.

  Es OPCIONAL y omitirlo se comporta exactamente como antes. Cuando no llega, el
  expediente queda a nombre del puesto y lo toma quien corresponda.

  Y aun cuando llega, IdResponsableActual es una INDICACION, nunca el unico
  filtro de la bandeja: cmn.paListarSolicitud sigue resolviendo por unidad y rol.
  Si la persona se va de la entidad, su reemplazo ve el expediente sin que nadie
  tenga que reasignarlo. Filtrar la bandeja solo por responsable volveria a
  crear el expediente huerfano; no se haga.
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

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente AS IdExpediente,
                   @CodigoEstado AS CodigoEstadoActual,
                   @Version      AS Version,
                   Transiciones = JSON_QUERY(COALESCE((
                       SELECT t.CodigoTransicion,
                              /* Nombre y destino salen de la funcion, no de la
                                 tabla: lo subsanado vuelve a quien observo, y el
                                 boton tiene que anunciar lo mismo que el motor
                                 va a hacer al pulsarlo. */
                              dest.NombreAccion,
                              dest.CodigoEstadoDestino,
                              EstadoDestino = d.Nombre,
                              t.RequiereComentario, t.RequiereFirma, t.DocumentoRequerido,
                              t.EncolaIntegracion, t.GeneraObservacion
                         FROM sigcm.Transicion AS t
                        CROSS APPLY sigcm.fnEstadoDestinoTransicion(
                                        @IdExpediente, t.CodigoTransicion,
                                        t.CodigoEstadoDestino, t.NombreAccion) AS dest
                         JOIN sigcm.Estado     AS d ON d.CodigoEstado = dest.CodigoEstadoDestino
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
                @IdResponsableDestino uniqueidentifier,
                @Datos           nvarchar(max);

        SELECT @IdExpediente     = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @CodigoTransicion = CodigoTransicion,
               @VersionCliente   = Version,
               @Comentario       = Comentario,
               @IdUnidadDestino  = TRY_CONVERT(uniqueidentifier, IdUnidadDestino),
               @IdResponsableDestino = TRY_CONVERT(uniqueidentifier, IdResponsableDestino),
               @Datos            = Datos
        FROM OPENJSON(@parametro)
        WITH (
            IdExpediente     varchar(50),
            CodigoTransicion varchar(70),
            Version          int,
            Comentario       nvarchar(max),
            IdUnidadDestino  varchar(50),
            IdResponsableDestino varchar(50),
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
                @RolFirmaRequerida varchar(40), @AccionObservacion varchar(15);

        SELECT @EstadoDestino        = CodigoEstadoDestino,
               @NombreAccion         = NombreAccion,
               @RequiereComentario   = RequiereComentario,
               @RequiereFirma        = RequiereFirma,
               @DocumentoRequerido   = DocumentoRequerido,
               @EncolaIntegracion    = EncolaIntegracion,
               @OperacionIntegracion = OperacionIntegracion,
               @GeneraObservacion    = GeneraObservacion,
               @RolFirmaRequerida    = RolFirmaRequerida,
               @AccionObservacion    = AccionObservacion
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

        /* ---- Destino real --------------------------------------------- */
        /*
          El destino de la tabla es el punto de partida, no siempre la respuesta:
          lo subsanado vuelve a quien observo (sigcm.fnEstadoDestinoTransicion,
          F001). Se resuelve AQUI, antes de enrutar y antes de abrir la
          transaccion, por dos razones:

          - CMN_SUBS_JEFE_ENVIAR es tambien la transicion que CIERRA la
            observacion (S018). Resolver el destino mas abajo, dentro del bucle
            y despues del cierre, leeria una observacion ya CERRADA y el
            expediente terminaria en el destino fijo: exactamente el defecto que
            esto corrige, con la pantalla anunciando "vuelve a OA" y el motor
            mandandolo a Abastecimiento.
          - El rol destino, la unidad y la validacion de IdResponsableDestino se
            calculan a partir del destino. Si se resolviera despues, se enrutaria
            contra un estado que no es al que se va.

          El lote tiene que resolver un unico destino, por el mismo motivo por el
          que tiene que estar todo en el mismo estado: si no, una sola accion
          significaria cosas distintas para cada expediente y no habria una
          transicion que ejecutar.
        */
        DECLARE @EstadoDestinoTabla varchar(60) = @EstadoDestino;

        SELECT TOP 1 @EstadoDestino = dest.CodigoEstadoDestino,
                     @NombreAccion  = dest.NombreAccion
          FROM @Lote AS l
         CROSS APPLY sigcm.fnEstadoDestinoTransicion(
                         l.IdExpediente, @CodigoTransicion,
                         @EstadoDestinoTabla, @NombreAccion) AS dest
         ORDER BY l.Orden;

        IF EXISTS (SELECT 1
                     FROM @Lote AS l
                    CROSS APPLY sigcm.fnEstadoDestinoTransicion(
                                    l.IdExpediente, @CodigoTransicion,
                                    @EstadoDestinoTabla, @NombreAccion) AS dest
                    WHERE dest.CodigoEstadoDestino <> @EstadoDestino)
        BEGIN
            DECLARE @errDestLote nvarchar(500) = CONCAT(
                'CONFLICTO_LOTE: los expedientes seleccionados no vuelven todos al mismo destino. ',
                'Lo observado por la Oficina de Administracion y lo observado por Abastecimiento ',
                'regresan por caminos distintos: envielos por separado.');
            THROW 51224, @errDestLote, 1;
        END

        /* El rol se comprueba contra la tabla, no contra una lista en codigo. */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol
                        WHERE CodigoTransicion = @CodigoTransicion AND CodigoRol = @CodigoRol)
        BEGIN
            DECLARE @errRol nvarchar(500) = CONCAT(
                'NO_AUTORIZADO: el rol ', @CodigoRol, ' no puede ejecutar "', @NombreAccion, '".');
            THROW 51216, @errRol, 1;
        END

        IF @CodigoTransicion IN ('REQ_INICIAR_INDAGACION', 'REQ_INICIAR_FILTROS')
           AND EXISTS (
               SELECT 1
                 FROM @Lote AS l
                 JOIN requerimiento.Requerimiento AS r
                   ON r.IdExpediente = l.IdExpediente AND r.Activo = 1
                WHERE r.CodigoTipoContratacion <> 'LOCACION')
        BEGIN
            THROW 51232,
                'CONFLICTO_TIPO: la indagacion uno a uno y los filtros de idoneidad solo aplican a locacion de servicios.',
                1;
        END

        IF @RequiereComentario = 1 AND NULLIF(LTRIM(RTRIM(@Comentario)), '') IS NULL
        BEGIN
            DECLARE @errCom nvarchar(400) = CONCAT(
                'VALIDACION_COMENTARIO: "', @NombreAccion, '" exige registrar el motivo.');
            THROW 51217, @errCom, 1;
        END

        /*
          Si la transicion declara un documento, tiene que existir en su version
          vigente. La FIRMA es otro requisito, y solo aplica cuando RequiereFirma
          vale 1: generar el Anexo 4 deposita el PDF y lo remite, no lo firma;
          firmarlo es el paso del jefe.

          RolFirmaRequerida (V011) precisa cual firma cuando si se exige:
            NULL  -> la version tiene que estar FIRMADO (todas las firmas).
            <rol> -> alcanza con la firma vigente de ese rol.
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
                                @RequiereFirma = 0
                             OR (@RolFirmaRequerida IS NULL AND dv.Estado = 'FIRMADO')
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
                    CASE WHEN @RequiereFirma = 0 THEN ''
                         WHEN @RolFirmaRequerida IS NULL
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
            3. Si exactamente una unidad CON centro de costo SIGA tiene ese rol,
               se usa esa. Es el caso de OA y de Abastecimiento, que son unicas
               en la entidad. Las unidades semilla sin centro (UO-OA) no cuentan:
               si se mezclaran, esta regla nunca dispararia y el expediente se
               quedaria en el area usuaria con un estado de OA.
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
              JOIN sigcm.Unidad AS n ON n.IdUnidad = ur.IdUnidad
             WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1 AND n.Activo = 1
               AND NULLIF(LTRIM(RTRIM(n.CentroCostoSiga)), '') IS NOT NULL
               AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()));

            IF @Candidatas = 1
                SELECT @UnidadUnicaRol = MIN(ur.IdUnidad)
                  FROM sigcm.UsuarioRol AS ur
                  JOIN sigcm.Unidad AS n ON n.IdUnidad = ur.IdUnidad
                 WHERE ur.CodigoRol = @RolDestino AND ur.Activo = 1 AND n.Activo = 1
                   AND NULLIF(LTRIM(RTRIM(n.CentroCostoSiga)), '') IS NOT NULL
                   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()));
        END

        /* ---- Derivacion a una persona --------------------------------- */
        /*
          El destinatario elegido tiene que ser uno de los que el arbol habilita
          para ESTE actor en ESTE modulo, y ademas ejercer el rol que el estado
          destino declara. Las dos condiciones, no una:

          - Sin la primera, cualquier cliente podria pasarle el expediente a
            quien quisiera con solo mandar un identificador; la lista de la
            pantalla seria una sugerencia y no un control.
          - Sin la segunda, un jefe podria derivar a un coordinador una
            transicion cuyo estado destino es del especialista, y el expediente
            quedaria a nombre de alguien que no lo ve en su bandeja.

          Se valida con la misma funcion que alimenta la pantalla, para que no
          puedan discrepar. El diagnostico distingue los dos motivos porque
          "no autorizado" a secas deja al usuario sin saber que corregir.
        */
        DECLARE @UnidadResponsableDestino uniqueidentifier = NULL;

        IF @IdResponsableDestino IS NOT NULL
        BEGIN
            SELECT @UnidadResponsableDestino = d.IdUnidad
              FROM sigcm.fnDestinatarioDerivacion(@CodigoModulo, @CodigoRol, @IdUnidad) AS d
             WHERE d.IdUsuario = @IdResponsableDestino
               AND d.CodigoRol = @RolDestino;

            IF @UnidadResponsableDestino IS NULL
            BEGIN
                DECLARE @errDest nvarchar(500);

                IF EXISTS (SELECT 1 FROM sigcm.fnDestinatarioDerivacion(@CodigoModulo, @CodigoRol, @IdUnidad) AS d
                            WHERE d.IdUsuario = @IdResponsableDestino)
                    SET @errDest = CONCAT(
                        'NO_AUTORIZADO: la persona elegida no ejerce el rol ', @RolDestino,
                        ', que es al que corresponde el expediente tras la accion "', @NombreAccion, '".');
                ELSE
                    SET @errDest = CONCAT(
                        'NO_AUTORIZADO: el rol ', @CodigoRol,
                        ' no puede derivar a esa persona en el modulo ', @CodigoModulo,
                        '. Revise sigcm.RolDerivacion o vuelva a cargar la lista de destinatarios.');

                THROW 51220, @errDest, 1;
            END

            /* La unidad la manda la persona: derivar a alguien es mandarle el
               expediente a donde esa persona ejerce, no a otra parte. Un
               IdUnidadDestino que contradiga eso seria una instruccion
               imposible de cumplir. */
            SET @IdUnidadDestino = @UnidadResponsableDestino;
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
                @IdObsAfectada uniqueidentifier;

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
               SET CodigoEstado                  = @EstadoDestino,
                   Version                       = @VersionNuevaExp,
                   IdUnidadActual                = @IdUnidadDestinoExp,
                   /* Sin IdResponsableDestino el responsable concreto se deja
                      sin fijar, como siempre: la bandeja se resuelve por rol y
                      unidad, y asignar a una persona en una unidad con varios
                      titulares seria inventar una regla que la Directiva no
                      establece.

                      Con el, queda a nombre de quien el jefe eligio. Sigue
                      siendo una indicacion y no un candado: la bandeja no
                      cambia de criterio, asi que el expediente no se pierde si
                      esa persona deja la entidad. */
                   IdResponsableActual           = @IdResponsableDestino,
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
                (@IdExpLoop, @EstadoActual, @EstadoDestino, @CodigoTransicion,
                 @Comentario, @IdUsuario, @CodigoRol, @IdUnidad,
                 CASE WHEN ISJSON(@Datos) = 1 THEN @Datos ELSE N'{}' END,
                 @Cuenta, @Equipo, @Programa);

            /* ---- Observacion ------------------------------------------ */
            /*
              CodigoEstadoRetorno se toma del estado en que ESTABA el expediente
              al observarse. Ahi vive la regla del mockup: lo que observa OA
              vuelve a OA, lo que observa Abastecimiento vuelve a Abastecimiento.
              Es dato, no un condicional por unidad.
            */
            IF @GeneraObservacion = 1
            BEGIN
                IF EXISTS (SELECT 1 FROM sigcm.Observacion
                            WHERE IdExpediente = @IdExpLoop
                              AND Estado IN ('PENDIENTE','RECEPCIONADA') AND Activo = 1)
                BEGIN
                    DECLARE @errObs nvarchar(400) = CONCAT(
                        'CONFLICTO_OBSERVACION: el expediente ', @CodigoExpLoop,
                        ' ya tiene una observacion abierta.');
                    THROW 51220, @errObs, 1;
                END

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

            /* ---- Avance y cierre de la observacion --------------------- */
            /*
              La contraparte de GeneraObservacion. Aquella marca dice que
              transiciones ABREN una observacion; AccionObservacion (V029) dice
              cuales la hacen avanzar y hasta donde, y el reparto concreto vive
              en la semilla S018. El motor sigue sin saber que existe CMN.

              Sin esto la observacion nacia PENDIENTE y se quedaba asi para
              siempre, y como el guard de CONFLICTO_OBSERVACION de mas arriba
              mira justamente PENDIENTE y RECEPCIONADA, un expediente observado
              una vez no podia volver a observarse nunca.

              Se toma la observacion abierta mas reciente del expediente. Solo
              puede haber una -lo garantiza UQ_sigcm_Observacion_Abierta- pero
              el TOP 1 con orden explicito evita depender de eso para los datos
              anteriores a esta correccion.

              Si no hay ninguna en el estado que la accion espera, no se hace
              nada y la transicion sigue: un expediente que llego a CMN_OBSERVADO
              por un camino antiguo no tiene por que ver abortado su tramite.
            */
            IF @AccionObservacion IS NOT NULL
            BEGIN
                SET @IdObsAfectada =
                    (SELECT TOP 1 o.IdObservacion
                       FROM sigcm.Observacion AS o
                      WHERE o.IdExpediente = @IdExpLoop
                        AND o.Activo = 1
                        AND ((@AccionObservacion = 'RECEPCIONAR' AND o.Estado = 'PENDIENTE')
                          OR (@AccionObservacion = 'SUBSANAR'    AND o.Estado IN ('PENDIENTE','RECEPCIONADA'))
                          OR (@AccionObservacion = 'CERRAR'      AND o.Estado <> 'CERRADA'))
                      ORDER BY o.FechaCreacionAuditoria DESC);

                IF @IdObsAfectada IS NOT NULL
                BEGIN
                    /*
                      Los COALESCE cubren los flujos que no tienen un escalon
                      para cada paso. En Requerimiento, REQ_SUBSANAR va de
                      REQ_OBSERVADO directo a REQ_BORRADOR y CIERRA: nadie
                      recepciono ni subsano por separado, y sin rellenar esas
                      marcas la fila violaria CK_sigcm_Observacion_Recepcion,
                      que exige RecepcionadaEn para cualquier estado distinto de
                      PENDIENTE. En CMN ya vienen puestas por los pasos previos y
                      el COALESCE las respeta: la recepcion conserva a quien
                      recepciono de verdad.

                      Respuesta se llena con el comentario de la transicion que
                      subsana, que es donde el flujo lo exige
                      (RequiereComentario=1 en CMN_SUBSANAR y en REQ_SUBSANAR).
                    */
                    UPDATE sigcm.Observacion
                       SET Estado = CASE @AccionObservacion
                                        WHEN 'RECEPCIONAR' THEN 'RECEPCIONADA'
                                        WHEN 'SUBSANAR'    THEN 'SUBSANADA'
                                        ELSE                    'CERRADA'
                                    END,
                           IdRecepcionadaPor = COALESCE(IdRecepcionadaPor, @IdUsuario),
                           RecepcionadaEn    = COALESCE(RecepcionadaEn,    @Ahora),
                           IdSubsanadaPor    = CASE WHEN @AccionObservacion = 'RECEPCIONAR'
                                                    THEN IdSubsanadaPor
                                                    ELSE COALESCE(IdSubsanadaPor, @IdUsuario) END,
                           SubsanadaEn       = CASE WHEN @AccionObservacion = 'RECEPCIONAR'
                                                    THEN SubsanadaEn
                                                    ELSE COALESCE(SubsanadaEn, @Ahora) END,
                           Respuesta         = CASE WHEN @AccionObservacion = 'RECEPCIONAR'
                                                    THEN Respuesta
                                                    ELSE COALESCE(Respuesta,
                                                                  NULLIF(LTRIM(RTRIM(@Comentario)), '')) END,
                           CerradaEn         = CASE WHEN @AccionObservacion = 'CERRAR'
                                                    THEN COALESCE(CerradaEn, @Ahora)
                                                    ELSE CerradaEn END,
                           UsuarioModificacionAuditoria  = @Cuenta,
                           FechaModificacionAuditoria    = @Ahora,
                           EquipoModificacionAuditoria   = @Equipo,
                           ProgramaModificacionAuditoria = @Programa
                     WHERE IdObservacion = @IdObsAfectada;

                    /* La respuesta del API informa que observacion se movio,
                       igual que informa cual se creo. Con lote se devuelve la
                       del primer expediente, como el resto de campos escalares. */
                    SET @IdObservacion = COALESCE(@IdObservacion, @IdObsAfectada);
                END
            END

            SET @Idx = @Idx + 1;
        END

        /* A partir de aqui el encolado trabaja sobre todo el lote de una vez. */
        SET @IdExpediente = (SELECT TOP 1 IdExpediente FROM @Lote ORDER BY Orden);

        /* ---- Dato del modulo que la accion trae consigo ---------------- */
        /*
          LA TIPIFICACION YA NO SE ESCRIBE AQUI.

          Hasta ahora, al conformar el Anexo 3, el especialista de Abastecimiento
          declaraba si la modificacion era ordinaria o urgente y esta rutina
          guardaba esa marca en cmn.Solicitud. El negocio la movio a su sitio: la
          declara el AREA USUARIA al registrar la solicitud (cmn.paRegistrarSolicitud),
          porque de ella depende el plazo -el Anexo 4 ordinario se genera los
          viernes, el extraordinario cualquier dia- y quien conoce la urgencia es
          quien tiene la necesidad, no quien la evalua despues.

          El bloque no se convierte en "acepta el dato si viene": una transicion
          que pudiera sobrescribir la tipificacion borraria la justificacion que
          la respalda -son un solo hecho- sin que nadie lo pidiera. Si llega
          TipoInclusion en el POST, se ignora.

          El error 51224 queda libre dentro del bloque 51200-51299.
        */

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
            ELSE IF @OperacionIntegracion = 'CREAR_CUADRO_ADQUISICION'
            BEGIN
                IF @CodigoModulo <> 'REQUERIMIENTO'
                    THROW 51225,
                        'CONFLICTO_CONFIGURACION: CREAR_CUADRO_ADQUISICION solo aplica al modulo REQUERIMIENTO.',
                        1;

                DECLARE @reqSinPedido varchar(40);
                SELECT TOP 1 @reqSinPedido = r.Codigo
                  FROM @Lote AS l
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = l.IdExpediente
                  JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente AND r.Activo = 1
                 WHERE NOT EXISTS (
                       SELECT 1
                         FROM requerimiento.RequerimientoPedido AS p
                        WHERE p.IdRequerimiento = r.IdRequerimiento AND p.Activo = 1);

                IF @reqSinPedido IS NOT NULL
                BEGIN
                    DECLARE @errPed nvarchar(400) = CONCAT(
                        'INTEGRACION_SIGA: el requerimiento ', @reqSinPedido,
                        ' no tiene pedido SIGA. Vincule el pedido de requerimiento antes de generar el cuadro.');
                    THROW 51229, @errPed, 1;
                END

                INSERT INTO integracion.Operacion
                    (IdempotenciaKey, IdExpediente, IdSolicitud, IdSolicitudItem,
                     IdRequerimiento, Operacion, Procedimiento, Secuencia, Estado, RequestJson,
                     UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                     EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                SELECT
                    CONCAT(CONVERT(varchar(36), r.IdRequerimiento), ':',
                           CONVERT(varchar(10), e.Version), ':CREAR_CUADRO_ADQUISICION'),
                    e.IdExpediente, NULL, NULL,
                    r.IdRequerimiento,
                    'CREAR_CUADRO_ADQUISICION', 'integracion.paEscribirCuadroAdquisicion', 1, 'PENDIENTE',
                    (SELECT
                        IdRequerimiento = r.IdRequerimiento,
                        CodigoRequerimiento = r.Codigo,
                        AnoEje = p.AnoEje,
                        SecEjec = p.SecEjec,
                        NumeroPedido = RIGHT('000000' + LTRIM(RTRIM(p.NumeroPedido)), 6),
                        Tdr = JSON_QUERY(ISNULL(tdr.Tdr, N'{}'))
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                    @Cuenta, @Ahora, @Equipo, @Programa
                  FROM @Lote AS l
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = l.IdExpediente
                  JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente AND r.Activo = 1
                  JOIN requerimiento.RequerimientoPedido AS p
                    ON p.IdRequerimiento = r.IdRequerimiento AND p.Activo = 1
                  OUTER APPLY (
                      SELECT TOP 1 JSON_QUERY(dv.Payload, '$.Tdr') AS Tdr
                        FROM sigcm.DocumentoExpediente AS de
                        JOIN sigcm.Documento AS doc
                          ON doc.IdDocumento = de.IdDocumento AND doc.Activo = 1
                        JOIN sigcm.DocumentoVersion AS dv
                          ON dv.IdDocumento = doc.IdDocumento AND dv.Activo = 1
                       WHERE de.IdExpediente = e.IdExpediente
                         AND doc.CodigoTipoDocumento = 'REQ_TDR_LOCACION'
                       ORDER BY dv.Version DESC
                  ) AS tdr;

                SET @Encoladas = @@ROWCOUNT;

                IF @Encoladas = 0
                    THROW 51230,
                        'INTEGRACION_SIGA: no se pudo encolar la generacion del cuadro de adquisicion.',
                        1;
            END
            ELSE IF @OperacionIntegracion = 'CREAR_ORDEN_SERVICIO'
            BEGIN
                IF @CodigoModulo <> 'REQUERIMIENTO'
                    THROW 51225,
                        'CONFLICTO_CONFIGURACION: CREAR_ORDEN_SERVICIO solo aplica al modulo REQUERIMIENTO.',
                        1;

                /* No consultar siga.vwCuadroAdquisicionPedido aqui: recorre
                   SIG_CUADRO_ADQUISICION y el clic de emitir O/S supera el
                   timeout de 30 s de la API. El SEC_CUADRO ya lo dejo el
                   worker en CREAR_CUADRO_ADQUISICION. */

                DECLARE @reqSinCuadro varchar(40);
                DECLARE @pedidoDiag varchar(80);
                SELECT TOP 1
                       @reqSinCuadro = r.Codigo,
                       @pedidoDiag = CONCAT(
                           'AnoEje=', p.AnoEje,
                           ', SecEjec=', p.SecEjec,
                           ', Pedido=', RIGHT('000000' + LTRIM(RTRIM(p.NumeroPedido)), 6))
                  FROM @Lote AS l
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = l.IdExpediente
                  JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente AND r.Activo = 1
                  JOIN requerimiento.RequerimientoPedido AS p ON p.IdRequerimiento = r.IdRequerimiento AND p.Activo = 1
                 WHERE NOT EXISTS (
                       SELECT 1
                         FROM requerimiento.OrdenServicio AS os
                        WHERE os.IdRequerimiento = r.IdRequerimiento
                          AND os.Activo = 1
                          AND os.SecCuadroSiga IS NOT NULL)
                   AND NOT EXISTS (
                       SELECT 1
                         FROM integracion.Operacion AS o
                        WHERE o.IdRequerimiento = r.IdRequerimiento
                          AND o.Operacion = 'CREAR_CUADRO_ADQUISICION'
                          AND o.Estado = 'COMPLETADO'
                          AND o.Activo = 1
                          AND TRY_CONVERT(bigint, JSON_VALUE(o.ResponseJson, '$.SecCuadro')) IS NOT NULL);

                IF @reqSinCuadro IS NOT NULL
                BEGIN
                    DECLARE @errCuadro nvarchar(700) = CONCAT(
                        'INTEGRACION_SIGA: no hay un cuadro de adquisicion generado para el requerimiento ',
                        @reqSinCuadro, ' (', @pedidoDiag, '). ',
                        'Ejecute antes la accion Generar cuadro de adquisicion y espere a que quede completada.');
                    THROW 51226, @errCuadro, 1;
                END

                DECLARE @reqSinProv varchar(40);
                SELECT TOP 1 @reqSinProv = r.Codigo
                  FROM @Lote AS l
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = l.IdExpediente
                  JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente AND r.Activo = 1
                 WHERE NULLIF(LTRIM(RTRIM(COALESCE(
                       JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Ruc'),
                       JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Ruc')))), '') IS NULL;

                IF @reqSinProv IS NOT NULL
                BEGIN
                    DECLARE @errProv nvarchar(500) = CONCAT(
                        'VALIDACION_PROVEEDOR: el requerimiento ', @reqSinProv,
                        ' no tiene RUC del locador en el Anexo 5 / Anexo 6.');
                    THROW 51227, @errProv, 1;
                END

                DECLARE @reqSinContratista varchar(40);
                DECLARE @rucDiag varchar(11);
                SELECT TOP 1
                       @reqSinContratista = r.Codigo,
                       @rucDiag = LEFT(REPLACE(COALESCE(
                           JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Ruc'),
                           JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Ruc')), ' ', ''), 11)
                  FROM @Lote AS l
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = l.IdExpediente
                  JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente AND r.Activo = 1
                 WHERE NOT EXISTS (
                       SELECT 1
                         FROM requerimiento.OrdenServicio AS os
                        WHERE os.IdRequerimiento = r.IdRequerimiento
                          AND os.Activo = 1 AND os.ProveedorSiga IS NOT NULL)
                   AND NOT EXISTS (
                       SELECT 1
                         FROM siga.SIG_CONTRATISTAS AS pr
                        WHERE pr.NRO_RUC = LEFT(REPLACE(COALESCE(
                                  JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Ruc'),
                                  JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Ruc')), ' ', ''), 11)
                          AND COALESCE(pr.ESTADO, 'A') <> 'I');

                IF @reqSinContratista IS NOT NULL
                BEGIN
                    DECLARE @errContratista nvarchar(500) = CONCAT(
                        'INTEGRACION_SIGA: el RUC ', ISNULL(@rucDiag, '(vacio)'),
                        ' del locador del requerimiento ', @reqSinContratista,
                        ' no existe en SIG_CONTRATISTAS o esta inactivo.');
                    THROW 51229, @errContratista, 1;
                END

                INSERT INTO integracion.Operacion
                    (IdempotenciaKey, IdExpediente, IdSolicitud, IdSolicitudItem,
                     IdRequerimiento, Operacion, Procedimiento, Secuencia, Estado, RequestJson,
                     UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                     EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                SELECT
                    CONCAT(CONVERT(varchar(36), r.IdRequerimiento), ':',
                           CONVERT(varchar(10), e.Version), ':CREAR_ORDEN_SERVICIO'),
                    e.IdExpediente, NULL, NULL,
                    r.IdRequerimiento,
                    'CREAR_ORDEN_SERVICIO', 'integracion.paEscribirOrdenServicio', 1, 'PENDIENTE',
                    (SELECT
                        IdRequerimiento = r.IdRequerimiento,
                        CodigoRequerimiento = r.Codigo,
                        AnoEje = p.AnoEje,
                        SecEjec = p.SecEjec,
                        SecCuadro = c.SecCuadro,
                        Proveedor = COALESCE(osPrev.ProveedorSiga, prov.Proveedor),
                        FechaOrden = CONVERT(varchar(30), @Ahora, 126),
                        Concepto = LEFT(r.Denominacion, 350),
                        PlazoEntrega = r.PlazoDias,
                        DocumentoReferencia = r.Codigo
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                    @Cuenta, @Ahora, @Equipo, @Programa
                  FROM @Lote AS l
                  JOIN sigcm.Expediente AS e ON e.IdExpediente = l.IdExpediente
                  JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente AND r.Activo = 1
                  JOIN requerimiento.RequerimientoPedido AS p ON p.IdRequerimiento = r.IdRequerimiento AND p.Activo = 1
                  LEFT JOIN requerimiento.OrdenServicio AS osPrev
                    ON osPrev.IdRequerimiento = r.IdRequerimiento AND osPrev.Activo = 1
                  CROSS APPLY (
                      SELECT TOP 1 x.SecCuadro
                        FROM (
                              SELECT os.SecCuadroSiga AS SecCuadro, 0 AS Ord
                                FROM requerimiento.OrdenServicio AS os
                               WHERE os.IdRequerimiento = r.IdRequerimiento
                                 AND os.Activo = 1
                                 AND os.SecCuadroSiga IS NOT NULL
                              UNION ALL
                              SELECT TRY_CONVERT(bigint, JSON_VALUE(o.ResponseJson, '$.SecCuadro')), 1
                                FROM integracion.Operacion AS o
                               WHERE o.IdRequerimiento = r.IdRequerimiento
                                 AND o.Operacion = 'CREAR_CUADRO_ADQUISICION'
                                 AND o.Estado = 'COMPLETADO'
                                 AND o.Activo = 1
                          ) AS x
                       WHERE x.SecCuadro IS NOT NULL
                       ORDER BY x.Ord
                  ) AS c
                  OUTER APPLY (
                      SELECT TOP 1 pr.PROVEEDOR AS Proveedor
                        FROM siga.SIG_CONTRATISTAS AS pr
                       WHERE pr.NRO_RUC = LEFT(REPLACE(COALESCE(
                                 JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Ruc'),
                                 JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Ruc')), ' ', ''), 11)
                         AND COALESCE(pr.ESTADO, 'A') <> 'I'
                       ORDER BY pr.PROVEEDOR
                  ) AS prov
                 WHERE EXISTS (
                       SELECT 1 FROM requerimiento.CertificacionCcp AS ccp
                        WHERE ccp.IdRequerimiento = r.IdRequerimiento
                          AND ccp.Activo = 1
                          AND NULLIF(LTRIM(RTRIM(ccp.NumeroCcp)), '') IS NOT NULL)
                   AND COALESCE(osPrev.ProveedorSiga, prov.Proveedor) IS NOT NULL;

                SET @Encoladas = @@ROWCOUNT;

                IF @Encoladas = 0
                    THROW 51228,
                        'CONFLICTO_CCP: no hay CCP registrada. Cargue la certificacion presupuestaria antes de emitir la orden.',
                        1;

                MERGE requerimiento.OrdenServicio AS d
                USING (
                    SELECT r.IdRequerimiento,
                           CorreoLocador = COALESCE(
                               NULLIF(LTRIM(RTRIM(JSON_VALUE(r.DatosAdicionales, '$.Proveedores[0].Email'))), ''),
                               NULLIF(LTRIM(RTRIM(JSON_VALUE(r.DatosAdicionales, '$.Proveedor.Email'))), '')),
                           CorreoAu = NULLIF(LTRIM(RTRIM(u.Correo)), '')
                      FROM @Lote AS l
                      JOIN sigcm.Expediente AS e ON e.IdExpediente = l.IdExpediente
                      JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente AND r.Activo = 1
                      LEFT JOIN sigcm.Usuario AS u ON u.IdUsuario = r.IdResponsable
                ) AS s
                ON d.IdRequerimiento = s.IdRequerimiento
                WHEN MATCHED THEN
                    UPDATE SET d.EstadoIntegracion = 'PENDIENTE',
                               d.ErrorIntegracion = NULL,
                               d.CorreoLocador = COALESCE(s.CorreoLocador, d.CorreoLocador),
                               d.CorreoAreaUsuaria = COALESCE(s.CorreoAu, d.CorreoAreaUsuaria),
                               d.UsuarioModificacionAuditoria = @Cuenta,
                               d.FechaModificacionAuditoria = @Ahora,
                               d.EquipoModificacionAuditoria = @Equipo,
                               d.ProgramaModificacionAuditoria = @Programa
                WHEN NOT MATCHED THEN
                    INSERT (IdRequerimiento, EstadoIntegracion, CorreoLocador, CorreoAreaUsuaria,
                            UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                    VALUES (s.IdRequerimiento, 'PENDIENTE', s.CorreoLocador, s.CorreoAu,
                            @Cuenta, @Equipo, @Programa);
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
