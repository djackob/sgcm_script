/*
===============================================================================
  SIGCM - S915 : Prueba de Modificacion-Ampliacion sobre el contrato de S914
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750

  FUERA DE LA SERIE. Se apoya en el contrato REQ-PRU-EJEC-0001 que deja S914
  (correr S914 antes). Limpia sus propias solicitudes y las rehace, y devuelve
  la fecha de fin del contrato a su valor original para ser repetible.

  ---------------------------------------------------------------------------
  QUE PRUEBA (Directiva 7.3.4 y 7.3.5)
  ---------------------------------------------------------------------------
  A. Ampliacion de plazo pedida por el proveedor, EN PLAZO (hecho generador
     hace 3 dias): DEC remite al AU -> AU opina PROCEDE -> DEC aprueba 5 de
     los 8 dias pedidos -> el contrato corre 5 dias y su plazo queda ampliado.
     Termina en AMP_APROBADA.
  B. Ampliacion FUERA DE PLAZO (hecho generador hace 20 dias): la DEC la
     deniega sin pedir opinion (7.3.5.3). Termina en AMP_DENEGADA.
     Se registra despues de cerrar la A, porque no puede haber dos abiertas.
  C. Modificacion iniciada por el AU: sustento -> jefe remite -> DEC declara
     procedente -> jefe de Abastecimiento registra, firma el acta -> el
     proveedor la suscribe. Termina en MOD_APROBADA.
  D. Intento de denegar una ampliacion con el plazo de 7 dias habiles ya
     vencido: DEBE fallar con CONFLICTO_PLAZO (7.3.5.4). Se simula moviendo
     el vencimiento del plazo hacia atras.

  Actores: los usuarios de prueba de S900.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Codigo varchar(40) = 'REQ-PRU-EJEC-0001';
DECLARE @Ahora datetime = GETDATE(), @Hoy date = CONVERT(date, GETDATE());

DECLARE @IdContrato uniqueidentifier, @IdExpContrato uniqueidentifier, @FechaFinOriginal date, @PlazoOriginal int;
SELECT @IdContrato = c.IdContrato, @IdExpContrato = c.IdExpediente, @FechaFinOriginal = c.FechaFinPrevista, @PlazoOriginal = c.PlazoDias
  FROM ejecucion.Contrato AS c WHERE c.CodigoRequerimiento = @Codigo AND c.Activo = 1;
IF @IdContrato IS NULL THROW 59150, 'NO_ENCONTRADO: no existe el contrato de REQ-PRU-EJEC-0001. Corre S914 primero.', 1;
IF OBJECT_ID('ampliacion.Solicitud', 'U') IS NULL THROW 59151, 'FALTA_MIGRACION: no existe ampliacion.Solicitud. Corre instalar.ps1.', 1;

DECLARE @CodigoUnidad varchar(30), @CodigoUnidadDec varchar(30), @CodigoUnidadLoc varchar(30);
SELECT @CodigoUnidad = un.Codigo FROM sigcm.Expediente AS e JOIN sigcm.Unidad AS un ON un.IdUnidad = e.IdUnidadOrigen WHERE e.IdExpediente = @IdExpContrato;
SELECT @CodigoUnidadDec = un.Codigo FROM sigcm.UsuarioRol AS ur JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario JOIN sigcm.Unidad AS un ON un.IdUnidad = ur.IdUnidad
 WHERE u.Cuenta = 'prueba.abast.esp' AND ur.CodigoRol = 'ABAST_ESPECIALISTA' AND ur.Activo = 1;
SELECT @CodigoUnidadLoc = un.Codigo FROM sigcm.UsuarioRol AS ur JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario JOIN sigcm.Unidad AS un ON un.IdUnidad = ur.IdUnidad
 WHERE u.Cuenta = 'prueba.locador' AND ur.CodigoRol = 'PROVEEDOR' AND ur.Activo = 1;

DECLARE @ActorEsp  nvarchar(max) = (SELECT Usuario = 'prueba.oti.esp',   Rol = 'AREA_ESPECIALISTA',  Unidad = @CodigoUnidad    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorJefe nvarchar(max) = (SELECT Usuario = 'prueba.oti.jefe',  Rol = 'AREA_JEFE',          Unidad = @CodigoUnidad    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorDec  nvarchar(max) = (SELECT Usuario = 'prueba.abast.esp', Rol = 'ABAST_ESPECIALISTA', Unidad = @CodigoUnidadDec FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorDecJ nvarchar(max) = (SELECT Usuario = 'prueba.abast.jefe',Rol = 'ABAST_JEFE',         Unidad = @CodigoUnidadDec FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorLoc  nvarchar(max) = (SELECT Usuario = 'prueba.locador',   Rol = 'PROVEEDOR',          Unidad = @CodigoUnidadLoc FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

/* -------------------------------------------------------------------------- */
/* 1. Limpieza: las solicitudes de este contrato y la fecha de fin            */
/* -------------------------------------------------------------------------- */

BEGIN TRANSACTION;
DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY);
INSERT INTO @Exp SELECT IdExpediente FROM ampliacion.Solicitud WHERE IdContrato = @IdContrato;
IF EXISTS (SELECT 1 FROM @Exp)
BEGIN
    DECLARE @Doc TABLE (IdDocumento uniqueidentifier PRIMARY KEY);
    INSERT INTO @Doc SELECT DISTINCT de.IdDocumento FROM sigcm.DocumentoExpediente AS de JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;
    DELETE f FROM sigcm.Firma AS f JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumentoVersion = f.IdDocumentoVersion JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
    DELETE o FROM sigcm.Observacion AS o JOIN @Exp AS x ON x.IdExpediente = o.IdExpediente;
    DELETE dv FROM sigcm.DocumentoVersion AS dv JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
    DELETE de FROM sigcm.DocumentoExpediente AS de JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;
    DELETE doc FROM sigcm.Documento AS doc JOIN @Doc AS d ON d.IdDocumento = doc.IdDocumento;
    DELETE pl FROM sigcm.Plazo AS pl JOIN @Exp AS x ON x.IdExpediente = pl.IdExpediente;
    DELETE h FROM sigcm.Historial AS h JOIN @Exp AS x ON x.IdExpediente = h.IdExpediente;
    DELETE FROM ampliacion.Solicitud WHERE IdContrato = @IdContrato;
    DELETE e FROM sigcm.Expediente AS e JOIN @Exp AS x ON x.IdExpediente = e.IdExpediente;
END
/* La corrida anterior pudo haber corrido la fecha de fin: se vuelve al valor
   de apertura, que es inicio + plazo original de S914 (30 dias). */
UPDATE c SET FechaFinPrevista = DATEADD(DAY, 29, c.FechaInicio), PlazoDias = 30
  FROM ejecucion.Contrato AS c WHERE c.IdContrato = @IdContrato;
UPDATE sigcm.Plazo SET AmpliadoHasta = NULL, MotivoAmpliacion = NULL
 WHERE IdExpediente = @IdExpContrato AND CodigoRegla = 'EJE_EJECUCION_CONTRATO' AND Activo = 1;
DELETE h FROM sigcm.Historial AS h WHERE h.IdExpediente = @IdExpContrato AND h.Comentario LIKE N'Plazo ampliado en %';
COMMIT TRANSACTION;

SELECT @FechaFinOriginal = FechaFinPrevista FROM ejecucion.Contrato WHERE IdContrato = @IdContrato;

DECLARE @p nvarchar(max);
DECLARE @t TABLE (j nvarchar(max));
DECLARE @Res TABLE (Paso varchar(90), Respuesta nvarchar(max));
DECLARE @IdExp uniqueidentifier;

/* -------------------------------------------------------------------------- */
/* A. Ampliacion en plazo: remite -> AU opina -> DEC aprueba 5 de 8 dias      */
/* -------------------------------------------------------------------------- */

SET @p = (SELECT Actor = JSON_QUERY(@ActorLoc), IdContrato = CONVERT(varchar(50), @IdContrato), Tipo = 'AMPLIACION_PLAZO',
                 Asunto = 'Ampliacion por demora en la importacion de los equipos', Sustento = 'El fabricante retraso el embarque; se adjunta carta del proveedor internacional.',
                 FechaFinHechoGenerador = CONVERT(varchar(10), DATEADD(DAY, -3, @Hoy), 23), DiasSolicitados = 8,
                 SolicitudDocumento = 'PRUEBA-CARTA-AMP-1.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paRegistrarSolicitud @p;
INSERT INTO @Res SELECT 'A1. Proveedor solicita ampliacion (en plazo)', j FROM @t;
SET @IdExp = (SELECT TOP 1 TRY_CONVERT(uniqueidentifier, JSON_VALUE(j, '$.IdExpediente')) FROM @t);
IF @IdExp IS NULL THROW 59152, 'No se registro la ampliacion A.', 1;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExp), CodigoTransicion = 'AMP_REMITIR_AU' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paEjecutarAccion @p;
INSERT INTO @Res SELECT 'A2. DEC remite al AU', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdExpediente = CONVERT(varchar(50), @IdExp), Resultado = 'PROCEDE',
                 Informe = 'El retraso no es imputable al contratista; se recomienda otorgar 5 dias.', InformeDocumento = 'PRUEBA-INF-AMP-1.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paOpinarAu @p;
INSERT INTO @Res SELECT 'A3. AU opina PROCEDE', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExp), Resultado = 'APROBADA', DiasOtorgados = 5,
                 Motivo = 'Se otorgan 5 dias conforme a la opinion tecnica del area usuaria.', CartaDocumento = 'PRUEBA-CARTA-RESP-AMP-1.pdf', NumeroCarta = 'CARTA-001-2026-DEC' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paDecidirDec @p;
INSERT INTO @Res SELECT 'A4. DEC aprueba 5 dias', j FROM @t;

/* Notificacion simulada (el correo lo manda el puente; aqui solo la marca). */
SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExp), ResultadoCorreo = 'Simulado por S915', CorreoEnviado = 'true' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paMarcarNotificada @p;
INSERT INTO @Res SELECT 'A5. Marcar notificada', j FROM @t;

/* -------------------------------------------------------------------------- */
/* B. Ampliacion fuera de plazo: la DEC deniega directo                       */
/* -------------------------------------------------------------------------- */

SET @p = (SELECT Actor = JSON_QUERY(@ActorLoc), IdContrato = CONVERT(varchar(50), @IdContrato), Tipo = 'AMPLIACION_PLAZO',
                 Asunto = 'Ampliacion por lluvias', Sustento = 'Lluvias en la ruta.',
                 FechaFinHechoGenerador = CONVERT(varchar(10), DATEADD(DAY, -20, @Hoy), 23), DiasSolicitados = 4 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paRegistrarSolicitud @p;
INSERT INTO @Res SELECT 'B1. Proveedor solicita ampliacion (fuera de plazo)', j FROM @t;
DECLARE @IdExpB uniqueidentifier = (SELECT TOP 1 TRY_CONVERT(uniqueidentifier, JSON_VALUE(j, '$.IdExpediente')) FROM @t);

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpB), Resultado = 'DENEGADA',
                 Motivo = 'Presentada fuera de los diez dias habiles del hecho generador (7.3.5.3).' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paDecidirDec @p;
INSERT INTO @Res SELECT 'B2. DEC deniega sin opinion del AU', j FROM @t;

/* -------------------------------------------------------------------------- */
/* C. Modificacion iniciada por el AU, con acta firmada y suscrita            */
/* -------------------------------------------------------------------------- */

SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdContrato = CONVERT(varchar(50), @IdContrato), Tipo = 'MODIFICACION',
                 Asunto = 'Cambio del lugar de entrega del lote 2', Sustento = 'La sede de destino cambio por reubicacion de la oficina.',
                 DetalleModificacion = 'La clausula de lugar de entrega pasa de Sede Central a la sede de Arequipa. No varia el monto.' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paRegistrarSolicitud @p;
INSERT INTO @Res SELECT 'C1. AU inicia la modificacion', j FROM @t;
DECLARE @IdExpC uniqueidentifier = (SELECT TOP 1 TRY_CONVERT(uniqueidentifier, JSON_VALUE(j, '$.IdExpediente')) FROM @t);
IF @IdExpC IS NULL THROW 59153, 'No se registro la modificacion C.', 1;

SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdExpediente = CONVERT(varchar(50), @IdExpC), Resultado = 'PROCEDE',
                 Informe = 'Sustento tecnico: la reubicacion esta aprobada por resolucion; no se altera el monto ni el objeto.', InformeDocumento = 'PRUEBA-INF-MOD-1.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paOpinarAu @p;
INSERT INTO @Res SELECT 'C2. Especialista eleva el sustento', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorJefe), IdExpediente = CONVERT(varchar(50), @IdExpC), CodigoTransicion = 'MOD_REMITIR_DEC' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paEjecutarAccion @p;
INSERT INTO @Res SELECT 'C3. Jefe AU remite a la DEC', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpC), Resultado = 'APROBADA',
                 Motivo = 'Procedente: no aumenta el monto ni desnaturaliza el requerimiento (7.3.4.1).' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paDecidirDec @p;
INSERT INTO @Res SELECT 'C4. DEC declara procedente', j FROM @t;

/* El jefe de Abastecimiento genera el acta: se registra el PDF (marcador) en
   el expediente, se anota su numero y se firma. Igual que hace la pantalla. */
SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpC), CodigoTipoDocumento = 'MOD_ACTA_MODIFICACION',
                 GeneradoDocumento = 'PRUEBA-ACTA-MOD-1.pdf', NombreDocumento = 'Acta de modificacion - prueba.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC sigcm.paRegistrarDocumento @p;
INSERT INTO @Res SELECT 'C5a. Jefe Abast registra el PDF del acta', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpC), NumeroActa = 'ACTA-001-2026-DEC', ActaDocumento = 'PRUEBA-ACTA-MOD-1.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paRegistrarActa @p;
INSERT INTO @Res SELECT 'C5b. Jefe Abast numera el acta', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpC), CodigoTipoDocumento = 'MOD_ACTA_MODIFICACION' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC sigcm.paFirmarDocumento @p;
INSERT INTO @Res SELECT 'C5c. Jefe Abast firma el acta', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpC), CodigoTransicion = 'MOD_FIRMAR_ACTA' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paEjecutarAccion @p;
INSERT INTO @Res SELECT 'C5d. Transicion firmar acta', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorLoc), IdExpediente = CONVERT(varchar(50), @IdExpC), CodigoTransicion = 'MOD_SUSCRIBIR_ACTA' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paEjecutarAccion @p;
INSERT INTO @Res SELECT 'C6. Proveedor suscribe el acta', j FROM @t;

/* -------------------------------------------------------------------------- */
/* D. Denegar con el plazo de decision vencido: DEBE fallar                   */
/* -------------------------------------------------------------------------- */

SET @p = (SELECT Actor = JSON_QUERY(@ActorLoc), IdContrato = CONVERT(varchar(50), @IdContrato), Tipo = 'AMPLIACION_PLAZO',
                 Asunto = 'Ampliacion tardia de la DEC', Sustento = 'Prueba de aceptacion tacita.',
                 FechaFinHechoGenerador = CONVERT(varchar(10), DATEADD(DAY, -1, @Hoy), 23), DiasSolicitados = 2 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paRegistrarSolicitud @p;
INSERT INTO @Res SELECT 'D1. Proveedor solicita ampliacion (para la tacita)', j FROM @t;
DECLARE @IdExpD uniqueidentifier = (SELECT TOP 1 TRY_CONVERT(uniqueidentifier, JSON_VALUE(j, '$.IdExpediente')) FROM @t);

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpD), CodigoTransicion = 'AMP_REMITIR_AU' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paEjecutarAccion @p;
SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdExpediente = CONVERT(varchar(50), @IdExpD), Resultado = 'NO_PROCEDE', Informe = 'Sin sustento tecnico.' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ampliacion.paOpinarAu @p;
INSERT INTO @Res SELECT 'D2. Remitida y opinada NO_PROCEDE', j FROM @t;

/* Se simula el paso del tiempo: el vencimiento de los 7 habiles queda ayer. */
UPDATE sigcm.Plazo SET Vencimiento = DATEADD(DAY, -1, @Hoy) WHERE IdExpediente = @IdExpD AND CodigoRegla = 'AMP_DECISION_DEC' AND Activo = 1;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpD), Resultado = 'DENEGADA', Motivo = 'Intento tardio.' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
PRINT 'D3. Denegar con el plazo vencido (debe responder estado 0, CONFLICTO_PLAZO):';
EXEC ampliacion.paDecidirDec @p;

/* -------------------------------------------------------------------------- */
/* Resultado                                                                  */
/* -------------------------------------------------------------------------- */

SELECT Paso, estado = JSON_VALUE(Respuesta, '$.estado'), mensaje = LEFT(JSON_VALUE(Respuesta, '$.mensaje'), 110) FROM @Res;

SELECT solicitud = e.Codigo, tipo = s.Tipo, origen = s.Origen, estado = e.CodigoEstado, en_plazo = s.PresentadaEnPlazo,
       pedidos = s.DiasSolicitados, otorgados = s.DiasOtorgados, au = s.ResultadoAu, dec = s.ResultadoDec,
       acta = s.NumeroActa, suscrita = CONVERT(varchar(16), s.SuscritaProveedorEn, 120), notificada = CONVERT(varchar(16), s.NotificadaEn, 120)
  FROM ampliacion.Solicitud AS s JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
 WHERE s.IdContrato = @IdContrato ORDER BY s.FechaPresentacion;

SELECT contrato = e.Codigo, fin_original = CONVERT(varchar(10), @FechaFinOriginal, 103), fin_actual = CONVERT(varchar(10), c.FechaFinPrevista, 103),
       plazo_dias = c.PlazoDias, ampliado_hasta = CONVERT(varchar(10), pl.AmpliadoHasta, 103)
  FROM ejecucion.Contrato AS c JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
  LEFT JOIN sigcm.Plazo AS pl ON pl.IdExpediente = c.IdExpediente AND pl.CodigoRegla = 'EJE_EJECUCION_CONTRATO' AND pl.Activo = 1
 WHERE c.IdContrato = @IdContrato;
GO

PRINT 'S915 aplicada: ampliacion aprobada (+5 dias), ampliacion denegada, modificacion con acta firmada y suscrita, y denegatoria tardia rechazada.';
GO
