/*
===============================================================================
  SIGCM - S917 : Muestra del Anexo 5 con cuatro propuestas (caso SEJDI en papel)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750

  FUERA DE LA SERIE. Repetible y se limpia solo, como S909.

  ---------------------------------------------------------------------------
  POR QUE EXISTE
  ---------------------------------------------------------------------------
  Reproduce el expediente fisico de la SEJDI: un Anexo 5 con cuatro locadores,
  cada uno con su propia denominacion, plazo y varios pedidos SIGA, y el TDR
  de Astrid Ita Luna (pedidos 7997-8000) cuyas metas solo se distinguen por el
  CUI. Sirve para probar el rediseño del registro (propuesta con varios
  pedidos) y del Anexo 3 (TDR armado para una propuesta elegida).

  ---------------------------------------------------------------------------
  QUE SIMULA, Y QUE NO
  ---------------------------------------------------------------------------
  - Se inserta directo, sin requerimiento.paRegistrarRequerimiento: la rutina
    compara el tope de ocho UIT (S/ 44,000.00) contra la SUMA de las cuatro
    filas (S/ 89,000.00) y rechaza el caso, aunque cada contrato por separado
    queda debajo del tope. Mientras esa regla no cambie, GUARDAR el registro
    desde la pantalla devuelve el mismo error; el Anexo 5 y el Anexo 3 si se
    pueden generar.
  - Los pedidos 7988-8000 todavia no estan en la copia de SIGA (llega al
    7950). Se graban con Verificado = 0, igual que cualquier pedido del
    registro.
  - Area usuaria y responsable: el especialista de OTI que se usa en las
    pruebas. La SEJDI no tiene a nadie con rol en el padron y nadie podria
    abrir el expediente desde la bandeja.
  - Metas: solo los pedidos de Astrid (7997-8000) tienen su hoja SIGA. Para
    los demas se repite la meta de los CUI conocidos (2386498 -> 32,
    2386533 -> 34, 2512573 -> 139); los CUI 2321591 y 2511978 quedan sin meta.
  - Direccion y ubigeo no figuran en el Anexo 5; van con un valor de prueba
    porque el formulario los exige.

  ---------------------------------------------------------------------------
  COMO SE USA
  ---------------------------------------------------------------------------
      sqlcmd -S 192.168.40.74 -U w_sgcmenores -d DBSIGCM -b -I -f 65001 \
             -i db/90_pruebas/S917__muestra_anexo5_cuatro_propuestas.sql

  Deja:
    REQ-PRU-ANX5-0001   en REQ_DOC_PENDIENTE, area usuaria OTI, locacion,
                        cuatro propuestas y once pedidos.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Codigo  varchar(40) = 'REQ-PRU-ANX5-0001';
DECLARE @Ahora   datetime    = GETDATE();
DECLARE @AnoEje  smallint    = 2026;
DECLARE @SecEjec int         = 1750;

DECLARE @IdUnidad      uniqueidentifier;
DECLARE @IdResponsable uniqueidentifier;
DECLARE @CentroCosto   varchar(15);

SELECT TOP 1
       @IdUnidad      = un.IdUnidad,
       @CentroCosto   = un.CentroCostoSiga,
       @IdResponsable = us.IdUsuario
  FROM sigcm.UsuarioRol AS ur
  JOIN sigcm.Usuario    AS us ON us.IdUsuario = ur.IdUsuario
  JOIN sigcm.Unidad     AS un ON un.IdUnidad  = ur.IdUnidad
 WHERE ur.CodigoRol = 'AREA_ESPECIALISTA'
   AND un.Sigla     = 'OTI'
   AND ur.Activo = 1 AND us.Activo = 1
 ORDER BY CASE WHEN us.Cuenta = '46183970' THEN 0 ELSE 1 END, us.Cuenta;

IF @IdResponsable IS NULL
    THROW 59170, 'NO_ENCONTRADO: no hay un AREA_ESPECIALISTA en OTI. Entra una vez con 46183970 para que se sincronice el padron.', 1;

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
    DECLARE @Doc TABLE (IdDocumento uniqueidentifier PRIMARY KEY);
    INSERT INTO @Doc (IdDocumento)
    SELECT DISTINCT de.IdDocumento
      FROM sigcm.DocumentoExpediente AS de
     WHERE de.IdExpediente = @IdExpediente;

    DELETE f
      FROM sigcm.Firma AS f
      JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumentoVersion = f.IdDocumentoVersion
      JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;

    DELETE FROM sigcm.Observacion WHERE IdExpediente = @IdExpediente;

    DELETE dv FROM sigcm.DocumentoVersion AS dv
      JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;

    DELETE FROM sigcm.DocumentoExpediente WHERE IdExpediente = @IdExpediente;

    DELETE doc FROM sigcm.Documento AS doc
      JOIN @Doc AS d ON d.IdDocumento = doc.IdDocumento;

    DELETE FROM sigcm.Plazo     WHERE IdExpediente = @IdExpediente;
    DELETE FROM sigcm.Historial WHERE IdExpediente = @IdExpediente;

    DELETE FROM integracion.Operacion              WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.CertificacionCcp     WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.FiltroIdoneidad      WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.InvitacionCotizacion WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.RequerimientoItem    WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.RequerimientoPedido  WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.OrdenServicio        WHERE IdRequerimiento = @IdRequerimiento;
    DELETE FROM requerimiento.Requerimiento        WHERE IdRequerimiento = @IdRequerimiento;

    DELETE FROM sigcm.Expediente WHERE IdExpediente = @IdExpediente;
END

/* -------------------------------------------------------------------------- */
/* 2. Datos del papel                                                         */
/* -------------------------------------------------------------------------- */

/* Una fila por pedido SIGA, en el orden en que los devuelve
   paObtenerRequerimiento (por NumeroPedido): PedidosExtra se empareja por
   posicion con esas filas. */
DECLARE @Ped TABLE (
    Orden         int PRIMARY KEY,
    Propuesta     int,
    NumeroPedido  varchar(20),
    Cui           varchar(10),
    SecFunc       int NULL,
    Meta          varchar(10),
    Monto         decimal(18,2),
    CodigoItem    varchar(20),
    NombreItem    nvarchar(350)
);

INSERT INTO @Ped VALUES
 ( 1, 1, '007988', '2386498',   32, '32',  18000.00, '', N'SERVICIO ESPECIALIZADO LEGAL PARA LA GESTIÓN DE PROYECTOS DE INVERSIÓN PÚBLICA'),
 ( 2, 1, '007989', '2511978', NULL, '',    18000.00, '', N'SERVICIO ESPECIALIZADO LEGAL PARA LA GESTIÓN DE PROYECTOS DE INVERSIÓN PÚBLICA'),
 ( 3, 2, '007992', '2321591', NULL, '',     4500.00, '', N'SERVICIO DE ASISTENCIA TÉCNICA PARA EL MONITOREO Y SEGUIMIENTO DE PROYECTOS DE INVERSIÓN'),
 ( 4, 2, '007993', '2386533',   34, '34',   4500.00, '', N'SERVICIO DE ASISTENCIA TÉCNICA PARA EL MONITOREO Y SEGUIMIENTO DE PROYECTOS DE INVERSIÓN'),
 ( 5, 3, '007994', '2386533',   34, '34',   8000.00, '', N'SERVICIO EN GESTIÓN TÉCNICA DE CIERRE COMERCIAL Y EQUIPAMIENTO'),
 ( 6, 3, '007995', '2321591', NULL, '',     8000.00, '', N'SERVICIO EN GESTIÓN TÉCNICA DE CIERRE COMERCIAL Y EQUIPAMIENTO'),
 ( 7, 3, '007996', '2512573',  139, '139',  8000.00, '', N'SERVICIO EN GESTIÓN TÉCNICA DE CIERRE COMERCIAL Y EQUIPAMIENTO'),
 ( 8, 4, '007997', '2386498',   32, '32',   5000.00, '071100380780', N'SERVICIO ESPECIALIZADO EN INGENIERIA SANITARIA'),
 ( 9, 4, '007998', '2386533',   34, '34',   5000.00, '071100380780', N'SERVICIO ESPECIALIZADO EN INGENIERIA SANITARIA'),
 (10, 4, '007999', '2427546',  280, '280',  5000.00, '071100380780', N'SERVICIO ESPECIALIZADO EN INGENIERIA SANITARIA'),
 (11, 4, '008000', '2512573',  139, '139',  5000.00, '071100380780', N'SERVICIO ESPECIALIZADO EN INGENIERIA SANITARIA');

DECLARE @Prov TABLE (
    Propuesta           int PRIMARY KEY,
    Dni                 varchar(8),
    Ruc                 varchar(11),
    Nombres             nvarchar(120),
    ApellidoPaterno     nvarchar(80),
    ApellidoMaterno     nvarchar(80),
    Email               varchar(120),
    Celular             varchar(15),
    Denominacion        nvarchar(1000),
    MontoMensual        decimal(18,2),
    CantidadEntregables int,
    PlazoDias           int
);

INSERT INTO @Prov VALUES
 (1, '48278614', '10482786141', N'VANESSA LISBETH', N'CATALAN', N'AGRAMONTE',
     'vane.catalanagramonte8294@gmail.com', '912332823',
     N'Servicio especializado legal para la Gestión de proyectos de Inversión Pública con CUI 2386498, 2511978 del sector salud de la cartera de la Subdirección de Ejecución de Inversión',
     12000.00, 3, 90),
 (2, '72880945', '10728809456', N'CÉSAR OSWALDO', N'VERA', N'LUNA',
     'cesar.vera.3208@outlook.es', '969282716',
     N'SERVICIO DE ASISTENCIA TÉCNICA PARA EL MONITOREO, SEGUIMIENTO PARA LA GESTIÓN DE PROYECTOS DE INVERSIÓN PÚBLICA, INCLUYENDO SOPORTE EN LA GESTIÓN Y CONCILIACIÓN FINANCIERA DE LOS PROYECTOS CON CUI 2321591, 2386533 DEL SECTOR SALUD DE LA CARTERA DE LA SUBDIRECCION DE EJECUCION DE INVERSION',
     3000.00, 3, 90),
 (3, '44537076', '10445370768', N'LUIS ALBERTO', N'MEDINA', N'REYNA',
     'luismedina2908@gmail.com', '941212519',
     N'Servicio en la especialidad de gestión técnica en cierre comercial de proyectos y la gestión del componente de equipamiento con CUI N° 2386533, 2321591 y 2512573 en etapa de ejecución contractual, proyectos correspondientes a la Subdirección de Ejecución de Inversión.',
     8000.00, 3, 90),
 (4, '41588429', '10415884295', N'ASTRID IRIS', N'ITA', N'LUNA',
     'irisastridi@gmail.com', '944982600',
     N'Servicio especializado en materia de instalaciones sanitarias y sistemas de protección contra incendios para el seguimiento y soporte técnico de los proyectos de inversión del sector Salud con CUI N° 2386498, 2386533, 2427546 y 2512573.',
     10000.00, 2, 60);

DECLARE @Monto decimal(18,2) = (SELECT SUM(Monto) FROM @Ped);

DECLARE @Proveedores nvarchar(max) = (
    SELECT TipoDocumento       = 'DNI',
           p.Dni,
           p.Ruc,
           TipoRegistro        = 'EXISTENTE',
           RazonSocial         = CONCAT_WS(' ', p.ApellidoPaterno, p.ApellidoMaterno, p.Nombres),
           p.Nombres,
           p.ApellidoPaterno,
           p.ApellidoMaterno,
           p.Celular,
           p.CantidadEntregables,
           p.MontoMensual,
           p.Email,
           p.Denominacion,
           p.PlazoDias,
           NumerosPedido       = JSON_QUERY(CONCAT('[',
                                     (SELECT STRING_AGG(CONCAT('"', x.NumeroPedido, '"'), ',')
                                             WITHIN GROUP (ORDER BY x.NumeroPedido)
                                        FROM @Ped AS x WHERE x.Propuesta = p.Propuesta), ']')),
           NumeroPedido        = (SELECT MIN(x.NumeroPedido) FROM @Ped AS x WHERE x.Propuesta = p.Propuesta),
           Direccion           = N'DIRECCIÓN DE PRUEBA (no figura en el Anexo 5)',
           CodDepartamento     = '15',
           Departamento        = 'LIMA',
           CodProvincia        = '1501',
           Provincia           = 'LIMA',
           CodDistrito         = '150101',
           Distrito            = 'LIMA',
           MontoTotal          = p.MontoMensual * p.CantidadEntregables
      FROM @Prov AS p
     ORDER BY p.Propuesta
       FOR JSON PATH);

DECLARE @PedidosExtra nvarchar(max) = (
    SELECT AnoPedido          = @AnoEje,
           ActividadOperativa = CONCAT(N'SUPERVISIÓN Y CONTROL DE OBRA DEL CUI ', x.Cui),
           MetaPresupuestaria = x.Meta,
           FuenteFinanc       = '00',
           Clasificador       = '2.6. 8  1. 4  3',
           Programa           = '020',
           ProdPy             = x.Cui,
           TipoActProy        = '2',
           NombreProyectoSiga = '',
           CodigoItemPedido   = x.CodigoItem,
           NombreItemPedido   = x.NombreItem
      FROM @Ped AS x
     ORDER BY x.NumeroPedido
       FOR JSON PATH);

DECLARE @Datos nvarchar(max) = (
    SELECT Proveedores  = JSON_QUERY(@Proveedores),
           Proveedor    = JSON_QUERY(@Proveedores, '$[0]'),
           PedidosExtra = JSON_QUERY(@PedidosExtra),
           Pedido       = JSON_QUERY(@PedidosExtra, '$[0]')
       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

/* -------------------------------------------------------------------------- */
/* 3. Expediente, requerimiento, pedidos e items                              */
/* -------------------------------------------------------------------------- */

SET @IdExpediente    = NEWID();
SET @IdRequerimiento = NEWID();

INSERT INTO sigcm.Expediente
      (IdExpediente, CodigoModulo, Codigo, AnoEje, CodigoEstado, Version,
       IdUnidadOrigen, IdUnidadActual, IdResponsableActual,
       Anulado, Activo,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria,
       EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdExpediente, 'REQUERIMIENTO', @Codigo, @AnoEje, 'REQ_DOC_PENDIENTE', 1,
        @IdUnidad, @IdUnidad, @IdResponsable,
        0, 1,
        'S917', @Ahora, 'SEED', 'SIGCM-PRUEBA');

INSERT INTO requerimiento.Requerimiento
      (IdRequerimiento, IdExpediente, Codigo, AnoEje, SecEjec, CentroCosto,
       Denominacion, CodigoTipoContratacion, CodigoDec, CondicionCmn,
       Monto, PlazoDias, FechaInicioPrevisto, Sustento, IdResponsable,
       DatosAdicionales, Activo,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria,
       EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdRequerimiento, @IdExpediente, @Codigo, @AnoEje, @SecEjec, @CentroCosto,
        N'Servicios técnicos y especializados para el seguimiento de los proyectos de inversión del sector Salud de la Subdirección de Ejecución de Inversión',
        'LOCACION', 'ABASTECIMIENTO', 'INCLUIDO',
        @Monto, 90, sigcm.fnSumarDiasHabiles(CONVERT(date, @Ahora), 12),
        N'Muestra sembrada por S917 con el Anexo 5 de la SEJDI (cuatro propuestas).',
        @IdResponsable, @Datos, 1,
        'S917', @Ahora, 'SEED', 'SIGCM-PRUEBA');

DECLARE @PedidoNuevo TABLE (IdRequerimientoPedido uniqueidentifier, NumeroPedido varchar(20));

INSERT INTO requerimiento.RequerimientoPedido
      (IdRequerimiento, AnoEje, SecEjec, NumeroPedido, SecPedido, FechaPedido,
       CentroCosto, SecFunc, Origen, FuenteFinanc, Clasificador, Verificado,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria,
       EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
OUTPUT inserted.IdRequerimientoPedido, inserted.NumeroPedido INTO @PedidoNuevo
SELECT @IdRequerimiento, @AnoEje, @SecEjec, x.NumeroPedido, NULL, '2026-08-07',
       @CentroCosto, x.SecFunc, '1', '00', '2.6. 8  1. 4  3', 0,
       'S917', @Ahora, 'SEED', 'SIGCM-PRUEBA'
  FROM @Ped AS x;

INSERT INTO requerimiento.RequerimientoItem
      (IdRequerimiento, IdRequerimientoPedido, Orden, DescripcionServicio,
       Cantidad, PrecioUnitario,
       UsuarioCreacionAuditoria, FechaCreacionAuditoria,
       EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
SELECT @IdRequerimiento, pn.IdRequerimientoPedido, x.Orden, LEFT(x.NombreItem, 350),
       1, x.Monto,
       'S917', @Ahora, 'SEED', 'SIGCM-PRUEBA'
  FROM @Ped AS x
  JOIN @PedidoNuevo AS pn ON pn.NumeroPedido = x.NumeroPedido;

INSERT INTO sigcm.Historial
      (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
       Comentario, IdActor, ActorRol, IdActorUnidad, OcurridoEn)
VALUES (@IdExpediente, NULL, 'REQ_DOC_PENDIENTE', NULL,
        'Expediente sembrado por S917 directamente en REQ_DOC_PENDIENTE con el Anexo 5 de la SEJDI. No recorrio el flujo.',
        @IdResponsable, 'AREA_ESPECIALISTA', @IdUnidad, @Ahora);

COMMIT TRANSACTION;

/* -------------------------------------------------------------------------- */
/* 4. Resultado                                                               */
/* -------------------------------------------------------------------------- */

SELECT requerimiento = r.Codigo,
       estado        = e.CodigoEstado,
       area          = un.Sigla,
       responsable   = us.Cuenta,
       monto         = r.Monto,
       pedidos       = (SELECT COUNT(*) FROM requerimiento.RequerimientoPedido
                         WHERE IdRequerimiento = r.IdRequerimiento),
       propuestas    = (SELECT COUNT(*) FROM OPENJSON(r.DatosAdicionales, '$.Proveedores'))
  FROM requerimiento.Requerimiento AS r
  JOIN sigcm.Expediente AS e  ON e.IdExpediente = r.IdExpediente
  JOIN sigcm.Unidad     AS un ON un.IdUnidad    = e.IdUnidadActual
  JOIN sigcm.Usuario    AS us ON us.IdUsuario   = r.IdResponsable
 WHERE r.Codigo = @Codigo;

SELECT propuesta = CONVERT(int, p.[key]) + 1,
       proveedor = JSON_VALUE(p.value, '$.RazonSocial'),
       plazo     = JSON_VALUE(p.value, '$.PlazoDias'),
       mensual   = JSON_VALUE(p.value, '$.MontoMensual'),
       pedidos   = JSON_QUERY(p.value, '$.NumerosPedido')
  FROM requerimiento.Requerimiento AS r
 CROSS APPLY OPENJSON(r.DatosAdicionales, '$.Proveedores') AS p
 WHERE r.Codigo = @Codigo;
GO

PRINT 'S917 aplicada: REQ-PRU-ANX5-0001 en REQ_DOC_PENDIENTE con cuatro propuestas del Anexo 5.';
GO
