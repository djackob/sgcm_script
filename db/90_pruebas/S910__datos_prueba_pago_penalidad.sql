/*
===============================================================================
  SIGCM - S910 : Entregable CON PENALIDAD, para probar el Anexo 10
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750

  FUERA DE LA SERIE. Repetible y se limpia solo, igual que S909.

  ---------------------------------------------------------------------------
  QUE PRUEBA, Y EN QUE SE DIFERENCIA DE S909
  ---------------------------------------------------------------------------
  S909 siembra el caso feliz: locador persona juridica y entregables presentados
  en plazo, sin mora. Con eso NUNCA se ve el Anexo 10, porque la Directiva lo
  pide "de corresponder" y sin atraso no corresponde.

  S910 siembra el otro caso, el que faltaba:

    - LOCADOR PERSONA NATURAL, con DNI y apellidos en vez de razon social.
    - FECHA DE INICIO EN EL PASADO: el cronograma queda vencido, asi que los
      entregables se presentan TARDE y al aprobar la conformidad tecnica la
      rutina calcula dias de atraso.
    - Con atraso hay penalidad por mora, y entonces:
        * el boton de la DEC dice "Generar Anexos 9 y 10" en vez de solo el 9;
        * el Anexo 11 marca CORRESPONDE PENALIDAD = Si;
        * el giro exige la papeleta de deposito de penalidades.

  El atraso NO se escribe a mano: se consigue moviendo la fecha de inicio del
  requerimiento hacia atras y dejando que pago.paAprobarConformidadTecnica haga
  su cuenta. Un UPDATE de DiasAtraso daria el numero sin ejercitar la formula,
  que es justamente lo que hay que probar.

  ---------------------------------------------------------------------------
  COMO SE USA
  ---------------------------------------------------------------------------
      sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I \
             -i db/90_pruebas/S910__datos_prueba_pago_penalidad.sql

  Vuelve a correrlo cuantas veces quieras: borra lo suyo y lo rehace. Convive
  con S909: son dos requerimientos distintos y cada script limpia solo el suyo.

  Deja:
    REQ-PRU-PAGO-0002   en REQ_OS_EMITIDA, area usuaria OTI, locacion,
                        con 2 entregables de S/ 2,000.00: el 1 llega 10 dias tarde
                        -con penalidad- y el 2 dentro de plazo.
    O/S PRU-OS-0002     emitida.
    2 expedientes de pago, los dos presentados fuera de plazo.

  El recorrido sigue igual: 46183970 aprueba la conformidad tecnica -y ahi
  aparece el atraso-, 44687266 firma el Anexo 11, 45648851 liquida con los
  Anexos 9 y 10, 17400217 devenga y 10712503 gira.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Codigo        varchar(40) = 'REQ-PRU-PAGO-0002';
DECLARE @NumeroOrden   varchar(40) = 'PRU-OS-0002';
DECLARE @Ahora         datetime    = GETDATE();
DECLARE @AnoEje        smallint    = YEAR(GETDATE());
DECLARE @SecEjec       int         = 1750;
DECLARE @Entregables   int         = 2;
DECLARE @MontoMensual  decimal(18,2) = 2000.00;

/* La orden se emitio hace 40 dias y cada entregable vence a los 30 dias del
   anterior. Con eso el PRIMERO llega 10 dias tarde -y genera penalidad- y el
   SEGUNDO todavia esta en plazo. Asi el mismo requerimiento muestra los dos
   casos: el boton de la DEC dice "Anexos 9 y 10" en uno y solo "Anexo 9" en el
   otro.

   El numero no es caprichoso: 10 dias x S/ 16.67 = S/ 166.70, por debajo del
   10 % del contrato (S/ 400), que es el tope que dispara ALERTA_RESOLUCION. Un
   atraso mayor obligaria a confirmar la alerta en cada prueba. */
DECLARE @DiasAtras    int         = 40;

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
    THROW 59095, 'NO_ENCONTRADO: no hay un AREA_ESPECIALISTA del SSO en OTI. Entra una vez con 46183970 para que se sincronice el padron.', 1;

IF OBJECT_ID('pago.ExpedientePago', 'U') IS NULL
    THROW 59096, 'FALTA_MIGRACION: no existe pago.ExpedientePago. Corre instalar.ps1 antes.', 1;

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
    /* Cada expediente de PAGO es un sigcm.Expediente propio, distinto del de
       requerimiento, y la limpieza tiene que barrer los dos. Los ids se anotan
       ANTES de tocar pago.ExpedientePago, porque despues ya no habria por donde
       encontrar los de pago. */
    DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY);
    INSERT INTO @Exp (IdExpediente) VALUES (@IdExpediente);
    INSERT INTO @Exp (IdExpediente)
    SELECT p.IdExpediente
      FROM pago.ExpedientePago AS p
     WHERE p.IdRequerimiento = @IdRequerimiento
       AND NOT EXISTS (SELECT 1 FROM @Exp AS x WHERE x.IdExpediente = p.IdExpediente);

    /* Los documentos y lo que cuelga de ellos. Un expediente por el que ya paso
       alguien trae su Anexo 11 con firma: sin esto la limpieza muere en
       FK_sigcm_DocExp_Expediente y el script deja de ser repetible, que es
       justo lo que paso la primera vez que se recorrio el flujo de verdad. */
    DECLARE @Doc TABLE (IdDocumento uniqueidentifier PRIMARY KEY);
    INSERT INTO @Doc (IdDocumento)
    SELECT DISTINCT de.IdDocumento
      FROM sigcm.DocumentoExpediente AS de
      JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;

    DELETE f
      FROM sigcm.Firma AS f
      JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumentoVersion = f.IdDocumentoVersion
      JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;

    DELETE o FROM sigcm.Observacion AS o
      JOIN @Exp AS x ON x.IdExpediente = o.IdExpediente;

    DELETE dv FROM sigcm.DocumentoVersion AS dv
      JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;

    DELETE de FROM sigcm.DocumentoExpediente AS de
      JOIN @Exp AS x ON x.IdExpediente = de.IdExpediente;

    DELETE doc FROM sigcm.Documento AS doc
      JOIN @Doc AS d ON d.IdDocumento = doc.IdDocumento;

    DELETE pl FROM sigcm.Plazo AS pl
      JOIN @Exp AS x ON x.IdExpediente = pl.IdExpediente;

    /* ChecklistMarca e HitoSincronizacion cuelgan del expediente de pago. */
    DELETE m
      FROM pago.ChecklistMarca AS m
      JOIN pago.ExpedientePago AS p ON p.IdExpedientePago = m.IdExpedientePago
     WHERE p.IdRequerimiento = @IdRequerimiento;

    DELETE h
      FROM pago.HitoSincronizacion AS h
      JOIN pago.ExpedientePago AS p ON p.IdExpedientePago = h.IdExpedientePago
     WHERE p.IdRequerimiento = @IdRequerimiento;

    DELETE h FROM sigcm.Historial AS h
      JOIN @Exp AS x ON x.IdExpediente = h.IdExpediente;

    DELETE FROM pago.ExpedientePago WHERE IdRequerimiento = @IdRequerimiento;

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

    DELETE FROM requerimiento.Requerimiento WHERE IdRequerimiento = @IdRequerimiento;

    DELETE e FROM sigcm.Expediente AS e
      JOIN @Exp AS x ON x.IdExpediente = e.IdExpediente;
END

/* -------------------------------------------------------------------------- */
/* 2. Expediente y requerimiento                                              */
/* -------------------------------------------------------------------------- */

SET @IdExpediente    = NEWID();
SET @IdRequerimiento = NEWID();

/* El proveedor va como PERSONA NATURAL, con DNI y apellidos: es el caso que
   S909 no cubre, porque alli el locador es una empresa con razon social. Entre
   los dos scripts quedan probadas las dos formas de nombrar al locador. */
DECLARE @Datos nvarchar(max) = (
    SELECT Proveedores = JSON_QUERY((
               SELECT TipoDocumento       = 'DNI',
                      Dni                 = '45678912',
                      Ruc                 = '10456789123',
                      RazonSocial         = '',
                      Nombres             = 'ROSA ELENA',
                      ApellidoPaterno     = 'QUISPE',
                      ApellidoMaterno     = 'HUAMAN',
                      Email               = 'locador.natural@anin.gob.pe',
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
        'S910', @Ahora, 'SEED', 'SIGCM-PRUEBA');

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
        @Entregables * @MontoMensual, 60, DATEADD(day, -@DiasAtras, CONVERT(date, @Ahora)),
        'Expediente sembrado por S910 para probar el modulo de pagos.',
        @IdResponsable, @Datos, 1,
        'S910', @Ahora, 'SEED', 'SIGCM-PRUEBA');

/* Un solo movimiento, y dice lo que es. No se falsifica el recorrido de
   aprobaciones: si la trazabilidad mostrara catorce pasos que nadie dio, el
   primero que la lea creeria que el expediente se aprobo de verdad. */
INSERT INTO sigcm.Historial
      (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
       Comentario, IdActor, ActorRol, IdActorUnidad, OcurridoEn)
VALUES (@IdExpediente, NULL, 'REQ_OS_EMITIDA', NULL,
        'Expediente sembrado por S910 directamente en REQ_OS_EMITIDA, para probar el modulo de pagos. No recorrio el flujo.',
        @IdResponsable, 'AREA_ESPECIALISTA', @IdUnidad, @Ahora);

/* -------------------------------------------------------------------------- */
/* 3. Orden de servicio                                                       */
/* -------------------------------------------------------------------------- */

/* La orden se emitio hace @DiasAtras dias: pago.paAbrirDesdeOrdenServicioInterno
   arma el cronograma desde FechaEmision, asi que con la emision en el pasado los
   vencimientos de los dos entregables ya pasaron y la presentacion de hoy llega
   tarde. Ese es todo el truco del script.

   EstadoIntegracion = 'SIMULADO' y las claves de SIGA en NULL: esta fila la
   habria escrito W002 al drenar CREAR_ORDEN_SERVICIO. Dejarla marcada evita
   que alguien la confunda con una orden realmente emitida en SIGA. */
INSERT INTO requerimiento.OrdenServicio
      (IdRequerimiento, NumeroOrden, FechaEmision, CorreoLocador, CorreoAreaUsuaria,
       Activo, EstadoIntegracion,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria,
       EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdRequerimiento, @NumeroOrden, DATEADD(day, -@DiasAtras, @Ahora),
        'locador.natural@anin.gob.pe', 'area.prueba@anin.gob.pe',
        1, 'SIMULADO',
        'S910', @Ahora, 'SEED', 'SIGCM-PRUEBA');

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

DECLARE @CuentaLocador varchar(120) = 'locador.natural';
DECLARE @IdLocador     uniqueidentifier;

SELECT @IdLocador = IdUsuario FROM sigcm.Usuario WHERE Cuenta = @CuentaLocador;

IF @IdLocador IS NULL
BEGIN
    SET @IdLocador = NEWID();
    INSERT INTO sigcm.Usuario (IdUsuario, Cuenta, Nombres, Apellidos, Correo, Activo,
                               UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                               EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
    VALUES (@IdLocador, @CuentaLocador, 'ROSA ELENA', 'QUISPE HUAMAN',
            'locador.natural@anin.gob.pe', 1,
            'S910', @Ahora, 'SEED', 'SIGCM-PRUEBA');
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
            'S910', @Ahora, 'SEED', 'SIGCM-PRUEBA');

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
       AND p.NumeroEntregable IN (1, 2)   /* los dos, no queda ninguno pendiente */
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

PRINT 'S910 aplicada: REQ-PRU-PAGO-0002 en REQ_OS_EMITIDA con su orden y sus expedientes de pago.';
GO
