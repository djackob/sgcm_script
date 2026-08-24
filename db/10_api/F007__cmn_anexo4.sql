/*
===============================================================================
  SIGCM - F007 : Anexo 4 (paquete) del modulo CMN
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51700-51799

  ---------------------------------------------------------------------------
  QUE RESUELVE
  ---------------------------------------------------------------------------
  El paso 8 del flujo: el especialista de Abastecimiento marca con un check uno
  o varios Anexos 3 ya firmados —que pueden ser de areas usuarias distintas— y
  genera con ellos UN Anexo 4.

  Son dos rutinas y una sola idea: paGenerarAnexo4 decide y reserva; despues el
  frontend arma el PDF, lo sube, lo registra con sigcm.paRegistrarDocumento
  (pasandole los N expedientes y el codigo del paquete), lo firma y mueve los N
  expedientes con sigcm.paEjecutarTransicion. paObtenerAnexo4 es lo que alimenta
  ese PDF y lo que permite reconstruirlo despues.

  ---------------------------------------------------------------------------
  POR QUE GENERAR ES UNA RUTINA APARTE Y NO PARTE DE LA TRANSICION
  ---------------------------------------------------------------------------
  Porque hay que emitir el numero del Anexo 4 y decidir si la fecha lo permite
  ANTES de que el frontend arme el PDF: el numero se imprime en el documento. Si
  el paquete naciera junto con la transicion, el PDF ya estaria armado y subido
  cuando la base descubriera que hoy es martes y el paquete es ordinario.

  Es tambien la razon de que el paquete quede reservado desde este momento: el
  indice unico de cmn.PaqueteSolicitud impide que otro especialista tome las
  mismas solicitudes mientras el primero arma su documento.

  ---------------------------------------------------------------------------
  LA REGLA DEL VIERNES
  ---------------------------------------------------------------------------
  Un paquete ORDINARIO solo se genera los viernes; uno URGENTE, cualquier dia.
  Se comprueba con DATEDIFF contra una fecha conocida y no con DATEPART(weekday),
  que depende de SET DATEFIRST y por lo tanto de la sesion: la misma consulta
  daria distinto segun quien la ejecute, y una regla de calendario que cambia con
  la configuracion del cliente no es una regla.

  1900-01-01 fue lunes, asi que el resto entre 7 vale 0 para lunes y 4 para
  viernes.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. cmn.paGenerarAnexo4                                                    */
/* ========================================================================== */

/*
  Entrada:
  {
    "Actor": { ... },
    "IdSolicitudes": ["...", "..."],   uno o varios Anexos 3 aprobados
    "Sustento": "...",                 opcional
    "Forzar": false                    opcional; ver la regla del viernes
  }

  Salida: el paquete creado con el detalle suficiente para armar el PDF sin otra
  llamada, y la lista de expedientes que despues hay que mover.
*/
CREATE OR ALTER PROCEDURE cmn.paGenerarAnexo4
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51700, 'JSON incorrecto.', 1;

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

        /* Quien genera el Anexo 4 lo dice la semilla, no esta rutina: es el rol
           habilitado para CMN_GENERAR_A4. Preguntarselo a sigcm.TransicionRol
           evita que la regla quede escrita en dos sitios y se separen. */
        IF NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol
                        WHERE CodigoTransicion = 'CMN_GENERAR_A4' AND CodigoRol = @CodigoRol)
        BEGIN
            DECLARE @errRol nvarchar(400) = CONCAT(
                'NO_AUTORIZADO: el rol ', @CodigoRol, ' no puede generar el Anexo 4.');
            THROW 51701, @errRol, 1;
        END

        DECLARE @Sustento nvarchar(max) = JSON_VALUE(@parametro, '$.Sustento');
        DECLARE @Forzar bit = ISNULL(TRY_CONVERT(bit, JSON_VALUE(@parametro, '$.Forzar')), 0);

        /* ---- Solicitudes seleccionadas -------------------------------- */
        DECLARE @Sel TABLE (IdSolicitud uniqueidentifier PRIMARY KEY);

        INSERT INTO @Sel (IdSolicitud)
        SELECT DISTINCT TRY_CONVERT(uniqueidentifier, value)
          FROM OPENJSON(@parametro, '$.IdSolicitudes')
         WHERE TRY_CONVERT(uniqueidentifier, value) IS NOT NULL;

        IF NOT EXISTS (SELECT 1 FROM @Sel)
            THROW 51702, 'VALIDACION_PAYLOAD: no se recibio ningun Anexo 3. Marque al menos uno.', 1;

        DECLARE @Cantidad int = (SELECT COUNT(*) FROM @Sel);

        /* ---- Todas deben existir y estar aprobadas -------------------- */
        /*
          CMN_A3_APROBADO es el unico estado desde el que sale CMN_GENERAR_A4. Se
          comprueba aqui ademas de en el motor porque el paquete se crea antes de
          la transicion: sin esto se reservarian solicitudes que despues no
          podrian moverse, y quedarian bloqueadas para cualquier otro Anexo 4.
        */
        DECLARE @Invalida varchar(40) =
            (SELECT TOP 1 ISNULL(s.Codigo, '(inexistente)')
               FROM @Sel AS x
               LEFT JOIN cmn.Solicitud    AS s ON s.IdSolicitud = x.IdSolicitud AND s.Activo = 1
               LEFT JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
                                              AND e.Anulado = 0 AND e.Activo = 1
              WHERE s.IdSolicitud IS NULL
                 OR e.IdExpediente IS NULL
                 OR e.CodigoEstado <> 'CMN_A3_APROBADO');

        IF @Invalida IS NOT NULL
        BEGIN
            DECLARE @errEstado nvarchar(500) = CONCAT(
                'CONFLICTO_ESTADO: el Anexo 3 ', @Invalida,
                ' no esta aprobado por Abastecimiento y no puede integrar un Anexo 4. ',
                'Vuelva a cargar la bandeja.');
            THROW 51703, @errEstado, 1;
        END

        /* ---- Ninguna puede estar ya en otro Anexo 4 ------------------- */
        /*
          El indice unico de cmn.PaqueteSolicitud tambien lo impide, pero ahi el
          error saldria como violacion de indice y sin decir cual solicitud ni en
          que Anexo 4 esta. Este control existe para el mensaje.
        */
        DECLARE @YaEnPaquete nvarchar(200) =
            (SELECT TOP 1 CONCAT(s.Codigo, ' (esta en el Anexo 4 ', p.Codigo, ')')
               FROM @Sel AS x
               JOIN cmn.Solicitud       AS s  ON s.IdSolicitud = x.IdSolicitud
               JOIN cmn.PaqueteSolicitud AS ps ON ps.IdSolicitud = x.IdSolicitud AND ps.Activo = 1
               JOIN cmn.Paquete         AS p  ON p.IdPaquete = ps.IdPaquete AND p.Anulado = 0);

        IF @YaEnPaquete IS NOT NULL
        BEGIN
            DECLARE @errPaq nvarchar(500) = CONCAT(
                'CONFLICTO_PAQUETE: ', @YaEnPaquete, '. Un Anexo 3 solo puede integrar un Anexo 4.');
            THROW 51704, @errPaq, 1;
        END

        /* ---- Ejercicio y unidad ejecutora comunes --------------------- */
        /*
          Un Anexo 4 aprueba modificaciones de UN cuadro multianual. Mezclar
          ejercicios o unidades ejecutoras produciria un documento que en SIGA no
          corresponde a ninguna, aunque el PDF se vea bien. Las areas usuarias si
          pueden ser distintas: eso es justamente lo que el paquete resuelve.
        */
        DECLARE @AnoEje smallint, @SecEjec int, @Combinaciones int;

        SELECT @Combinaciones = COUNT(*)
          FROM (SELECT DISTINCT s.AnoEje, s.SecEjec
                  FROM @Sel AS x JOIN cmn.Solicitud AS s ON s.IdSolicitud = x.IdSolicitud) AS c;

        IF @Combinaciones > 1
            THROW 51705, 'CONFLICTO_SELECCION: los Anexos 3 marcados pertenecen a ejercicios o unidades ejecutoras distintas. Un Anexo 4 cubre un solo cuadro.', 1;

        SELECT TOP 1 @AnoEje = s.AnoEje, @SecEjec = s.SecEjec
          FROM @Sel AS x JOIN cmn.Solicitud AS s ON s.IdSolicitud = x.IdSolicitud;

        /* ---- Ordinario o urgente -------------------------------------- */
        /*
          Lo declaro el especialista al conformar cada Anexo 3. El paquete hereda
          esa marca y por eso tiene que ser la misma en todos: si se admitiera
          mezclar, bastaria con incluir un urgente para generar un martes todo lo
          ordinario, y la restriccion de fecha dejaria de restringir nada.
        */
        DECLARE @TiposDistintos int;
        SELECT @TiposDistintos = COUNT(DISTINCT ISNULL(s.TipoInclusion, '(sin definir)'))
          FROM @Sel AS x JOIN cmn.Solicitud AS s ON s.IdSolicitud = x.IdSolicitud;

        IF @TiposDistintos > 1
            THROW 51706, 'CONFLICTO_SELECCION: hay Anexos 3 ordinarios y urgentes en la misma seleccion. Genere un Anexo 4 para cada tipo.', 1;

        DECLARE @TipoInclusion varchar(15);
        SELECT TOP 1 @TipoInclusion = s.TipoInclusion
          FROM @Sel AS x JOIN cmn.Solicitud AS s ON s.IdSolicitud = x.IdSolicitud;

        IF @TipoInclusion IS NULL
            THROW 51707, 'VALIDACION_DATOS: los Anexos 3 marcados no tienen definido si son ordinarios o urgentes. Debio declararse al conformarlos.', 1;

        /* ---- La regla del viernes ------------------------------------- */
        DECLARE @EsViernes bit =
            CASE WHEN DATEDIFF(day, '19000101', CONVERT(date, GETDATE())) % 7 = 4 THEN 1 ELSE 0 END;

        IF @TipoInclusion = 'ORDINARIA' AND @EsViernes = 0 AND @Forzar = 0
            THROW 51708, 'REGLA_CALENDARIO: los Anexos 4 ordinarios se generan los viernes. Para una modificacion que no puede esperar, el Anexo 3 debe conformarse como URGENTE.', 1;

        /* ---- Creacion -------------------------------------------------- */
        DECLARE @Ahora datetime = GETDATE();
        DECLARE @Codigo varchar(40);
        DECLARE @IdPaquete uniqueidentifier;
        DECLARE @Nuevo TABLE (IdPaquete uniqueidentifier);

        BEGIN TRANSACTION; SET @TranPropia = 1;

        /* Dentro de la transaccion, para que un fallo devuelva el numero en vez
           de dejar un hueco en la serie. La razon completa esta en V010. */
        EXEC sigcm.paSiguienteCodigo 'A4', @AnoEje, N'cmn.SeqPaquete', @Codigo OUTPUT;

        INSERT INTO cmn.Paquete
            (Codigo, AnoEje, SecEjec, TipoInclusion, IdUsuarioGenera, IdUnidadGenera,
             Sustento, UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        OUTPUT inserted.IdPaquete INTO @Nuevo
        VALUES
            (@Codigo, @AnoEje, @SecEjec, @TipoInclusion, @IdUsuario, @IdUnidad,
             @Sustento, @Cuenta, @Ahora, @Equipo, @Programa);

        SELECT @IdPaquete = IdPaquete FROM @Nuevo;

        /* El orden de impresion es el del codigo del Anexo 3: es estable, es el
           que el area usuaria reconoce y no depende de como llego el JSON. */
        INSERT INTO cmn.PaqueteSolicitud
            (IdPaquete, IdSolicitud, Orden,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT @IdPaquete, s.IdSolicitud,
               ROW_NUMBER() OVER (ORDER BY s.Codigo),
               @Cuenta, @Ahora, @Equipo, @Programa
          FROM @Sel AS x JOIN cmn.Solicitud AS s ON s.IdSolicitud = x.IdSolicitud;

        COMMIT TRANSACTION; SET @TranPropia = 0;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = 'CMN',
             @Entidad = 'cmn.Paquete', @IdEntidad = @IdPaquete,
             @Accion = 'GENERAR_ANEXO_4', @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta, @ActorRol = @CodigoRol,
             @IdActorUnidad = @IdUnidad, @OrigenIp = @Ip, @Equipo = @Equipo,
             @Programa = @Programa;

        EXEC cmn.paObtenerAnexo4Interno @IdPaquete = @IdPaquete, @Mensaje = N'Se genero el Anexo 4.';
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
/* 2. cmn.paObtenerAnexo4Interno                                             */
/* ========================================================================== */

/*
  El armado del JSON del paquete, en un solo sitio.

  Existe porque lo necesitan dos rutinas —la que genera y la que consulta— y
  duplicar la consulta significaria que el PDF recien generado y el PDF
  reconstruido tres meses despues pudieran salir distintos. No lleva actor ni
  valida nada: eso ya lo hizo quien la llama.
*/
CREATE OR ALTER PROCEDURE cmn.paObtenerAnexo4Interno
    @IdPaquete uniqueidentifier,
    @Mensaje   nvarchar(200) = N'OK'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    SELECT @resultado = (
        SELECT 1 AS estado,
               p.IdPaquete, p.Codigo, p.AnoEje, p.SecEjec, p.TipoInclusion,
               p.Sustento, p.Anulado,
               FechaGeneracion = CONVERT(varchar(19), p.FechaCreacionAuditoria, 126),
               GeneradoPor     = CONCAT(u.Nombres, ' ', u.Apellidos),
               CargoGenerador  = u.Cargo,
               UnidadGeneradora = un.Nombre,
               TotalSolicitudes = (SELECT COUNT(*) FROM cmn.PaqueteSolicitud AS c
                                    WHERE c.IdPaquete = p.IdPaquete AND c.Activo = 1),
               TotalItems = (SELECT COUNT(*)
                               FROM cmn.PaqueteSolicitud AS c
                               JOIN cmn.SolicitudItem AS ci ON ci.IdSolicitud = c.IdSolicitud AND ci.Activo = 1
                              WHERE c.IdPaquete = p.IdPaquete AND c.Activo = 1),
               MontoTotal = (SELECT ISNULL(SUM(cr.MontoTotal), 0)
                               FROM cmn.PaqueteSolicitud AS c
                               JOIN cmn.vwItemResumen AS cr ON cr.IdSolicitud = c.IdSolicitud
                              WHERE c.IdPaquete = p.IdPaquete AND c.Activo = 1),

               /* Un bloque por area usuaria, que es como se imprime el Anexo 4:
                  el area usuaria lee SU parte y Abastecimiento lee el total. */
               Solicitudes = JSON_QUERY(COALESCE((
                   SELECT ps.Orden,
                          s.IdSolicitud, s.Codigo, s.CentroCosto, s.Sustento,
                          s.TipoOperacion, s.TipoInclusion,
                          FechaSolicitud = CONVERT(varchar(10), s.FechaSolicitud, 126),
                          e.IdExpediente,
                          CodigoExpediente = e.Codigo,
                          e.CodigoEstado, e.Version,
                          AreaUsuaria = uo.Nombre,
                          SiglaArea   = uo.Sigla,
                          Responsable = CONCAT(ur.Nombres, ' ', ur.Apellidos),
                          CargoResponsable = ur.Cargo,
                          /* Se leen de cmn.vwItemResumen, la misma vista que
                             alimenta el Anexo 3. Recalcular los totales aqui
                             abriria la puerta a que el Anexo 4 muestre cifras
                             distintas de las del Anexo 3 que aprueba. */
                          Items = JSON_QUERY(COALESCE((
                              SELECT r.IdSolicitudItem, r.Orden, r.TipoMovimiento,
                                     r.CodigoItem, r.Descripcion,
                                     r.UnidadMedida, r.UnidadAbreviatura,
                                     r.PrecioUnitario, r.SecFunc, r.Clasificador,
                                     r.RefSecCuadro, r.RefSecItem,
                                     r.CantidadAno0, r.CantidadAno1, r.CantidadAno2, r.CantidadAno3,
                                     r.MontoAno0, r.MontoAno1, r.MontoAno2, r.MontoAno3,
                                     r.CantidadTotal, r.MontoTotal
                                FROM cmn.vwItemResumen AS r
                               WHERE r.IdSolicitud = s.IdSolicitud
                               ORDER BY r.Orden
                                 FOR JSON PATH), '[]'))
                     FROM cmn.PaqueteSolicitud AS ps
                     JOIN cmn.Solicitud    AS s  ON s.IdSolicitud = ps.IdSolicitud
                     JOIN sigcm.Expediente AS e  ON e.IdExpediente = s.IdExpediente
                     JOIN sigcm.Unidad     AS uo ON uo.IdUnidad = e.IdUnidadOrigen
                     LEFT JOIN sigcm.Usuario AS ur ON ur.IdUsuario = s.IdResponsable
                    WHERE ps.IdPaquete = p.IdPaquete AND ps.Activo = 1
                    ORDER BY ps.Orden
                      FOR JSON PATH), '[]')),
               @Mensaje AS mensaje
          FROM cmn.Paquete AS p
          JOIN sigcm.Usuario AS u  ON u.IdUsuario = p.IdUsuarioGenera
          JOIN sigcm.Unidad  AS un ON un.IdUnidad = p.IdUnidadGenera
         WHERE p.IdPaquete = @IdPaquete
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    SELECT @resultado;
END
GO

/* ========================================================================== */
/* 3. cmn.paObtenerAnexo4                                                    */
/* ========================================================================== */

/*
  El paquete completo, para armar o reconstruir el PDF.

  Entrada: { "Actor": {...}, "IdPaquete": "..." }
           o { "Actor": {...}, "IdSolicitud": "..." }

  Admite IdSolicitud porque la bandeja muestra Anexos 3, no paquetes: cuando el
  coordinador abre el Anexo 4 de una fila, lo que tiene a mano es la solicitud.
*/
CREATE OR ALTER PROCEDURE cmn.paObtenerAnexo4
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51710, 'JSON incorrecto.', 1;

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

        DECLARE @IdPaquete uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdPaquete'));
        DECLARE @IdSolicitud uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdSolicitud'));

        IF @IdPaquete IS NULL AND @IdSolicitud IS NOT NULL
            SELECT @IdPaquete = ps.IdPaquete
              FROM cmn.PaqueteSolicitud AS ps
              JOIN cmn.Paquete AS p ON p.IdPaquete = ps.IdPaquete
             WHERE ps.IdSolicitud = @IdSolicitud AND ps.Activo = 1 AND p.Anulado = 0;

        IF @IdPaquete IS NULL
            THROW 51711, 'NO_ENCONTRADO: no hay un Anexo 4 para lo solicitado.', 1;

        EXEC cmn.paObtenerAnexo4Interno @IdPaquete = @IdPaquete;
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
/* 4. cmn.paAnularAnexo4                                                     */
/* ========================================================================== */

/*
  Deshace un paquete que todavia no salio del especialista.

  Hace falta porque generar reserva las solicitudes: si el especialista se
  equivoco de seleccion y no hubiera forma de deshacer, esos Anexos 3 quedarian
  atrapados en un Anexo 4 que nadie va a firmar y ningun otro paquete podria
  tomarlos nunca.

  Solo mientras los expedientes sigan en CMN_A3_APROBADO. Una vez firmado y
  derivado al coordinador, el Anexo 4 ya es un documento del tramite y lo que
  corresponde no es borrarlo sino observarlo.

  Entrada: { "Actor": {...}, "IdPaquete": "...", "Motivo": "..." }
*/
CREATE OR ALTER PROCEDURE cmn.paAnularAnexo4
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51720, 'JSON incorrecto.', 1;

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

        IF NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol
                        WHERE CodigoTransicion = 'CMN_GENERAR_A4' AND CodigoRol = @CodigoRol)
            THROW 51721, 'NO_AUTORIZADO: solo quien genera el Anexo 4 puede deshacerlo.', 1;

        DECLARE @IdPaquete uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdPaquete'));
        DECLARE @Motivo nvarchar(max) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.Motivo'))), '');

        IF @IdPaquete IS NULL
            THROW 51722, 'VALIDACION_PAYLOAD: falta IdPaquete.', 1;
        IF @Motivo IS NULL
            THROW 51723, 'VALIDACION_PAYLOAD: falta el motivo de la anulacion.', 1;

        DECLARE @Codigo varchar(40) =
            (SELECT Codigo FROM cmn.Paquete WHERE IdPaquete = @IdPaquete AND Anulado = 0);

        IF @Codigo IS NULL
            THROW 51724, 'NO_ENCONTRADO: el Anexo 4 no existe o ya esta anulado.', 1;

        DECLARE @Avanzado varchar(40) =
            (SELECT TOP 1 e.Codigo
               FROM cmn.PaqueteSolicitud AS ps
               JOIN cmn.Solicitud    AS s ON s.IdSolicitud = ps.IdSolicitud
               JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
              WHERE ps.IdPaquete = @IdPaquete AND ps.Activo = 1
                AND e.CodigoEstado <> 'CMN_A3_APROBADO');

        IF @Avanzado IS NOT NULL
        BEGIN
            DECLARE @errAv nvarchar(500) = CONCAT(
                'CONFLICTO_ESTADO: el Anexo 4 ', @Codigo, ' ya avanzo en el flujo (expediente ',
                @Avanzado, '). Para revertirlo hay que observarlo, no anularlo.');
            THROW 51725, @errAv, 1;
        END

        DECLARE @Ahora datetime = GETDATE();

        BEGIN TRANSACTION; SET @TranPropia = 1;

        /* Activo = 0 en el detalle libera las solicitudes: el indice unico que
           impide que un Anexo 3 este en dos paquetes esta filtrado por Activo. */
        UPDATE cmn.PaqueteSolicitud SET Activo = 0 WHERE IdPaquete = @IdPaquete;

        UPDATE cmn.Paquete
           SET Anulado = 1,
               MotivoAnulacion = @Motivo,
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdPaquete = @IdPaquete;

        COMMIT TRANSACTION; SET @TranPropia = 0;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = 'CMN',
             @Entidad = 'cmn.Paquete', @IdEntidad = @IdPaquete,
             @Accion = 'ANULAR_ANEXO_4', @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta, @ActorRol = @CodigoRol,
             @IdActorUnidad = @IdUnidad, @OrigenIp = @Ip, @Equipo = @Equipo,
             @Programa = @Programa;

        SELECT @resultado = (
            SELECT 1 AS estado, @IdPaquete AS IdPaquete, @Codigo AS Codigo,
                   CONCAT(N'Se anulo el Anexo 4 ', @Codigo,
                          N'. Sus Anexos 3 quedan disponibles para otro.') AS mensaje
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

PRINT 'F007 aplicada: Anexo 4 multiple del modulo CMN.';
GO
