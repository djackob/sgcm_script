/*
===============================================================================
  SIGCM - S901 : Prueba de punta a punta del CMN contra SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]  (escribe tambien en SIGA_1750 a traves de W001)

  QUE DEMUESTRA
  -------------
  Que una inclusion registrada en el SIGCM llega a SIGA, y que llega en DOS
  MOMENTOS distintos, no en uno:

      Firma y validacion del Anexo 3  ->  el item aparece en
                                          SIG_CUADRO_MODIFICADO_DET con
                                          MOTIVO_SOLICITUD='1'. Existe, pero
                                          SIGA todavia NO lo deja pedir.

      Firma del Anexo 4               ->  la solicitud pasa a aprobada y el item
                                          queda con MOTIVO_SOLICITUD='0'. Recien
                                          entonces es pedible.

  La prueba comprueba las dos cosas explicitamente: cuenta si el item pasa el
  filtro del selector de requerimientos ANTES y DESPUES del Anexo 4.

  IMPORTANTE
  ----------
  ESTA PRUEBA CONFIRMA. No se revierte, porque el objetivo es poder abrir el
  aplicativo SIGA y ver el registro. Corre contra la copia local SIGA_1750.

  Al terminar imprime la ruta exacta del aplicativo y las claves con las que se
  encuentra el item en pantalla.

  Requisitos: S001, S900 y W001 aplicados, y los procedimientos
  usp_ext_incluir_item_cmn y usp_ext_aprobar_solicitud_cmn instalados en SIGA.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*
  @SoloAnexo3 = 1 detiene la prueba despues de validar el Anexo 3, o sea con la
  solicitud ABIERTA en SIGA (MOTIVO_SOLICITUD='1').

  Sirve para ver el item en la pantalla "Demanda Adicional - Identificacion",
  que muestra la demanda adicional EN CURSO. Una vez firmado el Anexo 4 la
  solicitud se cierra, el item pasa a MOTIVO_SOLICITUD='0' y deja esa pantalla:
  ya no es demanda adicional pendiente, es parte del cuadro vigente.

  Para completar despues el Anexo 4, usar S902 con el codigo de expediente.
*/
DECLARE @SoloAnexo3 bit = 1;

DECLARE @r TABLE (j nvarchar(max));
DECLARE @j nvarchar(max), @p nvarchar(max);
DECLARE @IdExpediente varchar(50), @IdSolicitud varchar(50), @Codigo varchar(40);
DECLARE @Version int, @paso varchar(80);

/* Datos del area usuaria elegida: OTI (01.07.05.03). Ver la cabecera de S900.
   El centro tiene que estar en SIG_CUADRO_X_CENTRO.estado='4' o el aplicativo
   no abre la Demanda Adicional, aunque la escritura en base funcione igual. */
DECLARE @CentroCosto varchar(15) = '01.07.05.03';
DECLARE @AnoEje int = 2026, @SecEjec int = 1750;
DECLARE @SecFunc int = 15, @Clasificador varchar(20) = '2.3. 2  9. 1  1';
DECLARE @TipoTarea varchar(1), @NivelTarea varchar(1), @CodigoTarea int;
DECLARE @GrupoBien varchar(2), @ClaseBien varchar(2),
        @FamiliaBien varchar(4), @ItemBien varchar(4);

/* Actores. El Anexo 3 lo firma el jefe del area; el Anexo 4, Abastecimiento. */
DECLARE @ActorEsp  nvarchar(400) = N'"Actor":{"Usuario":"prueba.oti.esp","Rol":"AREA_ESPECIALISTA","Unidad":"UO-OTI","Equipo":"S901","Programa":"S901"}';
DECLARE @ActorJefe nvarchar(400) = N'"Actor":{"Usuario":"prueba.oti.jefe","Rol":"AREA_JEFE","Unidad":"UO-OTI","Equipo":"S901","Programa":"S901"}';
DECLARE @ActorOA   nvarchar(400) = N'"Actor":{"Usuario":"prueba.oa","Rol":"OA","Unidad":"UO-OA","Equipo":"S901","Programa":"S901"}';
/* Abastecimiento son TRES personas distintas, no una con tres sombreros. Es lo
   que permite comprobar que cada firma la pone quien corresponde: con una sola
   cuenta multirol, el motor aceptaria todo y la prueba no probaria nada. */
DECLARE @ActorAbEs nvarchar(400) = N'"Actor":{"Usuario":"prueba.abast.esp","Rol":"ABAST_ESPECIALISTA","Unidad":"UO-ABAST","Equipo":"S901","Programa":"S901"}';
DECLARE @ActorAbCo nvarchar(400) = N'"Actor":{"Usuario":"prueba.abastecim","Rol":"ABAST_COORDINADOR","Unidad":"UO-ABAST","Equipo":"S901","Programa":"S901"}';
DECLARE @ActorAbJe nvarchar(400) = N'"Actor":{"Usuario":"prueba.abast.jefe","Rol":"ABAST_JEFE","Unidad":"UO-ABAST","Equipo":"S901","Programa":"S901"}';

/* -------------------------------------------------------------------------- */
/* 0. Un item de catalogo y una tarea que existan de verdad en ese centro      */
/* -------------------------------------------------------------------------- */
/* No se inventan: se toman de un item que el area ya tiene en su cuadro, para
   que la prueba falle por lo que se quiere probar y no por un maestro. */

SELECT TOP 1
       @TipoTarea = d.TIPO_TAREA, @NivelTarea = d.NIVEL_TAREA, @CodigoTarea = d.CODIGO_TAREA,
       @GrupoBien = d.GRUPO_BIEN, @ClaseBien = d.CLASE_BIEN,
       @FamiliaBien = d.FAMILIA_BIEN, @ItemBien = d.ITEM_BIEN
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC = @AnoEje AND d.SEC_EJEC = @SecEjec
   AND d.CENTRO_COSTO = @CentroCosto AND d.ANNO_PROG = @AnoEje
   AND d.SEC_FUNC = @SecFunc AND d.CLASIFICADOR = @Clasificador
   AND d.TIPO_BIEN = 'S'
 ORDER BY d.SEC_ITEM;

IF @TipoTarea IS NULL
BEGIN
    RAISERROR('No se encontro un item de referencia en el centro %s. Revisa el centro elegido.', 16, 1, @CentroCosto);
    RETURN;
END

PRINT '===========================================================';
PRINT ' PASO 0 - Referencias tomadas de SIGA';
PRINT '===========================================================';
PRINT '  Centro de costo : ' + @CentroCosto;
PRINT '  Meta (SEC_FUNC) : ' + CONVERT(varchar(10), @SecFunc);
PRINT '  Clasificador    : ' + @Clasificador;
PRINT '  Tarea           : ' + @TipoTarea + '/' + @NivelTarea + '/' + CONVERT(varchar(10), @CodigoTarea);
PRINT '  Item catalogo   : S-' + @GrupoBien + '-' + @ClaseBien + '-' + @FamiliaBien + '-' + @ItemBien;

/* -------------------------------------------------------------------------- */
/* 1. Registrar el Anexo 3 (area usuaria)                                     */
/* -------------------------------------------------------------------------- */
/* 4 000 unidades a S/ 1.00 repartidas en los ultimos cuatro meses del anio,
   holgadamente dentro de los S/ 131 994 libres del techo de OTI en la meta 15.
   Setiembre a diciembre es a proposito: los items que el area ya tiene estan
   cargados en meses anteriores, asi que el nuevo se distingue de un vistazo. */

SET @p = N'{' + @ActorEsp + N',
  "Solicitud": { "AnoEje": 2026, "SecEjec": 1750, "CentroCosto": "' + @CentroCosto + N'",
                 "TipoOperacion": "MODIFICACION",
                 "Sustento": "Prueba S901: inclusion de servicio para demostrar el registro en SIGA." },
  "Items": [ { "TipoMovimiento": "INCLUSION",
               "TipoTarea": "' + @TipoTarea + N'", "NivelTarea": "' + @NivelTarea + N'",
               "CodigoTarea": ' + CONVERT(varchar(10), @CodigoTarea) + N', "SecFunc": ' + CONVERT(varchar(10), @SecFunc) + N',
               "Origen": "1", "FuenteFinanc": "00", "Clasificador": "' + @Clasificador + N'",
               "TipoRecurso": "1", "TipoPpto": 1, "TipoUso": "C",
               "TipoBien": "S", "GrupoBien": "' + @GrupoBien + N'", "ClaseBien": "' + @ClaseBien + N'",
               "FamiliaBien": "' + @FamiliaBien + N'", "ItemBien": "' + @ItemBien + N'",
               "PrecioUnitario": 1.00,
               "Periodos": [ {"AnoOffset":0,"Mes":9,"Cantidad":1000},
                             {"AnoOffset":0,"Mes":10,"Cantidad":1000},
                             {"AnoOffset":0,"Mes":11,"Cantidad":1000},
                             {"AnoOffset":0,"Mes":12,"Cantidad":1000} ] } ] }';

DELETE FROM @r; INSERT INTO @r EXEC cmn.paRegistrarSolicitud @p;
SELECT @j = j FROM @r;

IF JSON_VALUE(@j, '$.estado') <> '1'
BEGIN
    PRINT '  FALLO al registrar: ' + ISNULL(JSON_VALUE(@j, '$.mensaje'), @j);
    RETURN;
END

SET @IdSolicitud  = JSON_VALUE(@j, '$.IdSolicitud');
SET @IdExpediente = JSON_VALUE(@j, '$.IdExpediente');
SET @Codigo       = JSON_VALUE(@j, '$.Codigo');
SET @Version      = 1;

PRINT '';
PRINT ' PASO 1 - Anexo 3 registrado: ' + @Codigo + '  (48 periodos por item)';

/* -------------------------------------------------------------------------- */
/* Helper implicito: cada transicion refresca la version del expediente        */
/* -------------------------------------------------------------------------- */

/* 2. Generar Anexo 3 */
SET @p = N'{' + @ActorEsp + N',"IdExpediente":"' + @IdExpediente + N'","CodigoTransicion":"CMN_GENERAR_A3","Version":' + CONVERT(varchar(10), @Version) + N'}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO CMN_GENERAR_A3: ' + @j; RETURN; END
SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));
PRINT ' PASO 2 - Anexo 3 generado. Estado: ' + JSON_VALUE(@j,'$.CodigoEstado');

/* 3. Registrar el PDF del Anexo 3 (lo genera el frontend; aqui se simula) */
SET @p = N'{' + @ActorEsp + N',"IdExpediente":"' + @IdExpediente + N'",
  "CodigoTipoDocumento":"CMN_ANEXO_3_SOLICITUD_MODIFICACION",
  "GeneradoDocumento":"http://localhost/files/cmn/' + @Codigo + N'-anexo3.pdf",
  "NombreDocumento":"Anexo 3 - ' + @Codigo + N'.pdf",
  "ArchivoHash":"S901-A3"}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paRegistrarDocumento @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO registrar A3: ' + @j; RETURN; END
PRINT ' PASO 3 - PDF del Anexo 3 registrado en version ' + ISNULL(JSON_VALUE(@j,'$.Version'),'?');

/* 4. Firmar el Anexo 3 (jefe del area usuaria) */
/* La firma es un asiento: queda constancia de quien firmo y cuando. Cuando se
   integre el firmador institucional, este es el unico punto que cambia. */
SET @p = N'{' + @ActorJefe + N',"IdExpediente":"' + @IdExpediente + N'",
  "CodigoTipoDocumento":"CMN_ANEXO_3_SOLICITUD_MODIFICACION","ArchivoHash":"S901-A3-FIRMADO"}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paFirmarDocumento @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO firmar A3: ' + @j; RETURN; END
PRINT ' PASO 4 - Anexo 3 FIRMADO por ' + ISNULL(JSON_VALUE(@j,'$.Firmante'),'?')
    + ' (' + ISNULL(JSON_VALUE(@j,'$.RolFirmante'),'?') + ')';

/* 5. Transicion de firma */
SET @p = N'{' + @ActorJefe + N',"IdExpediente":"' + @IdExpediente + N'","CodigoTransicion":"CMN_FIRMAR_A3","Version":' + CONVERT(varchar(10), @Version) + N'}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO CMN_FIRMAR_A3: ' + @j; RETURN; END
SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));
PRINT ' PASO 5 - Anexo 3 firmado y remitido a OA. Estado: ' + ISNULL(JSON_VALUE(@j,'$.CodigoEstado'),'?');

/* 7. OA deriva al JEFE de Abastecimiento, y de ahi baja la cadena             */
/* -------------------------------------------------------------------------- */
/* El flujo aprobado entra a Abastecimiento siempre por la jefatura: jefe ->
   coordinador -> especialista. Antes habia un solo salto (CMN_DERIVAR_UA) y por
   eso el especialista no existia en el circuito. */

DECLARE @Tr TABLE (n int IDENTITY(1,1), actor nvarchar(400), codigo varchar(70));
DECLARE @n int, @tot int, @ac nvarchar(400), @cd varchar(70);

INSERT INTO @Tr (actor, codigo) VALUES
    (@ActorOA,   'CMN_OA_DERIVAR'),
    (@ActorAbJe, 'CMN_ABAST_JEFE_DERIVAR'),
    (@ActorAbCo, 'CMN_ABAST_COORD_DERIVAR');

SET @n = 1; SET @tot = (SELECT COUNT(*) FROM @Tr);
WHILE @n <= @tot
BEGIN
    SELECT @ac = actor, @cd = codigo FROM @Tr WHERE n = @n;
    SET @p = N'{' + @ac + N',"IdExpediente":"' + @IdExpediente + N'","CodigoTransicion":"' + @cd + N'","Version":' + CONVERT(varchar(10), @Version) + N'}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO ' + @cd + ': ' + @j; RETURN; END
    SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));
    SET @n = @n + 1;
END

PRINT ' PASO 5 a 7 - Firmado, enviado a OA y bajado hasta el especialista de Abastecimiento.';

/* -------------------------------------------------------------------------- */
/* 8. Conformidad del especialista sobre el Anexo 3                            */
/* -------------------------------------------------------------------------- */
/*
  En Abastecimiento el especialista da conformidad y no firma. Ahi se encola
  ITEMS_ANEXO_3: el item entra a SIGA. El jefe no firma el Anexo 3.
*/

DECLARE @Fi TABLE (n int IDENTITY(1,1), actor nvarchar(400), codigo varchar(70), etiqueta varchar(40), firma bit);
INSERT INTO @Fi (actor, codigo, etiqueta, firma) VALUES
    (@ActorAbEs, 'CMN_ABAST_ESP_FIRMAR_A3', 'especialista', 0);

DECLARE @et varchar(40), @firmaPaso bit;
SET @n = 1; SET @tot = (SELECT COUNT(*) FROM @Fi);
WHILE @n <= @tot
BEGIN
    SELECT @ac = actor, @cd = codigo, @et = etiqueta, @firmaPaso = firma FROM @Fi WHERE n = @n;

    IF @firmaPaso = 1
    BEGIN
        SET @p = N'{' + @ac + N',"IdExpediente":"' + @IdExpediente + N'",
          "CodigoTipoDocumento":"CMN_ANEXO_3_SOLICITUD_MODIFICACION","ArchivoHash":"S901-A3-' + @et + N'"}';
        DELETE FROM @r; INSERT INTO @r EXEC sigcm.paFirmarDocumento @p;
        SELECT @j = j FROM @r;
        IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO firma A3 ' + @et + ': ' + @j; RETURN; END
        PRINT '   Firma del ' + @et + ': documento ' + ISNULL(JSON_VALUE(@j,'$.EstadoDocumento'),'?')
            + ', pendientes=' + ISNULL(JSON_VALUE(@j,'$.FirmasPendientes'),'?');
    END
    ELSE
        PRINT '   ' + @et + ' da conformidad sin firmar.';

    SET @p = N'{' + @ac + N',"IdExpediente":"' + @IdExpediente
           + N'","CodigoTransicion":"' + @cd
           + N'","Version":' + CONVERT(varchar(10), @Version)
           + CASE WHEN @cd = 'CMN_ABAST_ESP_FIRMAR_A3' THEN N',"TipoInclusion":"URGENTE"' ELSE N'' END
           + N'}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO ' + @cd + ': ' + @j; RETURN; END
    SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));
    SET @n = @n + 1;
END

PRINT ' PASO 8 - Anexo 3 conforme. Operaciones encoladas hacia SIGA: '
    + ISNULL(JSON_VALUE(@j,'$.OperacionesEncoladas'),'0');

/* -------------------------------------------------------------------------- */
/* 9. Drenar la cola EN MODO REAL: primer momento de escritura en SIGA */
SET @p = N'{"Actor":{"Usuario":"S901","Equipo":"S901","Programa":"S901"},"Modo":"real","Limite":50}';
DELETE FROM @r; INSERT INTO @r EXEC integracion.paEscribirCuadroModificado @p;
SELECT @j = j FROM @r;
PRINT ' PASO 9 - W001 (real) tras el Anexo 3: escritas='
    + ISNULL(JSON_VALUE(@j,'$.Escritas'),'?') + ' errores=' + ISNULL(JSON_VALUE(@j,'$.ConError'),'?');
IF ISNULL(JSON_VALUE(@j,'$.ConError'),'1') <> '0'
BEGIN
    PRINT '   DETALLE: ' + @j;
    RETURN;
END

/* -------------------------------------------------------------------------- */
/* COMPROBACION INTERMEDIA: el item existe en SIGA pero NO es pedible          */
/* -------------------------------------------------------------------------- */

DECLARE @SecCuadro bigint, @SecItem bigint;
SELECT TOP 1 @SecCuadro = m.SecCuadro, @SecItem = m.SecItem
  FROM integracion.MapeoCmn AS m
 WHERE m.IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolicitud);

IF @SecItem IS NULL BEGIN PRINT ' FALLO: no quedo mapeo hacia SIGA.'; RETURN; END

PRINT '';
PRINT '===========================================================';
PRINT ' DESPUES DEL ANEXO 3';
PRINT '===========================================================';
PRINT '  SIGA: cuadro ' + CONVERT(varchar(20), @SecCuadro)
    + ' / item ' + CONVERT(varchar(20), @SecItem);

SELECT etapa = 'Anexo 3 validado', d.ANNO_PROG, d.ESTADO, d.PROCEDENCIA,
       d.FLAG_MODIFICADO, d.MOTIVO_SOLICITUD, d.CANT_TOTAL, d.MNTO_TOTAL
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC=@AnoEje AND d.SEC_EJEC=@SecEjec AND d.CENTRO_COSTO=@CentroCosto
   AND d.SEC_CUADRO=@SecCuadro AND d.SEC_ITEM=@SecItem
 ORDER BY d.ANNO_PROG;

SELECT etapa = 'Anexo 3 validado',
       pedible_en_siga = COUNT(*)
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC=@AnoEje AND d.SEC_EJEC=@SecEjec AND d.CENTRO_COSTO=@CentroCosto
   AND d.SEC_CUADRO=@SecCuadro AND d.SEC_ITEM=@SecItem AND d.ANNO_PROG=@AnoEje
   AND d.MOTIVO_SOLICITUD IN ('0','3') AND d.ESTADO NOT IN ('E','ET','IC')
   AND EXISTS (SELECT 1 FROM siga.SIG_CUADRO_MODIFICADO_SALDO AS s
                WHERE s.SEC_EJEC=d.SEC_EJEC AND s.ANNO_EJEC=d.ANNO_EJEC
                  AND s.SEC_CUA_MOD_SAL=d.SEC_CUA_MOD_SAL
                  AND (s.CANT_TOTAL - s.CANT_TOTAL_CMN) > 0);

IF @SoloAnexo3 = 1
BEGIN
    PRINT '';
    PRINT '===========================================================';
    PRINT ' ALTO PEDIDO: se detiene con la solicitud ABIERTA';
    PRINT '===========================================================';
    PRINT '  El item quedo con MOTIVO_SOLICITUD=1, o sea con demanda';
    PRINT '  adicional en curso. Asi es como se ve en el aplicativo:';
    PRINT '';
    PRINT '    Logistica -> Programacion -> Programacion del C.M.N.';
    PRINT '      -> Bienes, Servicios y Obras';
    PRINT '    Anio 2026, area usuaria ' + @CentroCosto;
    PRINT '    Boton "Demanda Adicional - Identificacion"';
    PRINT '    Tipo: Servicio';
    PRINT '';
    PRINT '  SEC_CUADRO = ' + CONVERT(varchar(20), @SecCuadro)
        + '   SEC_ITEM = ' + CONVERT(varchar(20), @SecItem);
    PRINT '  Expediente = ' + @Codigo;
    PRINT '';
    PRINT '  Para cerrarlo despues:  S902 con @CodigoExpediente = ''' + @Codigo + '''';
    RETURN;
END

/* -------------------------------------------------------------------------- */
/* 10 a 13. Anexo 4                                                            */
/* -------------------------------------------------------------------------- */
/*
  El Anexo 4 ya no nace de una transicion sobre el expediente: lo arma el
  especialista con cmn.paGenerarAnexo4, que emite su codigo propio y reserva las
  solicitudes. Aqui va uno solo; el caso de varias areas usuarias lo cubre S903.
*/

DECLARE @IdPaquete varchar(50), @CodigoA4 varchar(40);

SET @p = N'{' + @ActorAbEs + N',"IdSolicitudes":["' + @IdSolicitud + N'"],
  "Sustento":"Prueba S901: aprobacion de la modificacion."}';
DELETE FROM @r; INSERT INTO @r EXEC cmn.paGenerarAnexo4 @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO paGenerarAnexo4: ' + @j; RETURN; END
SET @IdPaquete = JSON_VALUE(@j,'$.IdPaquete');
SET @CodigoA4  = JSON_VALUE(@j,'$.Codigo');
PRINT '';
PRINT ' PASO 10 - Anexo 4 ' + @CodigoA4 + ' generado con '
    + ISNULL(JSON_VALUE(@j,'$.TotalSolicitudes'),'?') + ' Anexo(s) 3 y '
    + ISNULL(JSON_VALUE(@j,'$.TotalItems'),'?') + ' item(s).';

/* El documento lleva el numero del PAQUETE, no el del expediente: es lo que
   permite que un mismo Anexo 4 cubra varios. */
SET @p = N'{' + @ActorAbEs + N',"IdExpedientes":["' + @IdExpediente + N'"],
  "CodigoTipoDocumento":"CMN_ANEXO_4_APROBACION_MODIFICACION",
  "Numero":"' + @CodigoA4 + N'",
  "GeneradoDocumento":"http://localhost/files/cmn/' + @CodigoA4 + N'.pdf",
  "NombreDocumento":"Anexo 4 - ' + @CodigoA4 + N'.pdf",
  "ArchivoHash":"S901-A4"}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paRegistrarDocumento @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO registrar A4: ' + @j; RETURN; END
PRINT ' PASO 11 - PDF del Anexo 4 registrado en version ' + ISNULL(JSON_VALUE(@j,'$.Version'),'?');

/* Elevacion del Anexo 4; solo el jefe firma. */
DECLARE @F4 TABLE (n int IDENTITY(1,1), actor nvarchar(400), codigo varchar(70), etiqueta varchar(40), firma bit);
INSERT INTO @F4 (actor, codigo, etiqueta, firma) VALUES
    (@ActorAbEs, 'CMN_GENERAR_A4',            'especialista', 0),
    (@ActorAbJe, 'CMN_ABAST_JEFE_FIRMAR_A4',  'jefe',         1);

SET @n = 1; SET @tot = (SELECT COUNT(*) FROM @F4);
WHILE @n <= @tot
BEGIN
    SELECT @ac = actor, @cd = codigo, @et = etiqueta, @firmaPaso = firma FROM @F4 WHERE n = @n;

    IF @firmaPaso = 1
    BEGIN
        SET @p = N'{' + @ac + N',"IdExpediente":"' + @IdExpediente + N'",
          "CodigoTipoDocumento":"CMN_ANEXO_4_APROBACION_MODIFICACION","ArchivoHash":"S901-A4-' + @et + N'"}';
        DELETE FROM @r; INSERT INTO @r EXEC sigcm.paFirmarDocumento @p;
        SELECT @j = j FROM @r;
        IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO firma A4 ' + @et + ': ' + @j; RETURN; END
        PRINT '   Firma del ' + @et + ': documento ' + ISNULL(JSON_VALUE(@j,'$.EstadoDocumento'),'?')
            + ', pendientes=' + ISNULL(JSON_VALUE(@j,'$.FirmasPendientes'),'?');
    END
    ELSE
        PRINT '   ' + @et + ' eleva el Anexo 4 sin firmar.';

    SET @p = N'{' + @ac + N',"IdExpediente":"' + @IdExpediente
           + N'","CodigoTransicion":"' + @cd
           + N'","Version":' + CONVERT(varchar(10), @Version) + N'}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO ' + @cd + ': ' + @j; RETURN; END
    SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));
    SET @n = @n + 1;
END

PRINT ' PASO 12 y 13 - Anexo 4 firmado por el jefe. Operaciones encoladas: '
    + ISNULL(JSON_VALUE(@j,'$.OperacionesEncoladas'),'0');

/* 14. Drenar: segundo momento de escritura en SIGA */
SET @p = N'{"Actor":{"Usuario":"S901","Equipo":"S901","Programa":"S901"},"Modo":"real","Limite":50}';
DELETE FROM @r; INSERT INTO @r EXEC integracion.paEscribirCuadroModificado @p;
SELECT @j = j FROM @r;
PRINT ' PASO 14 - W001 (real) tras el Anexo 4: escritas='
    + ISNULL(JSON_VALUE(@j,'$.Escritas'),'?') + ' errores=' + ISNULL(JSON_VALUE(@j,'$.ConError'),'?');
IF ISNULL(JSON_VALUE(@j,'$.ConError'),'1') <> '0'
BEGIN
    PRINT '   DETALLE: ' + @j;
    RETURN;
END

/* -------------------------------------------------------------------------- */
/* COMPROBACION FINAL                                                          */
/* -------------------------------------------------------------------------- */

PRINT '';
PRINT '===========================================================';
PRINT ' DESPUES DEL ANEXO 4';
PRINT '===========================================================';

SELECT etapa = 'Anexo 4 firmado', d.ANNO_PROG, d.ESTADO, d.PROCEDENCIA,
       d.FLAG_MODIFICADO, d.MOTIVO_SOLICITUD, d.CANT_TOTAL, d.MNTO_TOTAL, d.CUSER_MOD
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC=@AnoEje AND d.SEC_EJEC=@SecEjec AND d.CENTRO_COSTO=@CentroCosto
   AND d.SEC_CUADRO=@SecCuadro AND d.SEC_ITEM=@SecItem
 ORDER BY d.ANNO_PROG;

SELECT etapa = 'Anexo 4 firmado',
       pedible_en_siga = COUNT(*)
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC=@AnoEje AND d.SEC_EJEC=@SecEjec AND d.CENTRO_COSTO=@CentroCosto
   AND d.SEC_CUADRO=@SecCuadro AND d.SEC_ITEM=@SecItem AND d.ANNO_PROG=@AnoEje
   AND d.MOTIVO_SOLICITUD IN ('0','3') AND d.ESTADO NOT IN ('E','ET','IC')
   AND EXISTS (SELECT 1 FROM siga.SIG_CUADRO_MODIFICADO_SALDO AS s
                WHERE s.SEC_EJEC=d.SEC_EJEC AND s.ANNO_EJEC=d.ANNO_EJEC
                  AND s.SEC_CUA_MOD_SAL=d.SEC_CUA_MOD_SAL
                  AND (s.CANT_TOTAL - s.CANT_TOTAL_CMN) > 0);

/* -------------------------------------------------------------------------- */
/* Como verlo en el aplicativo                                                 */
/* -------------------------------------------------------------------------- */

DECLARE @SecSol varchar(20) = (
    SELECT TOP 1 JSON_VALUE(m.PayloadRespuesta, '$.SecSolicitud')
      FROM integracion.MapeoCmn AS m
     WHERE m.IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolicitud));

PRINT '';
PRINT '===========================================================';
PRINT ' COMO VERLO EN EL APLICATIVO SIGA';
PRINT '===========================================================';
PRINT '  Modulo Logistica';
PRINT '    -> Programacion';
PRINT '       -> Programacion del C.M.N.';
PRINT '          -> Bienes, Servicios y Obras';
PRINT '';
PRINT '  Anio          : 2026';
PRINT '  Area usuaria  : ' + @CentroCosto + '  (OTI)';
PRINT '  Boton         : Demanda Adicional - Identificacion';
PRINT '';
PRINT '  El item registrado desde el SIGCM es:';
PRINT '    SEC_CUADRO      = ' + CONVERT(varchar(20), @SecCuadro);
PRINT '    SEC_ITEM        = ' + CONVERT(varchar(20), @SecItem);
PRINT '    Solicitud SIGA  = ' + ISNULL(@SecSol, '(sin numero)');
PRINT '    Catalogo        = S-' + @GrupoBien + '-' + @ClaseBien + '-' + @FamiliaBien + '-' + @ItemBien;
PRINT '    Cantidad        = 4000 (1000 en cada mes de setiembre a diciembre)';
PRINT '    Expediente SIGCM= ' + @Codigo;
PRINT '';
PRINT '  Consulta de conciliacion:';
PRINT '    SELECT * FROM dbo.SIG_CUADRO_MODIFICADO_DET';
PRINT '     WHERE ANNO_EJEC=2026 AND SEC_EJEC=1750 AND CENTRO_COSTO=''' + @CentroCosto + '''';
PRINT '       AND SEC_CUADRO=' + CONVERT(varchar(20), @SecCuadro)
    + ' AND SEC_ITEM=' + CONVERT(varchar(20), @SecItem) + ';';
GO


