/*
===============================================================================
  SIGCM - S909 : Requerimiento con orden de servicio emitida, para probar PAGOS
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750

  FUERA DE LA SERIE. Repetible y se limpia solo, como S903.

  ---------------------------------------------------------------------------
  POR QUE EXISTE
  ---------------------------------------------------------------------------
  El expediente de PAGO nace de una orden de servicio: pago.paAbrirDesdeOrden-
  ServicioInterno busca una fila en requerimiento.OrdenServicio y si no la
  encuentra no hace nada. Hoy no se puede llegar ahi por pantalla, por dos
  huecos de la maquina de estados que este script NO inventa ni arregla:

    1. Falta la transicion REQ_REGISTRAR_CCP (REQ_CCP_SOLICITADO ->
       REQ_CCP_CARGADA). requerimiento.paRegistrarCcp graba la certificacion
       pero no mueve el estado, asi que el expediente se queda ahi.
    2. Falta REQ_NOTIFICAR_OS (REQ_OS_EMITIDA -> REQ_NOTIFICADO), que F008
       ejecuta en su linea 1024.

  Definir esas transiciones es fijar una regla de negocio -que estados unen, que
  roles las ejecutan, si encolan hacia SIGA- y eso le toca al modulo de
  Requerimiento. Mientras tanto, esto deja el punto de partida que PAGOS
  necesita, sin tocar sigcm.Transicion.

  ---------------------------------------------------------------------------
  QUE SIMULA, Y QUE NO
  ---------------------------------------------------------------------------
  El requerimiento se crea con datos completos y coherentes, y el expediente se
  deja directamente en REQ_OS_EMITIDA con su fila en requerimiento.OrdenServicio.

  Esa fila la escribiria W002 al drenar la operacion CREAR_ORDEN_SERVICIO contra
  SIGA. Aqui se escribe a mano y con EstadoIntegracion = 'SIMULADO', porque el
  worker de integracion esta apagado en desarrollo y porque el objetivo es
  probar PAGOS, no el viaje a SIGA. Los campos que vienen de SIGA -SecCuadroSiga
  y ProveedorSiga- quedan nulos a proposito: NO son datos reales y ningun paso
  de pagos los usa.

  El historial se escribe como un solo movimiento de apertura. No se falsifica
  el recorrido completo de aprobaciones: quien mire la trazabilidad tiene que
  ver que este expediente se sembro, no que paso por catorce manos.

  ---------------------------------------------------------------------------
  COMO SE USA
  ---------------------------------------------------------------------------
      sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I \
             -i db/90_pruebas/S909__datos_prueba_pago.sql

  Vuelve a correrlo cuantas veces quieras: borra lo suyo y lo rehace.

  Deja:
    REQ-PRU-PAGO-0001   en REQ_OS_EMITIDA, area usuaria OTI, locacion,
                        con 3 entregables de S/ 1,500.00 c/u.
    O/S PRU-OS-0001     emitida.
    3 expedientes de pago en PAG_PENDIENTE, uno por entregable.

  Y entonces el recorrido de pagos arranca en su paso 1.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Codigo        varchar(40) = 'REQ-PRU-PAGO-0001';
DECLARE @NumeroOrden   varchar(40) = 'PRU-OS-0001';
DECLARE @Ahora         datetime    = GETDATE();
DECLARE @AnoEje        smallint    = YEAR(GETDATE());
DECLARE @SecEjec       int         = 1750;
DECLARE @Entregables   int         = 3;
DECLARE @MontoMensual  decimal(18,2) = 1500.00;

/* El area usuaria y el responsable salen del padron, no de un id fijo: los
   identificadores cambian en cada ambiente. Se usa el especialista de OTI, que
   es quien registra en el recorrido de prueba. */
DECLARE @IdUnidad      uniqueidentifier;
DECLARE @IdResponsable uniqueidentifier;
DECLARE @CentroCosto   varchar(15);
DECLARE @CuentaResp    varchar(120);

SELECT TOP 1
       @IdUnidad      = un.IdUnidad,
       @CentroCosto   = un.CentroCostoSiga,
       @IdResponsable = us.IdUsuario,
       @CuentaResp    = us.Cuenta
  FROM sigcm.UsuarioRol AS ur
  JOIN sigcm.Usuario    AS us ON us.IdUsuario = ur.IdUsuario
  JOIN sigcm.Unidad     AS un ON un.IdUnidad  = ur.IdUnidad
 WHERE ur.CodigoRol = 'AREA_ESPECIALISTA'
   AND un.Sigla     = 'OTI'
   AND ur.Activo = 1 AND us.Activo = 1
   AND us.Cuenta NOT LIKE 'prueba%'
 ORDER BY us.Cuenta;

IF @IdResponsable IS NULL
    THROW 59090, 'NO_ENCONTRADO: no hay un AREA_ESPECIALISTA del SSO en OTI. Entra una vez con 46183970 para que se sincronice el padron.', 1;

IF OBJECT_ID('pago.ExpedientePago', 'U') IS NULL
    THROW 59091, 'FALTA_MIGRACION: no existe pago.ExpedientePago. Corre instalar.ps1 antes.', 1;

/* -------------------------------------------------------------------------- */
/* 1. Limpieza de la corrida anterior                                         */
/* -------------------------------------------------------------------------- */

DECLARE @IdExpediente    uniqueidentifier;
DECLARE @IdRequerimiento uniqueidentifier;

SELECT @IdRequerimiento = r.IdRequerimiento, @IdExpediente = r.IdExpediente
  FROM requerimiento.Requerimiento AS r
 WHERE r.Codigo = @Codigo;

BEGIN TRANSACTION;

IF @IdRequerimiento IS NOT NULL
BEGIN
    /* En orden inverso a las dependencias. ChecklistMarca e HitoSincronizacion
       cuelgan del expediente de pago; el resto, del requerimiento. */
    DELETE m
      FROM pago.ChecklistMarca AS m
      JOIN pago.ExpedientePago AS p ON p.IdExpedientePago = m.IdExpedientePago
     WHERE p.IdRequerimiento = @IdRequerimiento;

    DELETE h
      FROM pago.HitoSincronizacion AS h
      JOIN pago.ExpedientePago AS p ON p.IdExpedientePago = h.IdExpedientePago
     WHERE p.IdRequerimiento = @IdRequerimiento;

    /* Cada expediente de PAGO es un sigcm.Expediente propio, distinto del de
       requerimiento. Sus ids se anotan ANTES de borrar la fila de pago, porque
       despues ya no habria por donde encontrarlos; y el orden es historial ->
       pago -> expediente, que es el inverso de las claves foraneas. */
    DECLARE @ExpPago TABLE (IdExpediente uniqueidentifier);
    INSERT INTO @ExpPago (IdExpediente)
    SELECT IdExpediente FROM pago.ExpedientePago WHERE IdRequerimiento = @IdRequerimiento;

    DELETE h FROM sigcm.Historial AS h
      JOIN @ExpPago AS x ON x.IdExpediente = h.IdExpediente;

    DELETE FROM pago.ExpedientePago         WHERE IdRequerimiento = @IdRequerimiento;

    DELETE e FROM sigcm.Expediente AS e
      JOIN @ExpPago AS x ON x.IdExpediente = e.IdExpediente;
    /* Todo lo que apunta al requerimiento, no solo la orden: si manana alguien
       corre este script sobre un expediente que llego mas lejos, la limpieza
       tiene que seguir funcionando. Son las ocho tablas con clave foranea
       contra requerimiento.Requerimiento. */
    DELETE FROM integracion.Operacion              WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.CertificacionCcp     WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.FiltroIdoneidad      WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.InvitacionCotizacion WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.RequerimientoItem    WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.RequerimientoPedido  WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.OrdenServicio        WHERE IdRequerimiento = @IdRequerimiento;

    DELETE FROM sigcm.Historial             WHERE IdExpediente    = @IdExpediente;
    DELETE FROM requerimiento.Requerimiento WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM sigcm.Expediente            WHERE IdExpediente    = @IdExpediente;
END

/* -------------------------------------------------------------------------- */
/* 2. Expediente y requerimiento                                              */
/* -------------------------------------------------------------------------- */

SET @IdExpediente    = NEWID();
SET @IdRequerimiento = NEWID();

/* El proveedor va como persona juridica -con RazonSocial- a proposito: es el
   caso que el modulo de pagos no cubria hasta hoy, porque componia el nombre
   del locador con apellidos que una empresa no tiene. Cambia TipoDocumento a
   'DNI' y llena Nombres/ApellidoPaterno si quieres probar el otro caso. */
DECLARE @Datos nvarchar(max) = (
    SELECT Proveedores = JSON_QUERY((
               SELECT TipoDocumento       = 'DNI',
                      Dni                 = '',
                      Ruc                 = '20601030405',
                      RazonSocial         = 'SERVICIOS INTEGRALES DE PRUEBA S.A.C.',
                      Nombres             = '',
                      ApellidoPaterno     = '',
                      ApellidoMaterno     = '',
                      Email               = 'locador.prueba@anin.gob.pe',
                      Celular             = '999888777',
                      Cci                 = '00219100123456789012',
                      CantidadEntregables = @Entregables,
                      MontoMensual        = @MontoMensual,
                      Direccion           = 'AV. PRUEBA 123'
                 FOR JSON PATH))
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

INSERT INTO sigcm.Expediente
      (IdExpediente, CodigoModulo, Codigo, AnoEje, CodigoEstado, Version,
       IdUnidadOrigen, IdUnidadActual, IdResponsableActual,
       Anulado, Activo,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria,
       EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdExpediente, 'REQUERIMIENTO', @Codigo, @AnoEje, 'REQ_OS_EMITIDA', 1,
        @IdUnidad, @IdUnidad, @IdResponsable,
        0, 1,
        'S909', @Ahora, 'SEED', 'SIGCM-PRUEBA');

INSERT INTO requerimiento.Requerimiento
      (IdRequerimiento, IdExpediente, Codigo, AnoEje, SecEjec, CentroCosto,
       Denominacion, CodigoTipoContratacion, CodigoDec, CondicionCmn,
       Monto, PlazoDias, FechaInicioPrevisto, Sustento, IdResponsable,
       DatosAdicionales, Activo,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria,
       EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdRequerimiento, @IdExpediente, @Codigo, @AnoEje, @SecEjec, @CentroCosto,
        'Servicio de prueba para el modulo de entregables y pagos',
        'LOCACION', 'ABASTECIMIENTO', 'INCLUIDO',
        @Entregables * @MontoMensual, 90, CONVERT(date, @Ahora),
        'Expediente sembrado por S909 para probar el modulo de pagos.',
        @IdResponsable, @Datos, 1,
        'S909', @Ahora, 'SEED', 'SIGCM-PRUEBA');

/* Un solo movimiento, y dice lo que es. No se falsifica el recorrido de
   aprobaciones: si la trazabilidad mostrara catorce pasos que nadie dio, el
   primero que la lea creeria que el expediente se aprobo de verdad. */
INSERT INTO sigcm.Historial
      (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
       Comentario, IdActor, ActorRol, IdActorUnidad, OcurridoEn)
VALUES (@IdExpediente, NULL, 'REQ_OS_EMITIDA', NULL,
        'Expediente sembrado por S909 directamente en REQ_OS_EMITIDA, para probar el modulo de pagos. No recorrio el flujo.',
        @IdResponsable, 'AREA_ESPECIALISTA', @IdUnidad, @Ahora);

/* -------------------------------------------------------------------------- */
/* 3. Orden de servicio                                                       */
/* -------------------------------------------------------------------------- */

/* EstadoIntegracion = 'SIMULADO' y las claves de SIGA en NULL: esta fila la
   habria escrito W002 al drenar CREAR_ORDEN_SERVICIO. Dejarla marcada evita
   que alguien la confunda con una orden realmente emitida en SIGA. */
INSERT INTO requerimiento.OrdenServicio
      (IdRequerimiento, NumeroOrden, FechaEmision, CorreoLocador, CorreoAreaUsuaria,
       Activo, EstadoIntegracion,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria,
       EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdRequerimiento, @NumeroOrden, @Ahora,
        'locador.prueba@anin.gob.pe', 'area.prueba@anin.gob.pe',
        1, 'SIMULADO',
        'S909', @Ahora, 'SEED', 'SIGCM-PRUEBA');

COMMIT TRANSACTION;

/* -------------------------------------------------------------------------- */
/* 4. Apertura de los expedientes de pago                                     */
/* -------------------------------------------------------------------------- */

/* Por la rutina real, no a mano: es la misma que corre el sistema al emitir la
   orden, y asi la prueba ejercita el codigo de Jack en vez de imitarlo. */
DECLARE @p nvarchar(max) = (
    SELECT Actor = JSON_QUERY((SELECT Usuario = @CuentaResp,
                                      Rol     = 'AREA_ESPECIALISTA',
                                      Unidad  = (SELECT Codigo FROM sigcm.Unidad WHERE IdUnidad = @IdUnidad)
                                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
           IdRequerimiento = CONVERT(varchar(50), @IdRequerimiento)
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

EXEC pago.paAbrirDesdeOrdenServicioInterno @p;

/* -------------------------------------------------------------------------- */
/* 5. Locador de prueba, y dos entregables ya presentados                     */
/* -------------------------------------------------------------------------- */

/*
  POR QUE HACE FALTA
  El primer paso del flujo de pagos lo da el rol PROVEEDOR desde el portal
  externo, y ese portal no se puede recorrer hoy: no hay ningun usuario con ese
  rol en el padron, porque el locador no entra por el SSO institucional. Con los
  tres entregables en PAG_PENDIENTE la bandeja del area usuaria queda vacia y el
  flujo muere en el primer escalon.

  Asi que se crea un locador de prueba y se presentan dos de los tres
  entregables EN SU NOMBRE. El tercero se deja pendiente a proposito, para que
  tambien se pueda ver el estado inicial y, si se quiere, recorrer el portal.

  SE USA LA RUTINA REAL, pago.paPresentarEntregable, y no un UPDATE de estado:
  ella valida los documentos obligatorios, calcula el atraso y la penalidad
  contra el cronograma y mueve el expediente por la maquina de estados. Un
  UPDATE dejaria el expediente en el estado correcto pero sin nada de eso, y la
  prueba del area usuaria seria falsa.
*/

DECLARE @CuentaLocador varchar(120) = 'locador.prueba';
DECLARE @IdLocador     uniqueidentifier;

SELECT @IdLocador = IdUsuario FROM sigcm.Usuario WHERE Cuenta = @CuentaLocador;

IF @IdLocador IS NULL
BEGIN
    SET @IdLocador = NEWID();
    INSERT INTO sigcm.Usuario (IdUsuario, Cuenta, Nombres, Apellidos, Correo, Activo,
                               UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                               EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES (@IdLocador, @CuentaLocador, 'SERVICIOS INTEGRALES', 'DE PRUEBA S.A.C.',
            'locador.prueba@anin.gob.pe', 1,
            'S909', @Ahora, 'SEED', 'SIGCM-PRUEBA');
END

/* El rol va contra la unidad que tiene el expediente -el area usuaria que
   contrato-, porque paResolverActor exige una terna cuenta+rol+unidad vigente y
   el motor comprueba que el actor este donde esta el expediente. */
IF NOT EXISTS (SELECT 1 FROM sigcm.UsuarioRol
                WHERE IdUsuario = @IdLocador AND CodigoRol = 'PROVEEDOR'
                  AND IdUnidad = @IdUnidad AND Activo = 1)
    INSERT INTO sigcm.UsuarioRol (IdUsuario, CodigoRol, IdUnidad, EsTitular, Activo,
                                  UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                                  EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES (@IdLocador, 'PROVEEDOR', @IdUnidad, 1, 1,
            'S909', @Ahora, 'SEED', 'SIGCM-PRUEBA');

DECLARE @CodigoUnidad varchar(30) = (SELECT Codigo FROM sigcm.Unidad WHERE IdUnidad = @IdUnidad);

/* Los identificadores de archivo son marcadores, no archivos reales: en el file
   server no hay nada detras. Sirven porque la rutina solo exige que vengan; si
   alguien abre el documento desde la pantalla no encontrara el PDF, y eso es lo
   esperado en un expediente sembrado. */
DECLARE @IdExpPago uniqueidentifier, @NumEnt int, @VerPago int;

DECLARE curEnt CURSOR LOCAL FAST_FORWARD FOR
    SELECT p.IdExpediente, p.NumeroEntregable, e.Version
      FROM pago.ExpedientePago AS p
      JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
     WHERE p.IdRequerimiento = @IdRequerimiento
       AND p.NumeroEntregable IN (1, 2)
     ORDER BY p.NumeroEntregable;

OPEN curEnt;
FETCH NEXT FROM curEnt INTO @IdExpPago, @NumEnt, @VerPago;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @pp nvarchar(max) = (
        SELECT Actor = JSON_QUERY((SELECT Usuario = @CuentaLocador,
                                          Rol     = 'PROVEEDOR',
                                          Unidad  = @CodigoUnidad
                                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
               IdExpediente       = CONVERT(varchar(50), @IdExpPago),
               Version            = @VerPago,
               CodigoTransicion   = 'PAG_PRESENTAR',
               InformeDocumento   = CONCAT('PRUEBA-INFORME-', @NumEnt, '.pdf'),
               RhePdfDocumento    = CONCAT('PRUEBA-RHE-', @NumEnt, '.pdf'),
               RheXmlDocumento    = CONCAT('PRUEBA-RHE-', @NumEnt, '.xml'),
               RheSerie           = 'E001',
               RheNumero          = CONVERT(varchar(10), 500 + @NumEnt)
          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    EXEC pago.paPresentarEntregable @pp;

    FETCH NEXT FROM curEnt INTO @IdExpPago, @NumEnt, @VerPago;
END

CLOSE curEnt;
DEALLOCATE curEnt;

/* -------------------------------------------------------------------------- */
/* 5. Resultado                                                               */
/* -------------------------------------------------------------------------- */

SELECT requerimiento = r.Codigo,
       estado        = e.CodigoEstado,
       area          = un.Sigla,
       orden         = o.NumeroOrden,
       integracion   = o.EstadoIntegracion,
       expedientes_pago = (SELECT COUNT(*) FROM pago.ExpedientePago
                            WHERE IdRequerimiento = r.IdRequerimiento)
  FROM requerimiento.Requerimiento AS r
  JOIN sigcm.Expediente AS e  ON e.IdExpediente = r.IdExpediente
  JOIN sigcm.Unidad     AS un ON un.IdUnidad    = e.IdUnidadActual
  LEFT JOIN requerimiento.OrdenServicio AS o ON o.IdRequerimiento = r.IdRequerimiento
 WHERE r.Codigo = @Codigo;

SELECT entregable = p.NumeroEntregable,
       expediente = e.Codigo,
       estado     = e.CodigoEstado,
       responsable= w.RolResponsable,
       presentado = CONVERT(varchar(10), p.FechaPresentacion, 103),
       atraso     = p.DiasAtraso,
       penalidad  = p.MontoPenalidad,
       locador    = p.NombreLocador
  FROM pago.ExpedientePago AS p
  JOIN sigcm.Expediente AS e ON e.IdExpediente = p.IdExpediente
  JOIN sigcm.Estado     AS w ON w.CodigoEstado = e.CodigoEstado
 WHERE p.IdRequerimiento = @IdRequerimiento
 ORDER BY p.NumeroEntregable;
GO

PRINT 'S909 aplicada: REQ-PRU-PAGO-0001 en REQ_OS_EMITIDA con su orden y sus expedientes de pago.';
GO
