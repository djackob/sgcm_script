/*
===============================================================================
  SIGCM - F019 : Configuracion de firmantes del Anexo 4 (CMN)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51900-51999

  ADMIN_SISTEMA lista y guarda 1 o 2 firmantes. Al guardar:
  - reemplaza cmn.ConfigFirmanteAnexo4
  - sincroniza sigcm.TipoDocumentoFirma del Anexo 4 (nuevos documentos)
  - ajusta transiciones CMN_GENERAR_A4 / firma paso 1 / firma final

  Los paquetes ya generados NO se tocan (snapshot en cmn.PaqueteFirmante).
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* ========================================================================== */
/* 1. cmn.paListarConfigFirmanteAnexo4                                       */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE cmn.paListarConfigFirmanteAnexo4
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51900, 'JSON incorrecto.', 1;

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

        IF @CodigoRol <> 'ADMIN_SISTEMA'
            THROW 51901, 'PERMISO_DENEGADO: solo ADMIN_SISTEMA administra los firmantes del Anexo 4.', 1;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   ISNULL((
                       SELECT c.CodigoRol, c.OrdenFirma, c.EtiquetaCargo, c.Activo,
                              r.Nombre AS NombreRol
                         FROM cmn.ConfigFirmanteAnexo4 AS c
                         JOIN sigcm.Rol AS r ON r.CodigoRol = c.CodigoRol
                        WHERE c.Activo = 1
                        ORDER BY c.OrdenFirma
                          FOR JSON PATH
                   ), N'[]') AS Firmantes,
                   ISNULL((
                       SELECT v.CodigoRol, v.Nombre
                         FROM (VALUES
                             ('ABAST_JEFE', N'Jefe de Abastecimiento'),
                             ('ABAST_COORDINADOR', N'Coordinador de Abastecimiento'),
                             ('ABAST_ESPECIALISTA', N'Especialista de Abastecimiento')
                         ) AS v(CodigoRol, Nombre)
                        ORDER BY v.CodigoRol
                          FOR JSON PATH
                   ), N'[]') AS RolesDisponibles,
                   N'OK' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo,
                   JSON_QUERY('[]') AS Firmantes
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

/* ========================================================================== */
/* 2. cmn.paGuardarConfigFirmanteAnexo4                                      */
/* ========================================================================== */

CREATE OR ALTER PROCEDURE cmn.paGuardarConfigFirmanteAnexo4
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);
    DECLARE @TranPropia bit = 0;

    BEGIN TRY
        IF ISJSON(@parametro) <> 1
            THROW 51910, 'JSON incorrecto.', 1;

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

        IF @CodigoRol <> 'ADMIN_SISTEMA'
            THROW 51911, 'PERMISO_DENEGADO: solo ADMIN_SISTEMA administra los firmantes del Anexo 4.', 1;

        DECLARE @Firmantes TABLE (
            CodigoRol varchar(40) NOT NULL,
            OrdenFirma smallint NOT NULL,
            EtiquetaCargo nvarchar(200) NULL
        );

        INSERT INTO @Firmantes (CodigoRol, OrdenFirma, EtiquetaCargo)
        SELECT UPPER(LTRIM(RTRIM(CodigoRol))),
               OrdenFirma,
               NULLIF(LTRIM(RTRIM(EtiquetaCargo)), N'')
          FROM OPENJSON(@parametro, '$.Firmantes')
          WITH (
              CodigoRol varchar(40) '$.CodigoRol',
              OrdenFirma smallint '$.OrdenFirma',
              EtiquetaCargo nvarchar(200) '$.EtiquetaCargo'
          );

        IF NOT EXISTS (SELECT 1 FROM @Firmantes)
            THROW 51912, 'VALIDACION_PAYLOAD: indique al menos un firmante.', 1;

        IF (SELECT COUNT(*) FROM @Firmantes) > 2
            THROW 51913, 'VALIDACION_PAYLOAD: el Anexo 4 admite como maximo 2 firmantes.', 1;

        IF EXISTS (
            SELECT 1 FROM @Firmantes
             WHERE CodigoRol NOT IN ('ABAST_JEFE', 'ABAST_COORDINADOR', 'ABAST_ESPECIALISTA')
        )
            THROW 51914, 'VALIDACION_PAYLOAD: solo se admiten roles de Abastecimiento (jefe, coordinador, especialista).', 1;

        IF EXISTS (
            SELECT OrdenFirma FROM @Firmantes GROUP BY OrdenFirma HAVING COUNT(*) > 1
        ) OR EXISTS (
            SELECT CodigoRol FROM @Firmantes GROUP BY CodigoRol HAVING COUNT(*) > 1
        )
            THROW 51915, 'VALIDACION_PAYLOAD: roles y ordenes de firma deben ser unicos.', 1;

        IF EXISTS (SELECT 1 FROM @Firmantes WHERE OrdenFirma NOT BETWEEN 1 AND 2)
            THROW 51916, 'VALIDACION_PAYLOAD: OrdenFirma debe ser 1 o 2.', 1;

        /* Etiquetas por defecto si el admin no las mando. */
        UPDATE f
           SET EtiquetaCargo = CASE f.CodigoRol
                 WHEN 'ABAST_JEFE' THEN N'Jefe de la Unidad de Abastecimiento'
                 WHEN 'ABAST_COORDINADOR' THEN N'Coordinador de la Unidad de Abastecimiento'
                 WHEN 'ABAST_ESPECIALISTA' THEN N'Especialista de la Unidad de Abastecimiento'
                 ELSE f.CodigoRol END
          FROM @Firmantes AS f
         WHERE f.EtiquetaCargo IS NULL;

        DECLARE @Ahora datetime2(3) = SYSUTCDATETIME();

        BEGIN TRANSACTION; SET @TranPropia = 1;

        DELETE FROM cmn.ConfigFirmanteAnexo4;

        INSERT INTO cmn.ConfigFirmanteAnexo4
            (CodigoRol, OrdenFirma, EtiquetaCargo, Activo,
             UsuarioCreacionAuditoria, FechaCreacionAuditoria,
             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        SELECT CodigoRol, OrdenFirma, EtiquetaCargo, 1,
               @Cuenta, @Ahora, @Equipo, @Programa
          FROM @Firmantes;

        /* Catalogo global: solo afecta documentos NUEVOS (etiquetas PDF). */
        DELETE FROM sigcm.TipoDocumentoFirma
         WHERE CodigoTipoDocumento = 'CMN_ANEXO_4_APROBACION_MODIFICACION';

        INSERT INTO sigcm.TipoDocumentoFirma (CodigoTipoDocumento, CodigoRol, OrdenFirma)
        SELECT 'CMN_ANEXO_4_APROBACION_MODIFICACION', CodigoRol, OrdenFirma
          FROM @Firmantes;

        /* Circuito A4 operativo (S044): sin firma digital en SGCM. */
        UPDATE sigcm.Transicion
           SET CodigoEstadoDestino = 'CMN_A4_FIRMA_JEFE',
               Activo = 1
         WHERE CodigoTransicion = 'CMN_GENERAR_A4';

        UPDATE sigcm.Transicion
           SET Activo = 0
         WHERE CodigoTransicion = 'CMN_ABAST_COORD_FIRMAR_A4';

        DELETE FROM sigcm.TransicionRol
         WHERE CodigoTransicion = 'CMN_ABAST_COORD_FIRMAR_A4';

        UPDATE sigcm.Transicion
           SET CodigoEstadoOrigen   = 'CMN_A4_FIRMA_JEFE',
               CodigoEstadoDestino  = 'CMN_A4_PEND_DOC_SIGA',
               NombreAccion         = N'Aprobar en SIGA y esperar documento firmado',
               RequiereFirma        = 0,
               DocumentoRequerido   = 'CMN_ANEXO_4_APROBACION_MODIFICACION',
               EncolaIntegracion    = 1,
               OperacionIntegracion = 'CONSOLIDAR_CMN',
               RolFirmaRequerida    = NULL,
               Activo               = 1
         WHERE CodigoTransicion = 'CMN_ABAST_JEFE_FIRMAR_A4';

        DELETE FROM sigcm.TransicionRol
         WHERE CodigoTransicion = 'CMN_ABAST_JEFE_FIRMAR_A4';

        INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
        VALUES ('CMN_ABAST_JEFE_FIRMAR_A4', 'ABAST_JEFE');

        COMMIT TRANSACTION; SET @TranPropia = 0;

        EXEC sigcm.paRegistrarAuditoria
             @CorrelacionId = @CorrelacionId, @CodigoModulo = 'CMN',
             @Entidad = 'cmn.ConfigFirmanteAnexo4', @IdEntidad = NULL,
             @Accion = 'GUARDAR_FIRMANTES_A4', @Resultado = 'OK',
             @IdActor = @IdUsuario, @ActorCuenta = @Cuenta, @ActorRol = @CodigoRol,
             @IdActorUnidad = @IdUnidad, @OrigenIp = @Ip, @Equipo = @Equipo,
             @Programa = @Programa, @DatosDespues = NULL, @Metadata = NULL;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   ISNULL((
                       SELECT c.CodigoRol, c.OrdenFirma, c.EtiquetaCargo, c.Activo
                         FROM cmn.ConfigFirmanteAnexo4 AS c
                        WHERE c.Activo = 1
                        ORDER BY c.OrdenFirma
                          FOR JSON PATH
                   ), N'[]') AS Firmantes,
                   N'Se guardo la configuracion de firmantes del Anexo 4.' AS mensaje
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @TranPropia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

PRINT 'F019 aplicada: config firmantes Anexo 4.';
GO
