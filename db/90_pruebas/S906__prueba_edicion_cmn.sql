/*
===============================================================================
  SIGCM - S906 : Corregir y anular un Anexo 3
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA

  Comprueba lo que el negocio pidio sobre la edicion:

    1. El especialista corrige su borrador: es el MISMO expediente, con el mismo
       codigo, y los items quedan reemplazados. Antes esto creaba un expediente
       nuevo con correlativo nuevo y dejaba el anterior vivo.
    2. El JEFE del area tambien puede corregirlo, aunque el turno del estado sea
       del especialista.
    3. Un perfil de Abastecimiento NO puede corregirlo.
    4. Una vez firmado el Anexo 3 ya no se puede corregir.
    5. Un expediente devuelto observado vuelve a ser corregible, en los tres
       escalones del area usuaria por los que pasa.
    6. La anulacion del borrador esta disponible para el area usuaria.

  Se limpia sola y es repetible: reconoce lo suyo por Programa = 'S906'.
  No escribe en SIGA: la prueba se detiene antes de la conformidad de
  Abastecimiento, que es el primer momento de escritura.

    sqlcmd -S "localhost\SQLSERVER25" -d DBSIGCM -E -b -I -i db/90_pruebas/S906__prueba_edicion_cmn.sql
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DROP PROCEDURE IF EXISTS #LimpiarS906;
GO
CREATE PROCEDURE #LimpiarS906
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY);
    INSERT INTO @Exp
    SELECT IdExpediente FROM sigcm.Expediente WHERE ProgramaCreacionAuditoria = 'S906';

    IF NOT EXISTS (SELECT 1 FROM @Exp) RETURN;

    DECLARE @Doc TABLE (IdDocumento uniqueidentifier PRIMARY KEY);
    INSERT INTO @Doc
    SELECT DISTINCT de.IdDocumento
      FROM sigcm.DocumentoExpediente AS de
      JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;

    DELETE o  FROM integracion.Operacion AS o JOIN @Exp AS x ON x.IdExpediente = o.IdExpediente;
    DELETE de FROM sigcm.DocumentoExpediente AS de JOIN @Doc AS d ON d.IdDocumento = de.IdDocumento;
    DELETE dc FROM sigcm.Documento           AS dc JOIN @Doc AS d ON d.IdDocumento = dc.IdDocumento;
    DELETE ob FROM sigcm.Observacion AS ob JOIN @Exp AS x ON x.IdExpediente = ob.IdExpediente;
    DELETE pl FROM sigcm.Plazo       AS pl JOIN @Exp AS x ON x.IdExpediente = pl.IdExpediente;
    DELETE h  FROM sigcm.Historial   AS h  JOIN @Exp AS x ON x.IdExpediente = h.IdExpediente;
    DELETE e  FROM sigcm.Expediente  AS e  JOIN @Exp AS x ON x.IdExpediente = e.IdExpediente;

    DELETE FROM sigcm.EventoAuditoria WHERE Programa = 'S906';
END
GO

DECLARE @r TABLE (j nvarchar(max));
DECLARE @j nvarchar(max), @p nvarchar(max);
DECLARE @fallas int = 0;

DECLARE @AnoEje int = 2026, @SecEjec int = 1750;
DECLARE @Unidad varchar(30) = 'UO-PRUEBA', @CentroCosto varchar(15) = '01.01';

DECLARE @ActorEsp  nvarchar(400) = N'"Actor":{"Usuario":"prueba.especialista","Rol":"AREA_ESPECIALISTA","Unidad":"UO-PRUEBA","Equipo":"S906","Programa":"S906"}';
DECLARE @ActorJefe nvarchar(400) = N'"Actor":{"Usuario":"prueba.jefe","Rol":"AREA_JEFE","Unidad":"UO-PRUEBA","Equipo":"S906","Programa":"S906"}';
DECLARE @ActorAbEs nvarchar(400) = N'"Actor":{"Usuario":"prueba.abast.esp","Rol":"ABAST_ESPECIALISTA","Unidad":"UO-ABAST","Equipo":"S906","Programa":"S906"}';

PRINT '===========================================================';
PRINT ' S906 - Corregir y anular un Anexo 3';
PRINT '===========================================================';

EXEC #LimpiarS906;

/* -------------------------------------------------------------------------- */
/* 1. Registro inicial                                                         */
/* -------------------------------------------------------------------------- */
/* Las coordenadas presupuestales salen de un item que el area YA tiene en su
   cuadro: inventarlas haria fallar la prueba por un maestro y no por el flujo. */

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
    PRINT '  [SALTEADA] El centro ' + @CentroCosto + ' no tiene items de servicio de referencia en SIGA.';
    RETURN;
END

DECLARE @Item nvarchar(max) =
    N'{ "TipoMovimiento":"INCLUSION",
        "TipoTarea":"' + @TipoTarea + N'","NivelTarea":"' + @NivelTarea + N'",
        "CodigoTarea":' + CONVERT(varchar(10), @CodigoTarea) + N',"SecFunc":' + CONVERT(varchar(10), @SecFunc) + N',
        "Origen":"1","FuenteFinanc":"00","Clasificador":"' + @Clasificador + N'",
        "TipoRecurso":"1","TipoPpto":1,"TipoUso":"C",
        "TipoBien":"S","GrupoBien":"' + @GrupoBien + N'","ClaseBien":"' + @ClaseBien + N'",
        "FamiliaBien":"' + @FamiliaBien + N'","ItemBien":"' + @ItemBien + N'",
        "PrecioUnitario":1.00,
        "Periodos":[{"AnoOffset":0,"Mes":11,"Cantidad":@CANT@}] }';

SET @p = N'{' + @ActorEsp + N',
  "Solicitud": { "AnoEje": ' + CONVERT(varchar(4), @AnoEje) + N', "SecEjec": ' + CONVERT(varchar(10), @SecEjec) + N',
                 "CentroCosto": "' + @CentroCosto + N'", "TipoOperacion": "MODIFICACION",
                 "Sustento": "S906: registro inicial.", "TipoInclusion": "ORDINARIA" },
  "Items": [' + REPLACE(@Item, '@CANT@', '100') + N']}';

DELETE FROM @r; INSERT INTO @r EXEC cmn.paRegistrarSolicitud @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN PRINT ' FALLO el registro inicial: ' + @j; EXEC #LimpiarS906; RETURN; END

DECLARE @IdSolicitud varchar(50) = JSON_VALUE(@j,'$.IdSolicitud');
DECLARE @IdExpediente varchar(50) = JSON_VALUE(@j,'$.IdExpediente');
DECLARE @Codigo varchar(40) = JSON_VALUE(@j,'$.Codigo');
DECLARE @Version int = 1;

PRINT '  Registrado ' + @Codigo + ' con 1 item de 100.';

/* -------------------------------------------------------------------------- */
/* 2. El especialista corrige su borrador                                      */
/* -------------------------------------------------------------------------- */
/* Dos items en vez de uno, otro sustento y otra tipificacion: si la correccion
   funciona, el expediente es el mismo y su contenido es el nuevo. */

SET @p = N'{' + @ActorEsp + N',
  "Solicitud": { "IdSolicitud": "' + @IdSolicitud + N'",
                 "AnoEje": ' + CONVERT(varchar(4), @AnoEje) + N', "SecEjec": ' + CONVERT(varchar(10), @SecEjec) + N',
                 "CentroCosto": "' + @CentroCosto + N'", "TipoOperacion": "MODIFICACION",
                 "Sustento": "S906: corregido por el especialista.",
                 "TipoInclusion": "EXTRAORDINARIA",
                 "JustificacionUrgencia": "S906: la necesidad no puede esperar." },
  "Items": [' + REPLACE(@Item, '@CANT@', '250') + N']}';

DELETE FROM @r; INSERT INTO @r EXEC cmn.paRegistrarSolicitud @p;
SELECT @j = j FROM @r;

IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN
    PRINT '  [FALLA] El especialista no pudo corregir su borrador: ' + @j;
    SET @fallas = @fallas + 1;
END
ELSE IF JSON_VALUE(@j,'$.IdSolicitud') <> @IdSolicitud OR JSON_VALUE(@j,'$.Codigo') <> @Codigo
BEGIN
    PRINT '  [FALLA] La correccion creo un expediente nuevo: ' + @j;
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - El especialista corrige y sigue siendo ' + @Codigo + '.';

DECLARE @expedientes int = (SELECT COUNT(*) FROM sigcm.Expediente WHERE ProgramaCreacionAuditoria = 'S906');
IF @expedientes <> 1
BEGIN
    PRINT '  [FALLA] Hay ' + CONVERT(varchar(10), @expedientes) + ' expedientes y deberia haber 1.';
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Un solo expediente: corregir no duplica.';

DECLARE @items int, @cant decimal(18,2), @tipo varchar(15);
SELECT @items = COUNT(*) FROM cmn.SolicitudItem WHERE IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolicitud);
SELECT @cant = SUM(p.Cantidad)
  FROM cmn.SolicitudItem AS i
  JOIN cmn.SolicitudItemPeriodo AS p ON p.IdSolicitudItem = i.IdSolicitudItem
 WHERE i.IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolicitud);
SELECT @tipo = TipoInclusion FROM cmn.Solicitud WHERE IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolicitud);

IF @items <> 1 OR @cant <> 250 OR @tipo <> 'EXTRAORDINARIA'
BEGIN
    PRINT '  [FALLA] El contenido no quedo reemplazado: items=' + CONVERT(varchar(10), @items)
        + ', cantidad=' + CONVERT(varchar(20), @cant) + ', tipo=' + ISNULL(@tipo,'(nulo)');
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Los items y la tipificacion quedaron reemplazados, no acumulados.';

/* -------------------------------------------------------------------------- */
/* 3. El jefe del area tambien puede corregir                                  */
/* -------------------------------------------------------------------------- */
/* El turno del estado CMN_BORRADOR es del especialista, pero el negocio pidio
   que el jefe que encuentra un error no tenga que devolverlo para que lo
   arreglen. */

SET @p = N'{' + @ActorJefe + N',
  "Solicitud": { "IdSolicitud": "' + @IdSolicitud + N'",
                 "AnoEje": ' + CONVERT(varchar(4), @AnoEje) + N', "SecEjec": ' + CONVERT(varchar(10), @SecEjec) + N',
                 "CentroCosto": "' + @CentroCosto + N'", "TipoOperacion": "MODIFICACION",
                 "Sustento": "S906: corregido por el jefe.", "TipoInclusion": "ORDINARIA" },
  "Items": [' + REPLACE(@Item, '@CANT@', '300') + N']}';

DELETE FROM @r; INSERT INTO @r EXEC cmn.paRegistrarSolicitud @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN
    PRINT '  [FALLA] El jefe del area no pudo corregir: ' + @j;
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - El jefe del area usuaria tambien corrige.';

/* -------------------------------------------------------------------------- */
/* 4. Abastecimiento no puede corregir un Anexo 3 del area usuaria             */
/* -------------------------------------------------------------------------- */
/*
  LAS PRUEBAS NEGATIVAS NO USAN "INSERT ... EXEC": bajo esa forma el motor abre
  una transaccion implicita y, al fallar la rutina, queda no confirmable y el
  script muere con un 3930 que no dice nada. Se llama con EXEC a secas y se
  comprueba el EFECTO.
*/
SET @p = N'{' + @ActorAbEs + N',
  "Solicitud": { "IdSolicitud": "' + @IdSolicitud + N'",
                 "AnoEje": ' + CONVERT(varchar(4), @AnoEje) + N', "SecEjec": ' + CONVERT(varchar(10), @SecEjec) + N',
                 "CentroCosto": "' + @CentroCosto + N'", "TipoOperacion": "MODIFICACION",
                 "Sustento": "S906: intento de Abastecimiento.", "TipoInclusion": "ORDINARIA" },
  "Items": [' + REPLACE(@Item, '@CANT@', '999') + N']}';
EXEC cmn.paRegistrarSolicitud @p;

DECLARE @sustentoActual nvarchar(max);
SELECT @sustentoActual = Sustento FROM cmn.Solicitud WHERE IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolicitud);
IF @sustentoActual <> 'S906: corregido por el jefe.'
BEGIN
    PRINT '  [FALLA] Abastecimiento modifico el Anexo 3 del area usuaria.';
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Abastecimiento no puede corregir el Anexo 3 del area usuaria.';

/* -------------------------------------------------------------------------- */
/* 5. Firmado el Anexo 3, ya no se corrige                                     */
/* -------------------------------------------------------------------------- */

SET @p = N'{' + @ActorEsp + N',"IdExpediente":"' + @IdExpediente
       + N'","CodigoTransicion":"CMN_GENERAR_A3","Version":' + CONVERT(varchar(10), @Version) + N'}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN PRINT ' FALLO CMN_GENERAR_A3: ' + @j; EXEC #LimpiarS906; RETURN; END
SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));

/* En CMN_PEND_FIRMA_A3 todavia se corrige: el jefe encontro el error al ir a
   firmar y no tiene por que devolverlo. */
SET @p = N'{' + @ActorJefe + N',
  "Solicitud": { "IdSolicitud": "' + @IdSolicitud + N'",
                 "AnoEje": ' + CONVERT(varchar(4), @AnoEje) + N', "SecEjec": ' + CONVERT(varchar(10), @SecEjec) + N',
                 "CentroCosto": "' + @CentroCosto + N'", "TipoOperacion": "MODIFICACION",
                 "Sustento": "S906: corregido antes de firmar.", "TipoInclusion": "ORDINARIA" },
  "Items": [' + REPLACE(@Item, '@CANT@', '310') + N']}';
DELETE FROM @r; INSERT INTO @r EXEC cmn.paRegistrarSolicitud @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN
    PRINT '  [FALLA] No se pudo corregir en CMN_PEND_FIRMA_A3: ' + @j;
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Generado el Anexo 3 y pendiente de firma, todavia se corrige.';

/* Registrar y firmar el documento, para llegar a CMN_A3_FIRMADO. */
SET @p = N'{' + @ActorJefe + N',"IdExpediente":"' + @IdExpediente + N'",
  "CodigoTipoDocumento":"CMN_ANEXO_3_SOLICITUD_MODIFICACION",
  "GeneradoDocumento":"S906-a3.pdf","NombreDocumento":"S906 Anexo 3.pdf"}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paRegistrarDocumento @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN PRINT ' FALLO registrar documento: ' + @j; EXEC #LimpiarS906; RETURN; END

SET @p = N'{' + @ActorJefe + N',"IdExpediente":"' + @IdExpediente + N'",
  "CodigoTipoDocumento":"CMN_ANEXO_3_SOLICITUD_MODIFICACION","ArchivoHash":"S906-A3"}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paFirmarDocumento @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN PRINT ' FALLO firmar: ' + @j; EXEC #LimpiarS906; RETURN; END

SET @p = N'{' + @ActorJefe + N',"IdExpediente":"' + @IdExpediente
       + N'","CodigoTransicion":"CMN_FIRMAR_A3","Version":' + CONVERT(varchar(10), @Version) + N'}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN PRINT ' FALLO CMN_FIRMAR_A3: ' + @j; EXEC #LimpiarS906; RETURN; END
SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));

SET @p = N'{' + @ActorJefe + N',
  "Solicitud": { "IdSolicitud": "' + @IdSolicitud + N'",
                 "AnoEje": ' + CONVERT(varchar(4), @AnoEje) + N', "SecEjec": ' + CONVERT(varchar(10), @SecEjec) + N',
                 "CentroCosto": "' + @CentroCosto + N'", "TipoOperacion": "MODIFICACION",
                 "Sustento": "S906: intento despues de la firma.", "TipoInclusion": "ORDINARIA" },
  "Items": [' + REPLACE(@Item, '@CANT@', '400') + N']}';
EXEC cmn.paRegistrarSolicitud @p;

SELECT @sustentoActual = Sustento FROM cmn.Solicitud WHERE IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolicitud);
IF @sustentoActual <> 'S906: corregido antes de firmar.'
BEGIN
    PRINT '  [FALLA] Se pudo corregir un Anexo 3 ya firmado.';
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Firmado el Anexo 3, la correccion se rechaza.';

/* -------------------------------------------------------------------------- */
/* 6. Devuelto observado, vuelve a ser corregible                              */
/* -------------------------------------------------------------------------- */

DECLARE @Paso TABLE (o int IDENTITY(1,1), actor nvarchar(400), codigo varchar(70), comentario nvarchar(200));
INSERT INTO @Paso (actor, codigo, comentario) VALUES
    (@ActorJefe, 'CMN_ENVIAR_OA',   NULL),
    (N'"Actor":{"Usuario":"prueba.oa","Rol":"OA","Unidad":"UO-OA","Equipo":"S906","Programa":"S906"}',
     'CMN_OA_OBSERVAR', N'S906: observacion de prueba.');

DECLARE @o int = 1, @totPaso int = (SELECT COUNT(*) FROM @Paso);
DECLARE @ac nvarchar(400), @cd varchar(70), @com nvarchar(200);

WHILE @o <= @totPaso
BEGIN
    SELECT @ac = actor, @cd = codigo, @com = comentario FROM @Paso WHERE o = @o;

    SET @p = N'{' + @ac + N',"IdExpediente":"' + @IdExpediente
           + N'","CodigoTransicion":"' + @cd
           + N'","Version":' + CONVERT(varchar(10), @Version)
           + CASE WHEN @com IS NULL THEN N'' ELSE N',"Comentario":"' + @com + N'"' END + N'}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1'
    BEGIN PRINT ' FALLO ' + @cd + ': ' + @j; EXEC #LimpiarS906; RETURN; END
    SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));
    SET @o = @o + 1;
END

/* Queda en CMN_OBS_AU_JEFE: el jefe lo tiene y ya puede corregirlo, sin esperar
   a derivarlo al coordinador y al especialista. */
SET @p = N'{' + @ActorJefe + N',
  "Solicitud": { "IdSolicitud": "' + @IdSolicitud + N'",
                 "AnoEje": ' + CONVERT(varchar(4), @AnoEje) + N', "SecEjec": ' + CONVERT(varchar(10), @SecEjec) + N',
                 "CentroCosto": "' + @CentroCosto + N'", "TipoOperacion": "MODIFICACION",
                 "Sustento": "S906: subsanado por el jefe.", "TipoInclusion": "ORDINARIA" },
  "Items": [' + REPLACE(@Item, '@CANT@', '500') + N']}';
DELETE FROM @r; INSERT INTO @r EXEC cmn.paRegistrarSolicitud @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1'
BEGIN
    PRINT '  [FALLA] Devuelto observado, el jefe no pudo corregir: ' + @j;
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Observado y devuelto al area usuaria, vuelve a corregirse.';

/* -------------------------------------------------------------------------- */
/* 7. La anulacion esta disponible para el area usuaria en el borrador         */
/* -------------------------------------------------------------------------- */

DECLARE @rolesAnulan int =
    (SELECT COUNT(*) FROM sigcm.TransicionRol
      WHERE CodigoTransicion = 'CMN_ANULAR_BORRADOR'
        AND CodigoRol IN ('AREA_ESPECIALISTA','AREA_COORDINADOR','AREA_JEFE'));

IF @rolesAnulan <> 3
BEGIN
    PRINT '  [FALLA] CMN_ANULAR_BORRADOR no esta habilitada para los tres perfiles del area.';
    SET @fallas = @fallas + 1;
END
ELSE
    PRINT '  OK - Anular el borrador esta disponible para el area usuaria.';

/* -------------------------------------------------------------------------- */
/* Cierre                                                                      */
/* -------------------------------------------------------------------------- */

EXEC #LimpiarS906;

PRINT '';
PRINT '===========================================================';
IF @fallas = 0
    PRINT ' S906 OK - corregir y anular funcionan como pidio el negocio.';
ELSE
    PRINT ' S906 CON ' + CONVERT(varchar(10), @fallas) + ' FALLA(S). Revisar arriba.';
PRINT '===========================================================';
PRINT ' (Datos de la prueba retirados: la base quedo como estaba.)';
GO
