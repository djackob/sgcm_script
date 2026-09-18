/*
===============================================================================
  SIGCM - S916 : Prueba del modulo Resolucion sobre un contrato propio
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750

  FUERA DE LA SERIE. Repetible y se limpia solo. Siembra su propio contrato
  (REQ-PRU-RESOL-0001, locacion de 90 dias) porque la resolucion lo cierra y no
  puede compartir el de S914/S915.

  ---------------------------------------------------------------------------
  QUE PRUEBA (Directiva 7.3.7)
  ---------------------------------------------------------------------------
  A. El proveedor pide resolucion por MUTUO ACUERDO; el AU se pronuncia
     DESFAVORABLE; termina en RES_DENEGADA con carta de respuesta.
  B. El AU informa INCUMPLIMIENTO; el jefe remite a la DEC; la DEC intenta
     apercibir con 30 dias (DEBE fallar: el rango para 90 dias es 9-14) y
     luego apercibe con 10; el jefe de Abastecimiento genera y firma la carta
     de apercibimiento; el proveedor responde; el AU evalua que NO subsano; el
     jefe genera y firma la carta de resolucion. Termina en RES_RESUELTO y el
     contrato en EJE_RESUELTO.

  Actores: usuarios de prueba de S900.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Codigo varchar(40) = 'REQ-PRU-RESOL-0001';
DECLARE @NumeroOrden varchar(40) = 'PRU-OS-RES-0001';
DECLARE @Ahora datetime = GETDATE(), @Hoy date = CONVERT(date, GETDATE());
DECLARE @Notificado datetime = DATEADD(DAY, -10, GETDATE());
DECLARE @AnoEje smallint = YEAR(GETDATE()), @SecEjec int = 1750;

DECLARE @IdUnidad uniqueidentifier, @CodigoUnidad varchar(30), @CentroCosto varchar(15), @IdEsp uniqueidentifier, @CtaEsp varchar(120);
DECLARE @CtaJefe varchar(120) = 'prueba.oti.jefe', @CodigoUnidadDec varchar(30), @CodigoUnidadLoc varchar(30), @DocLoc varchar(20), @CorreoLoc varchar(200);

SELECT @IdUnidad = un.IdUnidad, @CodigoUnidad = un.Codigo, @CentroCosto = un.CentroCostoSiga, @IdEsp = u.IdUsuario, @CtaEsp = u.Cuenta
  FROM sigcm.UsuarioRol AS ur JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario JOIN sigcm.Unidad AS un ON un.IdUnidad = ur.IdUnidad
 WHERE u.Cuenta = 'prueba.oti.esp' AND ur.CodigoRol = 'AREA_ESPECIALISTA' AND ur.Activo = 1;
SELECT @CodigoUnidadDec = un.Codigo FROM sigcm.UsuarioRol AS ur JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario JOIN sigcm.Unidad AS un ON un.IdUnidad = ur.IdUnidad
 WHERE u.Cuenta = 'prueba.abast.esp' AND ur.CodigoRol = 'ABAST_ESPECIALISTA' AND ur.Activo = 1;
SELECT @CodigoUnidadLoc = un.Codigo, @DocLoc = NULLIF(u.DocumentoIdentidad, ''), @CorreoLoc = u.Correo
  FROM sigcm.UsuarioRol AS ur JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario JOIN sigcm.Unidad AS un ON un.IdUnidad = ur.IdUnidad
 WHERE u.Cuenta = 'prueba.locador' AND ur.CodigoRol = 'PROVEEDOR' AND ur.Activo = 1;
IF @IdEsp IS NULL OR @CodigoUnidadDec IS NULL OR @CodigoUnidadLoc IS NULL
    THROW 59160, 'NO_ENCONTRADO: faltan los usuarios de prueba de S900.', 1;
IF OBJECT_ID('resolucion.Procedimiento', 'U') IS NULL THROW 59161, 'FALTA_MIGRACION: no existe resolucion.Procedimiento.', 1;

/* -------------------------------------------------------------------------- */
/* 1. Limpieza                                                                */
/* -------------------------------------------------------------------------- */

DECLARE @IdExpediente uniqueidentifier, @IdRequerimiento uniqueidentifier;
SELECT @IdRequerimiento = r.IdRequerimiento, @IdExpediente = r.IdExpediente FROM requerimiento.Requerimiento AS r WHERE r.Codigo = @Codigo;

BEGIN TRANSACTION;
IF @IdRequerimiento IS NOT NULL
BEGIN
    DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY);
    INSERT INTO @Exp VALUES (@IdExpediente);
    INSERT INTO @Exp SELECT p.IdExpediente FROM pago.ExpedientePago AS p WHERE p.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = p.IdExpediente);
    INSERT INTO @Exp SELECT c.IdExpediente FROM ejecucion.Contrato AS c WHERE c.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = c.IdExpediente);
    INSERT INTO @Exp SELECT en.IdExpediente FROM ejecucion.Entrega AS en JOIN ejecucion.Contrato AS c ON c.IdContrato = en.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = en.IdExpediente);
    INSERT INTO @Exp SELECT s.IdExpediente FROM ampliacion.Solicitud AS s JOIN ejecucion.Contrato AS c ON c.IdContrato = s.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = s.IdExpediente);
    INSERT INTO @Exp SELECT r.IdExpediente FROM resolucion.Procedimiento AS r JOIN ejecucion.Contrato AS c ON c.IdContrato = r.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = r.IdExpediente);

    DECLARE @Doc TABLE (IdDocumento uniqueidentifier PRIMARY KEY);
    INSERT INTO @Doc SELECT DISTINCT de.IdDocumento FROM sigcm.DocumentoExpediente AS de JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;
    DELETE f FROM sigcm.Firma AS f JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumentoVersion = f.IdDocumentoVersion JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
    DELETE o FROM sigcm.Observacion AS o JOIN @Exp AS x ON x.IdExpediente = o.IdExpediente;
    DELETE dv FROM sigcm.DocumentoVersion AS dv JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
    DELETE de FROM sigcm.DocumentoExpediente AS de JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;
    DELETE doc FROM sigcm.Documento AS doc JOIN @Doc AS d ON d.IdDocumento = doc.IdDocumento;
    DELETE pl FROM sigcm.Plazo AS pl JOIN @Exp AS x ON x.IdExpediente = pl.IdExpediente;
    DELETE h FROM sigcm.Historial AS h JOIN @Exp AS x ON x.IdExpediente = h.IdExpediente;

    DELETE r FROM resolucion.Procedimiento AS r JOIN ejecucion.Contrato AS c ON c.IdContrato = r.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento;
    DELETE s FROM ampliacion.Solicitud AS s JOIN ejecucion.Contrato AS c ON c.IdContrato = s.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento;
    DELETE i FROM ejecucion.Incidencia AS i JOIN ejecucion.Contrato AS c ON c.IdContrato = i.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento;
    DELETE en FROM ejecucion.Entrega AS en JOIN ejecucion.Contrato AS c ON c.IdContrato = en.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento;
    DELETE FROM ejecucion.Contrato WHERE IdRequerimiento = @IdRequerimiento;
    DELETE m FROM pago.ChecklistMarca AS m JOIN pago.ExpedientePago AS p ON p.IdExpedientePago = m.IdExpedientePago WHERE p.IdRequerimiento = @IdRequerimiento;
    DELETE h FROM pago.HitoSincronizacion AS h JOIN pago.ExpedientePago AS p ON p.IdExpedientePago = h.IdExpedientePago WHERE p.IdRequerimiento = @IdRequerimiento;
    DELETE FROM pago.ExpedientePago WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM integracion.Operacion WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.CertificacionCcp WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.FiltroIdoneidad WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.InvitacionCotizacion WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.RequerimientoItem WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.RequerimientoPedido WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.OrdenServicio WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.Requerimiento WHERE IdRequerimiento = @IdRequerimiento;
    DELETE e FROM sigcm.Expediente AS e JOIN @Exp AS x ON x.IdExpediente = e.IdExpediente;
END

/* -------------------------------------------------------------------------- */
/* 2. Requerimiento de LOCACION (90 dias) con orden notificada                */
/* -------------------------------------------------------------------------- */

SET @IdExpediente = NEWID(); SET @IdRequerimiento = NEWID();
DECLARE @Datos nvarchar(max) = (
    SELECT Proveedores = JSON_QUERY((SELECT TipoDocumento = 'DNI', Dni = ISNULL(@DocLoc, ''), Ruc = '', RazonSocial = '',
                                            Nombres = 'DENIS', ApellidoPaterno = 'OCHOA', ApellidoMaterno = 'BERROCAL',
                                            Email = @CorreoLoc, Cci = '00219100123456789012', CantidadEntregables = 3, MontoMensual = 3000.00 FOR JSON PATH))
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

INSERT INTO sigcm.Expediente (IdExpediente, CodigoModulo, Codigo, AnoEje, CodigoEstado, Version, IdUnidadOrigen, IdUnidadActual, IdResponsableActual, Anulado, Activo,
                              UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdExpediente, 'REQUERIMIENTO', @Codigo, @AnoEje, 'REQ_NOTIFICADO', 1, @IdUnidad, @IdUnidad, @IdEsp, 0, 1, 'S916', @Ahora, 'SEED', 'SIGCM-PRUEBA');

INSERT INTO requerimiento.Requerimiento (IdRequerimiento, IdExpediente, Codigo, AnoEje, SecEjec, CentroCosto, Denominacion, CodigoTipoContratacion, CodigoDec, CondicionCmn,
                                         Monto, PlazoDias, FechaInicioPrevisto, Sustento, IdResponsable, DatosAdicionales, Activo,
                                         UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdRequerimiento, @IdExpediente, @Codigo, @AnoEje, @SecEjec, @CentroCosto, 'Servicio de soporte tecnico (prueba del modulo Resolucion)', 'LOCACION', 'ABASTECIMIENTO', 'INCLUIDO',
        9000.00, 90, CONVERT(date, @Ahora), 'Expediente sembrado por S916.', @IdEsp, @Datos, 1, 'S916', @Ahora, 'SEED', 'SIGCM-PRUEBA');

INSERT INTO sigcm.Historial (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion, Comentario, IdActor, ActorRol, IdActorUnidad, OcurridoEn)
VALUES (@IdExpediente, NULL, 'REQ_NOTIFICADO', NULL, 'Sembrado por S916 directamente en REQ_NOTIFICADO. No recorrio el flujo.', @IdEsp, 'AREA_ESPECIALISTA', @IdUnidad, @Ahora);

INSERT INTO requerimiento.OrdenServicio (IdRequerimiento, NumeroOrden, FechaEmision, CorreoLocador, CorreoAreaUsuaria, NotificadoEn, Activo, EstadoIntegracion,
                                         UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdRequerimiento, @NumeroOrden, DATEADD(DAY, -1, @Notificado), @CorreoLoc, 'area.prueba@anin.gob.pe', @Notificado, 1, 'SIMULADO', 'S916', @Ahora, 'SEED', 'SIGCM-PRUEBA');
COMMIT TRANSACTION;

DECLARE @ActorEsp  nvarchar(max) = (SELECT Usuario = @CtaEsp,            Rol = 'AREA_ESPECIALISTA',  Unidad = @CodigoUnidad    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorJefe nvarchar(max) = (SELECT Usuario = @CtaJefe,           Rol = 'AREA_JEFE',          Unidad = @CodigoUnidad    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorDec  nvarchar(max) = (SELECT Usuario = 'prueba.abast.esp', Rol = 'ABAST_ESPECIALISTA', Unidad = @CodigoUnidadDec FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorDecJ nvarchar(max) = (SELECT Usuario = 'prueba.abast.jefe',Rol = 'ABAST_JEFE',         Unidad = @CodigoUnidadDec FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorLoc  nvarchar(max) = (SELECT Usuario = 'prueba.locador',   Rol = 'PROVEEDOR',          Unidad = @CodigoUnidadLoc FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

DECLARE @p nvarchar(max);
DECLARE @t TABLE (j nvarchar(max));
DECLARE @Res TABLE (Paso varchar(90), Respuesta nvarchar(max));

SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdRequerimiento = CONVERT(varchar(50), @IdRequerimiento) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
EXEC pago.paAbrirDesdeOrdenServicioInterno @p;
EXEC ejecucion.paAbrirDesdeOrdenServicioInterno @p;

DECLARE @IdContrato uniqueidentifier, @IdExpContrato uniqueidentifier;
SELECT @IdContrato = IdContrato, @IdExpContrato = IdExpediente FROM ejecucion.Contrato WHERE IdRequerimiento = @IdRequerimiento;
IF @IdContrato IS NULL THROW 59162, 'El contrato no se abrio.', 1;

/* -------------------------------------------------------------------------- */
/* A. Mutuo acuerdo pedido por el proveedor, negado por el AU                 */
/* -------------------------------------------------------------------------- */

SET @p = (SELECT Actor = JSON_QUERY(@ActorLoc), IdContrato = CONVERT(varchar(50), @IdContrato), Causal = 'MUTUO_ACUERDO', Alcance = 'TOTAL',
                 Hechos = 'Solicito resolver el contrato de mutuo acuerdo por motivos personales.', Documento = 'PRUEBA-SOL-RES-1.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paRegistrarProcedimiento @p;
INSERT INTO @Res SELECT 'A1. Proveedor solicita mutuo acuerdo', j FROM @t;
DECLARE @IdExpA uniqueidentifier = (SELECT TOP 1 TRY_CONVERT(uniqueidentifier, JSON_VALUE(j, '$.IdExpediente')) FROM @t);
IF @IdExpA IS NULL THROW 59163, 'No se registro el procedimiento A.', 1;

SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdExpediente = CONVERT(varchar(50), @IdExpA), Pronunciamiento = 'DESFAVORABLE',
                 Informe = 'El servicio es critico para el cierre del ejercicio; no procede resolver de mutuo acuerdo.' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paPronunciarAu @p;
INSERT INTO @Res SELECT 'A2. AU se pronuncia DESFAVORABLE (deniega)', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpA), TipoCarta = 'RESPUESTA', NumeroCarta = 'CARTA-010-2026-DEC',
                 CartaDocumento = 'PRUEBA-CARTA-NEG-1.pdf', MedioNotificacion = 'CORREO' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paRegistrarCarta @p;
INSERT INTO @Res SELECT 'A3. DEC registra carta de respuesta', j FROM @t;

/* -------------------------------------------------------------------------- */
/* B. Incumplimiento: apercibimiento, respuesta, no subsano, resolucion       */
/* -------------------------------------------------------------------------- */

SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdContrato = CONVERT(varchar(50), @IdContrato), Causal = 'INCUMPLIMIENTO', Alcance = 'TOTAL',
                 Hechos = 'El locador no presento el entregable 1 en el plazo del cronograma ni respondio a los requerimientos del area.',
                 Documento = 'PRUEBA-INF-RES-1.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paRegistrarProcedimiento @p;
INSERT INTO @Res SELECT 'B1. AU informa INCUMPLIMIENTO', j FROM @t;
DECLARE @IdExpB uniqueidentifier = (SELECT TOP 1 TRY_CONVERT(uniqueidentifier, JSON_VALUE(j, '$.IdExpediente')) FROM @t);
IF @IdExpB IS NULL THROW 59164, 'No se registro el procedimiento B.', 1;
INSERT INTO @Res SELECT 'B1b. Rango del apercibimiento', (SELECT CONCAT('{"estado":1,"mensaje":"min ', JSON_VALUE(j, '$.PlazoApercibimientoMin'), ' - max ', JSON_VALUE(j, '$.PlazoApercibimientoMax'), ' dias"}') FROM @t);

SET @p = (SELECT Actor = JSON_QUERY(@ActorJefe), IdExpediente = CONVERT(varchar(50), @IdExpB), CodigoTransicion = 'RES_REMITIR_DEC' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paEjecutarAccion @p;
INSERT INTO @Res SELECT 'B2. Jefe AU remite a la DEC', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpB), Decision = 'APERCIBIR', PlazoApercibimientoDias = 30, Motivo = 'Prueba fuera de rango.' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
PRINT 'B3. Apercibir con 30 dias (debe responder estado 0, VALIDACION_PLAZO):';
EXEC resolucion.paDecidirDec @p;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpB), Decision = 'APERCIBIR', PlazoApercibimientoDias = 10,
                 Motivo = 'Se requiere el cumplimiento del entregable 1 bajo apercibimiento de resolucion (7.3.7.2.b).' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paDecidirDec @p;
INSERT INTO @Res SELECT 'B4. DEC apercibe con 10 dias', j FROM @t;

/* Carta de apercibimiento: PDF registrado, numerada y firmada por el jefe. */
SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpB), CodigoTipoDocumento = 'RES_CARTA_APERCIBIMIENTO',
                 GeneradoDocumento = 'PRUEBA-CARTA-AP-1.pdf', NombreDocumento = 'Carta de apercibimiento - prueba.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC sigcm.paRegistrarDocumento @p;
SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpB), TipoCarta = 'APERCIBIMIENTO', NumeroCarta = 'CARTA-011-2026-DEC',
                 CartaDocumento = 'PRUEBA-CARTA-AP-1.pdf', MedioNotificacion = 'NOTARIAL' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paRegistrarCarta @p;
SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpB), CodigoTipoDocumento = 'RES_CARTA_APERCIBIMIENTO' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC sigcm.paFirmarDocumento @p;
INSERT INTO @Res SELECT 'B5a. Jefe Abast firma la carta de apercibimiento', j FROM @t;
SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpB), CodigoTransicion = 'RES_FIRMAR_APERCIBIMIENTO' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paEjecutarAccion @p;
INSERT INTO @Res SELECT 'B5b. Apercibimiento notificado (plazo corre)', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorLoc), IdExpediente = CONVERT(varchar(50), @IdExpB), CodigoTransicion = 'RES_RESPONDER_APERCIBIMIENTO',
                 Respuesta = 'Presento el entregable 1 con la informacion disponible; el resto depende de accesos que el area no otorgo.',
                 RespuestaDocumento = 'PRUEBA-RESP-AP-1.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paEjecutarAccion @p;
INSERT INTO @Res SELECT 'B6. Proveedor responde', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdExpediente = CONVERT(varchar(50), @IdExpB), Pronunciamiento = 'DESFAVORABLE',
                 Informe = 'El entregable presentado no cumple los TDR; el incumplimiento persiste.' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paPronunciarAu @p;
INSERT INTO @Res SELECT 'B7. AU evalua: NO subsano', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpB), CodigoTipoDocumento = 'RES_CARTA_RESOLUCION',
                 GeneradoDocumento = 'PRUEBA-CARTA-RES-1.pdf', NombreDocumento = 'Carta de resolucion - prueba.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC sigcm.paRegistrarDocumento @p;
SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpB), TipoCarta = 'RESOLUCION', NumeroCarta = 'CARTA-012-2026-DEC',
                 CartaDocumento = 'PRUEBA-CARTA-RES-1.pdf', MedioNotificacion = 'NOTARIAL' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paRegistrarCarta @p;
SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpB), CodigoTipoDocumento = 'RES_CARTA_RESOLUCION' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC sigcm.paFirmarDocumento @p;
INSERT INTO @Res SELECT 'B8a. Jefe Abast firma la carta de resolucion', j FROM @t;
SET @p = (SELECT Actor = JSON_QUERY(@ActorDecJ), IdExpediente = CONVERT(varchar(50), @IdExpB), CodigoTransicion = 'RES_FIRMAR_RESOLUCION' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC resolucion.paEjecutarAccion @p;
INSERT INTO @Res SELECT 'B8b. Contrato resuelto', j FROM @t;

/* -------------------------------------------------------------------------- */
/* Resultado                                                                  */
/* -------------------------------------------------------------------------- */

SELECT Paso, estado = JSON_VALUE(Respuesta, '$.estado'), mensaje = LEFT(JSON_VALUE(Respuesta, '$.mensaje'), 110) FROM @Res;

SELECT procedimiento = e.Codigo, causal = r.Causal, origen = r.Origen, estado = e.CodigoEstado, apercibe = r.RequiereApercibimiento,
       rango = CONCAT(r.PlazoApercibimientoMin, '-', r.PlazoApercibimientoMax), dias = r.PlazoApercibimientoDias,
       limite = CONVERT(varchar(10), r.FechaLimiteSubsanacion, 103), resp_ap = r.ResultadoApercibimiento, dec = r.ResultadoDec,
       carta = r.NumeroCarta, medio = r.MedioNotificacion, resuelto = CONVERT(varchar(10), r.FechaResolucion, 103)
  FROM resolucion.Procedimiento AS r JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
 WHERE r.IdContrato = @IdContrato ORDER BY r.FechaInicio;

SELECT contrato = e.Codigo, estado = e.CodigoEstado, fin_real = CONVERT(varchar(10), c.FechaFinReal, 103), cerrado = CONVERT(varchar(16), e.CerradoEn, 120)
  FROM ejecucion.Contrato AS c JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente WHERE c.IdContrato = @IdContrato;
GO

PRINT 'S916 aplicada: mutuo acuerdo denegado por el AU e incumplimiento apercibido, no subsanado y resuelto; contrato en EJE_RESUELTO.';
GO
