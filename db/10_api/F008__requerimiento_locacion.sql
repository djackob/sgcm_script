/*
===============================================================================
  SIGCM - F008 : Locacion — filtros de idoneidad, CCP, orden y notificacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51800-51899

  Complementa F005 para el tramo posterior a REQ_CONFORME (ERF locacion <= 8 UIT).
  Las acciones de bandeja siguen siendo transiciones (S004). Aqui vive el dato
  que esas transiciones no pueden guardar: resultado de cada filtro, CCP,
  numero de O/S y el sobre de correo que el puente .NET envia con
  UT_Correo.envioCorreo.

  No hay HTTP a la PID ni escritura a SIGA/SIAF. Si no hay interoperabilidad,
  el especialista marca conformidad MANUAL de cada registro.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. requerimiento.paListarFiltroIdoneidad                                  */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE requerimiento.paListarFiltroIdoneidad
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51800, 'JSON incorrecto.', 1;

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

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        IF @IdRequerimiento IS NULL
            THROW 51801, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        IF NOT EXISTS (SELECT 1 FROM requerimiento.Requerimiento
                        WHERE IdRequerimiento = @IdRequerimiento AND Activo = 1)
            THROW 51802, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        DECLARE @EstadoFiltro varchar(60);
        SELECT @EstadoFiltro = e.CodigoEstado
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
         WHERE r.IdRequerimiento = @IdRequerimiento;

        IF @EstadoFiltro IN ('REQ_FILTROS','REQ_FILTROS_COORD','REQ_FILTROS_JEFE',
                             'REQ_CCP_SOLICITADO','REQ_CCP_CARGADA',
                             'REQ_OS_EMITIDA','REQ_NOTIFICADO')
        INSERT INTO requerimiento.FiltroIdoneidad
            (IdRequerimiento, CodigoFiltro, Resultado, Origen,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT @IdRequerimiento, t.CodigoFiltro, 'PENDIENTE', 'MANUAL',
               @Cuenta, @Equipo, @Programa
          FROM requerimiento.FiltroTipo AS t
         WHERE t.Activo = 1
           AND NOT EXISTS (SELECT 1 FROM requerimiento.FiltroIdoneidad AS f
                            WHERE f.IdRequerimiento = @IdRequerimiento
                              AND f.CodigoFiltro = t.CodigoFiltro);

        /* Numero del memorando: 001-AAAA-ANIN/OA-UA. Se reserva solo cuando
           el llamador lo pide (modal de solicitud CCP), y se reutiliza. */
        DECLARE @NumeroMemorando varchar(40);
        DECLARE @AnoMemo smallint;
        DECLARE @ReservarMemo bit = ISNULL(TRY_CONVERT(bit, JSON_VALUE(@parametro, '$.ReservarNumeroMemo')), 0);

        SELECT @AnoMemo = e.AnoEje, @NumeroMemorando = NULLIF(LTRIM(RTRIM(c.NumeroMemorando)), '')
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
          LEFT JOIN requerimiento.CertificacionCcp AS c
                 ON c.IdRequerimiento = r.IdRequerimiento AND c.Activo = 1
         WHERE r.IdRequerimiento = @IdRequerimiento;

        IF @ReservarMemo = 1 AND @NumeroMemorando IS NULL
        BEGIN
            DECLARE @NombreCorr nvarchar(128) = CONCAT(N'requerimiento.SeqMemoCcp|',
                CONVERT(varchar(4), ISNULL(@AnoMemo, YEAR(GETDATE()))));
            DECLARE @ValorMemo bigint;

            IF NOT EXISTS (SELECT 1 FROM sigcm.Correlativo WITH (UPDLOCK, HOLDLOCK)
                            WHERE Nombre = @NombreCorr)
                INSERT INTO sigcm.Correlativo (Nombre, Valor) VALUES (@NombreCorr, 0);

            UPDATE sigcm.Correlativo
               SET @ValorMemo = Valor = Valor + 1
             WHERE Nombre = @NombreCorr;

            DECLARE @CorrMemo varchar(12) = CONVERT(varchar(12), @ValorMemo);
            IF @ValorMemo < 1000
                SET @CorrMemo = RIGHT(CONCAT('000', @CorrMemo), 3);

            SET @NumeroMemorando = CONCAT(@CorrMemo, '-',
                CONVERT(varchar(4), ISNULL(@AnoMemo, YEAR(GETDATE()))),
                '-ANIN/OA-UA');

            MERGE requerimiento.CertificacionCcp AS c
            USING (SELECT @IdRequerimiento AS IdRequerimiento) AS s
            ON c.IdRequerimiento = s.IdRequerimiento
            WHEN MATCHED THEN
                UPDATE SET c.NumeroMemorando = ISNULL(NULLIF(LTRIM(RTRIM(c.NumeroMemorando)), ''), @NumeroMemorando),
                           c.UsuarioModificacionAuditoria = @Cuenta,
                           c.FechaModificacionAuditoria = GETDATE(),
                           c.EquipoModificacionAuditoria = @Equipo,
                           c.ProgramaModificacionAuditoria = @Programa
            WHEN NOT MATCHED THEN
                INSERT (IdRequerimiento, NumeroMemorando,
                        UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                VALUES (@IdRequerimiento, @NumeroMemorando, @Cuenta, @Equipo, @Programa);

            SELECT @NumeroMemorando = NULLIF(LTRIM(RTRIM(c.NumeroMemorando)), '')
              FROM requerimiento.CertificacionCcp AS c
             WHERE c.IdRequerimiento = @IdRequerimiento AND c.Activo = 1;
        END

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @NumeroMemorando AS NumeroMemorando,
                   Filtros = JSON_QUERY(COALESCE((
                       SELECT f.IdFiltro, f.CodigoFiltro, Tipo = t.Nombre, t.Orden,
                              f.Resultado, f.ResultadoPid, f.Origen, f.Observacion, f.FechaVerificacion,
                              f.GeneradoDocumentoEvidencia, f.NombreDocumentoEvidencia
                         FROM requerimiento.FiltroIdoneidad AS f
                         JOIN requerimiento.FiltroTipo AS t ON t.CodigoFiltro = f.CodigoFiltro
                        WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                          AND t.Activo = 1
                        ORDER BY t.Orden
                          FOR JSON PATH), '[]')),
                   'OK' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
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
/* 2. requerimiento.paRegistrarFiltroIdoneidad                               */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE requerimiento.paRegistrarFiltroIdoneidad
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51810, 'JSON incorrecto.', 1;

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

        IF @CodigoRol NOT IN ('ABAST_ESPECIALISTA')
            THROW 51811, 'NO_AUTORIZADO: los filtros de idoneidad los registra el especialista de Abastecimiento.', 1;

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        IF @IdRequerimiento IS NULL
            THROW 51812, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        DECLARE @EstadoActual varchar(60);
        SELECT @EstadoActual = e.CodigoEstado
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
         WHERE r.IdRequerimiento = @IdRequerimiento;

        IF @EstadoActual <> 'REQ_FILTROS'
            THROW 51813, 'CONFLICTO_ESTADO: los filtros solo se editan mientras el expediente esta con el especialista.', 1;

        DECLARE @Ahora datetime = GETDATE();

        MERGE requerimiento.FiltroIdoneidad AS d
        USING (
            SELECT CodigoFiltro, Resultado, ResultadoPid, Origen, Observacion,
                   GeneradoDocumentoEvidencia, NombreDocumentoEvidencia
              FROM OPENJSON(@parametro, '$.Filtros')
              WITH (
                  CodigoFiltro               varchar(30),
                  Resultado                  varchar(20),
                  ResultadoPid               varchar(20),
                  Origen                     varchar(20),
                  Observacion                nvarchar(500),
                  GeneradoDocumentoEvidencia nvarchar(1000),
                  NombreDocumentoEvidencia   nvarchar(1000)
              )
        ) AS s
        ON d.IdRequerimiento = @IdRequerimiento AND d.CodigoFiltro = s.CodigoFiltro
        WHEN MATCHED THEN
            UPDATE SET d.Resultado = ISNULL(NULLIF(LTRIM(RTRIM(s.Resultado)), ''), d.Resultado),
                       d.ResultadoPid = ISNULL(NULLIF(LTRIM(RTRIM(s.ResultadoPid)), ''), d.ResultadoPid),
                       d.Origen = ISNULL(NULLIF(LTRIM(RTRIM(s.Origen)), ''), 'MANUAL'),
                       d.Observacion = s.Observacion,
                       d.GeneradoDocumentoEvidencia = ISNULL(NULLIF(LTRIM(RTRIM(s.GeneradoDocumentoEvidencia)), ''), d.GeneradoDocumentoEvidencia),
                       d.NombreDocumentoEvidencia = ISNULL(NULLIF(LTRIM(RTRIM(s.NombreDocumentoEvidencia)), ''), d.NombreDocumentoEvidencia),
                       d.FechaVerificacion = @Ahora,
                       d.UsuarioModificacionAuditoria = @Cuenta,
                       d.FechaModificacionAuditoria = @Ahora,
                       d.EquipoModificacionAuditoria = @Equipo,
                       d.ProgramaModificacionAuditoria = @Programa
        WHEN NOT MATCHED THEN
            INSERT (IdRequerimiento, CodigoFiltro, Resultado, ResultadoPid, Origen, Observacion,
                    GeneradoDocumentoEvidencia, NombreDocumentoEvidencia, FechaVerificacion,
                    UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES (@IdRequerimiento, s.CodigoFiltro,
                    ISNULL(NULLIF(LTRIM(RTRIM(s.Resultado)), ''), 'PENDIENTE'),
                    ISNULL(NULLIF(LTRIM(RTRIM(s.ResultadoPid)), ''), 'PENDIENTE'),
                    ISNULL(NULLIF(LTRIM(RTRIM(s.Origen)), ''), 'MANUAL'),
                    s.Observacion,
                    NULLIF(LTRIM(RTRIM(s.GeneradoDocumentoEvidencia)), ''),
                    NULLIF(LTRIM(RTRIM(s.NombreDocumentoEvidencia)), ''),
                    @Ahora, @Cuenta, @Equipo, @Programa);

        SELECT @resultado = (
            SELECT 1 AS estado, N'Se registraron los filtros de idoneidad.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
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
/* 3b. requerimiento.paDerivarFiltrosIdoneidad                                */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE requerimiento.paDerivarFiltrosIdoneidad
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51815, 'JSON incorrecto.', 1;

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

        DECLARE @CodigoTransicion varchar(70) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.CodigoTransicion'))), '');
        IF @CodigoTransicion NOT IN ('REQ_ENVIAR_FILTROS_COORD', 'REQ_ENVIAR_FILTROS_JEFE')
            THROW 51816, 'VALIDACION_PAYLOAD: transicion de derivacion no reconocida.', 1;

        IF (@CodigoTransicion = 'REQ_ENVIAR_FILTROS_COORD' AND @CodigoRol <> 'ABAST_ESPECIALISTA')
         OR (@CodigoTransicion = 'REQ_ENVIAR_FILTROS_JEFE' AND @CodigoRol <> 'ABAST_COORDINADOR')
            THROW 51817, 'NO_AUTORIZADO: la derivacion de filtros sigue la linea especialista -> coordinador -> jefe.', 1;

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        IF @IdRequerimiento IS NULL
            THROW 51818, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        DECLARE @IdExpediente uniqueidentifier, @Version int, @EstadoActual varchar(60);

        SELECT @IdExpediente = r.IdExpediente, @Version = e.Version, @EstadoActual = e.CodigoEstado
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
         WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1 AND e.Anulado = 0;

        IF @IdExpediente IS NULL
            THROW 51822, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        IF (@CodigoTransicion = 'REQ_ENVIAR_FILTROS_COORD' AND @EstadoActual <> 'REQ_FILTROS')
         OR (@CodigoTransicion = 'REQ_ENVIAR_FILTROS_JEFE' AND @EstadoActual <> 'REQ_FILTROS_COORD')
            THROW 51829, 'CONFLICTO_ESTADO: el expediente no esta en la etapa que corresponde a esta derivacion.', 1;

        INSERT INTO requerimiento.FiltroIdoneidad
            (IdRequerimiento, CodigoFiltro, Resultado, Origen,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT @IdRequerimiento, t.CodigoFiltro, 'PENDIENTE', 'MANUAL',
               @Cuenta, @Equipo, @Programa
          FROM requerimiento.FiltroTipo AS t
         WHERE t.Activo = 1
           AND NOT EXISTS (SELECT 1 FROM requerimiento.FiltroIdoneidad AS f
                            WHERE f.IdRequerimiento = @IdRequerimiento
                              AND f.CodigoFiltro = t.CodigoFiltro);

        IF EXISTS (SELECT 1
                     FROM requerimiento.FiltroIdoneidad AS f
                     JOIN requerimiento.FiltroTipo AS t
                       ON t.CodigoFiltro = f.CodigoFiltro AND t.Activo = 1
                    WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                      AND f.Resultado = 'NO_CONFORME')
            THROW 51823, 'VALIDACION_IDONEIDAD: hay un filtro no conforme. No se puede derivar el expediente.', 1;

        IF EXISTS (SELECT 1
                     FROM requerimiento.FiltroIdoneidad AS f
                     JOIN requerimiento.FiltroTipo AS t
                       ON t.CodigoFiltro = f.CodigoFiltro AND t.Activo = 1
                    WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                      AND f.Resultado = 'PENDIENTE')
            THROW 51824, 'VALIDACION_IDONEIDAD: indique Si o No en todos los filtros antes de derivar.', 1;

        IF EXISTS (SELECT 1
                     FROM requerimiento.FiltroIdoneidad AS f
                     JOIN requerimiento.FiltroTipo AS t
                       ON t.CodigoFiltro = f.CodigoFiltro AND t.Activo = 1
                    WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                      AND (f.GeneradoDocumentoEvidencia IS NULL
                           OR LTRIM(RTRIM(f.GeneradoDocumentoEvidencia)) = ''))
            THROW 51826, 'VALIDACION_IDONEIDAD: adjunte la evidencia PDF de cada filtro antes de derivar.', 1;

        SET @parametro = JSON_MODIFY(@parametro, '$.IdExpediente', CONVERT(nvarchar(36), @IdExpediente));
        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', @CodigoTransicion);
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 3. requerimiento.paConfirmarFiltrosIdoneidad                              */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE requerimiento.paConfirmarFiltrosIdoneidad
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51820, 'JSON incorrecto.', 1;

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

        IF @CodigoRol NOT IN ('ABAST_ESPECIALISTA', 'ABAST_COORDINADOR', 'ABAST_JEFE')
            THROW 51819, 'NO_AUTORIZADO: la solicitud de CCP la confirma Abastecimiento (DEC).', 1;

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        IF @IdRequerimiento IS NULL
            THROW 51821, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        DECLARE @IdExpediente uniqueidentifier, @Version int;

        SELECT @IdExpediente = r.IdExpediente, @Version = e.Version
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
         WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1 AND e.Anulado = 0;

        IF @IdExpediente IS NULL
            THROW 51822, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        DECLARE @EstadoFiltro varchar(60);
        SELECT @EstadoFiltro = e.CodigoEstado
          FROM sigcm.Expediente AS e
         WHERE e.IdExpediente = @IdExpediente;

        IF @EstadoFiltro NOT IN ('REQ_FILTROS', 'REQ_FILTROS_JEFE')
            THROW 51828, 'CONFLICTO_ESTADO: la solicitud de CCP solo procede en la etapa de filtros de idoneidad.', 1;

        /* Misma siembra que paListarFiltroIdoneidad: si el especialista confirma
           desde la bandeja sin abrir el detalle, los registros deben existir. */
        INSERT INTO requerimiento.FiltroIdoneidad
            (IdRequerimiento, CodigoFiltro, Resultado, Origen,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT @IdRequerimiento, t.CodigoFiltro, 'PENDIENTE', 'MANUAL',
               @Cuenta, @Equipo, @Programa
          FROM requerimiento.FiltroTipo AS t
         WHERE t.Activo = 1
           AND NOT EXISTS (SELECT 1 FROM requerimiento.FiltroIdoneidad AS f
                            WHERE f.IdRequerimiento = @IdRequerimiento
                              AND f.CodigoFiltro = t.CodigoFiltro);

        IF EXISTS (SELECT 1
                     FROM requerimiento.FiltroIdoneidad AS f
                    WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                      AND f.CodigoFiltro = 'SUNAT_HABIDO'
                      AND (f.Resultado <> 'CONFORME'
                           OR f.GeneradoDocumentoEvidencia IS NULL
                           OR LTRIM(RTRIM(f.GeneradoDocumentoEvidencia)) = ''))
            THROW 51823, 'VALIDACION_IDONEIDAD: SUNAT debe figurar como Activo y Habido y con la constancia PDF.', 1;

        IF EXISTS (SELECT 1
                     FROM requerimiento.FiltroIdoneidad AS f
                    WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                      AND f.CodigoFiltro = 'RNP'
                      AND (f.Resultado <> 'CONFORME'
                           OR f.GeneradoDocumentoEvidencia IS NULL
                           OR LTRIM(RTRIM(f.GeneradoDocumentoEvidencia)) = ''))
            THROW 51823, 'VALIDACION_IDONEIDAD: el RNP debe estar vigente y con la constancia PDF.', 1;

        IF EXISTS (SELECT 1
                     FROM requerimiento.FiltroIdoneidad AS f
                     JOIN requerimiento.FiltroTipo AS t
                       ON t.CodigoFiltro = f.CodigoFiltro AND t.Activo = 1
                    WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                      AND f.Resultado = 'NO_CONFORME')
            THROW 51823, 'VALIDACION_IDONEIDAD: hay un filtro no conforme. No se puede solicitar la CCP.', 1;

        IF EXISTS (SELECT 1
                     FROM requerimiento.FiltroIdoneidad AS f
                     JOIN requerimiento.FiltroTipo AS t
                       ON t.CodigoFiltro = f.CodigoFiltro AND t.Activo = 1
                    WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                      AND f.Resultado = 'PENDIENTE')
            THROW 51824, 'VALIDACION_IDONEIDAD: indique Si o No en todos los filtros antes de solicitar la CCP.', 1;

        IF NOT EXISTS (SELECT 1
                         FROM requerimiento.FiltroIdoneidad AS f
                         JOIN requerimiento.FiltroTipo AS t
                           ON t.CodigoFiltro = f.CodigoFiltro AND t.Activo = 1
                        WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1)
            THROW 51825, 'VALIDACION_IDONEIDAD: no hay filtros registrados. Abra Iniciar filtros de idoneidad y registre cada registro.', 1;

        IF EXISTS (SELECT 1
                     FROM requerimiento.FiltroIdoneidad AS f
                     JOIN requerimiento.FiltroTipo AS t
                       ON t.CodigoFiltro = f.CodigoFiltro AND t.Activo = 1
                    WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                      AND (f.GeneradoDocumentoEvidencia IS NULL
                           OR LTRIM(RTRIM(f.GeneradoDocumentoEvidencia)) = ''))
            THROW 51826, 'VALIDACION_IDONEIDAD: adjunte la evidencia PDF de SUNAT, RNP y de cada filtro de la matriz.', 1;

        DECLARE @CuerpoMemorando nvarchar(max);
        DECLARE @DocMemo nvarchar(1000) = JSON_VALUE(@parametro, '$.GeneradoDocumentoMemo');
        DECLARE @NomMemo nvarchar(1000) = JSON_VALUE(@parametro, '$.NombreDocumentoMemo');
        DECLARE @NotasMemo nvarchar(500) = JSON_VALUE(@parametro, '$.NotasMemorando');
        DECLARE @NumeroMemo nvarchar(40) = JSON_VALUE(@parametro, '$.NumeroMemorando');
        DECLARE @EnviarSinFirma bit = ISNULL(TRY_CONVERT(bit, JSON_VALUE(@parametro, '$.EnviarSinFirma')), 0);
        DECLARE @AhoraCcp datetime = GETDATE();

        SELECT @CuerpoMemorando = j.CuerpoMemorando
          FROM OPENJSON(@parametro) WITH (CuerpoMemorando nvarchar(max) '$.CuerpoMemorando') AS j;

        IF @DocMemo IS NULL OR LTRIM(RTRIM(@DocMemo)) = ''
        BEGIN
            DECLARE @errMemo nvarchar(400) =
                CASE WHEN @EnviarSinFirma = 1
                     THEN 'VALIDACION_CCP: genere y guarde el memorando antes de enviar a OPP.'
                     ELSE 'VALIDACION_CCP: firme el memorando de solicitud antes de enviar a OPP.'
                END;
            THROW 51827, @errMemo, 1;
        END

        MERGE requerimiento.CertificacionCcp AS c
        USING (SELECT @IdRequerimiento AS IdRequerimiento) AS s
        ON c.IdRequerimiento = s.IdRequerimiento
        WHEN MATCHED THEN
            UPDATE SET c.FechaSolicitud = ISNULL(c.FechaSolicitud, @AhoraCcp),
                       c.CuerpoMemorando = ISNULL(@CuerpoMemorando, c.CuerpoMemorando),
                       c.GeneradoDocumentoMemo = @DocMemo,
                       c.NombreDocumentoMemo = ISNULL(@NomMemo, c.NombreDocumentoMemo),
                       c.NumeroMemorando = ISNULL(NULLIF(LTRIM(RTRIM(@NumeroMemo)), ''), c.NumeroMemorando),
                       c.Observacion = ISNULL(@NotasMemo, c.Observacion),
                       c.UsuarioModificacionAuditoria = @Cuenta,
                       c.FechaModificacionAuditoria = @AhoraCcp,
                       c.EquipoModificacionAuditoria = @Equipo,
                       c.ProgramaModificacionAuditoria = @Programa
        WHEN NOT MATCHED THEN
            INSERT (IdRequerimiento, FechaSolicitud, CuerpoMemorando,
                    GeneradoDocumentoMemo, NombreDocumentoMemo, NumeroMemorando, Observacion,
                    UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES (@IdRequerimiento, @AhoraCcp, @CuerpoMemorando,
                    @DocMemo, @NomMemo, @NumeroMemo, @NotasMemo,
                    @Cuenta, @Equipo, @Programa);

        SET @parametro = JSON_MODIFY(@parametro, '$.IdExpediente', CONVERT(nvarchar(36), @IdExpediente));
        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'REQ_CONFIRMAR_FILTROS');
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        /* Devolver el JSON del motor sin INSERT ... EXEC: bajo ese patron un
           CONFLICTO_VERSION deja la transaccion irrecuperable (3930/3915). */
        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 4. requerimiento.paRegistrarCcp                                           */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE requerimiento.paRegistrarCcp
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51830, 'JSON incorrecto.', 1;

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

        IF @CodigoRol NOT IN ('ABAST_ESPECIALISTA', 'ABAST_COORDINADOR', 'ABAST_JEFE')
            THROW 51831, 'NO_AUTORIZADO: la carga de la CCP la registra el asistente de la DEC (Abastecimiento).', 1;

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));
        DECLARE @NumeroCcp varchar(40) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.NumeroCcp'))), '');
        DECLARE @NumeroExpedienteSiaf varchar(20) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.NumeroExpedienteSiaf'))), '');
        DECLARE @MontoCertificado decimal(18, 2) = TRY_CONVERT(decimal(18, 2), JSON_VALUE(@parametro, '$.MontoCertificado'));
        DECLARE @FechaEmision date = TRY_CONVERT(date, JSON_VALUE(@parametro, '$.FechaEmision'));
        DECLARE @Observacion nvarchar(500) = JSON_VALUE(@parametro, '$.Observacion');
        DECLARE @DocCcp nvarchar(1000) = JSON_VALUE(@parametro, '$.GeneradoDocumentoCcp');
        DECLARE @NomCcp nvarchar(1000) = JSON_VALUE(@parametro, '$.NombreDocumentoCcp');
        DECLARE @DocMemo nvarchar(1000) = JSON_VALUE(@parametro, '$.GeneradoDocumentoMemo');
        DECLARE @NomMemo nvarchar(1000) = JSON_VALUE(@parametro, '$.NombreDocumentoMemo');
        DECLARE @DocMemoUp nvarchar(1000) = JSON_VALUE(@parametro, '$.GeneradoDocumentoMemoUp');
        DECLARE @NomMemoUp nvarchar(1000) = JSON_VALUE(@parametro, '$.NombreDocumentoMemoUp');
        DECLARE @DocPrevision nvarchar(1000) = JSON_VALUE(@parametro, '$.GeneradoDocumentoPrevision');
        DECLARE @NomPrevision nvarchar(1000) = JSON_VALUE(@parametro, '$.NombreDocumentoPrevision');
        DECLARE @CuerpoMemorando nvarchar(max);
        DECLARE @MarcarSolicitud bit = ISNULL(TRY_CONVERT(bit, JSON_VALUE(@parametro, '$.MarcarSolicitud')), 0);
        DECLARE @ValidarCompleto bit = ISNULL(TRY_CONVERT(bit, JSON_VALUE(@parametro, '$.ValidarCompleto')), 1);

        SELECT @CuerpoMemorando = j.CuerpoMemorando
          FROM OPENJSON(@parametro) WITH (CuerpoMemorando nvarchar(max) '$.CuerpoMemorando') AS j;

        IF @IdRequerimiento IS NULL
            THROW 51832, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        IF NOT EXISTS (SELECT 1 FROM requerimiento.Requerimiento
                        WHERE IdRequerimiento = @IdRequerimiento AND Activo = 1)
            THROW 51833, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        IF @ValidarCompleto = 1
        BEGIN
            IF @NumeroCcp IS NULL
                THROW 51834, 'VALIDACION_CCP: indique el numero de certificacion (CCP).', 1;
            IF @NumeroExpedienteSiaf IS NULL
                THROW 51835, 'VALIDACION_CCP: indique el numero de expediente SIAF.', 1;
            IF @MontoCertificado IS NULL OR @MontoCertificado <= 0
                THROW 51836, 'VALIDACION_CCP: indique el monto certificado.', 1;
            IF @FechaEmision IS NULL
                THROW 51837, 'VALIDACION_CCP: indique la fecha de emision de la CCP.', 1;
            IF NULLIF(LTRIM(RTRIM(@DocCcp)), '') IS NULL
                THROW 51838, 'VALIDACION_CCP: adjunte el PDF de la certificacion presupuestaria.', 1;
            IF NULLIF(LTRIM(RTRIM(@DocMemoUp)), '') IS NULL
                THROW 51839, 'VALIDACION_CCP: adjunte el memorando de respuesta de la Unidad de Presupuesto.', 1;

            DECLARE @Datos nvarchar(max), @AnoEje int, @FechaIni date, @Plazo int, @MontoContrato decimal(18, 2);
            DECLARE @CantEnt int, @MesIni int, @RequierePrevision bit = 0;
            DECLARE @FechaSolicitudCcp date;

            SELECT @Datos = r.DatosAdicionales,
                   @AnoEje = r.AnoEje,
                   @FechaIni = r.FechaInicioPrevisto,
                   @Plazo = ISNULL(r.PlazoDias, 0)
              FROM requerimiento.Requerimiento AS r
             WHERE r.IdRequerimiento = @IdRequerimiento;

            SELECT @FechaSolicitudCcp = CONVERT(date, c.FechaSolicitud)
              FROM requerimiento.CertificacionCcp AS c
             WHERE c.IdRequerimiento = @IdRequerimiento AND c.Activo = 1;

            IF @FechaSolicitudCcp IS NOT NULL AND @FechaEmision < @FechaSolicitudCcp
                THROW 51840, 'VALIDACION_CCP: la fecha de emision no puede ser anterior a la fecha de solicitud de la CCP.', 1;

            SET @CantEnt = COALESCE(
                TRY_CONVERT(int, JSON_VALUE(@Datos, '$.Proveedores[0].CantidadEntregables')),
                TRY_CONVERT(int, JSON_VALUE(@Datos, '$.Proveedor.CantidadEntregables')),
                0);

            SET @MontoContrato = COALESCE(
                TRY_CONVERT(decimal(18, 2), JSON_VALUE(@Datos, '$.Proveedores[0].CantidadEntregables'))
                    * TRY_CONVERT(decimal(18, 2), JSON_VALUE(@Datos, '$.Proveedores[0].MontoMensual')),
                TRY_CONVERT(decimal(18, 2), JSON_VALUE(@Datos, '$.Proveedor.CantidadEntregables'))
                    * TRY_CONVERT(decimal(18, 2), JSON_VALUE(@Datos, '$.Proveedor.MontoMensual')),
                0);

            IF @MontoContrato = 0
                SELECT @MontoContrato = ISNULL(r.Monto, 0)
                  FROM requerimiento.Requerimiento AS r
                 WHERE r.IdRequerimiento = @IdRequerimiento;

            IF ABS(@MontoCertificado - @MontoContrato) > 0.01
                THROW 51841,
                    'VALIDACION_CCP: el monto de la certificacion ingresada no coincide con el monto total de la propuesta economica del Anexo 5. Revise el expediente.',
                    1;

            SET @MesIni = MONTH(ISNULL(@FechaIni, GETDATE()));
            IF (@MesIni + ISNULL(@CantEnt, 0) - 1) > 12
                SET @RequierePrevision = 1;
            IF YEAR(DATEADD(day, @Plazo, ISNULL(@FechaIni, GETDATE()))) > @AnoEje
                SET @RequierePrevision = 1;

            IF @RequierePrevision = 1 AND NULLIF(LTRIM(RTRIM(@DocPrevision)), '') IS NULL
                THROW 51842,
                    'VALIDACION_CCP: el plazo supera el ano fiscal. Adjunte la prevision presupuestal aprobada por OPP.',
                    1;

            IF EXISTS (SELECT 1
                         FROM requerimiento.FiltroIdoneidad AS f
                         JOIN requerimiento.FiltroTipo AS t
                           ON t.CodigoFiltro = f.CodigoFiltro AND t.Activo = 1
                        WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                          AND f.Resultado = 'NO_CONFORME')
                THROW 51843,
                    'VALIDACION_IDONEIDAD: hay filtros de idoneidad con resultado No Apto. No es posible emitir la orden de servicio.',
                    1;

            IF EXISTS (SELECT 1
                         FROM requerimiento.FiltroIdoneidad AS f
                         JOIN requerimiento.FiltroTipo AS t
                           ON t.CodigoFiltro = f.CodigoFiltro AND t.Activo = 1
                        WHERE f.IdRequerimiento = @IdRequerimiento AND f.Activo = 1
                          AND f.Resultado NOT IN ('CONFORME', 'NO_APLICA'))
                THROW 51844,
                    'VALIDACION_IDONEIDAD: los filtros de idoneidad deben seguir vigentes (sin alertas pendientes).',
                    1;
        END

        DECLARE @Ahora datetime = GETDATE();

        MERGE requerimiento.CertificacionCcp AS d
        USING (SELECT @IdRequerimiento AS IdRequerimiento) AS s
        ON d.IdRequerimiento = s.IdRequerimiento
        WHEN MATCHED THEN
            UPDATE SET d.NumeroCcp = ISNULL(@NumeroCcp, d.NumeroCcp),
                       d.NumeroExpedienteSiaf = ISNULL(@NumeroExpedienteSiaf, d.NumeroExpedienteSiaf),
                       d.MontoCertificado = ISNULL(@MontoCertificado, d.MontoCertificado),
                       d.FechaEmision = ISNULL(@FechaEmision, d.FechaEmision),
                       d.FechaSolicitud = CASE WHEN @MarcarSolicitud = 1 THEN ISNULL(d.FechaSolicitud, @Ahora) ELSE d.FechaSolicitud END,
                       d.Observacion = ISNULL(@Observacion, d.Observacion),
                       d.GeneradoDocumentoCcp = ISNULL(@DocCcp, d.GeneradoDocumentoCcp),
                       d.NombreDocumentoCcp = ISNULL(@NomCcp, d.NombreDocumentoCcp),
                       d.GeneradoDocumentoMemo = ISNULL(@DocMemo, d.GeneradoDocumentoMemo),
                       d.NombreDocumentoMemo = ISNULL(@NomMemo, d.NombreDocumentoMemo),
                       d.GeneradoDocumentoMemoUp = ISNULL(@DocMemoUp, d.GeneradoDocumentoMemoUp),
                       d.NombreDocumentoMemoUp = ISNULL(@NomMemoUp, d.NombreDocumentoMemoUp),
                       d.GeneradoDocumentoPrevision = ISNULL(@DocPrevision, d.GeneradoDocumentoPrevision),
                       d.NombreDocumentoPrevision = ISNULL(@NomPrevision, d.NombreDocumentoPrevision),
                       d.CuerpoMemorando = ISNULL(@CuerpoMemorando, d.CuerpoMemorando),
                       d.UsuarioModificacionAuditoria = @Cuenta,
                       d.FechaModificacionAuditoria = @Ahora,
                       d.EquipoModificacionAuditoria = @Equipo,
                       d.ProgramaModificacionAuditoria = @Programa
        WHEN NOT MATCHED THEN
            INSERT (IdRequerimiento, NumeroCcp, NumeroExpedienteSiaf, MontoCertificado,
                    FechaSolicitud, FechaEmision, Observacion,
                    GeneradoDocumentoCcp, NombreDocumentoCcp,
                    GeneradoDocumentoMemo, NombreDocumentoMemo,
                    GeneradoDocumentoMemoUp, NombreDocumentoMemoUp,
                    GeneradoDocumentoPrevision, NombreDocumentoPrevision,
                    CuerpoMemorando,
                    UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES (@IdRequerimiento, @NumeroCcp, @NumeroExpedienteSiaf, @MontoCertificado,
                    CASE WHEN @MarcarSolicitud = 1 THEN @Ahora ELSE NULL END,
                    @FechaEmision, @Observacion,
                    @DocCcp, @NomCcp, @DocMemo, @NomMemo,
                    @DocMemoUp, @NomMemoUp, @DocPrevision, @NomPrevision,
                    @CuerpoMemorando,
                    @Cuenta, @Equipo, @Programa);

        SELECT @resultado = (
            SELECT 1 AS estado, N'Se registró la certificación presupuestaria.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
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
/* 5. requerimiento.paRegistrarOrdenServicio                                 */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE requerimiento.paRegistrarOrdenServicio
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51840, 'JSON incorrecto.', 1;

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

        IF @CodigoRol NOT IN ('ABAST_ESPECIALISTA','ABAST_COORDINADOR','ABAST_JEFE')
            THROW 51841, 'NO_AUTORIZADO: la orden de servicio la emite Abastecimiento.', 1;

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));
        DECLARE @NumeroOrden varchar(40) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.NumeroOrden'))), '');
        DECLARE @Doc nvarchar(1000) = JSON_VALUE(@parametro, '$.GeneradoDocumento');
        DECLARE @Nom nvarchar(1000) = JSON_VALUE(@parametro, '$.NombreDocumento');

        IF @IdRequerimiento IS NULL
            THROW 51842, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        IF NOT EXISTS (SELECT 1 FROM requerimiento.CertificacionCcp
                        WHERE IdRequerimiento = @IdRequerimiento AND Activo = 1
                          AND NULLIF(LTRIM(RTRIM(NumeroCcp)), '') IS NOT NULL)
            THROW 51844, 'CONFLICTO_CCP: no hay una CCP cargada. Registre el numero de certificacion antes de emitir la orden.', 1;

        DECLARE @Datos nvarchar(max), @CorreoLocador varchar(200), @CorreoAu varchar(200);
        DECLARE @IdResponsable uniqueidentifier;

        SELECT @Datos = r.DatosAdicionales, @IdResponsable = r.IdResponsable
          FROM requerimiento.Requerimiento AS r
         WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1;

        IF @Datos IS NULL
            THROW 51845, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        SET @CorreoLocador = COALESCE(
            NULLIF(LTRIM(RTRIM(JSON_VALUE(@Datos, '$.Proveedores[0].Email'))), ''),
            NULLIF(LTRIM(RTRIM(JSON_VALUE(@Datos, '$.Proveedor.Email'))), ''));

        SELECT @CorreoAu = NULLIF(LTRIM(RTRIM(u.Correo)), '')
          FROM sigcm.Usuario AS u
         WHERE u.IdUsuario = @IdResponsable;

        DECLARE @Ahora datetime = GETDATE();

        MERGE requerimiento.OrdenServicio AS d
        USING (SELECT @IdRequerimiento AS IdRequerimiento) AS s
        ON d.IdRequerimiento = s.IdRequerimiento
        WHEN MATCHED THEN
            UPDATE SET d.NumeroOrden = COALESCE(@NumeroOrden, d.NumeroOrden),
                       d.FechaEmision = ISNULL(d.FechaEmision, @Ahora),
                       d.CorreoLocador = ISNULL(@CorreoLocador, d.CorreoLocador),
                       d.CorreoAreaUsuaria = ISNULL(@CorreoAu, d.CorreoAreaUsuaria),
                       d.GeneradoDocumento = ISNULL(@Doc, d.GeneradoDocumento),
                       d.NombreDocumento = ISNULL(@Nom, d.NombreDocumento),
                       d.UsuarioModificacionAuditoria = @Cuenta,
                       d.FechaModificacionAuditoria = @Ahora,
                       d.EquipoModificacionAuditoria = @Equipo,
                       d.ProgramaModificacionAuditoria = @Programa
        WHEN NOT MATCHED THEN
            INSERT (IdRequerimiento, NumeroOrden, FechaEmision, CorreoLocador, CorreoAreaUsuaria,
                    GeneradoDocumento, NombreDocumento,
                    UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
            VALUES (@IdRequerimiento, @NumeroOrden, @Ahora, @CorreoLocador, @CorreoAu,
                    @Doc, @Nom, @Cuenta, @Equipo, @Programa);

        SELECT @resultado = (
            SELECT 1 AS estado,
                   N'Se registraron los datos de la orden de servicio. Use la accion Emitir orden de servicio en la bandeja para crearla en SIGA.' AS mensaje,
                   NumeroOrden = COALESCE(@NumeroOrden, (SELECT TOP 1 o.NumeroOrden
                                                           FROM requerimiento.OrdenServicio AS o
                                                          WHERE o.IdRequerimiento = @IdRequerimiento)),
                   @CorreoLocador AS CorreoLocador,
                   @CorreoAu AS CorreoAreaUsuaria
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
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
/* 6. requerimiento.paPrepararNotificacionOrden                              */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE requerimiento.paPrepararNotificacionOrden
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51850, 'JSON incorrecto.', 1;

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

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));

        IF @IdRequerimiento IS NULL
            THROW 51851, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        DECLARE @Codigo varchar(40), @Denominacion varchar(500), @Plazo int,
                @NumeroOrden varchar(40), @CorreoLocador varchar(200), @CorreoAu varchar(200),
                @IdExpediente uniqueidentifier, @Version int, @Estado varchar(60),
                @Datos nvarchar(max), @Proveedor nvarchar(max);

        SELECT @Codigo = r.Codigo, @Denominacion = r.Denominacion, @Plazo = r.PlazoDias,
               @IdExpediente = r.IdExpediente,
               @NumeroOrden = o.NumeroOrden,
               @CorreoLocador = o.CorreoLocador,
               @CorreoAu = o.CorreoAreaUsuaria,
               @Version = e.Version,
               @Estado = e.CodigoEstado,
               @Datos = r.DatosAdicionales
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
          JOIN requerimiento.OrdenServicio AS o ON o.IdRequerimiento = r.IdRequerimiento AND o.Activo = 1
         WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1;

        IF @Codigo IS NULL
            THROW 51852, 'NO_ENCONTRADO: no hay una orden de servicio registrada para este requerimiento.', 1;

        IF @Estado <> 'REQ_OS_EMITIDA'
            THROW 51853, 'CONFLICTO_ESTADO: la orden solo se notifica cuando ya fue emitida.', 1;

        IF NULLIF(LTRIM(RTRIM(@CorreoLocador)), '') IS NULL
            THROW 51854, 'VALIDACION_CORREO: el locador no tiene correo en el Anexo 5 / Anexo 6. Completelo antes de notificar.', 1;

        SET @Proveedor = COALESCE(
            JSON_QUERY(@Datos, '$.Proveedores[0]'),
            JSON_QUERY(@Datos, '$.Proveedor'));

        DECLARE @Asunto nvarchar(300) = CONCAT(N'Orden de servicio ', ISNULL(@NumeroOrden, @Codigo), N' — ', @Denominacion);
        DECLARE @Cuerpo nvarchar(max) = CONCAT(
            N'<p>Se comunica la emisión de la orden de servicio <b>', ISNULL(@NumeroOrden, @Codigo),
            N'</b> correspondiente al requerimiento <b>', @Codigo, N'</b>.</p>',
            N'<p><b>Denominación:</b> ', @Denominacion, N'</p>',
            N'<p>A partir de esta notificación inicia el plazo de ejecución (',
            CONVERT(varchar(10), ISNULL(@Plazo, 0)), N' día(s) calendario).</p>',
            N'<p>Autoridad Nacional de Infraestructura — SIGCM</p>');

        SELECT @resultado = (
            SELECT 1 AS estado,
                   @IdExpediente AS IdExpediente,
                   @Version AS Version,
                   @NumeroOrden AS NumeroOrden,
                   Destinatario = @CorreoLocador,
                   Copia = @CorreoAu,
                   Asunto = @Asunto,
                   Cuerpo = @Cuerpo,
                   JSON_QUERY(@Proveedor) AS Proveedor,
                   N'Sobre de notificación listo.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
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
/* 7. requerimiento.paMarcarOrdenNotificada                                  */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE requerimiento.paMarcarOrdenNotificada
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51860, 'JSON incorrecto.', 1;

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

        DECLARE @IdRequerimiento uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdRequerimiento'));
        DECLARE @ResultadoCorreo nvarchar(300) = JSON_VALUE(@parametro, '$.ResultadoCorreo');

        IF @IdRequerimiento IS NULL
            THROW 51861, 'VALIDACION_PAYLOAD: falta IdRequerimiento.', 1;

        DECLARE @IdExpediente uniqueidentifier, @Version int, @Ahora datetime = GETDATE();

        SELECT @IdExpediente = r.IdExpediente, @Version = e.Version
          FROM requerimiento.Requerimiento AS r
          JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
         WHERE r.IdRequerimiento = @IdRequerimiento AND r.Activo = 1;

        IF @IdExpediente IS NULL
            THROW 51862, 'NO_ENCONTRADO: el requerimiento no existe.', 1;

        UPDATE requerimiento.OrdenServicio
           SET NotificadoEn = @Ahora,
               ResultadoNotificacion = @ResultadoCorreo,
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = @Ahora,
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdRequerimiento = @IdRequerimiento AND Activo = 1;

        SET @parametro = JSON_MODIFY(@parametro, '$.IdExpediente', CONVERT(nvarchar(36), @IdExpediente));
        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'REQ_NOTIFICAR_OS');
        IF JSON_VALUE(@parametro, '$.Version') IS NULL
            SET @parametro = JSON_MODIFY(@parametro, '$.Version', @Version);

        EXEC sigcm.paEjecutarTransicion @parametro;
        RETURN;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F008 aplicada: filtros, CCP, orden y notificacion de locacion.';
GO
