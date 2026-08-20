/*
===============================================================================
  SIGCM - F003 : Documentos, firmas e invalidacion por version
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51600-51699

  QUE RESUELVE
  ------------
  Es la pieza que faltaba para que el flujo pase de "Por firmar Anexo 3". El
  motor de transiciones (F004) exige, para las acciones marcadas con
  DocumentoRequerido, que el documento exista en su version vigente y FIRMADO.
  Sin estas rutinas no habia forma de crear ese documento ni de firmarlo, y el
  unico que existia en la base se habia insertado a mano.

  Sirve a los dos modulos: el Anexo 3 y el Anexo 4 de CMN, y las EETT, TDR y
  anexos de Requerimiento. El tipo de documento es un dato de
  sigcm.TipoDocumento, no una rama de codigo.

  ---------------------------------------------------------------------------
  DONDE SE GENERA EL PDF
  ---------------------------------------------------------------------------
  En el frontend. Aqui NO se arma el archivo: se recibe ya subido al file
  server y se registra su URL. La base guarda tres cosas distintas:

      Payload            los datos con los que se armo, en JSON. Es lo que
                         permite reimprimir o comparar versiones.
      GeneradoDocumento  la URL del PDF en el file server.
      ArchivoHash        la huella del archivo, para detectar que el PDF que
                         hoy responde esa URL sigue siendo el que se firmo.

  ---------------------------------------------------------------------------
  LA REGLA QUE JUSTIFICA EL VERSIONADO
  ---------------------------------------------------------------------------
  CMN-18 y REQ-29 del analisis: si se actualiza un documento ya firmado, la
  firma anterior se invalida y hay que firmar de nuevo. Por eso el documento
  tiene versiones y no un solo registro que se sobrescribe: la version firmada
  se conserva, y la correccion nace como version nueva en BORRADOR. Sin esto,
  un expediente podria enviarse con una firma que ya no corresponde al contenido.

  Estados de una version:  BORRADOR -> FIRMADO -> ANULADA
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. sigcm.paRegistrarDocumento                                             */
/* ========================================================================== */

/*
  Registra el documento generado por el frontend y lo vincula al expediente.

  Entrada:
  {
    "Actor": { ... },
    "IdExpediente": "...",           uno solo
    "IdExpedientes": ["...","..."],  o varios, para un documento consolidado
    "CodigoTipoDocumento": "CMN_ANEXO_3_SOLICITUD_MODIFICACION",
    "GeneradoDocumento": "http://.../files/cmn/2026....pdf",
    "NombreDocumento": "Anexo 3 - CMN-2026-000002.pdf",
    "Numero": "A4-2026-000007",      opcional; ver numeracion, mas abajo
    "ArchivoHash": "...",            opcional
    "Payload": { ... },              opcional, los datos con que se armo
    "MotivoVersion": "..."           opcional
  }

  ---------------------------------------------------------------------------
  UN DOCUMENTO, VARIOS EXPEDIENTES
  ---------------------------------------------------------------------------
  El Anexo 4 puede cubrir varios Anexos 3 de areas usuarias distintas. En ese
  caso llega IdExpedientes con la lista y se crea UN solo documento enlazado a
  todos por sigcm.DocumentoExpediente, que ya era N:M desde V002.

  No se crea un documento por expediente. Si se hiciera, cada area usuaria
  tendria su propio Anexo 4 con su propia numeracion y sus propias firmas, y
  el "Anexo 4 unico que aprueba lo de varias oficinas" dejaria de existir en la
  base aunque el PDF lo mostrara. Ademas habria que firmar N veces lo mismo.

  NUMERACION
  Con un expediente, el numero sale de su codigo (CMN-2026-000002-Anexo 3), que
  es lo que se venia haciendo. Con varios no puede salir de ninguno de ellos
  —elegir uno seria arbitrario— y por eso el llamador manda Numero: es el codigo
  del paquete (A4-2026-000007), que cmn.paGenerarAnexo4 ya emitio.

  COMPORTAMIENTO SEGUN LO QUE YA EXISTA
  - No hay documento          -> se crea con la version 1 en BORRADOR.
  - La version vigente esta en BORRADOR -> se REEMPLAZA. Regenerar un borrador
    no es una version nueva: es el mismo borrador otra vez, y numerarlo llenaria
    el historial de ruido.
  - La version vigente esta FIRMADA -> se crea una version NUEVA en BORRADOR y
    la anterior queda ANULADA. Es la invalidacion de firma de CMN-18.
*/
CREATE OR ALTER PROCEDURE sigcm.paRegistrarDocumento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51600, 'JSON incorrecto.', 1;

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
        DECLARE @IdExpediente        uniqueidentifier,
                @CodigoTipoDocumento varchar(60),
                @GeneradoDocumento   nvarchar(1000),
                @NombreDocumento     nvarchar(1000),
                @NumeroPedido        varchar(80),
                @ArchivoHash         varchar(128),
                @Payload             nvarchar(max),
                @MotivoVersion       nvarchar(max);

        SELECT @IdExpediente        = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @CodigoTipoDocumento = CodigoTipoDocumento,
               @GeneradoDocumento   = GeneradoDocumento,
               @NombreDocumento     = NombreDocumento,
               @NumeroPedido        = Numero,
               @ArchivoHash         = ArchivoHash,
               @Payload             = Payload,
               @MotivoVersion       = MotivoVersion
        FROM OPENJSON(@parametro)
        WITH (
            IdExpediente        varchar(50),
            CodigoTipoDocumento varchar(60),
            GeneradoDocumento   nvarchar(1000),
            NombreDocumento     nvarchar(1000),
            Numero              varchar(80),
            ArchivoHash         varchar(128),
            Payload             nvarchar(max) AS JSON,
            MotivoVersion       nvarchar(max)
        );

        /* ---- Expedientes que cubre el documento ------------------------ */
        /* Se admite IdExpediente (uno) o IdExpedientes (varios). Se juntan en
           una sola tabla para que el resto de la rutina no tenga que preguntar
           por cual de los dos vino. */
        DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY, Orden int);

        INSERT INTO @Exp (IdExpediente, Orden)
        SELECT DISTINCT TRY_CONVERT(uniqueidentifier, value), 0
          FROM OPENJSON(@parametro, '$.IdExpedientes')
         WHERE TRY_CONVERT(uniqueidentifier, value) IS NOT NULL;

        IF @IdExpediente IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM @Exp WHERE IdExpediente = @IdExpediente)
            INSERT INTO @Exp (IdExpediente, Orden) VALUES (@IdExpediente, 0);

        IF NOT EXISTS (SELECT 1 FROM @Exp)
            THROW 51601, 'VALIDACION_PAYLOAD: falta IdExpediente o IdExpedientes.', 1;
        IF NULLIF(LTRIM(RTRIM(@CodigoTipoDocumento)), '') IS NULL
            THROW 51602, 'VALIDACION_PAYLOAD: falta CodigoTipoDocumento.', 1;
        IF NULLIF(LTRIM(RTRIM(@GeneradoDocumento)), '') IS NULL
            THROW 51603, 'VALIDACION_ARCHIVO: falta GeneradoDocumento. El PDF debe subirse al file server antes de registrarlo.', 1;

        IF ISJSON(ISNULL(@Payload, N'{}')) <> 1 SET @Payload = N'{}';
        SET @Payload = ISNULL(@Payload, N'{}');

        DECLARE @CantidadExp int = (SELECT COUNT(*) FROM @Exp);

        /* ---- Expediente y tipo ---------------------------------------- */
        /* El expediente "principal" es solo el que presta su codigo para la
           numeracion cuando el documento cubre uno solo. Se elige por codigo
           para que el resultado no dependa del orden en que llego el JSON. */
        DECLARE @CodigoModulo varchar(30), @CodigoExpediente varchar(40), @AnoEje smallint;

        SELECT TOP 1 @CodigoModulo = e.CodigoModulo,
                     @CodigoExpediente = e.Codigo,
                     @AnoEje = e.AnoEje,
                     @IdExpediente = e.IdExpediente
          FROM sigcm.Expediente AS e
          JOIN @Exp AS x ON x.IdExpediente = e.IdExpediente
         WHERE e.Anulado = 0 AND e.Activo = 1
         ORDER BY e.Codigo;

        IF @CodigoModulo IS NULL
            THROW 51604, 'NO_ENCONTRADO: el expediente no existe o esta anulado.', 1;

        /* Todos deben existir y ser del mismo modulo: un documento que cubriera
           expedientes de modulos distintos no tendria tipo valido para ambos. */
        IF EXISTS (SELECT 1 FROM @Exp AS x
                    WHERE NOT EXISTS (SELECT 1 FROM sigcm.Expediente AS e
                                       WHERE e.IdExpediente = x.IdExpediente
                                         AND e.Anulado = 0 AND e.Activo = 1
                                         AND e.CodigoModulo = @CodigoModulo))
            THROW 51606, 'VALIDACION_PAYLOAD: algun expediente de la lista no existe, esta anulado o es de otro modulo.', 1;

        /* Consolidar exige que el tipo lo admita. Es la unica comprobacion que
           impide colgar cinco expedientes de un Anexo 3, que es individual. */
        IF @CantidadExp > 1
           AND NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento
                            WHERE CodigoTipoDocumento = @CodigoTipoDocumento
                              AND AdmiteConsolidado = 1)
        BEGIN
            DECLARE @errCons nvarchar(400) = CONCAT(
                'VALIDACION_TIPO_DOCUMENTO: ', @CodigoTipoDocumento,
                ' no admite consolidado y se recibieron ', @CantidadExp, ' expedientes.');
            THROW 51607, @errCons, 1;
        END

        /* El tipo de documento debe pertenecer al modulo del expediente: sin
           esto se podria colgar un Anexo 4 de CMN a un requerimiento. */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumento
                        WHERE CodigoTipoDocumento = @CodigoTipoDocumento
                          AND CodigoModulo = @CodigoModulo AND Activo = 1)
        BEGIN
            DECLARE @errTipo nvarchar(400) = CONCAT(
                'VALIDACION_TIPO_DOCUMENTO: ', @CodigoTipoDocumento,
                ' no es un documento del modulo ', @CodigoModulo, '.');
            THROW 51605, @errTipo, 1;
        END

        /* ---- Documento existente -------------------------------------- */
        DECLARE @IdDocumento uniqueidentifier, @VersionVigente int, @EstadoVigente varchar(15);

        /* Basta con que CUALQUIERA de los expedientes ya tenga el documento de
           este tipo: es el mismo documento consolidado, y regenerarlo debe caer
           sobre el que ya existe en vez de crear un segundo. */
        SELECT TOP 1 @IdDocumento = d.IdDocumento,
                     @VersionVigente = d.VersionVigente
          FROM sigcm.Documento AS d
          JOIN sigcm.DocumentoExpediente AS de ON de.IdDocumento = d.IdDocumento
          JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente
         WHERE d.CodigoTipoDocumento = @CodigoTipoDocumento
           AND d.Anulado = 0 AND d.Activo = 1
         ORDER BY d.FechaCreacionAuditoria DESC;

        IF @IdDocumento IS NOT NULL
            SELECT @EstadoVigente = Estado
              FROM sigcm.DocumentoVersion
             WHERE IdDocumento = @IdDocumento AND Version = @VersionVigente;

        DECLARE @Ahora datetime = GETDATE();
        DECLARE @VersionNueva int;
        DECLARE @FirmaInvalidada bit = 0;

        BEGIN TRANSACTION; SET @TranPropia = 1;

        IF @IdDocumento IS NULL
        BEGIN
            /* Numeracion visible. Con un expediente sale de su codigo, que es lo
               que se venia haciendo y evita una secuencia por tipo. Con varios
               no puede salir de ninguno y la manda el llamador: es el codigo del
               paquete. */
            DECLARE @Numero varchar(80) =
                ISNULL(NULLIF(LTRIM(RTRIM(@NumeroPedido)), ''),
                       CONCAT(@CodigoExpediente, '-',
                              (SELECT NumeracionVisible FROM sigcm.TipoDocumento
                                WHERE CodigoTipoDocumento = @CodigoTipoDocumento)));

            IF @CantidadExp > 1 AND NULLIF(LTRIM(RTRIM(@NumeroPedido)), '') IS NULL
                THROW 51608, 'VALIDACION_PAYLOAD: un documento que cubre varios expedientes debe traer Numero propio.', 1;

            DECLARE @Doc TABLE (IdDocumento uniqueidentifier);

            INSERT INTO sigcm.Documento
                (CodigoTipoDocumento, Numero, Consolidado, VersionVigente,
                 UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                 EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            OUTPUT inserted.IdDocumento INTO @Doc
            VALUES
                (@CodigoTipoDocumento, @Numero,
                 CASE WHEN @CantidadExp > 1 THEN 1 ELSE 0 END, 1,
                 @Cuenta, @Ahora, @Equipo, @Programa);

            /* OUTPUT y no un SELECT por Numero: dos registros simultaneos con
               numeros distintos podrian intercalarse, y releer por Numero es un
               ida y vuelta a la tabla para un dato que la propia insercion ya
               conoce. */
            SELECT @IdDocumento = IdDocumento FROM @Doc;

            INSERT INTO sigcm.DocumentoExpediente (IdDocumento, IdExpediente)
            SELECT @IdDocumento, x.IdExpediente FROM @Exp AS x;

            SET @VersionNueva = 1;
        END
        ELSE IF @EstadoVigente = 'BORRADOR'
        BEGIN
            /* Se reemplaza el borrador en su sitio. */
            SET @VersionNueva = @VersionVigente;

            UPDATE sigcm.DocumentoVersion
               SET Payload = @Payload,
                   GeneradoDocumento = @GeneradoDocumento,
                   NombreDocumento = @NombreDocumento,
                   ArchivoHash = @ArchivoHash,
                   MotivoVersion = @MotivoVersion,
                   UsuarioModificacionAuditoria = @Cuenta,
                   FechaModificacionAuditoria = @Ahora,
                   EquipoModificacionAuditoria = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdDocumento = @IdDocumento AND Version = @VersionVigente;
        END
        ELSE
        BEGIN
            /* Tenia firmas —FIRMADO o PARCIAL—: nace una version nueva y TODAS
               las firmas de la anterior caen, no solo la ultima. Con firma en
               cadena esto importa mucho mas que antes: si el especialista de
               Abastecimiento regenera el Anexo 3 despues de que el jefe del area
               usuaria lo firmo, esa firma dejo de corresponder al contenido y
               conservarla seria dar por bueno un documento que nadie leyo. */
            SET @VersionNueva = @VersionVigente + 1;
            SET @FirmaInvalidada = 1;

            UPDATE f
               SET f.Estado = 'INVALIDADA',
                   f.InvalidadaEn = @Ahora,
                   f.MotivoInvalidacion = CONCAT(
                       N'Se genero la version ', @VersionNueva, ' del documento.')
              FROM sigcm.Firma AS f
              JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumentoVersion = f.IdDocumentoVersion
             WHERE dv.IdDocumento = @IdDocumento
               AND dv.Version = @VersionVigente
               AND f.Estado = 'FIRMADA';

            UPDATE sigcm.DocumentoVersion
               SET Estado = 'ANULADA',
                   UsuarioModificacionAuditoria = @Cuenta,
                   FechaModificacionAuditoria = @Ahora,
                   EquipoModificacionAuditoria = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdDocumento = @IdDocumento AND Version = @VersionVigente;

            UPDATE sigcm.Documento
               SET VersionVigente = @VersionNueva,
                   UsuarioModificacionAuditoria = @Cuenta,
                   FechaModificacionAuditoria = @Ahora,
                   EquipoModificacionAuditoria = @Equipo,
                   ProgramaModificacionAuditoria = @Programa
             WHERE IdDocumento = @IdDocumento;
        END

        /* Un expediente que no estaba enlazado se enlaza ahora. Cubre el caso de
           regenerar un Anexo 4 despues de agregarle una solicitud. */
        INSERT INTO sigcm.DocumentoExpediente (IdDocumento, IdExpediente)
        SELECT @IdDocumento, x.IdExpediente
          FROM @Exp AS x
         WHERE NOT EXISTS (SELECT 1 FROM sigcm.DocumentoExpediente AS de
                            WHERE de.IdDocumento = @IdDocumento
                              AND de.IdExpediente = x.IdExpediente);

        /* La version 1 y las nuevas se insertan; el borrador reemplazado no. */
        IF NOT EXISTS (SELECT 1 FROM sigcm.DocumentoVersion
                        WHERE IdDocumento = @IdDocumento AND Version = @VersionNueva)
            INSERT INTO sigcm.DocumentoVersion
                (IdDocumento, Version, Estado, Payload, GeneradoDocumento,
                 NombreDocumento, ArchivoHash, MotivoVersion,
                 UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                 EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdDocumento, @VersionNueva, 'BORRADOR', @Payload, @GeneradoDocumento,
                 @NombreDocumento, @ArchivoHash, @MotivoVersion,
                 @Cuenta, @Ahora, @Equipo, @Programa);

        COMMIT TRANSACTION; SET @TranPropia = 0;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = @CodigoModulo,
             @Entidad = 'sigcm.Documento', @IdEntidad = @IdDocumento,
             @Accion = 'REGISTRAR_DOCUMENTO', @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta, @ActorRol = @CodigoRol,
             @IdActorUnidad = @IdUnidad, @OrigenIp = @Ip, @Equipo = @Equipo,
             @Programa = @Programa;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdDocumento     AS IdDocumento,
                   @VersionNueva    AS Version,
                   'BORRADOR'       AS EstadoDocumento,
                   @FirmaInvalidada AS FirmaInvalidada,
                   CASE WHEN @FirmaInvalidada = 1
                        THEN N'Se registro el documento. La firma anterior quedo invalidada y debe firmarse nuevamente.'
                        ELSE N'Se registro el documento satisfactoriamente.' END AS mensaje
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
/* 2. sigcm.paFirmarDocumento                                                */
/* ========================================================================== */

/*
  Marca como FIRMADA la version vigente del documento.

  Entrada:
  { "Actor": {...}, "IdExpediente": "...", "CodigoTipoDocumento": "...",
    "ArchivoHash": "...",        opcional, huella del PDF firmado
    "GeneradoDocumento": "..."   opcional, si el firmador devuelve otro archivo }

  ---------------------------------------------------------------------------
  AQUI ENTRA EL FIRMADOR
  ---------------------------------------------------------------------------
  Hoy la firma es un asiento: quien tiene el rol autorizado deja constancia de
  que firmo, con fecha y actor. Es lo que hace el mockup, y alcanza para
  recorrer y validar el flujo.

  Cuando se integre el firmador institucional, el cambio queda contenido AQUI:
  el firmador devolvera un PDF con la firma incrustada y su huella, y esta
  rutina recibira GeneradoDocumento y ArchivoHash con esos valores en vez de
  conservar los del borrador. Ninguna otra rutina, ningun endpoint y ninguna
  pantalla cambian, porque todas preguntan por el ESTADO de la version, no por
  como se firmo.

  QUIEN PUEDE FIRMAR
  Lo dice sigcm.TipoDocumentoFirma, que es dato sembrado. No esta cableado aqui.
  El Anexo 3 lleva cuatro firmas —jefe del area usuaria, y despues especialista,
  coordinador y jefe de Abastecimiento— y el Anexo 4 lleva tres.

  ---------------------------------------------------------------------------
  FIRMA POR FIRMA, Y LA VERSION SE CIERRA CON LA ULTIMA
  ---------------------------------------------------------------------------
  Esta rutina hacia una sola cosa: poner la version en FIRMADO. No escribia en
  sigcm.Firma, que existe desde V002 con UNIQUE (IdDocumentoVersion, CodigoRol)
  precisamente para llevar varias firmas por version.

  Mientras cada documento tuvo un firmante, la diferencia no se notaba. Con la
  cadena de firmas del flujo nuevo se nota entera: el primero que firmaba daba
  el documento por cerrado y el segundo recibia "la version vigente ya esta
  firmada". Es lo que ya habia obligado a retirar la segunda firma del Anexo 4;
  no era una decision funcional, era este defecto.

  Ahora:
    1. Se registra la firma del rol actual en sigcm.Firma, con el nombre y el
       cargo congelados al momento de firmar.
    2. Se cuentan las firmas vigentes contra los firmantes declarados.
    3. Faltan  -> la version queda PARCIAL.
       Estan todas -> la version pasa a FIRMADO y se sella FirmadoEn.

  IDEMPOTENTE POR ROL
  Si el rol ya tiene su firma vigente sobre esta version, se responde OK sin
  duplicarla en vez de fallar. El frontend encadena firmar y luego mover el
  estado; si la transicion falla y el usuario reintenta, la firma ya esta puesta
  y el reintento tiene que poder completarse. Fallar ahi dejaba al expediente
  trabado sin ninguna forma de destrabarlo desde la pantalla.
*/
CREATE OR ALTER PROCEDURE sigcm.paFirmarDocumento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51610, 'JSON incorrecto.', 1;

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

        DECLARE @IdExpediente        uniqueidentifier,
                @CodigoTipoDocumento varchar(60),
                @ArchivoHash         varchar(128),
                @GeneradoDocumento   nvarchar(1000);

        SELECT @IdExpediente        = TRY_CONVERT(uniqueidentifier, IdExpediente),
               @CodigoTipoDocumento = CodigoTipoDocumento,
               @ArchivoHash         = ArchivoHash,
               @GeneradoDocumento   = GeneradoDocumento
        FROM OPENJSON(@parametro)
        WITH (
            IdExpediente        varchar(50),
            CodigoTipoDocumento varchar(60),
            ArchivoHash         varchar(128),
            GeneradoDocumento   nvarchar(1000)
        );

        IF @IdExpediente IS NULL
            THROW 51611, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF NULLIF(LTRIM(RTRIM(@CodigoTipoDocumento)), '') IS NULL
            THROW 51612, 'VALIDACION_PAYLOAD: falta CodigoTipoDocumento.', 1;

        DECLARE @CodigoModulo varchar(30) =
            (SELECT CodigoModulo FROM sigcm.Expediente
              WHERE IdExpediente = @IdExpediente AND Anulado = 0 AND Activo = 1);

        IF @CodigoModulo IS NULL
            THROW 51613, 'NO_ENCONTRADO: el expediente no existe o esta anulado.', 1;

        /* ---- El rol debe estar autorizado a firmar ESTE tipo ----------- */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TipoDocumentoFirma
                        WHERE CodigoTipoDocumento = @CodigoTipoDocumento
                          AND CodigoRol = @CodigoRol)
        BEGIN
            DECLARE @errRol nvarchar(500) = CONCAT(
                'NO_AUTORIZADO: el rol ', @CodigoRol, ' no figura entre los firmantes de ',
                @CodigoTipoDocumento, '. Firman: ',
                ISNULL((SELECT STRING_AGG(CodigoRol, ', ') WITHIN GROUP (ORDER BY OrdenFirma)
                          FROM sigcm.TipoDocumentoFirma
                         WHERE CodigoTipoDocumento = @CodigoTipoDocumento), '(ninguno configurado)'), '.');
            THROW 51614, @errRol, 1;
        END

        /* ---- Version vigente ------------------------------------------ */
        DECLARE @IdDocumento uniqueidentifier, @IdDocumentoVersion uniqueidentifier,
                @Version int, @EstadoVersion varchar(15);

        SELECT TOP 1 @IdDocumento = d.IdDocumento, @Version = d.VersionVigente
          FROM sigcm.Documento AS d
          JOIN sigcm.DocumentoExpediente AS de ON de.IdDocumento = d.IdDocumento
         WHERE de.IdExpediente = @IdExpediente
           AND d.CodigoTipoDocumento = @CodigoTipoDocumento
           AND d.Anulado = 0 AND d.Activo = 1
         ORDER BY d.FechaCreacionAuditoria DESC;

        IF @IdDocumento IS NULL
        BEGIN
            DECLARE @errDoc nvarchar(500) = CONCAT(
                'NO_ENCONTRADO: el expediente no tiene el documento ', @CodigoTipoDocumento,
                '. Debe generarse antes de firmarlo.');
            THROW 51615, @errDoc, 1;
        END

        SELECT @IdDocumentoVersion = IdDocumentoVersion, @EstadoVersion = Estado
          FROM sigcm.DocumentoVersion
         WHERE IdDocumento = @IdDocumento AND Version = @Version;

        IF @EstadoVersion IN ('ANULADA','SUPERADA')
            THROW 51617, 'CONFLICTO_DOCUMENTO: la version vigente del documento no admite firmas.', 1;

        DECLARE @Ahora datetime = GETDATE();
        DECLARE @OrdenFirma smallint =
            (SELECT OrdenFirma FROM sigcm.TipoDocumentoFirma
              WHERE CodigoTipoDocumento = @CodigoTipoDocumento AND CodigoRol = @CodigoRol);

        DECLARE @YaFirmo bit =
            CASE WHEN EXISTS (SELECT 1 FROM sigcm.Firma
                               WHERE IdDocumentoVersion = @IdDocumentoVersion
                                 AND CodigoRol = @CodigoRol
                                 AND Estado = 'FIRMADA')
                 THEN 1 ELSE 0 END;

        BEGIN TRANSACTION; SET @TranPropia = 1;

        IF @YaFirmo = 0
        BEGIN
            /* Una firma retirada del mismo rol sobre la misma version se
               reemplaza: la fila INVALIDADA ocupa la clave unica, y sin este
               borrado el rol no podria volver a firmar nunca esa version. */
            DELETE FROM sigcm.Firma
             WHERE IdDocumentoVersion = @IdDocumentoVersion
               AND CodigoRol = @CodigoRol;

            INSERT INTO sigcm.Firma
                (IdDocumentoVersion, CodigoRol, OrdenFirma, IdFirmante,
                 FirmanteNombre, FirmanteCargo, Estado, FirmaHash, FirmaPayload, FirmadoEn,
                 UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES
                (@IdDocumentoVersion, @CodigoRol, ISNULL(@OrdenFirma, 1), @IdUsuario,
                 @NombreCompleto, ISNULL(NULLIF(LTRIM(RTRIM(@Cargo)), ''), @CodigoRol),
                 'FIRMADA',
                 /* Mientras no haya firmador institucional, la huella de la firma
                    es la del archivo firmado. Cuando lo haya, este es el valor
                    que devuelve el certificado y nada mas cambia. */
                 ISNULL(@ArchivoHash, CONVERT(varchar(64), HASHBYTES('SHA2_256',
                        CONCAT(CONVERT(varchar(36), @IdDocumentoVersion), '|',
                               @CodigoRol, '|', CONVERT(varchar(30), @Ahora, 126))), 2)),
                 (SELECT Cuenta = @Cuenta, Rol = @CodigoRol,
                         FirmadoEn = CONVERT(varchar(19), @Ahora, 126)
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                 @Ahora, @Cuenta, @Equipo, @Programa);
        END

        /* ---- ¿Quedan firmas pendientes? ------------------------------- */
        DECLARE @Faltantes int =
            (SELECT COUNT(*)
               FROM sigcm.TipoDocumentoFirma AS tf
              WHERE tf.CodigoTipoDocumento = @CodigoTipoDocumento
                AND NOT EXISTS (SELECT 1 FROM sigcm.Firma AS f
                                 WHERE f.IdDocumentoVersion = @IdDocumentoVersion
                                   AND f.CodigoRol = tf.CodigoRol
                                   AND f.Estado = 'FIRMADA'));

        DECLARE @EstadoNuevo varchar(15) = CASE WHEN @Faltantes = 0 THEN 'FIRMADO' ELSE 'PARCIAL' END;

        UPDATE sigcm.DocumentoVersion
           SET Estado = @EstadoNuevo,
               /* FirmadoEn marca el cierre del documento, no cada firma: la
                  fecha de cada una vive en sigcm.Firma. */
               FirmadoEn = CASE WHEN @Faltantes = 0 THEN @Ahora ELSE NULL END,
               ArchivoHash = ISNULL(@ArchivoHash, ArchivoHash),
               GeneradoDocumento = ISNULL(@GeneradoDocumento, GeneradoDocumento),
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdDocumento = @IdDocumento AND Version = @Version;

        COMMIT TRANSACTION; SET @TranPropia = 0;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = @CodigoModulo,
             @Entidad = 'sigcm.DocumentoVersion', @IdEntidad = @IdDocumento,
             @Accion = 'FIRMAR_DOCUMENTO', @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta, @ActorRol = @CodigoRol,
             @IdActorUnidad = @IdUnidad, @OrigenIp = @Ip, @Equipo = @Equipo,
             @Programa = @Programa;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdDocumento AS IdDocumento,
                   @Version     AS Version,
                   @EstadoNuevo AS EstadoDocumento,
                   @NombreCompleto AS Firmante,
                   @CodigoRol   AS RolFirmante,
                   @Faltantes   AS FirmasPendientes,
                   @YaFirmo     AS YaHabiaFirmado,
                   CONVERT(varchar(19), @Ahora, 126) AS FirmadoEn,
                   Pendientes = JSON_QUERY(COALESCE((
                       SELECT tf.CodigoRol, tf.OrdenFirma, Rol = r.Nombre
                         FROM sigcm.TipoDocumentoFirma AS tf
                         JOIN sigcm.Rol AS r ON r.CodigoRol = tf.CodigoRol
                        WHERE tf.CodigoTipoDocumento = @CodigoTipoDocumento
                          AND NOT EXISTS (SELECT 1 FROM sigcm.Firma AS f
                                           WHERE f.IdDocumentoVersion = @IdDocumentoVersion
                                             AND f.CodigoRol = tf.CodigoRol
                                             AND f.Estado = 'FIRMADA')
                        ORDER BY tf.OrdenFirma
                          FOR JSON PATH), '[]')),
                   CASE WHEN @YaFirmo = 1
                        THEN N'Este rol ya tenia su firma registrada en la version vigente.'
                        WHEN @Faltantes = 0
                        THEN N'Se registro la firma. El documento quedo firmado por todos sus firmantes.'
                        ELSE CONCAT(N'Se registro la firma. Faltan ', @Faltantes,
                                    N' firma(s) para cerrar el documento.') END AS mensaje
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
/* 3. sigcm.paListarDocumento                                                */
/* ========================================================================== */

/*
  Documentos de un expediente con su version vigente. Es lo que la pantalla
  necesita para saber si hay que generar, si se puede firmar y con que URL se
  abre el PDF.

  Entrada: { "Actor": {...}, "IdExpediente": "..." }
*/
CREATE OR ALTER PROCEDURE sigcm.paListarDocumento
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51620, 'JSON incorrecto.', 1;

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
            THROW 51621, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   'OK' AS mensaje,
                   Documentos = JSON_QUERY(COALESCE((
                       SELECT d.IdDocumento, d.CodigoTipoDocumento, d.Numero,
                              TipoDocumento = td.Nombre,
                              dv.Version, dv.Estado,
                              dv.GeneradoDocumento, dv.NombreDocumento,
                              dv.FirmadoEn, d.Consolidado,
                              /* Para que la pantalla sepa si ofrecer el boton de
                                 firmar a QUIEN esta mirando. */
                              PuedeFirmarEsteRol = CONVERT(bit, CASE WHEN EXISTS (
                                  SELECT 1 FROM sigcm.TipoDocumentoFirma AS f
                                   WHERE f.CodigoTipoDocumento = d.CodigoTipoDocumento
                                     AND f.CodigoRol = @CodigoRol) THEN 1 ELSE 0 END),
                              EsteRolYaFirmo = CONVERT(bit, CASE WHEN EXISTS (
                                  SELECT 1 FROM sigcm.Firma AS f
                                   WHERE f.IdDocumentoVersion = dv.IdDocumentoVersion
                                     AND f.CodigoRol = @CodigoRol
                                     AND f.Estado = 'FIRMADA') THEN 1 ELSE 0 END),
                              /* La cadena de firmas, en orden, con quien firmo y
                                 cuando. Es lo que el visor del anexo necesita
                                 para mostrar el pie de firmas sin recalcularlo. */
                              Firmas = JSON_QUERY(COALESCE((
                                  SELECT tf.OrdenFirma, tf.CodigoRol,
                                         Rol = r.Nombre,
                                         Estado = ISNULL(fi.Estado, 'PENDIENTE'),
                                         fi.FirmanteNombre, fi.FirmanteCargo, fi.FirmadoEn
                                    FROM sigcm.TipoDocumentoFirma AS tf
                                    JOIN sigcm.Rol AS r ON r.CodigoRol = tf.CodigoRol
                                    LEFT JOIN sigcm.Firma AS fi
                                           ON fi.IdDocumentoVersion = dv.IdDocumentoVersion
                                          AND fi.CodigoRol = tf.CodigoRol
                                          AND fi.Estado = 'FIRMADA'
                                   WHERE tf.CodigoTipoDocumento = d.CodigoTipoDocumento
                                   ORDER BY tf.OrdenFirma
                                     FOR JSON PATH), '[]'))
                         FROM sigcm.Documento AS d
                         JOIN sigcm.DocumentoExpediente AS de ON de.IdDocumento = d.IdDocumento
                         JOIN sigcm.TipoDocumento AS td ON td.CodigoTipoDocumento = d.CodigoTipoDocumento
                         JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumento = d.IdDocumento
                                                          AND dv.Version = d.VersionVigente
                        WHERE de.IdExpediente = @IdExpediente
                          AND d.Anulado = 0 AND d.Activo = 1
                        ORDER BY d.CodigoTipoDocumento
                          FOR JSON PATH), '[]'))
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
                   JSON_QUERY('[]') AS Documentos
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

PRINT 'F003 aplicada: documentos, firmas e invalidacion por version.';
GO
