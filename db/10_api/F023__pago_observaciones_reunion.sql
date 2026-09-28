/*
===============================================================================
  SIGCM - F023 : Observaciones de la reunion del 27-09-2026 (modulo PAGO)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Requiere V038. Se aplica ANTES de F012 (que usa pago.fnMeToca y
  pago.fnCodigoExpedientePago) y de S052.

   1. sigcm.fnSiguienteDiaHabil
   2. pago.fnCodigoExpedientePago
   3. pago.fnMeToca
   4. pago.paAsignarEspecialista
   5. pago.paNotificarObservacion
   6. pago.paActualizarNumeroContrato
   7. pago.paRegistrarDocumentoAdicional / pago.paAnularDocumentoAdicional
   8. pago.paResumenAlertas
   9. sigcm.fnExpedienteReferencia / sigcm.paResolverCopiaCorreo
  10. sigcm.paRegistrarCorreo / sigcm.paListarCorreo
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. sigcm.fnSiguienteDiaHabil                                              */
/* ========================================================================== */

/* La misma fecha si es habil; si cae en fin de semana o en sigcm.DiaNoHabil,
   el primer dia habil siguiente. */
CREATE OR ALTER FUNCTION sigcm.fnSiguienteDiaHabil (@Fecha date)
RETURNS date
AS
BEGIN
    IF @Fecha IS NULL RETURN NULL;
    IF sigcm.fnEsDiaHabil(@Fecha) = 1 RETURN @Fecha;
    RETURN sigcm.fnSumarDiasHabiles(@Fecha, 1);
END
GO

/* ========================================================================== */
/* 2. pago.fnCodigoExpedientePago                                            */
/* ========================================================================== */

/* (nro.pago-OS/OC)_(nro O/S u O/C)_(nro entregable). El nro. de pago es el
   correlativo de paSiguienteCodigo ('PAG-AAAA-000123' -> '000123'). */
CREATE OR ALTER FUNCTION pago.fnCodigoExpedientePago
(
    @CodigoBase       varchar(40),
    @TipoOrden        char(2),
    @NumeroOrden      varchar(40),
    @NumeroEntregable smallint
)
RETURNS varchar(40)
AS
BEGIN
    DECLARE @Seq varchar(10) = RIGHT(@CodigoBase, 6);
    IF @Seq LIKE '%[^0-9]%' SET @Seq = RIGHT(REPLACE(@CodigoBase, '-', ''), 6);

    RETURN LEFT(CONCAT(@Seq, '-', ISNULL(NULLIF(@TipoOrden, ''), 'OS'), '_',
                       LTRIM(RTRIM(ISNULL(@NumeroOrden, ''))), '_',
                       CONVERT(varchar(5), @NumeroEntregable)), 40);
END
GO

/* ========================================================================== */
/* 3. pago.fnMeToca                                                          */
/* ========================================================================== */

/* Si la accion pendiente del expediente es de ESTE actor. La secretaria del
   area atiende lo del jefe salvo la firma, y un expediente asignado a una
   persona solo le toca a esa persona. */
CREATE OR ALTER FUNCTION pago.fnMeToca
(
    @IdExpedientePago    uniqueidentifier,
    @CodigoEstado        varchar(60),
    @IdUnidadActual      uniqueidentifier,
    @IdResponsableActual uniqueidentifier,
    @RolResponsable      varchar(40),
    @IdUsuario           uniqueidentifier,
    @CodigoRol           varchar(40),
    @IdUnidad            uniqueidentifier
)
RETURNS bit
AS
BEGIN
    IF @CodigoEstado = 'PAG_PEND_VISTO_BUENO'
        RETURN CASE WHEN EXISTS (
            SELECT 1
              FROM pago.RutaInformePrevio AS rv
             WHERE rv.IdExpedientePago = @IdExpedientePago
               AND rv.Otorgado = 0
               AND rv.IdUnidad = @IdUnidad
               AND rv.CodigoRol = @CodigoRol
               AND rv.Orden = (SELECT MIN(rv2.Orden)
                                 FROM pago.RutaInformePrevio AS rv2
                                WHERE rv2.IdExpedientePago = @IdExpedientePago
                                  AND rv2.Otorgado = 0))
            THEN 1 ELSE 0 END;

    IF @IdUnidadActual = @IdUnidad
       AND (@RolResponsable = @CodigoRol
            OR (@RolResponsable = 'AREA_JEFE' AND @CodigoRol = 'AREA_SECRETARIA'
                AND @CodigoEstado <> 'PAG_CONFORMIDAD_PEND_FIRMA'))
       AND (@IdResponsableActual IS NULL OR @IdResponsableActual = @IdUsuario)
        RETURN 1;

    RETURN 0;
END
GO

/* ========================================================================== */
/* 4. pago.paAsignarEspecialista                                             */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE pago.paAsignarEspecialista
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52301, 'JSON incorrecto.', 1;

        DECLARE @IdExpediente uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @IdResponsable uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdResponsableDestino'));

        IF @IdExpediente IS NULL
            THROW 52302, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;
        IF @IdResponsable IS NULL
            THROW 52303, 'VALIDACION_PAYLOAD: seleccione el especialista al que se asigna el entregable.', 1;

        DECLARE @Estado varchar(60), @Version int;
        SELECT @Estado = e.CodigoEstado, @Version = e.Version
          FROM sigcm.Expediente AS e
          JOIN pago.ExpedientePago AS p ON p.IdExpediente = e.IdExpediente
         WHERE e.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @Estado IS NULL
            THROW 52304, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;
        IF @Estado <> 'PAG_RECIBIDO_AU'
            THROW 52305, 'CONFLICTO_ESTADO: el entregable ya fue asignado o no esta en recepcion del area usuaria.', 1;

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'PAG_ASIGNAR_ESPECIALISTA');
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
/* 5. pago.paNotificarObservacion                                            */
/* ========================================================================== */

/* Abastecimiento notifica formalmente al proveedor la observacion del area
   usuaria. El plazo de subsanacion (30% del plazo del entregable) corre desde
   aqui, no desde que el area observo. */
CREATE OR ALTER PROCEDURE pago.paNotificarObservacion
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52311, 'JSON incorrecto.', 1;

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
            THROW 52312, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @IdPago uniqueidentifier, @Plazo int, @Version int, @Estado varchar(60);
        SELECT @IdPago = p.IdExpedientePago, @Plazo = p.PlazoDias,
               @Version = e.Version, @Estado = e.CodigoEstado
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
         WHERE p.IdExpediente = @IdExpediente AND p.Activo = 1;

        IF @IdPago IS NULL
            THROW 52313, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;
        IF @Estado <> 'PAG_OBS_AU_ABAST'
            THROW 52314, 'CONFLICTO_ESTADO: el entregable no tiene una observacion del area usuaria por notificar.', 1;

        DECLARE @DiasSub int = CEILING(@Plazo * 0.30);
        IF @DiasSub < 1 SET @DiasSub = 1;

        UPDATE pago.ExpedientePago
           SET FechaLimiteSubsanacion = DATEADD(DAY, @DiasSub, GETDATE()),
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdExpedientePago = @IdPago;

        SET @parametro = JSON_MODIFY(@parametro, '$.CodigoTransicion', 'PAG_NOTIFICAR_OBS_PROVEEDOR');
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
/* 6. pago.paActualizarNumeroContrato                                        */
/* ========================================================================== */

/* N.° de contrato del Anexo 11. Aplica a todos los entregables de la misma
   orden: es un dato del contrato, no del entregable. */
CREATE OR ALTER PROCEDURE pago.paActualizarNumeroContrato
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52321, 'JSON incorrecto.', 1;

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

        IF @CodigoRol NOT LIKE 'AREA[_]%' AND @CodigoRol NOT LIKE 'ABAST[_]%'
            THROW 52322, 'NO_AUTORIZADO: solo el area usuaria o Abastecimiento registran el numero de contrato.', 1;

        DECLARE @IdExpediente uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @Numero varchar(60) =
            NULLIF(LTRIM(RTRIM(JSON_VALUE(@parametro, '$.NumeroContrato'))), '');

        DECLARE @IdRequerimiento uniqueidentifier;
        SELECT @IdRequerimiento = IdRequerimiento
          FROM pago.ExpedientePago WHERE IdExpediente = @IdExpediente AND Activo = 1;
        IF @IdRequerimiento IS NULL
            THROW 52323, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        UPDATE pago.ExpedientePago
           SET NumeroContrato = @Numero,
               UsuarioModificacionAuditoria = @Cuenta,
               FechaModificacionAuditoria = GETDATE(),
               EquipoModificacionAuditoria = @Equipo,
               ProgramaModificacionAuditoria = @Programa
         WHERE IdRequerimiento = @IdRequerimiento AND Activo = 1;

        SELECT @resultado = (
            SELECT 1 AS estado, N'Numero de contrato registrado.' AS mensaje,
                   @Numero AS NumeroContrato
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 7. Otros documentos del pago                                              */
/* ========================================================================== */

/*
  Entrada:
  { "IdExpediente": "...",
    "Documentos": [ { "GeneradoDocumento": "...", "NombreDocumento": "...",
                      "Descripcion": "..." }, ... ] }
  Los archivos ya estan en el file server (carpeta pago).
*/
CREATE OR ALTER PROCEDURE pago.paRegistrarDocumentoAdicional
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52331, 'JSON incorrecto.', 1;

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
        DECLARE @IdPago uniqueidentifier;
        SELECT @IdPago = IdExpedientePago
          FROM pago.ExpedientePago WHERE IdExpediente = @IdExpediente AND Activo = 1;
        IF @IdPago IS NULL
            THROW 52332, 'NO_ENCONTRADO: el expediente de pago no existe.', 1;

        DECLARE @Docs TABLE (GeneradoDocumento nvarchar(200), NombreDocumento nvarchar(300),
                             Descripcion nvarchar(500));
        INSERT INTO @Docs
        SELECT NULLIF(LTRIM(RTRIM(d.GeneradoDocumento)), N''),
               LEFT(COALESCE(NULLIF(LTRIM(RTRIM(d.NombreDocumento)), N''), d.GeneradoDocumento), 300),
               NULLIF(LTRIM(RTRIM(d.Descripcion)), N'')
          FROM OPENJSON(@parametro, '$.Documentos')
          WITH (GeneradoDocumento nvarchar(200), NombreDocumento nvarchar(300),
                Descripcion nvarchar(500)) AS d;

        DELETE FROM @Docs WHERE GeneradoDocumento IS NULL;
        IF NOT EXISTS (SELECT 1 FROM @Docs)
            THROW 52333, 'VALIDACION_PAYLOAD: adjunte al menos un archivo.', 1;

        INSERT INTO pago.DocumentoAdicional
            (IdExpedientePago, GeneradoDocumento, NombreDocumento, Descripcion,
             IdUsuario, NombreUsuario, CodigoRol,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT @IdPago, GeneradoDocumento, NombreDocumento, Descripcion,
               @IdUsuario, @NombreCompleto, @CodigoRol,
               LEFT(@Cuenta, 30), @Equipo, @Programa
          FROM @Docs;

        DECLARE @n int = @@ROWCOUNT;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   CONCAT(N'Se registraron ', @n, N' documento(s).') AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE pago.paAnularDocumentoAdicional
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52341, 'JSON incorrecto.', 1;

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

        DECLARE @Id uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdDocumentoAdicional'));
        DECLARE @Autor uniqueidentifier;
        SELECT @Autor = IdUsuario FROM pago.DocumentoAdicional
         WHERE IdDocumentoAdicional = @Id AND Activo = 1;

        IF @Id IS NULL OR NOT EXISTS (SELECT 1 FROM pago.DocumentoAdicional
                                       WHERE IdDocumentoAdicional = @Id AND Activo = 1)
            THROW 52342, 'NO_ENCONTRADO: el documento no existe o ya fue retirado.', 1;
        IF ISNULL(@Autor, '00000000-0000-0000-0000-000000000000') <> @IdUsuario
           AND @CodigoRol NOT LIKE 'ABAST[_]%'
            THROW 52343, 'NO_AUTORIZADO: solo quien subio el documento o Abastecimiento pueden retirarlo.', 1;

        UPDATE pago.DocumentoAdicional
           SET Activo = 0,
               UsuarioModificacionAuditoria = LEFT(@Cuenta, 30),
               FechaModificacionAuditoria = GETDATE()
         WHERE IdDocumentoAdicional = @Id;

        SELECT @resultado = (
            SELECT 1 AS estado, N'Documento retirado del expediente.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 8. pago.paResumenAlertas                                                  */
/* ========================================================================== */

/*
  Campanita y tablero de alertas:
    Pendientes : expedientes cuya accion le toca a este actor.
    PorVencer  : entregables por presentar que vencen en los proximos 7 dias.
    Vencidos   : entregables vencidos sin presentacion (sin recepcion).
  Abastecimiento ve toda la entidad; el resto, lo de su unidad o lo que paso
  por ella; el proveedor, lo suyo.
*/
CREATE OR ALTER PROCEDURE pago.paResumenAlertas
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52351, 'JSON incorrecto.', 1;

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

        DECLARE @DocIdent varchar(20), @CorreoActor varchar(200);
        SELECT @DocIdent = NULLIF(DocumentoIdentidad, ''), @CorreoActor = Correo
          FROM sigcm.Usuario WHERE IdUsuario = @IdUsuario;

        DECLARE @Hoy date = CONVERT(date, GETDATE());
        DECLARE @Limite7 date = DATEADD(DAY, 7, @Hoy);
        DECLARE @TodaEntidad bit = CASE WHEN @CodigoRol LIKE 'ABAST[_]%' THEN 1 ELSE 0 END;

        DECLARE @Base TABLE (
            IdExpediente uniqueidentifier PRIMARY KEY, Codigo varchar(40),
            CodigoEstado varchar(60), Estado varchar(150), NumeroOrdenSiga varchar(40),
            TipoOrden char(2), NumeroEntregable smallint, NombreEntregable nvarchar(300),
            NombreLocador nvarchar(250), FechaLimite date, MeToca bit);

        INSERT INTO @Base
        SELECT e.IdExpediente, e.Codigo, e.CodigoEstado, w.Nombre, p.NumeroOrdenSiga,
               p.TipoOrden, p.NumeroEntregable, p.NombreEntregable, p.NombreLocador,
               p.FechaLimiteCronograma,
               pago.fnMeToca(p.IdExpedientePago, e.CodigoEstado, e.IdUnidadActual,
                             e.IdResponsableActual, w.RolResponsable,
                             @IdUsuario, @CodigoRol, @IdUnidad)
          FROM pago.ExpedientePago AS p
          JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
          JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
         WHERE e.Anulado = 0 AND e.Activo = 1 AND p.Activo = 1
           AND e.CodigoEstado <> 'PAG_PAGO_EFECTUADO'
           AND (
                (@CodigoRol = 'PROVEEDOR' AND (
                    (@DocIdent IS NOT NULL AND (p.DniLocador = @DocIdent OR p.RucLocador = @DocIdent))
                 OR p.RucLocador = @Cuenta OR p.DniLocador = @Cuenta
                 OR (@CorreoActor IS NOT NULL AND p.CorreoLocador = @CorreoActor)))
             OR (@CodigoRol <> 'PROVEEDOR' AND (
                    @TodaEntidad = 1
                 OR e.IdUnidadActual = @IdUnidad
                 OR e.IdUnidadOrigen = @IdUnidad
                 OR EXISTS (SELECT 1 FROM sigcm.Historial AS h
                             WHERE h.IdExpediente = e.IdExpediente
                               AND (h.IdActor = @IdUsuario OR h.IdActorUnidad = @IdUnidad))))
           );

        DECLARE @Items TABLE (IdExpediente uniqueidentifier, Tipo varchar(20), Prioridad int);
        INSERT INTO @Items
        SELECT IdExpediente, 'VENCIDO', 1 FROM @Base
         WHERE CodigoEstado = 'PAG_PENDIENTE' AND FechaLimite < @Hoy;
        INSERT INTO @Items
        SELECT IdExpediente, 'POR_VENCER', 2 FROM @Base
         WHERE CodigoEstado = 'PAG_PENDIENTE' AND FechaLimite BETWEEN @Hoy AND @Limite7;
        INSERT INTO @Items
        SELECT b.IdExpediente, 'PENDIENTE', 3 FROM @Base AS b
         WHERE b.MeToca = 1
           AND NOT EXISTS (SELECT 1 FROM @Items AS i WHERE i.IdExpediente = b.IdExpediente);

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Pendientes = (SELECT COUNT(*) FROM @Base WHERE MeToca = 1),
                   PorVencer  = (SELECT COUNT(*) FROM @Items WHERE Tipo = 'POR_VENCER'),
                   Vencidos   = (SELECT COUNT(*) FROM @Items WHERE Tipo = 'VENCIDO'),
                   Items = JSON_QUERY(COALESCE((
                       SELECT TOP 30 b.IdExpediente, b.Codigo, b.CodigoEstado, b.Estado,
                              b.NumeroOrdenSiga, b.TipoOrden, b.NumeroEntregable,
                              b.NombreEntregable, b.NombreLocador, b.FechaLimite,
                              i.Tipo,
                              DiasParaVencer = DATEDIFF(DAY, @Hoy, b.FechaLimite)
                         FROM @Items AS i
                         JOIN @Base AS b ON b.IdExpediente = i.IdExpediente
                        ORDER BY i.Prioridad, b.FechaLimite
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 9. Expediente de referencia de un correo y copia institucional            */
/* ========================================================================== */

/* Resuelve el expediente al que pertenece un envio a partir de la entrada del
   endpoint: IdExpediente, IdExpedientes[0], IdRequerimiento, IdSolicitud,
   IdExpedientePago o IdContrato, en ese orden. */
CREATE OR ALTER FUNCTION sigcm.fnExpedienteReferencia (@Json nvarchar(max))
RETURNS uniqueidentifier
AS
BEGIN
    IF @Json IS NULL OR ISJSON(@Json) <> 1 RETURN NULL;

    DECLARE @Id uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@Json, '$.IdExpediente'));
    IF @Id IS NULL
        SET @Id = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@Json, '$.IdExpedientes[0]'));
    IF @Id IS NULL
        SELECT @Id = r.IdExpediente FROM requerimiento.Requerimiento AS r
         WHERE r.IdRequerimiento = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@Json, '$.IdRequerimiento'));
    IF @Id IS NULL
        SELECT @Id = s.IdExpediente FROM cmn.Solicitud AS s
         WHERE s.IdSolicitud = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@Json, '$.IdSolicitud'));
    IF @Id IS NULL
        SELECT @Id = p.IdExpediente FROM pago.ExpedientePago AS p
         WHERE p.IdExpedientePago = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@Json, '$.IdExpedientePago'));
    IF @Id IS NULL
        SELECT @Id = c.IdExpediente FROM ejecucion.Contrato AS c
         WHERE c.IdContrato = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@Json, '$.IdContrato'));

    IF @Id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sigcm.Expediente WHERE IdExpediente = @Id)
        SET @Id = NULL;
    RETURN @Id;
END
GO

/*
  Copia institucional automatica de los correos al proveedor: el especialista
  que envia, el jefe del area usuaria y el punto focal del area
  (sigcm.UsuarioRol.EsPuntoFocal). Devuelve la copia ya fusionada con la que
  traia el sobre, sin duplicados y sin repetir al destinatario.

  Entrada: { ...entrada del endpoint..., "Destinatario": "...", "Copia": "..." }
  Salida : { "estado": 1, "Copia": "a@x;b@y" }
*/
CREATE OR ALTER PROCEDURE sigcm.paResolverCopiaCorreo
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52361, 'JSON incorrecto.', 1;

        DECLARE @Cuenta varchar(120) = JSON_VALUE(@parametro, '$.Actor.Usuario');
        DECLARE @Para nvarchar(1000) = ISNULL(JSON_VALUE(@parametro, '$.Destinatario'), N'');
        DECLARE @Copia nvarchar(1000) = ISNULL(JSON_VALUE(@parametro, '$.Copia'), N'');
        DECLARE @IdExpediente uniqueidentifier = sigcm.fnExpedienteReferencia(@parametro);
        DECLARE @IdUnidadOrigen uniqueidentifier;

        /* Un pago o un contrato cuelgan del requerimiento: el area usuaria es
           la de origen de cualquiera de los dos. */
        SELECT @IdUnidadOrigen = e.IdUnidadOrigen
          FROM sigcm.Expediente AS e WHERE e.IdExpediente = @IdExpediente;

        DECLARE @Lista TABLE (Correo nvarchar(200) PRIMARY KEY);

        INSERT INTO @Lista
        SELECT DISTINCT LOWER(LTRIM(RTRIM(value)))
          FROM STRING_SPLIT(@Copia, ';')
         WHERE LTRIM(RTRIM(value)) <> N'';

        INSERT INTO @Lista
        SELECT DISTINCT LOWER(LTRIM(RTRIM(x.Correo)))
          FROM (
                SELECT u.Correo FROM sigcm.Usuario AS u
                 WHERE u.Cuenta = @Cuenta AND u.Activo = 1
                UNION
                SELECT u.Correo
                  FROM sigcm.UsuarioRol AS ur
                  JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
                 WHERE ur.IdUnidad = @IdUnidadOrigen
                   AND ur.Activo = 1 AND u.Activo = 1
                   AND (ur.CodigoRol = 'AREA_JEFE' OR ur.EsPuntoFocal = 1)
                   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()))
          ) AS x
         WHERE NULLIF(LTRIM(RTRIM(x.Correo)), N'') IS NOT NULL
           AND x.Correo LIKE '%_@_%'
           AND NOT EXISTS (SELECT 1 FROM @Lista AS l WHERE l.Correo = LOWER(LTRIM(RTRIM(x.Correo))));

        DELETE l FROM @Lista AS l
         WHERE EXISTS (SELECT 1 FROM STRING_SPLIT(@Para, ';') AS d
                        WHERE LOWER(LTRIM(RTRIM(d.value))) = l.Correo);

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Copia = (SELECT STRING_AGG(Correo, ';') FROM @Lista)
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/* ========================================================================== */
/* 10. Evidencia de correos                                                  */
/* ========================================================================== */

/*
  Entrada: { ...entrada del endpoint..., "Origen": "requerimiento.notificarOrdenServicio",
             "Destinatario": "...", "Copia": "...", "Asunto": "...", "Cuerpo": "<html>",
             "Adjuntos": [ { "Nombre": "..." } ], "Enviado": true, "Resultado": "..." }
  No valida el actor: el correo ya salio (o fallo) y la evidencia tiene que
  quedar igual.
*/
CREATE OR ALTER PROCEDURE sigcm.paRegistrarCorreo
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52371, 'JSON incorrecto.', 1;

        DECLARE @Cuenta varchar(120) = JSON_VALUE(@parametro, '$.Actor.Usuario');
        DECLARE @CodigoRol varchar(40) = JSON_VALUE(@parametro, '$.Actor.Rol');
        DECLARE @IdUsuario uniqueidentifier;
        SELECT @IdUsuario = IdUsuario FROM sigcm.Usuario WHERE Cuenta = @Cuenta;

        INSERT INTO sigcm.CorreoEnviado
            (IdExpediente, Origen, Destinatario, Copia, Asunto, Cuerpo, Adjuntos,
             Enviado, Resultado, Referencia, IdUsuario, CodigoRol,
             UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES
            (sigcm.fnExpedienteReferencia(@parametro),
             LEFT(ISNULL(JSON_VALUE(@parametro, '$.Origen'), 'desconocido'), 80),
             ISNULL(JSON_VALUE(@parametro, '$.Destinatario'), N''),
             JSON_VALUE(@parametro, '$.Copia'),
             ISNULL(JSON_VALUE(@parametro, '$.Asunto'), N''),
             ISNULL((SELECT Cuerpo FROM OPENJSON(@parametro) WITH (Cuerpo nvarchar(max) '$.Cuerpo')), N''),
             JSON_QUERY(@parametro, '$.Adjuntos'),
             CASE WHEN JSON_VALUE(@parametro, '$.Enviado') IN ('true', '1') THEN 1 ELSE 0 END,
             LEFT(JSON_VALUE(@parametro, '$.Resultado'), 1000),
             JSON_MODIFY(JSON_MODIFY(@parametro, '$.Cuerpo', NULL), '$.Actor', NULL),
             @IdUsuario, @CodigoRol,
             LEFT(@Cuenta, 30), LEFT(JSON_VALUE(@parametro, '$.Actor.Equipo'), 50),
             LEFT(JSON_VALUE(@parametro, '$.Actor.Programa'), 50));

        SELECT (SELECT 1 AS estado, N'Correo registrado.' AS mensaje
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

/*
  Entrada: { "IdExpediente": "...", "IdCorreo": "..." (opcional) }
  Lista los correos del expediente y de su expediente padre (un pago muestra
  tambien la invitacion y la notificacion de la O/S del requerimiento). Con
  IdCorreo devuelve ese correo con su cuerpo, para reconstruirlo.
*/
CREATE OR ALTER PROCEDURE sigcm.paListarCorreo
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @resultado nvarchar(max);
    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 52381, 'JSON incorrecto.', 1;

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

        IF @CodigoRol = 'PROVEEDOR'
            THROW 52382, 'NO_AUTORIZADO: la evidencia de correos es de uso interno.', 1;

        DECLARE @IdExpediente uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdExpediente'));
        DECLARE @IdCorreo uniqueidentifier =
            TRY_CONVERT(uniqueidentifier, JSON_VALUE(@parametro, '$.IdCorreo'));

        IF @IdCorreo IS NOT NULL
        BEGIN
            SELECT @resultado = (
                SELECT 1 AS estado,
                       Correo = JSON_QUERY((
                           SELECT c.IdCorreo, c.Origen, c.Destinatario, c.Copia, c.Asunto,
                                  c.Cuerpo, c.Adjuntos, c.Enviado, c.Resultado, c.EnviadoEn,
                                  e.Codigo AS CodigoExpediente,
                                  Remitente = CONCAT_WS(' ', u.Nombres, u.Apellidos)
                             FROM sigcm.CorreoEnviado AS c
                             LEFT JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
                             LEFT JOIN sigcm.Usuario AS u ON u.IdUsuario = c.IdUsuario
                            WHERE c.IdCorreo = @IdCorreo
                              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER))
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            SELECT @resultado;
            RETURN;
        END

        IF @IdExpediente IS NULL
            THROW 52383, 'VALIDACION_PAYLOAD: falta IdExpediente.', 1;

        DECLARE @Padre uniqueidentifier;
        SELECT @Padre = IdExpedientePadre FROM sigcm.Expediente WHERE IdExpediente = @IdExpediente;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   Correos = JSON_QUERY(COALESCE((
                       SELECT c.IdCorreo, c.Origen, c.Destinatario, c.Copia, c.Asunto,
                              c.Enviado, c.Resultado, c.EnviadoEn,
                              e.Codigo AS CodigoExpediente,
                              Remitente = CONCAT_WS(' ', u.Nombres, u.Apellidos)
                         FROM sigcm.CorreoEnviado AS c
                         LEFT JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
                         LEFT JOIN sigcm.Usuario AS u ON u.IdUsuario = c.IdUsuario
                        WHERE c.IdExpediente IN (@IdExpediente, @Padre)
                        ORDER BY c.EnviadoEn DESC
                          FOR JSON PATH), N'[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END CATCH
END
GO

PRINT 'F023 aplicada: dias habiles, codigo de pago, asignacion, observacion via DEC, otros documentos, alertas y correos.';
GO
