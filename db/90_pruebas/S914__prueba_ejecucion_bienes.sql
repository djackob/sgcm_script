/*
===============================================================================
  SIGCM - S914 : Prueba del modulo Ejecucion - contrato de BIENES con entregas
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750

  FUERA DE LA SERIE. Repetible y se limpia solo, como S903 y S909.

  ---------------------------------------------------------------------------
  QUE PRUEBA
  ---------------------------------------------------------------------------
  El recorrido de la Directiva 7.3.6.3 con las rutinas REALES de F016, nunca
  con UPDATE de estados:

    1. Un requerimiento de BIEN con orden notificada, sembrado directamente
       en REQ_NOTIFICADO (igual que S909 siembra el suyo en REQ_OS_EMITIDA).
    2. Apertura del contrato y de los expedientes de pago por las mismas
       rutinas que corre el sistema al notificar la orden (7.3.1).
    3. El AU fija el lugar de entrega: Sede Central.
    4. Entrega 1, ruta ALMACEN completa y CONFORME:
         proveedor anuncia -> DEC autoriza ingreso -> jefe AU designa al
         verificador -> DEC verifica conforme con guia suscrita -> DEC entrega
         al AU con Pecosa. Termina en EJE_ENT_ENTREGADA_AU.
    5. Entrega 2, ruta ALMACEN OBSERVADA:
         proveedor anuncia -> DEC autoriza -> jefe designa -> DEC observa con
         acta de incumplimiento -> proveedor confirma el retiro. Termina en
         EJE_ENT_RETIRADA.
    6. Una incidencia del AU (7.3.3) atendida por la DEC.
    7. Un intento de culminar el contrato, que DEBE fallar porque ningun
       entregable tiene conformidad todavia: la conformidad se da en Pagos.

  Actores: los usuarios de prueba de S900 (prueba.oti.*, prueba.abast.esp,
  prueba.locador). El proveedor del contrato se identifica con el documento y
  el correo de prueba.locador, que es lo que ejecucion.paAnunciarEntrega
  comprueba antes de aceptar el anuncio.

  Los identificadores de archivo (PRUEBA-GUIA-1.pdf, ...) son marcadores: no
  hay PDF detras en el file server.

  ---------------------------------------------------------------------------
  COMO SE USA
  ---------------------------------------------------------------------------
      sqlcmd -S "localhost\SQLSERVER25" -d DBSIGCM -E -b -I -i db/90_pruebas/S914__prueba_ejecucion_bienes.sql

  Deja REQ-PRU-EJEC-0001 con su contrato EJE-*, dos entregas cerradas y una
  incidencia atendida. Para recorrerlo por pantalla, borra la seccion 4 en
  adelante o corre solo hasta la 3 y sigue con los perfiles de prueba.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Codigo        varchar(40) = 'REQ-PRU-EJEC-0001';
DECLARE @NumeroOrden   varchar(40) = 'PRU-OC-0001';
DECLARE @Ahora         datetime    = GETDATE();
DECLARE @Notificado    datetime    = DATEADD(DAY, -3, GETDATE());
DECLARE @AnoEje        smallint    = YEAR(GETDATE());
DECLARE @SecEjec       int         = 1750;
DECLARE @Entregables   int         = 2;
DECLARE @MontoUnit     decimal(18,2) = 12500.00;

DECLARE @IdUnidad uniqueidentifier, @CodigoUnidad varchar(30), @CentroCosto varchar(15);
DECLARE @IdEsp uniqueidentifier, @CtaEsp varchar(120);
DECLARE @IdJefe uniqueidentifier, @CtaJefe varchar(120);
DECLARE @IdDec uniqueidentifier, @CtaDec varchar(120), @CodigoUnidadDec varchar(30);
DECLARE @IdLoc uniqueidentifier, @CtaLoc varchar(120), @CodigoUnidadLoc varchar(30), @DocLoc varchar(20), @CorreoLoc varchar(200);

SELECT @IdUnidad = un.IdUnidad, @CodigoUnidad = un.Codigo, @CentroCosto = un.CentroCostoSiga,
       @IdEsp = u.IdUsuario, @CtaEsp = u.Cuenta
  FROM sigcm.UsuarioRol AS ur JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
  JOIN sigcm.Unidad AS un ON un.IdUnidad = ur.IdUnidad
 WHERE u.Cuenta = 'prueba.oti.esp' AND ur.CodigoRol = 'AREA_ESPECIALISTA' AND ur.Activo = 1;

SELECT @IdJefe = u.IdUsuario, @CtaJefe = u.Cuenta
  FROM sigcm.UsuarioRol AS ur JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
 WHERE u.Cuenta = 'prueba.oti.jefe' AND ur.CodigoRol = 'AREA_JEFE' AND ur.IdUnidad = @IdUnidad AND ur.Activo = 1;

SELECT @IdDec = u.IdUsuario, @CtaDec = u.Cuenta, @CodigoUnidadDec = un.Codigo
  FROM sigcm.UsuarioRol AS ur JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
  JOIN sigcm.Unidad AS un ON un.IdUnidad = ur.IdUnidad
 WHERE u.Cuenta = 'prueba.abast.esp' AND ur.CodigoRol = 'ABAST_ESPECIALISTA' AND ur.Activo = 1;

SELECT @IdLoc = u.IdUsuario, @CtaLoc = u.Cuenta, @CodigoUnidadLoc = un.Codigo,
       @DocLoc = NULLIF(u.DocumentoIdentidad, ''), @CorreoLoc = u.Correo
  FROM sigcm.UsuarioRol AS ur JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
  JOIN sigcm.Unidad AS un ON un.IdUnidad = ur.IdUnidad
 WHERE u.Cuenta = 'prueba.locador' AND ur.CodigoRol = 'PROVEEDOR' AND ur.Activo = 1;

IF @IdEsp IS NULL OR @IdJefe IS NULL OR @IdDec IS NULL OR @IdLoc IS NULL
    THROW 59140, 'NO_ENCONTRADO: faltan los usuarios de prueba de S900 (prueba.oti.esp, prueba.oti.jefe, prueba.abast.esp, prueba.locador).', 1;
IF OBJECT_ID('ejecucion.Contrato', 'U') IS NULL
    THROW 59141, 'FALTA_MIGRACION: no existe ejecucion.Contrato. Corre instalar.ps1 antes.', 1;

/* -------------------------------------------------------------------------- */
/* 1. Limpieza de la corrida anterior                                         */
/* -------------------------------------------------------------------------- */

DECLARE @IdExpediente uniqueidentifier, @IdRequerimiento uniqueidentifier;
SELECT @IdRequerimiento = r.IdRequerimiento, @IdExpediente = r.IdExpediente
  FROM requerimiento.Requerimiento AS r WHERE r.Codigo = @Codigo;

BEGIN TRANSACTION;

IF @IdRequerimiento IS NOT NULL
BEGIN
    DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY);
    INSERT INTO @Exp VALUES (@IdExpediente);
    INSERT INTO @Exp SELECT p.IdExpediente FROM pago.ExpedientePago AS p
     WHERE p.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = p.IdExpediente);
    INSERT INTO @Exp SELECT c.IdExpediente FROM ejecucion.Contrato AS c
     WHERE c.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = c.IdExpediente);
    INSERT INTO @Exp SELECT en.IdExpediente FROM ejecucion.Entrega AS en JOIN ejecucion.Contrato AS c ON c.IdContrato = en.IdContrato
     WHERE c.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = en.IdExpediente);
    /* Los modulos 4 y 5 cuelgan del contrato (S915 usa este mismo). */
    IF OBJECT_ID('ampliacion.Solicitud', 'U') IS NOT NULL
        INSERT INTO @Exp SELECT s.IdExpediente FROM ampliacion.Solicitud AS s JOIN ejecucion.Contrato AS c ON c.IdContrato = s.IdContrato
         WHERE c.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = s.IdExpediente);
    IF OBJECT_ID('resolucion.Procedimiento', 'U') IS NOT NULL
        INSERT INTO @Exp SELECT r.IdExpediente FROM resolucion.Procedimiento AS r JOIN ejecucion.Contrato AS c ON c.IdContrato = r.IdContrato
         WHERE c.IdRequerimiento = @IdRequerimiento AND NOT EXISTS (SELECT 1 FROM @Exp x WHERE x.IdExpediente = r.IdExpediente);

    DECLARE @Doc TABLE (IdDocumento uniqueidentifier PRIMARY KEY);
    INSERT INTO @Doc SELECT DISTINCT de.IdDocumento FROM sigcm.DocumentoExpediente AS de JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;

    DELETE f FROM sigcm.Firma AS f JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumentoVersion = f.IdDocumentoVersion JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
    DELETE o FROM sigcm.Observacion AS o JOIN @Exp AS x ON x.IdExpediente = o.IdExpediente;
    DELETE dv FROM sigcm.DocumentoVersion AS dv JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
    DELETE de FROM sigcm.DocumentoExpediente AS de JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;
    DELETE doc FROM sigcm.Documento AS doc JOIN @Doc AS d ON d.IdDocumento = doc.IdDocumento;
    DELETE pl FROM sigcm.Plazo AS pl JOIN @Exp AS x ON x.IdExpediente = pl.IdExpediente;
    DELETE h FROM sigcm.Historial AS h JOIN @Exp AS x ON x.IdExpediente = h.IdExpediente;

    IF OBJECT_ID('ampliacion.Solicitud', 'U') IS NOT NULL
        DELETE s FROM ampliacion.Solicitud AS s JOIN ejecucion.Contrato AS c ON c.IdContrato = s.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento;
    IF OBJECT_ID('resolucion.Procedimiento', 'U') IS NOT NULL
        DELETE r FROM resolucion.Procedimiento AS r JOIN ejecucion.Contrato AS c ON c.IdContrato = r.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento;
    DELETE i FROM ejecucion.Incidencia AS i JOIN ejecucion.Contrato AS c ON c.IdContrato = i.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento;
    DELETE en FROM ejecucion.Entrega AS en JOIN ejecucion.Contrato AS c ON c.IdContrato = en.IdContrato WHERE c.IdRequerimiento = @IdRequerimiento;
    DELETE FROM ejecucion.Contrato WHERE IdRequerimiento = @IdRequerimiento;

    DELETE m FROM pago.ChecklistMarca AS m JOIN pago.ExpedientePago AS p ON p.IdExpedientePago = m.IdExpedientePago WHERE p.IdRequerimiento = @IdRequerimiento;
    DELETE h FROM pago.HitoSincronizacion AS h JOIN pago.ExpedientePago AS p ON p.IdExpedientePago = h.IdExpedientePago WHERE p.IdRequerimiento = @IdRequerimiento;
    DELETE FROM pago.ExpedientePago WHERE IdRequerimiento = @IdRequerimiento;

    DELETE FROM integracion.Operacion              WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.CertificacionCcp     WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.FiltroIdoneidad      WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.InvitacionCotizacion WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.RequerimientoItem    WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.RequerimientoPedido  WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.OrdenServicio        WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.Requerimiento        WHERE IdRequerimiento = @IdRequerimiento;

    DELETE e FROM sigcm.Expediente AS e JOIN @Exp AS x ON x.IdExpediente = e.IdExpediente;
END

/* -------------------------------------------------------------------------- */
/* 2. Requerimiento de BIEN con orden notificada                              */
/* -------------------------------------------------------------------------- */

SET @IdExpediente = NEWID();
SET @IdRequerimiento = NEWID();

DECLARE @Datos nvarchar(max) = (
    SELECT Proveedores = JSON_QUERY((
               SELECT TipoDocumento = 'DNI', Dni = ISNULL(@DocLoc, ''), Ruc = '',
                      RazonSocial = 'DISTRIBUIDORA DE PRUEBA E.I.R.L.',
                      Nombres = '', ApellidoPaterno = '', ApellidoMaterno = '',
                      Email = @CorreoLoc, Celular = '999888777',
                      Cci = '00219100123456789012',
                      CantidadEntregables = @Entregables, MontoMensual = @MontoUnit,
                      Direccion = 'AV. PRUEBA 123'
                 FOR JSON PATH))
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

INSERT INTO sigcm.Expediente
      (IdExpediente, CodigoModulo, Codigo, AnoEje, CodigoEstado, Version,
       IdUnidadOrigen, IdUnidadActual, IdResponsableActual, Anulado, Activo,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdExpediente, 'REQUERIMIENTO', @Codigo, @AnoEje, 'REQ_NOTIFICADO', 1,
        @IdUnidad, @IdUnidad, @IdEsp, 0, 1,
        'S914', @Ahora, 'SEED', 'SIGCM-PRUEBA');

INSERT INTO requerimiento.Requerimiento
      (IdRequerimiento, IdExpediente, Codigo, AnoEje, SecEjec, CentroCosto,
       Denominacion, CodigoTipoContratacion, CodigoDec, CondicionCmn,
       Monto, PlazoDias, FechaInicioPrevisto, Sustento, IdResponsable, DatosAdicionales, Activo,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdRequerimiento, @IdExpediente, @Codigo, @AnoEje, @SecEjec, @CentroCosto,
        'Adquisicion de equipos de computo para la OTI (prueba del modulo Ejecucion)',
        'BIEN', 'ABASTECIMIENTO', 'INCLUIDO',
        @Entregables * @MontoUnit, 30, CONVERT(date, @Ahora),
        'Expediente sembrado por S914 para probar la ejecucion contractual de bienes.',
        @IdEsp, @Datos, 1,
        'S914', @Ahora, 'SEED', 'SIGCM-PRUEBA');

INSERT INTO sigcm.Historial
      (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
       Comentario, IdActor, ActorRol, IdActorUnidad, OcurridoEn)
VALUES (@IdExpediente, NULL, 'REQ_NOTIFICADO', NULL,
        'Expediente sembrado por S914 directamente en REQ_NOTIFICADO, para probar el modulo de ejecucion. No recorrio el flujo.',
        @IdEsp, 'AREA_ESPECIALISTA', @IdUnidad, @Ahora);

INSERT INTO requerimiento.OrdenServicio
      (IdRequerimiento, NumeroOrden, FechaEmision, CorreoLocador, CorreoAreaUsuaria, NotificadoEn,
       Activo, EstadoIntegracion,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdRequerimiento, @NumeroOrden, DATEADD(DAY, -1, @Notificado), @CorreoLoc, 'area.prueba@anin.gob.pe', @Notificado,
        1, 'SIMULADO',
        'S914', @Ahora, 'SEED', 'SIGCM-PRUEBA');

COMMIT TRANSACTION;

/* -------------------------------------------------------------------------- */
/* 3. Apertura por las rutinas reales: pagos (cronograma) y contrato          */
/* -------------------------------------------------------------------------- */

DECLARE @ActorEsp  nvarchar(max) = (SELECT Usuario = @CtaEsp,  Rol = 'AREA_ESPECIALISTA',  Unidad = @CodigoUnidad    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorJefe nvarchar(max) = (SELECT Usuario = @CtaJefe, Rol = 'AREA_JEFE',          Unidad = @CodigoUnidad    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorDec  nvarchar(max) = (SELECT Usuario = @CtaDec,  Rol = 'ABAST_ESPECIALISTA', Unidad = @CodigoUnidadDec FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DECLARE @ActorLoc  nvarchar(max) = (SELECT Usuario = @CtaLoc,  Rol = 'PROVEEDOR',          Unidad = @CodigoUnidadLoc FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

DECLARE @p nvarchar(max), @r nvarchar(max);
DECLARE @Res TABLE (Paso varchar(80), Respuesta nvarchar(max));

SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdRequerimiento = CONVERT(varchar(50), @IdRequerimiento) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
EXEC pago.paAbrirDesdeOrdenServicioInterno @p;
EXEC ejecucion.paAbrirDesdeOrdenServicioInterno @p;

DECLARE @IdContrato uniqueidentifier, @IdExpContrato uniqueidentifier;
SELECT @IdContrato = IdContrato, @IdExpContrato = IdExpediente FROM ejecucion.Contrato WHERE IdRequerimiento = @IdRequerimiento;
IF @IdContrato IS NULL
    THROW 59142, 'El contrato no se abrio. Revisa ejecucion.paAbrirDesdeOrdenServicioInterno.', 1;

/* El AU fija el lugar: Sede Central -> ruta Almacen. */
DECLARE @t TABLE (j nvarchar(max));
SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdContrato = CONVERT(varchar(50), @IdContrato),
                 LugarEntrega = 'SEDE_CENTRAL', IdSupervisor = CONVERT(varchar(50), @IdEsp)
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paActualizarContrato @p;
INSERT INTO @Res SELECT '3. Lugar de entrega', j FROM @t;

/* -------------------------------------------------------------------------- */
/* 4. Entrega 1: ruta Almacen, CONFORME                                       */
/* -------------------------------------------------------------------------- */

SET @p = (SELECT Actor = JSON_QUERY(@ActorLoc), IdContrato = CONVERT(varchar(50), @IdContrato),
                 NumeroEntregable = 1, Detalle = '10 equipos de computo segun EETT, lote 1',
                 FechaPrevista = CONVERT(varchar(10), @Ahora, 23), NumeroGuiaRemision = 'T001-000101',
                 GuiaDocumento = 'PRUEBA-GUIA-1.pdf'
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paAnunciarEntrega @p;
INSERT INTO @Res SELECT '4a. Proveedor anuncia entrega 1', j FROM @t;

DECLARE @IdExpEnt1 uniqueidentifier = (SELECT TOP 1 TRY_CONVERT(uniqueidentifier, JSON_VALUE(j, '$.IdExpediente')) FROM @t);
IF @IdExpEnt1 IS NULL THROW 59143, 'No se creo la entrega 1.', 1;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpEnt1) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paAutorizarIngreso @p;
INSERT INTO @Res SELECT '4b. DEC autoriza ingreso', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorJefe), IdExpediente = CONVERT(varchar(50), @IdExpEnt1),
                 IdVerificador = CONVERT(varchar(50), @IdEsp) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paDesignarVerificador @p;
INSERT INTO @Res SELECT '4c. Jefe AU designa verificador', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpEnt1),
                 Resultado = 'CONFORME', Detalle = 'Cumple las EETT. Visto bueno del AU en la guia.',
                 GuiaSuscritaDocumento = 'PRUEBA-GUIA-1-VB.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paVerificarEntrega @p;
INSERT INTO @Res SELECT '4d. DEC verifica CONFORME', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpEnt1),
                 NumeroPecosa = 'PECOSA-2026-0001', PecosaDocumento = 'PRUEBA-PECOSA-1.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paEntregarBienAu @p;
INSERT INTO @Res SELECT '4e. DEC entrega al AU con Pecosa', j FROM @t;

/* -------------------------------------------------------------------------- */
/* 5. Entrega 2: ruta Almacen, OBSERVADA y retirada                           */
/* -------------------------------------------------------------------------- */

SET @p = (SELECT Actor = JSON_QUERY(@ActorLoc), IdContrato = CONVERT(varchar(50), @IdContrato),
                 NumeroEntregable = 2, Detalle = '10 equipos de computo, lote 2',
                 FechaPrevista = CONVERT(varchar(10), @Ahora, 23), NumeroGuiaRemision = 'T001-000102',
                 GuiaDocumento = 'PRUEBA-GUIA-2.pdf'
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paAnunciarEntrega @p;
INSERT INTO @Res SELECT '5a. Proveedor anuncia entrega 2', j FROM @t;

DECLARE @IdExpEnt2 uniqueidentifier = (SELECT TOP 1 TRY_CONVERT(uniqueidentifier, JSON_VALUE(j, '$.IdExpediente')) FROM @t);
IF @IdExpEnt2 IS NULL THROW 59144, 'No se creo la entrega 2.', 1;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpEnt2) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paAutorizarIngreso @p;
INSERT INTO @Res SELECT '5b. DEC autoriza ingreso', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorJefe), IdExpediente = CONVERT(varchar(50), @IdExpEnt2),
                 IdVerificador = CONVERT(varchar(50), @IdEsp) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paDesignarVerificador @p;
INSERT INTO @Res SELECT '5c. Jefe AU designa verificador', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdExpediente = CONVERT(varchar(50), @IdExpEnt2),
                 Resultado = 'OBSERVADO', Detalle = 'Los equipos no cumplen la memoria minima exigida en las EETT.',
                 ActaIncumplimientoDocumento = 'PRUEBA-ACTA-2.pdf' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paVerificarEntrega @p;
INSERT INTO @Res SELECT '5d. DEC observa con acta', j FROM @t;

SET @p = (SELECT Actor = JSON_QUERY(@ActorLoc), IdExpediente = CONVERT(varchar(50), @IdExpEnt2),
                 CodigoTransicion = 'EJE_ENT_RETIRAR' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paEjecutarAccionEntrega @p;
INSERT INTO @Res SELECT '5e. Proveedor confirma retiro', j FROM @t;

/* -------------------------------------------------------------------------- */
/* 6. Incidencia (7.3.3)                                                      */
/* -------------------------------------------------------------------------- */

SET @p = (SELECT Actor = JSON_QUERY(@ActorEsp), IdContrato = CONVERT(varchar(50), @IdContrato),
                 Tipo = 'INCUMPLIMIENTO', Detalle = 'El lote 2 fue observado y retirado; riesgo de atraso en el plazo.',
                 DocumentoSgd = 'MEMO-000123-2026-OTI' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paRegistrarIncidencia @p;
INSERT INTO @Res SELECT '6a. AU registra incidencia', j FROM @t;

DECLARE @IdInc uniqueidentifier = (SELECT TOP 1 TRY_CONVERT(uniqueidentifier, JSON_VALUE(j, '$.IdIncidencia')) FROM @t);
SET @p = (SELECT Actor = JSON_QUERY(@ActorDec), IdIncidencia = CONVERT(varchar(50), @IdInc),
                 Respuesta = 'Se notifico al proveedor el plazo para la nueva entrega del lote 2.' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
DELETE @t; INSERT INTO @t EXEC ejecucion.paAtenderIncidencia @p;
INSERT INTO @Res SELECT '6b. DEC atiende incidencia', j FROM @t;

/* -------------------------------------------------------------------------- */
/* 7. Culminar: DEBE fallar (sin conformidades en Pagos)                      */
/* -------------------------------------------------------------------------- */

/* Se ejecuta directo y no con INSERT ... EXEC: la rutina lanza y captura un
   THROW con XACT_ABORT ON, y eso condena la transaccion implicita del INSERT
   (error 3930). El resultado -estado 0, CONFLICTO_ESTADO- sale a la consola. */
SET @p = (SELECT Actor = JSON_QUERY(@ActorJefe), IdExpediente = CONVERT(varchar(50), @IdExpContrato) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
PRINT '7. Culminar el contrato (debe responder estado 0):';
EXEC ejecucion.paCulminarContrato @p;

/* -------------------------------------------------------------------------- */
/* 8. Resultado                                                               */
/* -------------------------------------------------------------------------- */

SELECT Paso, estado = JSON_VALUE(Respuesta, '$.estado'), mensaje = LEFT(JSON_VALUE(Respuesta, '$.mensaje'), 120) FROM @Res;

SELECT contrato = e.Codigo, estado = e.CodigoEstado, tipo = c.TipoPrestacion, lugar = c.LugarEntrega,
       inicio = CONVERT(varchar(10), c.FechaInicio, 103), fin = CONVERT(varchar(10), c.FechaFinPrevista, 103),
       proveedor = c.NombreProveedor
  FROM ejecucion.Contrato AS c JOIN sigcm.Expediente AS e ON e.IdExpediente = c.IdExpediente
 WHERE c.IdContrato = @IdContrato;

SELECT entrega = en.NumeroEntrega, expediente = e.Codigo, estado = e.CodigoEstado, unidad_actual = un.Sigla,
       resultado = en.ResultadoVerificacion, guia = en.NumeroGuiaRemision, pecosa = en.NumeroPecosa,
       verificador = (SELECT Cuenta FROM sigcm.Usuario WHERE IdUsuario = en.IdVerificador)
  FROM ejecucion.Entrega AS en JOIN sigcm.Expediente AS e ON e.IdExpediente = en.IdExpediente
  JOIN sigcm.Unidad AS un ON un.IdUnidad = e.IdUnidadActual
 WHERE en.IdContrato = @IdContrato ORDER BY en.NumeroEntrega;

SELECT incidencia = Tipo, estado = Estado, sgd = DocumentoSgd FROM ejecucion.Incidencia WHERE IdContrato = @IdContrato;
GO

PRINT 'S914 aplicada: REQ-PRU-EJEC-0001 con contrato de bienes, dos entregas cerradas y una incidencia atendida.';
GO
