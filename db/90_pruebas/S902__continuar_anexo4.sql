/*
===============================================================================
  SIGCM - S902 : Continuar un expediente CMN desde el Anexo 4
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]  (escribe en SIGA_1750 a traves de W001)

  Toma un expediente que ya paso por la firma del jefe de Abastecimiento sobre
  el Anexo 3 -es decir, cuyos items ya
  estan en SIG_CUADRO_MODIFICADO_DET con la solicitud abierta- y lo lleva hasta
  la firma del Anexo 4, que es lo que aprueba la solicitud en SIGA y deja el
  item disponible para pedir.

  Sirve para retomar una corrida de S901 que se interrumpio, y para probar el
  Anexo 4 por separado sin volver a registrar todo.

  CONFIRMA. No se revierte.

  Uso: cambiar @CodigoExpediente y ejecutar.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @CodigoExpediente varchar(40) = 'CMN-2026-000009';

DECLARE @r TABLE (j nvarchar(max));
DECLARE @j nvarchar(max), @p nvarchar(max);
DECLARE @IdExpediente varchar(50), @IdSolicitud varchar(50);
DECLARE @Version int, @Estado varchar(60), @CentroCosto varchar(15);
DECLARE @SecCuadro bigint, @SecItem bigint, @SecSol varchar(20);

DECLARE @ActorAbEs nvarchar(400) = N'"Actor":{"Usuario":"prueba.abast.esp","Rol":"ABAST_ESPECIALISTA","Unidad":"UO-ABAST","Equipo":"S902","Programa":"S902"}';
DECLARE @ActorAbCo nvarchar(400) = N'"Actor":{"Usuario":"prueba.abastecim","Rol":"ABAST_COORDINADOR","Unidad":"UO-ABAST","Equipo":"S902","Programa":"S902"}';
DECLARE @ActorAbJe nvarchar(400) = N'"Actor":{"Usuario":"prueba.abast.jefe","Rol":"ABAST_JEFE","Unidad":"UO-ABAST","Equipo":"S902","Programa":"S902"}';

SELECT @IdExpediente = CONVERT(varchar(50), e.IdExpediente),
       @Version      = e.Version,
       @Estado       = e.CodigoEstado
  FROM sigcm.Expediente AS e
 WHERE e.Codigo = @CodigoExpediente AND e.Anulado = 0;

IF @IdExpediente IS NULL
BEGIN
    RAISERROR('No existe el expediente %s.', 16, 1, @CodigoExpediente);
    RETURN;
END

SELECT @IdSolicitud = CONVERT(varchar(50), s.IdSolicitud), @CentroCosto = s.CentroCosto
  FROM cmn.Solicitud AS s
 WHERE s.IdExpediente = TRY_CONVERT(uniqueidentifier, @IdExpediente) AND s.Activo = 1;

SELECT TOP 1 @SecCuadro = m.SecCuadro, @SecItem = m.SecItem,
             @SecSol = JSON_VALUE(m.PayloadRespuesta, '$.SecSolicitud')
  FROM integracion.MapeoCmn AS m
 WHERE m.IdSolicitud = TRY_CONVERT(uniqueidentifier, @IdSolicitud);

PRINT '===========================================================';
PRINT ' ' + @CodigoExpediente + '   estado: ' + @Estado + '   version: ' + CONVERT(varchar(10), @Version);
PRINT ' Centro de costo: ' + ISNULL(@CentroCosto, '?');
PRINT ' En SIGA: cuadro ' + ISNULL(CONVERT(varchar(20), @SecCuadro), '?')
    + ' / item ' + ISNULL(CONVERT(varchar(20), @SecItem), '?')
    + ' / solicitud ' + ISNULL(@SecSol, '?');
PRINT '===========================================================';

IF @SecItem IS NULL
BEGIN
    RAISERROR('El expediente no tiene items registrados en SIGA. Falta validar el Anexo 3.', 16, 1);
    RETURN;
END

/* -------------------------------------------------------------------------- */
/* Estado en SIGA ANTES del Anexo 4                                            */
/* -------------------------------------------------------------------------- */

SELECT etapa = '1. antes del Anexo 4', d.ANNO_PROG, d.ESTADO, d.PROCEDENCIA,
       d.FLAG_MODIFICADO, d.MOTIVO_SOLICITUD, d.CANT_TOTAL, d.MNTO_TOTAL
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC=2026 AND d.SEC_EJEC=1750 AND d.CENTRO_COSTO=@CentroCosto
   AND d.SEC_CUADRO=@SecCuadro AND d.SEC_ITEM=@SecItem
 ORDER BY d.ANNO_PROG;

SELECT etapa = '1. antes del Anexo 4', pedible_en_siga = COUNT(*)
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC=2026 AND d.SEC_EJEC=1750 AND d.CENTRO_COSTO=@CentroCosto
   AND d.SEC_CUADRO=@SecCuadro AND d.SEC_ITEM=@SecItem AND d.ANNO_PROG=2026
   AND d.MOTIVO_SOLICITUD IN ('0','3') AND d.ESTADO NOT IN ('E','ET','IC')
   AND EXISTS (SELECT 1 FROM siga.SIG_CUADRO_MODIFICADO_SALDO AS s
                WHERE s.SEC_EJEC=d.SEC_EJEC AND s.ANNO_EJEC=d.ANNO_EJEC
                  AND s.SEC_CUA_MOD_SAL=d.SEC_CUA_MOD_SAL
                  AND (s.CANT_TOTAL - s.CANT_TOTAL_CMN) > 0);

/* -------------------------------------------------------------------------- */
/* Anexo 4                                                                     */
/* -------------------------------------------------------------------------- */

/*
  El expediente tiene que estar en CMN_A3_APROBADO: el Anexo 3 ya lleva sus
  cuatro firmas y sus items ya entraron a SIGA como demanda adicional en curso.
*/
IF @Estado <> 'CMN_A3_APROBADO'
BEGIN
    PRINT ' El expediente esta en ' + @Estado + ' y S902 solo continua desde CMN_A3_APROBADO.';
    RETURN;
END

/* @IdSolicitud ya viene resuelto desde la cabecera del script. */
DECLARE @IdPaquete varchar(50), @CodigoA4 varchar(40);

SET @p = N'{' + @ActorAbEs + N',"IdSolicitudes":["' + @IdSolicitud + N'"],
  "Sustento":"Prueba S902: aprobacion de la modificacion."}';
DELETE FROM @r; INSERT INTO @r EXEC cmn.paGenerarAnexo4 @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO paGenerarAnexo4: ' + @j; RETURN; END
SET @IdPaquete = JSON_VALUE(@j,'$.IdPaquete');
SET @CodigoA4  = JSON_VALUE(@j,'$.Codigo');
PRINT ' PASO 1 - Anexo 4 ' + @CodigoA4 + ' generado.';

/* El PDF lo arma el frontend; aqui se registra su URL y su huella. Lleva el
   numero del paquete porque un Anexo 4 puede cubrir varios expedientes. */
SET @p = N'{' + @ActorAbEs + N',"IdExpedientes":["' + @IdExpediente + N'"],
  "CodigoTipoDocumento":"CMN_ANEXO_4_APROBACION_MODIFICACION",
  "Numero":"' + @CodigoA4 + N'",
  "GeneradoDocumento":"http://localhost/files/cmn/' + @CodigoA4 + N'.pdf",
  "NombreDocumento":"Anexo 4 - ' + @CodigoA4 + N'.pdf",
  "ArchivoHash":"S902-A4"}';
DELETE FROM @r; INSERT INTO @r EXEC sigcm.paRegistrarDocumento @p;
SELECT @j = j FROM @r;
IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO registrar A4: ' + @j; RETURN; END
PRINT ' PASO 2 - PDF del Anexo 4 registrado en version ' + ISNULL(JSON_VALUE(@j,'$.Version'),'?');

/*
  Las tres firmas del Anexo 4. Hoy cada una es un asiento: queda constancia de
  quien firmo y cuando, y la version del documento no se cierra hasta la ultima.
  Cuando entre el firmador institucional, el PDF firmado y su huella llegan por
  GeneradoDocumento y ArchivoHash, y no cambia nada mas.
*/
DECLARE @F4 TABLE (n int IDENTITY(1,1), actor nvarchar(400), codigo varchar(70), etiqueta varchar(40));
INSERT INTO @F4 (actor, codigo, etiqueta) VALUES
    (@ActorAbEs, 'CMN_GENERAR_A4',            'especialista'),
    (@ActorAbJe, 'CMN_ABAST_JEFE_FIRMAR_A4',  'jefe');

DECLARE @n int = 1, @tot int = (SELECT COUNT(*) FROM @F4);
DECLARE @ac nvarchar(400), @cd varchar(70), @et varchar(40);

WHILE @n <= @tot
BEGIN
    SELECT @ac = actor, @cd = codigo, @et = etiqueta FROM @F4 WHERE n = @n;

    IF @cd <> 'CMN_GENERAR_A4'
    BEGIN
        SET @p = N'{' + @ac + N',"IdExpediente":"' + @IdExpediente + N'",
          "CodigoTipoDocumento":"CMN_ANEXO_4_APROBACION_MODIFICACION","ArchivoHash":"S902-A4-' + @et + N'"}';
        DELETE FROM @r; INSERT INTO @r EXEC sigcm.paFirmarDocumento @p;
        SELECT @j = j FROM @r;
        IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO firma A4 ' + @et + ': ' + @j; RETURN; END
        PRINT '   Firma del ' + @et + ': documento ' + ISNULL(JSON_VALUE(@j,'$.EstadoDocumento'),'?')
            + ', pendientes=' + ISNULL(JSON_VALUE(@j,'$.FirmasPendientes'),'?');
    END

    SET @p = N'{' + @ac + N',"IdExpediente":"' + @IdExpediente
           + N'","CodigoTransicion":"' + @cd
           + N'","Version":' + CONVERT(varchar(10), @Version) + N'}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1' BEGIN PRINT ' FALLO ' + @cd + ': ' + @j; RETURN; END
    SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));
    SET @n = @n + 1;
END

PRINT ' PASO 3 y 4 - Anexo 4 firmado por los tres. Estado: ' + JSON_VALUE(@j,'$.CodigoEstado')
    + '. Operaciones encoladas: ' + ISNULL(JSON_VALUE(@j,'$.OperacionesEncoladas'),'0');

/* Segundo momento de escritura en SIGA. */
SET @p = N'{"Actor":{"Usuario":"S902","Equipo":"S902","Programa":"S902"},"Modo":"real","Limite":50}';
DELETE FROM @r; INSERT INTO @r EXEC integracion.paEscribirCuadroModificado @p;
SELECT @j = j FROM @r;
PRINT ' PASO 5 - W001 (real): escritas=' + ISNULL(JSON_VALUE(@j,'$.Escritas'),'?')
    + ' errores=' + ISNULL(JSON_VALUE(@j,'$.ConError'),'?');
IF ISNULL(JSON_VALUE(@j,'$.ConError'),'1') <> '0'
BEGIN
    PRINT '   DETALLE: ' + @j;
    RETURN;
END

/* -------------------------------------------------------------------------- */
/* Estado en SIGA DESPUES del Anexo 4                                          */
/* -------------------------------------------------------------------------- */

SELECT etapa = '2. despues del Anexo 4', d.ANNO_PROG, d.ESTADO, d.PROCEDENCIA,
       d.FLAG_MODIFICADO, d.MOTIVO_SOLICITUD, d.CANT_TOTAL, d.MNTO_TOTAL, d.CUSER_MOD
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC=2026 AND d.SEC_EJEC=1750 AND d.CENTRO_COSTO=@CentroCosto
   AND d.SEC_CUADRO=@SecCuadro AND d.SEC_ITEM=@SecItem
 ORDER BY d.ANNO_PROG;

SELECT etapa = '2. despues del Anexo 4', pedible_en_siga = COUNT(*)
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_EJEC=2026 AND d.SEC_EJEC=1750 AND d.CENTRO_COSTO=@CentroCosto
   AND d.SEC_CUADRO=@SecCuadro AND d.SEC_ITEM=@SecItem AND d.ANNO_PROG=2026
   AND d.MOTIVO_SOLICITUD IN ('0','3') AND d.ESTADO NOT IN ('E','ET','IC')
   AND EXISTS (SELECT 1 FROM siga.SIG_CUADRO_MODIFICADO_SALDO AS s
                WHERE s.SEC_EJEC=d.SEC_EJEC AND s.ANNO_EJEC=d.ANNO_EJEC
                  AND s.SEC_CUA_MOD_SAL=d.SEC_CUA_MOD_SAL
                  AND (s.CANT_TOTAL - s.CANT_TOTAL_CMN) > 0);

PRINT '';
PRINT '===========================================================';
PRINT ' COMO VERLO EN EL APLICATIVO SIGA';
PRINT '===========================================================';
PRINT '  Modulo Logistica -> Programacion -> Modificacion de C.M.N.';
PRINT '     -> Bienes, Servicios y Obras';
PRINT '  Anio 2026, area usuaria ' + @CentroCosto;
PRINT '  Tipo: Servicio';
PRINT '';
PRINT '  Con el Anexo 4 ya firmado el item NO esta en "Demanda Adicional -';
PRINT '  Identificacion": al pasar a MOTIVO_SOLICITUD=0 dejo de ser demanda';
PRINT '  en curso. Buscarlo ahi y no encontrarlo es lo esperado.';
PRINT '';
PRINT '  SEC_CUADRO = ' + CONVERT(varchar(20), @SecCuadro)
    + '   SEC_ITEM = ' + CONVERT(varchar(20), @SecItem)
    + '   Solicitud SIGA = ' + ISNULL(@SecSol, '?');
GO

