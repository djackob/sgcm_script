/*
===============================================================================
  SIGCM - S903 : Anexo 4 que agrupa Anexos 3 de varias areas usuarias
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO escribe en SIGA.

  ---------------------------------------------------------------------------
  QUE DEMUESTRA
  ---------------------------------------------------------------------------
  El circuito completo del flujo aprobado por Abastecimiento, con DOS areas
  usuarias distintas y un solo Anexo 4:

    1. Cada area registra y firma su Anexo 3.
    2. OA lo deriva al JEFE de Abastecimiento, y de ahi baja al coordinador y al
       especialista.
    3. El especialista conforma y firma, el coordinador firma, el jefe firma. La
       firma del jefe encola el primer registro en SIGA.
    4. El especialista marca LOS DOS Anexos 3 y genera UN Anexo 4.
    5. Coordinador y jefe firman ese unico documento; la firma del jefe encola
       UNA APROBACION POR AREA USUARIA.
    6. Cada expediente vuelve a SU propia area usuaria.

  Y comprueba las reglas que el flujo introduce:

    - la version del documento queda PARCIAL mientras falten firmas y solo pasa
      a FIRMADO con la ultima;
    - un Anexo 3 no puede integrar dos Anexos 4;
    - un Anexo 4 ordinario solo se genera los viernes;
    - la firma del Anexo 4 mueve los N expedientes en una sola transaccion.

  ---------------------------------------------------------------------------
  NO DEJA RASTRO
  ---------------------------------------------------------------------------
  Todo lo que crea lo borra al terminar, y tambien al empezar: es repetible.

  La limpieza es explicita y no un ROLLBACK envolvente, aunque seria mas corto.
  Con XACT_ABORT ON —que llevan todas las rutinas— un error deja la transaccion
  en estado no confirmable, y esta prueba PROVOCA errores a proposito: comprueba
  que un Anexo 4 ordinario se rechaza fuera de viernes y que un Anexo 3 no entra
  en dos Anexos 4. Dentro de una transaccion envolvente, el primer rechazo
  esperado mataria la prueba en vez de aprobarla.

  No toca SIGA: comprueba que las operaciones QUEDAN ENCOLADAS, que es lo propio
  del SIGCM; drenar la cola es lo que prueba S901.

  Requisitos: instalar.ps1 -ConDatosPrueba (S001, S900, V011, F003, F004, F007).
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ========================================================================== */
/* Limpieza de lo que crea esta prueba                                        */
/* ========================================================================== */

/*
  Se reconoce por ProgramaCreacionAuditoria = 'S903', que es el campo Programa
  del bloque Actor con el que la prueba llama a todas las rutinas. No borra nada
  que no haya creado ella.

  El orden es el de las dependencias, de la hoja a la raiz. Donde hay ON DELETE
  CASCADE se aprovecha: borrar el expediente arrastra la solicitud, sus items y
  sus 48 periodos; borrar el documento arrastra sus versiones y sus firmas.
*/
DROP PROCEDURE IF EXISTS #LimpiarS903;
GO
CREATE PROCEDURE #LimpiarS903
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY);
    INSERT INTO @Exp
    SELECT IdExpediente FROM sigcm.Expediente WHERE ProgramaCreacionAuditoria = 'S903';

    IF NOT EXISTS (SELECT 1 FROM @Exp) RETURN;

    DECLARE @Doc TABLE (IdDocumento uniqueidentifier PRIMARY KEY);
    INSERT INTO @Doc
    SELECT DISTINCT de.IdDocumento
      FROM sigcm.DocumentoExpediente AS de
      JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;

    DECLARE @Paq TABLE (IdPaquete uniqueidentifier PRIMARY KEY);
    INSERT INTO @Paq
    SELECT DISTINCT ps.IdPaquete
      FROM cmn.PaqueteSolicitud AS ps
      JOIN cmn.Solicitud AS s ON s.IdSolicitud = ps.IdSolicitud
      JOIN @Exp AS x ON x.IdExpediente = s.IdExpediente;

    DELETE o FROM integracion.Operacion AS o JOIN @Exp AS x ON x.IdExpediente = o.IdExpediente;
    DELETE m FROM integracion.MapeoCmn  AS m
      JOIN cmn.Solicitud AS s ON s.IdSolicitud = m.IdSolicitud
      JOIN @Exp AS x ON x.IdExpediente = s.IdExpediente;

    DELETE ps FROM cmn.PaqueteSolicitud AS ps JOIN @Paq AS q ON q.IdPaquete = ps.IdPaquete;
    DELETE p  FROM cmn.Paquete          AS p  JOIN @Paq AS q ON q.IdPaquete = p.IdPaquete;

    DELETE de FROM sigcm.DocumentoExpediente AS de JOIN @Doc AS d ON d.IdDocumento = de.IdDocumento;
    DELETE dc FROM sigcm.Documento           AS dc JOIN @Doc AS d ON d.IdDocumento = dc.IdDocumento;

    DELETE ob FROM sigcm.Observacion AS ob JOIN @Exp AS x ON x.IdExpediente = ob.IdExpediente;
    DELETE h  FROM sigcm.Historial   AS h  JOIN @Exp AS x ON x.IdExpediente = h.IdExpediente;

    DELETE e FROM sigcm.Expediente AS e JOIN @Exp AS x ON x.IdExpediente = e.IdExpediente;

    /* La auditoria de la prueba tambien se retira: es ruido, no trazabilidad. */
    DELETE FROM sigcm.EventoAuditoria WHERE Programa = 'S903';
END
GO

DECLARE @r TABLE (j nvarchar(max));
DECLARE @j nvarchar(max), @p nvarchar(max);
DECLARE @fallas int = 0;

/* Las dos areas usuarias sembradas por S900. Son dos y no una porque un Anexo 4
   con una sola area no demuestra nada de lo que este cambio agrega. */
DECLARE @Area TABLE (
    n            int IDENTITY(1,1),
    Unidad       varchar(30),
    CentroCosto  varchar(15),
    CuentaEsp    varchar(120),
    CuentaJefe   varchar(120),
    IdExpediente varchar(50) NULL,
    IdSolicitud  varchar(50) NULL,
    Codigo       varchar(40) NULL,
    Version      int NULL
);
INSERT INTO @Area (Unidad, CentroCosto, CuentaEsp, CuentaJefe) VALUES
    ('UO-PRUEBA', '01.01',       'prueba.especialista', 'prueba.jefe'),
    ('UO-OTI',    '01.07.05.03', 'prueba.oti.esp',      'prueba.oti.jefe');

DECLARE @AnoEje int = 2026, @SecEjec int = 1750;

DECLARE @ActorOA   nvarchar(400) = N'"Actor":{"Usuario":"prueba.oa","Rol":"OA","Unidad":"UO-OA","Equipo":"S903","Programa":"S903"}';
DECLARE @ActorAbEs nvarchar(400) = N'"Actor":{"Usuario":"prueba.abast.esp","Rol":"ABAST_ESPECIALISTA","Unidad":"UO-ABAST","Equipo":"S903","Programa":"S903"}';
DECLARE @ActorAbCo nvarchar(400) = N'"Actor":{"Usuario":"prueba.abastecim","Rol":"ABAST_COORDINADOR","Unidad":"UO-ABAST","Equipo":"S903","Programa":"S903"}';
DECLARE @ActorAbJe nvarchar(400) = N'"Actor":{"Usuario":"prueba.abast.jefe","Rol":"ABAST_JEFE","Unidad":"UO-ABAST","Equipo":"S903","Programa":"S903"}';

DECLARE @n int, @tot int;
DECLARE @Unidad varchar(30), @CentroCosto varchar(15),
        @CuentaEsp varchar(120), @CuentaJefe varchar(120),
        @IdExpediente varchar(50), @IdSolicitud varchar(50),
        @Codigo varchar(40), @Version int;
DECLARE @ActorEsp nvarchar(400), @ActorJefe nvarchar(400);

PRINT '===========================================================';
PRINT ' S903 - Anexo 4 multiple';
PRINT '===========================================================';

/* -------------------------------------------------------------------------- */
/* 0. Limpieza previa                                                          */
/* -------------------------------------------------------------------------- */
/* Barre lo que haya quedado de una corrida anterior interrumpida, para que la
   prueba no falle por restos suyos ni acumule expedientes de prueba. */
EXEC #LimpiarS903;

/* -------------------------------------------------------------------------- */
/* 1. Cada area registra su Anexo 3                                            */
/* -------------------------------------------------------------------------- */
/*
  Las coordenadas presupuestales se toman de un item que el area YA tiene en su
  cuadro. Inventarlas haria fallar la prueba por un maestro y no por el flujo,
  que es lo que se quiere comprobar.
*/

SET @n = 1; SET @tot = (SELECT COUNT(*) FROM @Area);
WHILE @n <= @tot
BEGIN
    SELECT @Unidad = Unidad, @CentroCosto = CentroCosto,
           @CuentaEsp = CuentaEsp, @CuentaJefe = CuentaJefe
      FROM @Area WHERE n = @n;

    DECLARE @TipoTarea varchar(1), @NivelTarea varchar(1), @CodigoTarea int,
            @SecFunc int, @Clasificador varchar(20),
            @GrupoBien varchar(2), @ClaseBien varchar(2),
            @FamiliaBien varchar(4), @ItemBien varchar(4);

    SELECT TOP 1
           @TipoTarea = d.TIPO_TAREA, @NivelTarea = d.NIVEL_TAREA, @CodigoTarea = d.CODIGO_TAREA,
           @SecFunc = d.SEC_FUNC, @Clasificador = d.CLASIFICADOR,
           @GrupoBien = d.GRUPO_BIEN, @ClaseBien = d.CLASE_BIEN,
           @FamiliaBien = d.FAMILIA_BIEN, @ItemBien = d.ITEM_BIEN
      FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
     WHERE d.ANNO_EJEC = @AnoEje AND d.SEC_EJEC = @SecEjec
       AND d.CENTRO_COSTO = @CentroCosto AND d.ANNO_PROG = @AnoEje
       AND d.TIPO_BIEN = 'S'
     ORDER BY d.SEC_ITEM;

    IF @TipoTarea IS NULL
    BEGIN
        PRINT '  [SALTEADA] El centro ' + @CentroCosto + ' (' + @Unidad
            + ') no tiene items de servicio de referencia en SIGA.';
        EXEC #LimpiarS903;
        RETURN;
    END

    SET @ActorEsp  = N'"Actor":{"Usuario":"' + @CuentaEsp  + N'","Rol":"AREA_ESPECIALISTA","Unidad":"' + @Unidad + N'","Equipo":"S903","Programa":"S903"}';
    SET @ActorJefe = N'"Actor":{"Usuario":"' + @CuentaJefe + N'","Rol":"AREA_JEFE","Unidad":"' + @Unidad + N'","Equipo":"S903","Programa":"S903"}';

    SET @p = N'{' + @ActorEsp + N',
      "Solicitud": { "AnoEje": ' + CONVERT(varchar(4), @AnoEje) + N', "SecEjec": ' + CONVERT(varchar(10), @SecEjec) + N',
                     "CentroCosto": "' + @CentroCosto + N'", "TipoOperacion": "MODIFICACION",
                     "Sustento": "Prueba S903: inclusion del area ' + @Unidad + N' para el Anexo 4 multiple." },
      "Items": [ { "TipoMovimiento": "INCLUSION",
                   "TipoTarea": "' + @TipoTarea + N'", "NivelTarea": "' + @NivelTarea + N'",
                   "CodigoTarea": ' + CONVERT(varchar(10), @CodigoTarea) + N', "SecFunc": ' + CONVERT(varchar(10), @SecFunc) + N',
                   "Origen": "1", "FuenteFinanc": "00", "Clasificador": "' + @Clasificador + N'",
                   "TipoRecurso": "1", "TipoPpto": 1, "TipoUso": "C",
                   "TipoBien": "S", "GrupoBien": "' + @GrupoBien + N'", "ClaseBien": "' + @ClaseBien + N'",
                   "FamiliaBien": "' + @FamiliaBien + N'", "ItemBien": "' + @ItemBien + N'",
                   "PrecioUnitario": 1.00,
                   "Periodos": [ {"AnoOffset":0,"Mes":11,"Cantidad":100},
                                 {"AnoOffset":0,"Mes":12,"Cantidad":100} ] } ] }';

    DELETE FROM @r; INSERT INTO @r EXEC cmn.paRegistrarSolicitud @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1'
    BEGIN PRINT ' FALLO registrar Anexo 3 de ' + @Unidad + ': ' + @j; EXEC #LimpiarS903; RETURN; END

    UPDATE @Area
       SET IdSolicitud  = JSON_VALUE(@j,'$.IdSolicitud'),
           IdExpediente = JSON_VALUE(@j,'$.IdExpediente'),
           Codigo       = JSON_VALUE(@j,'$.Codigo'),
           Version      = 1
     WHERE n = @n;

    PRINT '  Anexo 3 ' + JSON_VALUE(@j,'$.Codigo') + ' registrado para ' + @Unidad
        + ' (centro ' + @CentroCosto + ').';

    SET @n = @n + 1;
END

/* -------------------------------------------------------------------------- */
/* 2. Cada Anexo 3 recorre el circuito hasta CMN_A3_APROBADO                   */
/* -------------------------------------------------------------------------- */

DECLARE @Paso TABLE (o int IDENTITY(1,1), quien varchar(10), codigo varchar(70), firma bit, extra nvarchar(100));
INSERT INTO @Paso (quien, codigo, firma, extra) VALUES
    ('ESP',   'CMN_GENERAR_A3',            0, NULL),
    ('JEFE',  'CMN_FIRMAR_A3',             1, NULL),
    ('OA',    'CMN_OA_DERIVAR',            0, NULL),
    ('ABJE',  'CMN_ABAST_JEFE_DERIVAR',    0, NULL),
    ('ABCO',  'CMN_ABAST_COORD_DERIVAR',   0, NULL),
    /* URGENTE a proposito: si fuera ORDINARIA, la prueba solo pasaria los
       viernes. La regla del viernes se comprueba aparte, mas abajo. */
    ('ABES',  'CMN_ABAST_ESP_FIRMAR_A3',   0, N',"TipoInclusion":"URGENTE"');

DECLARE @o int, @quien varchar(10), @codTr varchar(70), @firmaPaso bit, @extraPaso nvarchar(100);
DECLARE @actor nvarchar(400), @totPaso int = (SELECT COUNT(*) FROM @Paso);
DECLARE @encoladasA3 int = 0;

SET @n = 1;
WHILE @n <= @tot
BEGIN
    SELECT @Unidad = Unidad, @CuentaEsp = CuentaEsp, @CuentaJefe = CuentaJefe,
           @IdExpediente = IdExpediente, @Codigo = Codigo, @Version = Version
      FROM @Area WHERE n = @n;

    SET @ActorEsp  = N'"Actor":{"Usuario":"' + @CuentaEsp  + N'","Rol":"AREA_ESPECIALISTA","Unidad":"' + @Unidad + N'","Equipo":"S903","Programa":"S903"}';
    SET @ActorJefe = N'"Actor":{"Usuario":"' + @CuentaJefe + N'","Rol":"AREA_JEFE","Unidad":"' + @Unidad + N'","Equipo":"S903","Programa":"S903"}';

    /* El PDF lo arma el frontend; aqui se registra su URL y su huella. */
    SET @p = N'{' + @ActorEsp + N',"IdExpediente":"' + @IdExpediente + N'",
      "CodigoTipoDocumento":"CMN_ANEXO_3_SOLICITUD_MODIFICACION",
      "GeneradoDocumento":"http://localhost/files/cmn/' + @Codigo + N'-anexo3.pdf",
      "NombreDocumento":"Anexo 3 - ' + @Codigo + N'.pdf","ArchivoHash":"S903-A3"}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paRegistrarDocumento @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1'
    BEGIN PRINT ' FALLO registrar PDF A3 de ' + @Codigo + ': ' + @j; EXEC #LimpiarS903; RETURN; END

    SET @o = 1;
    WHILE @o <= @totPaso
    BEGIN
        SELECT @quien = quien, @codTr = codigo, @firmaPaso = firma, @extraPaso = extra
          FROM @Paso WHERE o = @o;

        SET @actor = CASE @quien
                        WHEN 'ESP'  THEN @ActorEsp
                        WHEN 'JEFE' THEN @ActorJefe
                        WHEN 'OA'   THEN @ActorOA
                        WHEN 'ABES' THEN @ActorAbEs
                        WHEN 'ABCO' THEN @ActorAbCo
                        ELSE @ActorAbJe END;

        IF @firmaPaso = 1
        BEGIN
            SET @p = N'{' + @actor + N',"IdExpediente":"' + @IdExpediente + N'",
              "CodigoTipoDocumento":"CMN_ANEXO_3_SOLICITUD_MODIFICACION","ArchivoHash":"S903-A3-' + @codTr + N'"}';
            DELETE FROM @r; INSERT INTO @r EXEC sigcm.paFirmarDocumento @p;
            SELECT @j = j FROM @r;
            IF JSON_VALUE(@j,'$.estado') <> '1'
            BEGIN PRINT ' FALLO firma A3 (' + @codTr + ') en ' + @Codigo + ': ' + @j; EXEC #LimpiarS903; RETURN; END

            /* AREA_JEFE es el unico firmante del Anexo 3. */
            IF @codTr = 'CMN_FIRMAR_A3' AND JSON_VALUE(@j,'$.EstadoDocumento') <> 'FIRMADO'
            BEGIN
                PRINT '  [FALLA] Con la firma del jefe del area usuaria el Anexo 3 deberia quedar FIRMADO y quedo '
                    + ISNULL(JSON_VALUE(@j,'$.EstadoDocumento'),'NULL');
                SET @fallas = @fallas + 1;
            END
        END

        SET @p = N'{' + @actor + N',"IdExpediente":"' + @IdExpediente
               + N'","CodigoTransicion":"' + @codTr
               + N'","Version":' + CONVERT(varchar(10), @Version)
               + ISNULL(@extraPaso, N'') + N'}';
        DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
        SELECT @j = j FROM @r;
        IF JSON_VALUE(@j,'$.estado') <> '1'
        BEGIN PRINT ' FALLO ' + @codTr + ' en ' + @Codigo + ': ' + @j; EXEC #LimpiarS903; RETURN; END

        SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));

        IF @codTr = 'CMN_ABAST_ESP_FIRMAR_A3'
            SET @encoladasA3 = @encoladasA3 + CONVERT(int, ISNULL(JSON_VALUE(@j,'$.OperacionesEncoladas'),'0'));

        SET @o = @o + 1;
    END

    UPDATE @Area SET Version = @Version WHERE n = @n;
    PRINT '  ' + @Codigo + ' llego a CMN_A3_APROBADO con la conformidad del especialista.';

    SET @n = @n + 1;
END

PRINT '  Operaciones encoladas hacia SIGA por los Anexos 3: ' + CONVERT(varchar(10), @encoladasA3);

IF @encoladasA3 < @tot
BEGIN
    PRINT '  [FALLA] La firma del jefe deberia encolar al menos una operacion por area.';
    SET @fallas = @fallas + 1;
END

/* -------------------------------------------------------------------------- */
/* 3. La regla del viernes                                                     */
/* -------------------------------------------------------------------------- */
/*
  Los dos Anexos 3 se conformaron como URGENTE, asi que generar debe poder
  hacerse hoy sea el dia que sea. Se comprueba ademas el rechazo: se marca uno
  como ORDINARIA, se intenta generar y se espera REGLA_CALENDARIO cualquier dia
  que no sea viernes.
*/
DECLARE @IdSolA varchar(50), @IdSolB varchar(50), @IdExpA varchar(50), @IdExpB varchar(50);
DECLARE @VerA int, @VerB int;

SELECT @IdSolA = IdSolicitud, @IdExpA = IdExpediente, @VerA = Version FROM @Area WHERE n = 1;
SELECT @IdSolB = IdSolicitud, @IdExpB = IdExpediente, @VerB = Version FROM @Area WHERE n = 2;

DECLARE @EsViernes bit =
    CASE WHEN DATEDIFF(day, '19000101', CONVERT(date, GETDATE())) % 7 = 4 THEN 1 ELSE 0 END;

UPDATE cmn.Solicitud SET TipoInclusion = 'ORDINARIA'
 WHERE IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolA);
UPDATE cmn.Solicitud SET TipoInclusion = 'ORDINARIA'
 WHERE IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolB);

/*
  LAS PRUEBAS NEGATIVAS NO USAN "INSERT ... EXEC".

  Bajo INSERT ... EXEC el motor abre una transaccion implicita para la sentencia.
  Si la rutina llamada falla —y estas dos deben fallar, es lo que se comprueba—
  esa transaccion queda no confirmable y el resto del script muere con un 3930
  que no tiene nada que ver con lo que se estaba probando.

  Asi que se llaman con EXEC a secas, dejando que su JSON salga por pantalla, y
  se comprueba el EFECTO: que no haya nacido ningun Anexo 4. Es una asercion mas
  fuerte que leer el mensaje de error, porque lo que importa no es como se
  explica el rechazo sino que efectivamente no se haya creado nada.
*/
SET @p = N'{' + @ActorAbEs + N',"IdSolicitudes":["' + @IdSolA + N'","' + @IdSolB + N'"]}';
EXEC cmn.paGenerarAnexo4 @p;

DECLARE @paquetesTrasOrdinaria int =
    (SELECT COUNT(*) FROM cmn.Paquete WHERE ProgramaCreacionAuditoria = 'S903' AND Anulado = 0);

IF @EsViernes = 0
BEGIN
    IF @paquetesTrasOrdinaria <> 0
    BEGIN
        PRINT '  [FALLA] Se genero un Anexo 4 ordinario en un dia que no es viernes.';
        SET @fallas = @fallas + 1;
    END
    ELSE
        PRINT '  OK - Un Anexo 4 ordinario se rechaza si el dia no es viernes.';
END
ELSE
BEGIN
    PRINT '  (Hoy es viernes: la regla de calendario no rechaza, y es correcto.)';
    /* Si hoy SI es viernes el paquete nacio, y hay que retirarlo para que el
       resto de la prueba parta de cero. */
    DELETE ps FROM cmn.PaqueteSolicitud AS ps
      JOIN cmn.Paquete AS pk ON pk.IdPaquete = ps.IdPaquete
     WHERE pk.ProgramaCreacionAuditoria = 'S903';
    DELETE FROM cmn.Paquete WHERE ProgramaCreacionAuditoria = 'S903';
END

/* Se devuelven a URGENTE para poder seguir cualquier dia de la semana. */
UPDATE cmn.Solicitud SET TipoInclusion = 'URGENTE'
 WHERE IdSolicitud IN (TRY_CONVERT(uniqueidentifier, @IdSolA), TRY_CONVERT(uniqueidentifier, @IdSolB));

/* -------------------------------------------------------------------------- */
/* 4. UN Anexo 4 con los DOS Anexos 3                                          */
/* -------------------------------------------------------------------------- */

DECLARE @IdPaquete varchar(50), @CodigoA4 varchar(40);

SET @p = N'{' + @ActorAbEs + N',"IdSolicitudes":["' + @IdSolA + N'","' + @IdSolB + N'"],
  "Sustento":"Prueba S903: aprobacion conjunta de dos areas usuarias."}';
DELETE FROM @r; INSERT INTO @r EXEC cmn.paGenerarAnexo4 @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN PRINT ' FALLO paGenerarAnexo4: ' + @j; EXEC #LimpiarS903; RETURN; END

SET @IdPaquete = JSON_VALUE(@j,'$.IdPaquete');
SET @CodigoA4  = JSON_VALUE(@j,'$.Codigo');

PRINT '';
PRINT '  Anexo 4 ' + @CodigoA4 + ': '
    + ISNULL(JSON_VALUE(@j,'$.TotalSolicitudes'),'?') + ' Anexos 3, '
    + ISNULL(JSON_VALUE(@j,'$.TotalItems'),'?') + ' items, S/ '
    + ISNULL(JSON_VALUE(@j,'$.MontoTotal'),'?');

IF ISNULL(JSON_VALUE(@j,'$.TotalSolicitudes'),'0') <> '2'
BEGIN
    PRINT '  [FALLA] El Anexo 4 deberia agrupar 2 Anexos 3.';
    SET @fallas = @fallas + 1;
END

/* Las areas usuarias del paquete tienen que ser dos distintas: es lo que
   distingue este Anexo 4 de la suma de dos Anexos 4 individuales. */
DECLARE @areasEnPaquete int =
    (SELECT COUNT(DISTINCT e.IdUnidadOrigen)
       FROM cmn.PaqueteSolicitud AS ps
       JOIN cmn.Solicitud    AS s ON s.IdSolicitud = ps.IdSolicitud
       JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
      WHERE ps.IdPaquete = TRY_CONVERT(uniqueidentifier, @IdPaquete) AND ps.Activo = 1);

IF @areasEnPaquete <> 2
BEGIN
    PRINT '  [FALLA] El Anexo 4 deberia cubrir 2 areas usuarias distintas y cubre ' + CONVERT(varchar(10), @areasEnPaquete) + '.';
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - El Anexo 4 cubre 2 areas usuarias distintas.';

/* Un Anexo 3 no puede integrar dos Anexos 4. Igual que arriba: EXEC a secas y
   se comprueba que no haya nacido un segundo paquete. */
SET @p = N'{' + @ActorAbEs + N',"IdSolicitudes":["' + @IdSolA + N'"]}';
EXEC cmn.paGenerarAnexo4 @p;

DECLARE @paquetesTrasDuplicado int =
    (SELECT COUNT(*) FROM cmn.Paquete WHERE ProgramaCreacionAuditoria = 'S903' AND Anulado = 0);

IF @paquetesTrasDuplicado <> 1
BEGIN
    PRINT '  [FALLA] Se permitio incluir un Anexo 3 en un segundo Anexo 4 (paquetes='
        + CONVERT(varchar(10), @paquetesTrasDuplicado) + ').';
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Un Anexo 3 ya tomado no puede integrar otro Anexo 4.';

/* -------------------------------------------------------------------------- */
/* 5. UN documento consolidado para los dos expedientes                        */
/* -------------------------------------------------------------------------- */

SET @p = N'{' + @ActorAbEs + N',"IdExpedientes":["' + @IdExpA + N'","' + @IdExpB + N'"],
  "CodigoTipoDocumento":"CMN_ANEXO_4_APROBACION_MODIFICACION",
  "Numero":"' + @CodigoA4 + N'",
  "GeneradoDocumento":"http://localhost/files/cmn/' + @CodigoA4 + N'.pdf",
  "NombreDocumento":"Anexo 4 - ' + @CodigoA4 + N'.pdf","ArchivoHash":"S903-A4"}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paRegistrarDocumento @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN PRINT ' FALLO registrar A4 consolidado: ' + @j; EXEC #LimpiarS903; RETURN; END

DECLARE @IdDocA4 uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@j,'$.IdDocumento'));
DECLARE @expedientesDelDoc int =
    (SELECT COUNT(*) FROM sigcm.DocumentoExpediente WHERE IdDocumento = @IdDocA4);
DECLARE @esConsolidado bit =
    (SELECT Consolidado FROM sigcm.Documento WHERE IdDocumento = @IdDocA4);

IF @expedientesDelDoc <> 2 OR @esConsolidado <> 1
BEGIN
    PRINT '  [FALLA] El Anexo 4 deberia ser UN documento consolidado enlazado a 2 expedientes; '
        + 'enlazados=' + CONVERT(varchar(10), @expedientesDelDoc)
        + ' consolidado=' + CONVERT(varchar(1), ISNULL(@esConsolidado, 0));
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Un solo documento Anexo 4, marcado consolidado y enlazado a los 2 expedientes.';

/* -------------------------------------------------------------------------- */
/* 6. Elevacion del Anexo 4 y firma del jefe en lote                           */
/* -------------------------------------------------------------------------- */

DECLARE @Lote nvarchar(max) =
    N'[{"IdExpediente":"' + @IdExpA + N'","Version":' + CONVERT(varchar(10), @VerA) + N'},'
  + N' {"IdExpediente":"' + @IdExpB + N'","Version":' + CONVERT(varchar(10), @VerB) + N'}]';

DECLARE @F4 TABLE (o int IDENTITY(1,1), actor nvarchar(400), codigo varchar(70), etiqueta varchar(20), firma bit);
INSERT INTO @F4 (actor, codigo, etiqueta, firma) VALUES
    (@ActorAbEs, 'CMN_GENERAR_A4',            'especialista', 0),
    (@ActorAbJe, 'CMN_ABAST_JEFE_FIRMAR_A4',  'jefe',         1);

DECLARE @etiqueta varchar(20), @encoladasA4 int = 0, @movidos int = 0;
SET @o = 1; SET @totPaso = (SELECT COUNT(*) FROM @F4);

WHILE @o <= @totPaso
BEGIN
    SELECT @actor = actor, @codTr = codigo, @etiqueta = etiqueta, @firmaPaso = firma FROM @F4 WHERE o = @o;

    IF @firmaPaso = 1
    BEGIN
        /* Se firma por UN expediente: el documento es uno solo y la rutina lo
           encuentra por cualquiera de sus enlaces. */
        SET @p = N'{' + @actor + N',"IdExpediente":"' + @IdExpA + N'",
          "CodigoTipoDocumento":"CMN_ANEXO_4_APROBACION_MODIFICACION","ArchivoHash":"S903-A4-' + @etiqueta + N'"}';
        DELETE FROM @r; INSERT INTO @r EXEC sigcm.paFirmarDocumento @p;
        SELECT @j = j FROM @r;
        IF JSON_VALUE(@j,'$.estado') <> '1'
        BEGIN PRINT ' FALLO firma A4 (' + @etiqueta + '): ' + @j; EXEC #LimpiarS903; RETURN; END

        PRINT '  Firma del ' + @etiqueta + ': documento ' + ISNULL(JSON_VALUE(@j,'$.EstadoDocumento'),'?')
            + ', pendientes=' + ISNULL(JSON_VALUE(@j,'$.FirmasPendientes'),'?');
    END
    ELSE
        PRINT '  ' + @etiqueta + ' eleva el Anexo 4 sin firmar.';

    /* La transicion, sobre los DOS expedientes a la vez. */
    SET @p = N'{' + @actor + N',"IdExpedientes":' + @Lote
           + N',"CodigoTransicion":"' + @codTr + N'"}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1'
    BEGIN PRINT ' FALLO ' + @codTr + ': ' + @j; EXEC #LimpiarS903; RETURN; END

    SET @movidos = CONVERT(int, ISNULL(JSON_VALUE(@j,'$.ExpedientesMovidos'),'0'));
    IF @movidos <> 2
    BEGIN
        PRINT '  [FALLA] ' + @codTr + ' deberia mover 2 expedientes y movio ' + CONVERT(varchar(10), @movidos) + '.';
        SET @fallas = @fallas + 1;
    END

    IF @codTr = 'CMN_ABAST_JEFE_FIRMAR_A4'
        SET @encoladasA4 = CONVERT(int, ISNULL(JSON_VALUE(@j,'$.OperacionesEncoladas'),'0'));

    /* Las versiones subieron: el lote de la vuelta siguiente tiene que llevar
       las nuevas o el control de concurrencia lo rechaza, que es justamente lo
       que debe hacer. */
    SELECT @Lote = N'[' + STRING_AGG(
               N'{"IdExpediente":"' + CONVERT(varchar(50), e.IdExpediente)
               + N'","Version":' + CONVERT(varchar(10), e.Version) + N'}', N',') + N']'
      FROM sigcm.Expediente AS e
     WHERE e.IdExpediente IN (TRY_CONVERT(uniqueidentifier, @IdExpA),
                              TRY_CONVERT(uniqueidentifier, @IdExpB));

    SET @o = @o + 1;
END

PRINT '';
PRINT '  Aprobaciones encoladas hacia SIGA por el Anexo 4: ' + CONVERT(varchar(10), @encoladasA4);

IF @encoladasA4 <> 2
BEGIN
    PRINT '  [FALLA] La firma del jefe deberia encolar UNA aprobacion por area usuaria (2).';
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Registro multiple de aprobaciones: una por cada area usuaria del Anexo 4.';

/* -------------------------------------------------------------------------- */
/* 7. Cada expediente volvio a SU area usuaria                                 */
/* -------------------------------------------------------------------------- */

SELECT bloque = 'ESTADO FINAL',
       Expediente = e.Codigo,
       Estado     = e.CodigoEstado,
       AreaOrigen = uo.Codigo,
       AreaActual = ua.Codigo,
       Correcto   = CASE WHEN e.IdUnidadActual = e.IdUnidadOrigen
                          AND e.CodigoEstado = 'CMN_A4_ENVIADO'
                         THEN 'OK' ELSE '*** NO ***' END
  FROM sigcm.Expediente AS e
  JOIN sigcm.Unidad AS uo ON uo.IdUnidad = e.IdUnidadOrigen
  LEFT JOIN sigcm.Unidad AS ua ON ua.IdUnidad = e.IdUnidadActual
 WHERE e.IdExpediente IN (TRY_CONVERT(uniqueidentifier, @IdExpA),
                          TRY_CONVERT(uniqueidentifier, @IdExpB))
 ORDER BY e.Codigo;

DECLARE @malRuteados int =
    (SELECT COUNT(*) FROM sigcm.Expediente AS e
      WHERE e.IdExpediente IN (TRY_CONVERT(uniqueidentifier, @IdExpA),
                               TRY_CONVERT(uniqueidentifier, @IdExpB))
        AND (e.IdUnidadActual <> e.IdUnidadOrigen OR e.CodigoEstado <> 'CMN_A4_ENVIADO'));

IF @malRuteados > 0
BEGIN
    PRINT '  [FALLA] Algun expediente no volvio a su area usuaria en CMN_A4_ENVIADO.';
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Cada Anexo 3 volvio a la oficina que lo pidio.';

/* La cadena de firmas del Anexo 4, como quedo registrada. */
SELECT bloque = 'FIRMAS DEL ANEXO 4',
       f.OrdenFirma, f.CodigoRol, f.FirmanteNombre, f.Estado
  FROM sigcm.Firma AS f
  JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumentoVersion = f.IdDocumentoVersion
 WHERE dv.IdDocumento = @IdDocA4
 ORDER BY f.OrdenFirma;

/* -------------------------------------------------------------------------- */
/* Resultado                                                                   */
/* -------------------------------------------------------------------------- */

PRINT '';
PRINT '===========================================================';
IF @fallas = 0
    PRINT ' S903 OK - el Anexo 4 multiple funciona de punta a punta.';
ELSE
    PRINT ' S903 CON ' + CONVERT(varchar(10), @fallas) + ' FALLA(S). Revisar arriba.';
PRINT '===========================================================';

/* No deja rastro: la prueba es repetible. */
EXEC #LimpiarS903;
PRINT ' (Datos de la prueba retirados: la base quedo como estaba.)';
GO

DROP PROCEDURE IF EXISTS #LimpiarS903;
GO
