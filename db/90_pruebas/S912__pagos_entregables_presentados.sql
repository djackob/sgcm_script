/*
===============================================================================
  SIGCM - S912 : Entregables presentados sobre expedientes de pago YA ABIERTOS
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM] del servidor DESPLEGADO (192.168.40.74). NO TOCA SIGA_1750.

  FUERA DE LA SERIE. Repetible: si el entregable ya esta presentado, lo deja.

  ---------------------------------------------------------------------------
  POR QUE EXISTE, Y EN QUE SE DIFERENCIA DE S909/S910
  ---------------------------------------------------------------------------
  S909 y S910 siembran un requerimiento entero con su orden de servicio para
  poder llegar a pagos. En el ambiente DESPLEGADO eso no hace falta y ademas
  sobra: la base ya tiene requerimientos reales con la orden emitida y sus
  expedientes de pago abiertos, todos en PAG_PENDIENTE. Lo unico que falta para
  arrancar el recorrido de pagos es el PASO 1, que lo da el locador desde el
  portal externo, y ese portal no siempre esta montado.

  Este script solo hace ese paso 1. NO crea requerimientos, NO crea ordenes de
  servicio, NO toca CMN, NO escribe en integracion.Operacion ni en SIGA. Se
  limita a los expedientes que ya existen en pago.ExpedientePago.

  ---------------------------------------------------------------------------
  QUE HACE, EXACTAMENTE
  ---------------------------------------------------------------------------
  1. Por cada requerimiento con expedientes de pago abiertos, toma los primeros
     @PorRequerimiento entregables (por numero) y los deja PRESENTADOS. Los que
     ya avanzaron cuentan para ese cupo, asi que volver a correrlo no arrastra
     el resto del cronograma.
  2. Los demas entregables quedan en PAG_PENDIENTE a proposito, para que
     tambien se pueda ver el estado inicial y recorrer el portal del locador.

  SE USA LA RUTINA REAL, pago.paPresentarEntregable, y no un UPDATE de estado:
  ella valida los documentos obligatorios, marca el RHE como validado, calcula
  la retencion de 4ta y mueve el expediente por la maquina de estados
  (PAG_PRESENTAR). Un UPDATE dejaria el estado correcto y todo lo demas falso.

  LO UNICO QUE ESCRIBE FUERA DEL ESQUEMA pago
  El actor del paso 1 es el rol PROVEEDOR, y paResolverActor exige una terna
  cuenta+rol+unidad vigente. El locador no entra por el SSO institucional, asi
  que si no esta en el padron se le da de alta a partir de los datos que YA
  tiene su expediente de pago (documento, nombre, correo): una fila en
  sigcm.Usuario y otra en sigcm.UsuarioRol, marcadas con programa SIGCM-PRUEBA.
  Si ya existe, no se toca. Esa misma cuenta es la que usa el portal del locador.

  Los identificadores de archivo son marcadores: en el file server no hay
  ningun PDF detras. La rutina solo exige que vengan.

  ---------------------------------------------------------------------------
  COMO SE USA
  ---------------------------------------------------------------------------
      sqlcmd -S 192.168.40.74 -U w_sgcmenores -d DBSIGCM -b -I \
             -i db/90_pruebas/S912__pagos_entregables_presentados.sql

  La clave del usuario no va aqui: vive en CNX_BASEDATOS_DESA.txt, fuera de los
  repositorios.

  Y entonces el recorrido de pagos arranca en su paso 2: el especialista del
  area usuaria (46183970) ve los entregables en su bandeja y puede aprobar la
  conformidad tecnica u observarlos.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Cuantos entregables se dejan presentados por requerimiento. El resto del
   cronograma se queda en PAG_PENDIENTE. */
DECLARE @PorRequerimiento int = 2;

DECLARE @Ahora datetime = GETDATE();

IF OBJECT_ID('pago.paPresentarEntregable', 'P') IS NULL
    THROW 59120, 'FALTA_MIGRACION: no existe pago.paPresentarEntregable. Corre instalar.ps1 antes.', 1;

/* -------------------------------------------------------------------------- */
/* 1. A quien le toca                                                         */
/* -------------------------------------------------------------------------- */
/* El cupo cuenta los que YA avanzaron: si el entregable 1 esta en conformidad
   y el cupo es 2, aqui solo entra el 2. */

IF OBJECT_ID('tempdb..#Objetivo') IS NOT NULL DROP TABLE #Objetivo;

SELECT p.IdExpedientePago,
       p.IdExpediente,
       p.IdRequerimiento,
       p.CodigoRequerimiento,
       p.NumeroEntregable,
       CodigoPago   = e.Codigo,
       Version      = e.Version,
       IdUnidad     = e.IdUnidadActual,
       Documento    = COALESCE(NULLIF(p.DniLocador, ''), NULLIF(p.RucLocador, '')),
       Nombre       = p.NombreLocador,
       Correo       = p.CorreoLocador,
       Orden        = ROW_NUMBER() OVER (PARTITION BY p.IdRequerimiento ORDER BY p.NumeroEntregable),
       /* Los que ya avanzaron NO estan en este conjunto -el WHERE de abajo lo
          deja solo con pendientes-, asi que se cuentan aparte. Con una funcion
          de ventana saldria siempre cero y cada corrida presentaria dos mas. */
       YaAvanzados  = (SELECT COUNT(*)
                         FROM pago.ExpedientePago AS q
                         JOIN sigcm.Expediente    AS f ON f.IdExpediente = q.IdExpediente
                        WHERE q.IdRequerimiento = p.IdRequerimiento
                          AND q.Activo = 1 AND f.Anulado = 0
                          AND f.CodigoEstado <> 'PAG_PENDIENTE')
  INTO #Objetivo
  FROM pago.ExpedientePago AS p
  JOIN sigcm.Expediente    AS e ON e.IdExpediente = p.IdExpediente
 WHERE p.Activo = 1
   AND e.Anulado = 0
   AND e.CodigoEstado = 'PAG_PENDIENTE';

DELETE FROM #Objetivo WHERE Orden > @PorRequerimiento - YaAvanzados;

/* Sin documento no hay cuenta de locador que valga: paResolverActor cruza por
   Cuenta y el portal del locador cruza por DNI/RUC. */
DELETE FROM #Objetivo WHERE Documento IS NULL;

IF NOT EXISTS (SELECT 1 FROM #Objetivo)
BEGIN
    PRINT 'S912: no hay ningun entregable pendiente que presentar. Nada que hacer.';
    RETURN;
END

/* -------------------------------------------------------------------------- */
/* 2. Alta del locador como PROVEEDOR, solo si falta                          */
/* -------------------------------------------------------------------------- */
/* El rol va contra la unidad que tiene el expediente -el area usuaria que
   contrato-, porque el motor comprueba que el actor este donde esta el
   expediente. */

DECLARE @Doc varchar(15), @Nom nvarchar(500), @Cor varchar(200), @Uni uniqueidentifier;
DECLARE @IdLocador uniqueidentifier;

DECLARE curLoc CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT Documento, Nombre, Correo, IdUnidad FROM #Objetivo;

OPEN curLoc;
FETCH NEXT FROM curLoc INTO @Doc, @Nom, @Cor, @Uni;

WHILE @@FETCH_STATUS = 0
BEGIN
    /* En blanco ANTES de buscar: un SELECT de asignacion que no encuentra fila
       deja la variable como estaba, y en la segunda vuelta del cursor eso
       significaria dar por existente al locador anterior. */
    SET @IdLocador = NULL;
    SELECT @IdLocador = IdUsuario FROM sigcm.Usuario WHERE Cuenta = @Doc;

    IF @IdLocador IS NULL
    BEGIN
        SET @IdLocador = NEWID();
        INSERT INTO sigcm.Usuario (IdUsuario, Cuenta, Nombres, Apellidos, Correo, Activo,
                                   UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                                   EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES (@IdLocador, @Doc, LEFT(@Nom, 200), N'', @Cor, 1,
                'S912', @Ahora, 'SEED', 'SIGCM-PRUEBA');
    END

    IF NOT EXISTS (SELECT 1 FROM sigcm.UsuarioRol
                    WHERE IdUsuario = @IdLocador AND CodigoRol = 'PROVEEDOR'
                      AND IdUnidad = @Uni AND Activo = 1)
        INSERT INTO sigcm.UsuarioRol (IdUsuario, CodigoRol, IdUnidad, EsTitular, Activo,
                                      UsuarioCreacionAuditoria, FechaCreacionAuditoria,
                                      EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES (@IdLocador, 'PROVEEDOR', @Uni, 1, 1,
                'S912', @Ahora, 'SEED', 'SIGCM-PRUEBA');

    FETCH NEXT FROM curLoc INTO @Doc, @Nom, @Cor, @Uni;
END

CLOSE curLoc;
DEALLOCATE curLoc;

/* -------------------------------------------------------------------------- */
/* 3. La presentacion, por la rutina real                                     */
/* -------------------------------------------------------------------------- */

DECLARE @IdExpPago uniqueidentifier, @NumEnt int, @VerPago int,
        @CodPago varchar(40), @CodigoUnidad varchar(30);

DECLARE curEnt CURSOR LOCAL FAST_FORWARD FOR
    SELECT o.IdExpediente, o.NumeroEntregable, o.Version, o.CodigoPago,
           o.Documento, un.Codigo
      FROM #Objetivo AS o
      JOIN sigcm.Unidad AS un ON un.IdUnidad = o.IdUnidad
     ORDER BY o.CodigoRequerimiento, o.NumeroEntregable;

OPEN curEnt;
FETCH NEXT FROM curEnt INTO @IdExpPago, @NumEnt, @VerPago, @CodPago, @Doc, @CodigoUnidad;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @pp nvarchar(max) = (
        SELECT Actor = JSON_QUERY((SELECT Usuario = @Doc,
                                          Rol     = 'PROVEEDOR',
                                          Unidad  = @CodigoUnidad,
                                          Equipo  = 'SEED',
                                          Programa= 'SIGCM-PRUEBA'
                                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
               IdExpediente     = CONVERT(varchar(50), @IdExpPago),
               Version          = @VerPago,
               CodigoTransicion = 'PAG_PRESENTAR',
               InformeDocumento = CONCAT('PRUEBA-INFORME-', @CodPago, '-', @NumEnt, '.pdf'),
               RhePdfDocumento  = CONCAT('PRUEBA-RHE-', @CodPago, '-', @NumEnt, '.pdf'),
               RheXmlDocumento  = CONCAT('PRUEBA-RHE-', @CodPago, '-', @NumEnt, '.xml'),
               RheSerie         = 'E001',
               RheNumero        = CONVERT(varchar(10), 500 + @NumEnt)
          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    EXEC pago.paPresentarEntregable @pp;

    FETCH NEXT FROM curEnt INTO @IdExpPago, @NumEnt, @VerPago, @CodPago, @Doc, @CodigoUnidad;
END

CLOSE curEnt;
DEALLOCATE curEnt;

/* -------------------------------------------------------------------------- */
/* 4. Comprobacion                                                            */
/* -------------------------------------------------------------------------- */
/* paPresentarEntregable atrapa sus errores y los devuelve como JSON en vez de
   levantarlos, asi que una corrida puede "terminar bien" sin haber movido
   nada. Esto lo convierte en un fallo visible. */

IF EXISTS (SELECT 1
             FROM #Objetivo AS o
             JOIN sigcm.Expediente AS e ON e.IdExpediente = o.IdExpediente
            WHERE e.CodigoEstado = 'PAG_PENDIENTE')
BEGIN
    SELECT sin_presentar = e.Codigo, entregable = o.NumeroEntregable, estado = e.CodigoEstado
      FROM #Objetivo AS o
      JOIN sigcm.Expediente AS e ON e.IdExpediente = o.IdExpediente
     WHERE e.CodigoEstado = 'PAG_PENDIENTE';

    THROW 59121, 'S912: algun entregable objetivo sigue en PAG_PENDIENTE. Mira el JSON de error que imprimio pago.paPresentarEntregable mas arriba.', 1;
END

/* -------------------------------------------------------------------------- */
/* 5. Resultado                                                               */
/* -------------------------------------------------------------------------- */

SELECT requerimiento = p.CodigoRequerimiento,
       expediente    = e.Codigo,
       entregable    = p.NumeroEntregable,
       estado        = e.CodigoEstado,
       responsable   = w.RolResponsable,
       unidad        = un.Sigla,
       locador       = p.NombreLocador,
       documento     = COALESCE(NULLIF(p.DniLocador, ''), p.RucLocador),
       monto         = p.MontoEntregable,
       cronograma    = CONVERT(varchar(10), p.FechaLimiteCronograma, 103),
       presentado    = CONVERT(varchar(10), p.FechaPresentacion, 103),
       atraso        = p.DiasAtraso,
       penalidad     = p.MontoPenalidad
  FROM pago.ExpedientePago AS p
  JOIN sigcm.Expediente    AS e  ON e.IdExpediente = p.IdExpediente
  JOIN sigcm.Estado        AS w  ON w.CodigoEstado = e.CodigoEstado
  LEFT JOIN sigcm.Unidad   AS un ON un.IdUnidad    = e.IdUnidadActual
 WHERE p.Activo = 1
 ORDER BY p.CodigoRequerimiento, p.NumeroEntregable;

DROP TABLE #Objetivo;
GO

PRINT 'S912 aplicada: los primeros entregables de cada requerimiento quedan en PAG_ENTREGABLE_PRESENTADO.';
GO
