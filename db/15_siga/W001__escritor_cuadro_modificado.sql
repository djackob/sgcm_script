/*
===============================================================================
  SIGCM - W001 : Escritor del cuadro modificado de SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  ---------------------------------------------------------------------------
  QUE HACE
  ---------------------------------------------------------------------------
  Drena integracion.Operacion: toma las operaciones pendientes que dejaron las
  transiciones de F004 y las lleva a SIGA.

  ES EL UNICO LUGAR DEL SISTEMA DONDE EL JSON DEJA DE EXISTIR. Del lado del
  SIGCM todo viaja como JSON porque DBSIGCM esta en compatibilidad 160 y tiene
  OPENJSON. SIGA_1750 esta en compatibilidad 100: ahi no hay OPENJSON, no hay
  JSON_VALUE, no hay nada de JSON. Y no hace falta que lo haya, porque a SIGA no
  se le manda JSON: se le manda lo que entiende desde 2005, que son parametros
  tipados y XML.

  La traduccion concreta:

      JSON del SIGCM                        parametros de SIGA
      ------------------------------        --------------------------------
      "AnoEje": 2026                   ->   @AnoEje numeric(4,0)
      "CentroCosto": "01.01"           ->   @CentroCosto varchar(15)
      "PrecioUnitario": 12.500000      ->   @PrecioUnit numeric(16,6)
      "Periodos": [ {AnoOffset, Mes,   ->   @Periodos xml
                     Cantidad}, ... ]       <Periodos>
        48 filas, una por mes             <Periodo codigo="0" c01=".." c12=".."/>
        de los 4 anios                    ... una fila por anio, 4 en total
                                          </Periodos>

  El pivote de los 48 periodos a 4 filas de 12 columnas es el corazon de este
  script: es literalmente donde el modelo del SIGCM se convierte en el modelo
  del producto SIGA.

  ---------------------------------------------------------------------------
  MODO SIMULACION (ADR-003)
  ---------------------------------------------------------------------------
  Por defecto NO escribe en SIGA. Hace toda la traduccion, arma el XML, valida
  lo que puede validar, y deja en ResponseJson exactamente lo que habria
  mandado. Sirve para revisar la conversion sin tocar la base de otro dueno.

  Para escribir de verdad hay que pedirlo explicitamente con "Modo":"real", y
  ademas tiene que existir el procedimiento del lado de SIGA. Si no existe, la
  operacion queda en ERROR con un mensaje que lo dice, no falla en silencio.

  En ModoEjecucion se graba lo que EFECTIVAMENTE se hizo, no lo que se pidio.

  ---------------------------------------------------------------------------
  CONTRATO
  ---------------------------------------------------------------------------
  Entrada:
  {
    "Actor": { "Usuario":"...", "Equipo":"...", "Programa":"..." },
    "Modo": "simulacion" | "real",     por defecto "simulacion"
    "Limite": 50,                      cuantas operaciones drena como maximo
    "IdOperacion": "..."               opcional: drena solo esa
  }

  Salida: el resumen del drenaje, con el detalle por operacion.

  Bloque de error: 51300-51399 (integracion con SIGA).
===============================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Sinonimo hacia el procedimiento de SIGA                                 */
/* -------------------------------------------------------------------------- */

/*
  El nombre de la base SIGA no se escribe aqui: se descubre de los sinonimos que
  ya creo C003. Asi este script funciona igual en local, en desarrollo y en
  produccion, donde la base puede llamarse distinto.

  El procedimiento usp_ext_registrar_item_cmn es de SIGA y esta entregado para
  homologacion. Mientras el ANIN no lo instale, el sinonimo no se puede crear y
  el modo real no esta disponible; el modo simulacion si.
*/

DECLARE @bdSiga sysname;

SELECT TOP 1 @bdSiga = PARSENAME(base_object_name, 3)
  FROM sys.synonyms
 WHERE SCHEMA_NAME(schema_id) = N'siga';

IF @bdSiga IS NULL
BEGIN
    PRINT '  [AVISO] No hay sinonimos en el esquema siga. Ejecuta C003 antes que W001.';
END
ELSE
BEGIN
    DECLARE @existeProc bit = 0;
    DECLARE @sql nvarchar(max) =
        N'SELECT @r = COUNT(*) FROM ' + QUOTENAME(@bdSiga) + N'.sys.procedures
           WHERE name = ''usp_ext_registrar_item_cmn'';';
    EXEC sys.sp_executesql @sql, N'@r bit OUTPUT', @r = @existeProc OUTPUT;

    IF EXISTS (SELECT 1 FROM sys.synonyms
                WHERE name = N'usp_ext_registrar_item_cmn'
                  AND SCHEMA_NAME(schema_id) = N'siga')
        DROP SYNONYM siga.usp_ext_registrar_item_cmn;

    IF @existeProc = 1
    BEGIN
        SET @sql = N'CREATE SYNONYM siga.usp_ext_registrar_item_cmn FOR '
                 + QUOTENAME(@bdSiga) + N'.dbo.usp_ext_registrar_item_cmn;';
        EXEC sys.sp_executesql @sql;
        PRINT '  Sinonimo creado hacia ' + @bdSiga + '.dbo.usp_ext_registrar_item_cmn';
    END
    ELSE
        PRINT '  [AVISO] ' + @bdSiga + ' no tiene usp_ext_registrar_item_cmn. '
            + 'Solo queda disponible el modo simulacion, que es lo esperado '
            + 'mientras el procedimiento no este homologado.';
END
GO

/* -------------------------------------------------------------------------- */
/* 2. integracion.paEscribirCuadroModificado                                  */
/* -------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE integracion.paEscribirCuadroModificado
    @parametro nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    /* Se escribe en la base de otro dueno: si SIGA esta ocupado preferimos
       fallar rapido y reintentar, no quedarnos colgados sobre sus tablas. */
    SET LOCK_TIMEOUT 10000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF @parametro IS NULL SET @parametro = N'{}';
        IF ISJSON(@parametro) <> 1
            THROW 51300, 'JSON incorrecto.', 1;

        DECLARE @Modo        varchar(15),
                @Limite      int,
                @IdOperacion uniqueidentifier,
                @Cuenta      varchar(120),
                @Equipo      varchar(50),
                @Programa    varchar(50);

        SELECT @Modo        = LOWER(LTRIM(RTRIM(ISNULL(Modo, 'simulacion')))),
               @Limite      = ISNULL(Limite, 50),
               @IdOperacion = TRY_CONVERT(uniqueidentifier, IdOperacion)
          FROM OPENJSON(@parametro)
          WITH (Modo varchar(15), Limite int, IdOperacion varchar(50));

        SELECT @Cuenta   = ISNULL(Usuario, 'w001'),
               @Equipo   = Equipo,
               @Programa = ISNULL(Programa, 'W001')
          FROM OPENJSON(@parametro, '$.Actor')
          WITH (Usuario varchar(120), Equipo varchar(50), Programa varchar(50));

        SET @Cuenta = ISNULL(@Cuenta, 'w001');
        SET @Programa = ISNULL(@Programa, 'W001');

        IF @Modo NOT IN ('simulacion', 'real')
            THROW 51301, 'VALIDACION_PAYLOAD: Modo debe ser "simulacion" o "real".', 1;

        /* El modo real exige que exista el procedimiento del lado de SIGA. */
        DECLARE @haySinonimo bit =
            CASE WHEN EXISTS (SELECT 1 FROM sys.synonyms
                               WHERE name = N'usp_ext_registrar_item_cmn'
                                 AND SCHEMA_NAME(schema_id) = N'siga')
                 THEN 1 ELSE 0 END;

        /* THROW no admite expresiones en el mensaje: solo literal o variable. */
        DECLARE @msgSinSinonimo nvarchar(400) =
            N'INTEGRACION_NO_DISPONIBLE: no existe siga.usp_ext_registrar_item_cmn. '
          + N'El procedimiento debe estar instalado y homologado en SIGA. '
          + N'Reejecuta W001 despues de instalarlo, o usa el modo simulacion.';

        IF @Modo = 'real' AND @haySinonimo = 0
            THROW 51302, @msgSinSinonimo, 1;

        DECLARE @Ahora datetime = GETDATE();

        /* ---- Lote a drenar --------------------------------------------- */
        DECLARE @lote TABLE (
            IdOperacion     uniqueidentifier NOT NULL PRIMARY KEY,
            Secuencia       int              NOT NULL,
            Operacion       varchar(30)      NOT NULL,
            IdSolicitud     uniqueidentifier NOT NULL,
            IdSolicitudItem uniqueidentifier     NULL,
            IdempotenciaKey varchar(200)     NOT NULL,
            RequestJson     nvarchar(max)    NOT NULL
        );

        INSERT INTO @lote (IdOperacion, Secuencia, Operacion, IdSolicitud,
                           IdSolicitudItem, IdempotenciaKey, RequestJson)
        SELECT TOP (@Limite)
               o.IdOperacion, o.Secuencia, o.Operacion, o.IdSolicitud,
               o.IdSolicitudItem, o.IdempotenciaKey, o.RequestJson
          FROM integracion.Operacion AS o
         WHERE o.Activo = 1
           AND o.Estado IN ('PENDIENTE', 'REINTENTO')
           AND o.ProximoIntentoEn <= @Ahora
           AND o.Intentos < o.MaxIntentos
           AND (@IdOperacion IS NULL OR o.IdOperacion = @IdOperacion)
         ORDER BY o.Secuencia, o.FechaCreacionAuditoria;

        DECLARE @detalle TABLE (
            IdOperacion uniqueidentifier NOT NULL,
            Secuencia   int              NOT NULL,
            Operacion   varchar(30)      NOT NULL,
            Resultado   varchar(20)      NOT NULL,
            SecCuadro   bigint               NULL,
            SecItem     bigint               NULL,
            Mensaje     nvarchar(400)        NULL
        );

        /* ---- Drenaje, una operacion por vez ---------------------------- */
        DECLARE @id        uniqueidentifier,
                @sec       int,
                @op        varchar(30),
                @idSol     uniqueidentifier,
                @idItem    uniqueidentifier,
                @clave     varchar(200),
                @req       nvarchar(max);

        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT IdOperacion, Secuencia, Operacion, IdSolicitud,
                   IdSolicitudItem, IdempotenciaKey, RequestJson
              FROM @lote ORDER BY Secuencia;

        OPEN cur;
        FETCH NEXT FROM cur INTO @id, @sec, @op, @idSol, @idItem, @clave, @req;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                UPDATE integracion.Operacion
                   SET Estado = 'EN_PROCESO',
                       BloqueadoEn = GETDATE(),
                       BloqueadoPor = @Cuenta,
                       BloqueoToken = NEWID()
                 WHERE IdOperacion = @id;

                /* ---- Cabecera del item ------------------------------- */
                DECLARE @AnoEje numeric(4,0), @SecEjec numeric(6,0),
                        @CentroCosto varchar(15), @TipoMovimiento varchar(20),
                        @TipoTarea varchar(1), @NivelTarea varchar(1),
                        @CodigoTarea numeric(10,0), @SecFunc numeric(4,0),
                        @SecFuncProp numeric(4,0), @Origen varchar(1),
                        @FuenteFinanc varchar(2), @Clasificador varchar(20),
                        @TipoRecurso varchar(2), @TipoPpto numeric(1,0),
                        @TipoUso varchar(1), @TipoBien varchar(1),
                        @GrupoBien varchar(2), @ClaseBien varchar(2),
                        @FamiliaBien varchar(4), @ItemBien varchar(4),
                        @UnidadMedida numeric(3,0), @PrecioUnit numeric(16,6);

                SELECT @AnoEje         = j.AnoEje,
                       @SecEjec        = j.SecEjec,
                       @CentroCosto    = j.CentroCosto,
                       @TipoMovimiento = j.TipoMovimiento,
                       @TipoTarea      = j.TipoTarea,
                       @NivelTarea     = j.NivelTarea,
                       @CodigoTarea    = j.CodigoTarea,
                       @SecFunc        = j.SecFunc,
                       @SecFuncProp    = j.SecFuncProp,
                       @Origen         = j.Origen,
                       @FuenteFinanc   = j.FuenteFinanc,
                       @Clasificador   = j.Clasificador,
                       @TipoRecurso    = j.TipoRecurso,
                       @TipoPpto       = j.TipoPpto,
                       @TipoUso        = j.TipoUso,
                       @TipoBien       = j.TipoBien,
                       @GrupoBien      = j.GrupoBien,
                       @ClaseBien      = j.ClaseBien,
                       @FamiliaBien    = j.FamiliaBien,
                       @ItemBien       = j.ItemBien,
                       @UnidadMedida   = j.UnidadMedida,
                       @PrecioUnit     = j.PrecioUnitario
                  FROM OPENJSON(@req)
                  WITH (AnoEje numeric(4,0),         SecEjec numeric(6,0),
                        CentroCosto varchar(15),     TipoMovimiento varchar(20),
                        TipoTarea varchar(1),        NivelTarea varchar(1),
                        CodigoTarea numeric(10,0),   SecFunc numeric(4,0),
                        SecFuncProp numeric(4,0),    Origen varchar(1),
                        FuenteFinanc varchar(2),     Clasificador varchar(20),
                        TipoRecurso varchar(2),      TipoPpto numeric(1,0),
                        TipoUso varchar(1),          TipoBien varchar(1),
                        GrupoBien varchar(2),        ClaseBien varchar(2),
                        FamiliaBien varchar(4),      ItemBien varchar(4),
                        UnidadMedida numeric(3,0),   PrecioUnitario numeric(16,6)) AS j;

                /* ---- EL PIVOTE: 48 periodos JSON -> 4 filas XML ------- */
                /*
                   SIGA quiere una fila por anio (codigo 0 a 3) con doce
                   atributos c01..c12. Nosotros tenemos 48 objetos planos con
                   AnoOffset y Mes. El anio va contra la lista fija de cuatro,
                   para que la fila exista aunque el JSON no la traiga.
                */
                DECLARE @Periodos xml =
                    (SELECT a.codigo,
                            c01 = ISNULL(SUM(CASE WHEN p.Mes =  1 THEN p.Cantidad END), 0),
                            c02 = ISNULL(SUM(CASE WHEN p.Mes =  2 THEN p.Cantidad END), 0),
                            c03 = ISNULL(SUM(CASE WHEN p.Mes =  3 THEN p.Cantidad END), 0),
                            c04 = ISNULL(SUM(CASE WHEN p.Mes =  4 THEN p.Cantidad END), 0),
                            c05 = ISNULL(SUM(CASE WHEN p.Mes =  5 THEN p.Cantidad END), 0),
                            c06 = ISNULL(SUM(CASE WHEN p.Mes =  6 THEN p.Cantidad END), 0),
                            c07 = ISNULL(SUM(CASE WHEN p.Mes =  7 THEN p.Cantidad END), 0),
                            c08 = ISNULL(SUM(CASE WHEN p.Mes =  8 THEN p.Cantidad END), 0),
                            c09 = ISNULL(SUM(CASE WHEN p.Mes =  9 THEN p.Cantidad END), 0),
                            c10 = ISNULL(SUM(CASE WHEN p.Mes = 10 THEN p.Cantidad END), 0),
                            c11 = ISNULL(SUM(CASE WHEN p.Mes = 11 THEN p.Cantidad END), 0),
                            c12 = ISNULL(SUM(CASE WHEN p.Mes = 12 THEN p.Cantidad END), 0)
                       FROM (VALUES (0), (1), (2), (3)) AS a(codigo)
                       LEFT JOIN OPENJSON(@req, '$.Periodos')
                            WITH (AnoOffset tinyint, Mes tinyint,
                                  Cantidad numeric(14,2)) AS p
                         ON p.AnoOffset = a.codigo
                      GROUP BY a.codigo
                      ORDER BY a.codigo
                        FOR XML RAW('Periodo'), ROOT('Periodos'));

                DECLARE @SecCuadro numeric(10,0) = NULL;
                DECLARE @ItemSec   numeric(6,0)  = NULL;
                DECLARE @modoReal  varchar(15)   = @Modo;

                DECLARE @msgSinExpansion nvarchar(400) =
                    N'OPERACION_SIN_EXPANSION: W001 solo implementa INCLUIR_ITEM. '
                  + N'EXCLUIR_ITEM, MODIFICAR_CANTIDADES y CONSOLIDAR_CMN estan pendientes.';

                IF @op <> 'INCLUIR_ITEM'
                    THROW 51303, @msgSinExpansion, 1;

                IF @Modo = 'real'
                BEGIN
                    EXEC siga.usp_ext_registrar_item_cmn
                         @AnoEje      = @AnoEje,
                         @SecEjec     = @SecEjec,
                         @CentroCosto = @CentroCosto,
                         @FaseCuadro  = 5,
                         @Secuencia   = @SecCuadro OUTPUT,
                         @TipoTarea   = @TipoTarea,
                         @NivelTarea  = @NivelTarea,
                         @CodigoTarea = @CodigoTarea,
                         @SecFunc     = @SecFunc,
                         @SecFuncProp = @SecFuncProp,
                         @Origen      = @Origen,
                         @FuenteFinanc= @FuenteFinanc,
                         @Clasificador= @Clasificador,
                         @TipoRecurso = @TipoRecurso,
                         @TipoPpto    = @TipoPpto,
                         @TipoUso     = @TipoUso,
                         @TipoBien    = @TipoBien,
                         @GrupoBien   = @GrupoBien,
                         @ClaseBien   = @ClaseBien,
                         @FamiliaBien = @FamiliaBien,
                         @ItemBien    = @ItemBien,
                         @UnidadMedida= @UnidadMedida,
                         @PrecioUnit  = @PrecioUnit,
                         @Periodos    = @Periodos,
                         @Usuario     = @Cuenta,
                         @Equipo      = @Equipo,
                         @ItemSec     = @ItemSec OUTPUT;

                    /* Correspondencia de identificadores: sin esto no se puede
                       conciliar despues lo que quedo en SIGA con lo nuestro. */
                    IF @ItemSec IS NOT NULL AND @idItem IS NOT NULL
                       AND NOT EXISTS (SELECT 1 FROM integracion.MapeoCmn
                                        WHERE IdSolicitudItem = @idItem)
                    BEGIN
                        /* MapeoCmn no lleva FechaCreacionAuditoria: la fecha del
                           asiento es RegistradoEnSiga, que es la que importa. */
                        INSERT INTO integracion.MapeoCmn
                            (IdSolicitudItem, IdSolicitud, AnoEje, SecEjec, CentroCosto,
                             SecCuadro, SecItem, EstadoSiga, IdempotenciaKey,
                             RegistradoEnSiga, PayloadRespuesta,
                             UsuarioCreacionAuditoria,
                             EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
                        VALUES
                            (@idItem, @idSol, @AnoEje, @SecEjec, @CentroCosto,
                             @SecCuadro, @ItemSec, '5', @clave,
                             GETDATE(),
                             (SELECT SecCuadro = @SecCuadro, SecItem = @ItemSec,
                                     Fase = 5, Estado = '5'
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                             @Cuenta, @Equipo, @Programa);
                    END
                END

                /* ---- Cierre de la operacion --------------------------- */
                UPDATE integracion.Operacion
                   SET Estado        = 'COMPLETADO',
                       ModoEjecucion = @modoReal,
                       CompletadoEn  = GETDATE(),
                       Intentos      = Intentos + 1,
                       BloqueoToken  = NULL,
                       BloqueadoEn   = NULL,
                       BloqueadoPor  = NULL,
                       ResponseJson  =
                           (SELECT Modo       = @modoReal,
                                   SecCuadro  = @SecCuadro,
                                   SecItem    = @ItemSec,
                                   EnviadoASiga = CASE WHEN @modoReal = 'real'
                                                       THEN CONVERT(bit, 1) ELSE CONVERT(bit, 0) END,
                                   Periodos   = CONVERT(nvarchar(max), @Periodos)
                              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       UsuarioModificacionAuditoria  = @Cuenta,
                       FechaModificacionAuditoria    = GETDATE(),
                       EquipoModificacionAuditoria   = @Equipo,
                       ProgramaModificacionAuditoria = @Programa
                 WHERE IdOperacion = @id;

                INSERT INTO @detalle (IdOperacion, Secuencia, Operacion, Resultado,
                                      SecCuadro, SecItem, Mensaje)
                VALUES (@id, @sec, @op,
                        CASE WHEN @modoReal = 'real' THEN 'ESCRITO' ELSE 'SIMULADO' END,
                        @SecCuadro, @ItemSec, NULL);
            END TRY
            BEGIN CATCH
                DECLARE @err nvarchar(400) = LEFT(ERROR_MESSAGE(), 400);
                DECLARE @nro int = ERROR_NUMBER();

                /* El reintento se separa en el tiempo: si SIGA esta caido o
                   bloqueado, insistir de inmediato solo empeora las cosas. */
                UPDATE integracion.Operacion
                   SET Estado = CASE WHEN Intentos + 1 >= MaxIntentos
                                     THEN 'ERROR' ELSE 'REINTENTO' END,
                       Intentos         = Intentos + 1,
                       ProximoIntentoEn = DATEADD(minute, 5 * (Intentos + 1), GETDATE()),
                       ErrorCodigo      = CONVERT(varchar(80), @nro),
                       ErrorMensaje     = @err,
                       BloqueoToken     = NULL,
                       BloqueadoEn      = NULL,
                       BloqueadoPor     = NULL,
                       UsuarioModificacionAuditoria  = @Cuenta,
                       FechaModificacionAuditoria    = GETDATE(),
                       EquipoModificacionAuditoria   = @Equipo,
                       ProgramaModificacionAuditoria = @Programa
                 WHERE IdOperacion = @id;

                INSERT INTO @detalle (IdOperacion, Secuencia, Operacion, Resultado,
                                      SecCuadro, SecItem, Mensaje)
                VALUES (@id, @sec, @op, 'ERROR', NULL, NULL, @err);
            END CATCH

            FETCH NEXT FROM cur INTO @id, @sec, @op, @idSol, @idItem, @clave, @req;
        END

        CLOSE cur;
        DEALLOCATE cur;

        /* ---- Respuesta ------------------------------------------------- */
        SET @resultado =
            (SELECT estado      = 1,
                    Modo        = @Modo,
                    Tomadas     = (SELECT COUNT(*) FROM @lote),
                    Escritas    = (SELECT COUNT(*) FROM @detalle WHERE Resultado = 'ESCRITO'),
                    Simuladas   = (SELECT COUNT(*) FROM @detalle WHERE Resultado = 'SIMULADO'),
                    ConError    = (SELECT COUNT(*) FROM @detalle WHERE Resultado = 'ERROR'),
                    Detalle     = (SELECT IdOperacion, Secuencia, Operacion,
                                          Resultado, SecCuadro, SecItem, Mensaje
                                     FROM @detalle ORDER BY Secuencia
                                      FOR JSON PATH),
                    mensaje     = 'Drenaje terminado.'
               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado AS respuesta;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'cur') >= 0
        BEGIN
            CLOSE cur;
            DEALLOCATE cur;
        END

        SET @resultado =
            (SELECT estado  = 0,
                    codigo  = ERROR_NUMBER(),
                    mensaje = ERROR_MESSAGE()
               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado AS respuesta;
    END CATCH
END
GO

PRINT 'W001 instalado: integracion.paEscribirCuadroModificado';
GO
