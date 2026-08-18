/*
===============================================================================
  SIGCM - Migracion V009 : Modulo Requerimiento a Notificacion - registro
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Autoridad : SIGCM

  ALCANCE DE ESTA MIGRACION
  -------------------------
  El nucleo del requerimiento: la necesidad, los pedidos SIGA vinculados y sus
  items. Cubre las reglas REQ-01 a REQ-14 del analisis
  (Analisis/reglas-negocio-mockup.md).

  NO entran aqui la indagacion de mercado, el cuadro de cotizaciones (Anexo 8),
  la CCP ni la orden: van en V010, cuando el registro este verificado. Se separan
  a proposito, porque son la segunda mitad del flujo y su modelo depende de
  decisiones funcionales todavia abiertas (numero de cotizaciones, excepciones).

  LO QUE ESTE MODULO NO PUEDE HACER TODAVIA
  -----------------------------------------
  REQ-02 dice que los datos del pedido se PRECARGAN desde SIGA y son de solo
  lectura. Hoy no existe una vista de pedidos en el esquema siga: V004 creo diez
  vistas y ninguna expone SIG_PEDIDO. Mientras no exista siga.vwPedido, los
  campos del pedido se capturan y no se validan contra SIGA. Las columnas ya
  estan preparadas para esa validacion. Ver la nota al pie de la tabla.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Parametros por anio                                                     */
/* -------------------------------------------------------------------------- */

/* La UIT y el tope de ocho UIT cambian cada anio. Son dato, no constante: en
   2026 el tope es S/ 44 000, y en 2027 sera otro sin que nadie recompile.
   Vive en el esquema del modulo porque el limite de ocho UIT es propio de la
   contratacion menor. */
IF OBJECT_ID(N'requerimiento.ParametroAnio', N'U') IS NULL
CREATE TABLE requerimiento.ParametroAnio (
    AnoEje      smallint      NOT NULL CONSTRAINT PK_req_ParametroAnio PRIMARY KEY,
    ValorUit    decimal(18,2) NOT NULL,
    TopeUit     decimal(9,2)  NOT NULL CONSTRAINT DF_req_ParametroAnio_Tope DEFAULT (8),
    MontoTope   AS (ValorUit * TopeUit) PERSISTED,
    Activo      bit NOT NULL CONSTRAINT DF_req_ParametroAnio_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_req_ParamAnio_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,
    UsuarioEliminacionAuditoria   varchar(30)  NULL,
    FechaEliminacionAuditoria     datetime     NULL,
    EquipoEliminacionAuditoria    varchar(50)  NULL,
    ProgramaEliminacionAuditoria  varchar(50)  NULL
);
GO

/* -------------------------------------------------------------------------- */
/* 2. Requerimiento                                                           */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'requerimiento.SeqRequerimiento', N'SO') IS NULL
    CREATE SEQUENCE requerimiento.SeqRequerimiento AS bigint START WITH 1 INCREMENT BY 1;
GO

IF OBJECT_ID(N'requerimiento.Requerimiento', N'U') IS NULL
CREATE TABLE requerimiento.Requerimiento (
    IdRequerimiento uniqueidentifier NOT NULL
                    CONSTRAINT DF_req_Requerimiento_Id DEFAULT (NEWSEQUENTIALID())
                    CONSTRAINT PK_req_Requerimiento PRIMARY KEY,

    /* Un requerimiento es un expediente: hereda de ahi su estado, su unidad
       actual y su version optimista. La relacion es uno a uno. */
    IdExpediente    uniqueidentifier NOT NULL
                    CONSTRAINT FK_req_Requerimiento_Expediente REFERENCES sigcm.Expediente(IdExpediente)
                    CONSTRAINT UQ_req_Requerimiento_Expediente UNIQUE,

    Codigo          varchar(40)  NOT NULL CONSTRAINT UQ_req_Requerimiento_Codigo UNIQUE,
    AnoEje          smallint     NOT NULL,
    SecEjec         int          NOT NULL,
    CentroCosto     varchar(15)  NOT NULL,

    Denominacion    varchar(500) NOT NULL,

    /* Bien, Servicio, Consultoria o Locacion (REQ-07). Gobierna que documento
       tecnico corresponde y, en Ejecucion, si hay recepcion fisica. */
    CodigoTipoContratacion varchar(20) NOT NULL
                    CONSTRAINT FK_req_Requerimiento_TipoCon REFERENCES sigcm.TipoContratacion(CodigoTipoContratacion),

    /* Dependencia encargada de las contrataciones. Decide la ruta: con
       ABASTECIMIENTO el expediente pasa por OA; con DAI no (REQ-14). */
    CodigoDec       varchar(20)  NOT NULL,

    /* REQ-03 y REQ-04. Si NO_INCLUIDO, el requerimiento debe apoyarse en una
       modificacion del CMN aprobada: ahi entra IdSolicitudCmn. */
    CondicionCmn    varchar(20)  NOT NULL,

    /* El puente con el modulo CMN. Es la unica referencia entre modulos y por
       eso es una clave foranea real y no un texto: un requerimiento que dice
       ampararse en una modificacion inexistente no debe poder guardarse. */
    IdSolicitudCmn  uniqueidentifier NULL
                    CONSTRAINT FK_req_Requerimiento_SolicitudCmn REFERENCES cmn.Solicitud(IdSolicitud),

    /* Evidencia del Anexo 1 firmado (si esta incluido en el CMN) o del Anexo 4
       adjunto (si no lo esta). Mismo par de columnas de archivo que el resto de
       la casa. */
    GeneradoDocumentoCmn nvarchar(1000) NULL,
    NombreDocumentoCmn   nvarchar(1000) NULL,

    Monto           decimal(18,2) NOT NULL,

    /* Plazo de ejecucion ofrecido, en dias. */
    PlazoDias       int          NOT NULL,
    /* PLZ-01: el requerimiento se presenta al menos 10 dias habiles antes. */
    FechaInicioPrevisto date     NULL,

    /* Area tecnica especializada y RUC sugerido, cuando corresponde. */
    Ate             varchar(200) NULL,
    RucSugerido     varchar(11)  NULL,

    /* Disponibilidad presupuestal declarada y su evidencia (REQ-05). */
    TieneDisponibilidad bit NOT NULL CONSTRAINT DF_req_Requerimiento_Disp DEFAULT (0),
    GeneradoDocumentoDisponibilidad nvarchar(1000) NULL,
    NombreDocumentoDisponibilidad   nvarchar(1000) NULL,

    Sustento        nvarchar(max) NOT NULL,

    IdResponsable   uniqueidentifier NOT NULL
                    CONSTRAINT FK_req_Requerimiento_Responsable REFERENCES sigcm.Usuario(IdUsuario),

    DatosAdicionales nvarchar(max) NOT NULL
                    CONSTRAINT DF_req_Requerimiento_Datos DEFAULT (N'{}')
                    CONSTRAINT CK_req_Requerimiento_Datos CHECK (ISJSON(DatosAdicionales) = 1),

    Activo          bit NOT NULL CONSTRAINT DF_req_Requerimiento_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_req_Requerimiento_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,
    UsuarioEliminacionAuditoria   varchar(30)  NULL,
    FechaEliminacionAuditoria     datetime     NULL,
    EquipoEliminacionAuditoria    varchar(50)  NULL,
    ProgramaEliminacionAuditoria  varchar(50)  NULL,

    CONSTRAINT CK_req_Requerimiento_Dec
        CHECK (CodigoDec IN ('ABASTECIMIENTO','DAI')),
    CONSTRAINT CK_req_Requerimiento_CondicionCmn
        CHECK (CondicionCmn IN ('INCLUIDO','NO_INCLUIDO')),
    /* REQ-06: el monto debe ser mayor que cero. El tope de ocho UIT no se
       comprueba aqui porque depende del anio y vive en ParametroAnio; lo valida
       la rutina de registro, que puede dar un mensaje util. */
    CONSTRAINT CK_req_Requerimiento_Monto CHECK (Monto > 0),
    CONSTRAINT CK_req_Requerimiento_Plazo CHECK (PlazoDias > 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_req_Requerimiento_Centro' AND object_id = OBJECT_ID(N'requerimiento.Requerimiento'))
CREATE NONCLUSTERED INDEX IX_req_Requerimiento_Centro
    ON requerimiento.Requerimiento(AnoEje, SecEjec, CentroCosto);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_req_Requerimiento_SolicitudCmn' AND object_id = OBJECT_ID(N'requerimiento.Requerimiento'))
CREATE NONCLUSTERED INDEX IX_req_Requerimiento_SolicitudCmn
    ON requerimiento.Requerimiento(IdSolicitudCmn)
    WHERE IdSolicitudCmn IS NOT NULL;
GO

/* -------------------------------------------------------------------------- */
/* 3. Pedidos SIGA vinculados                                                 */
/* -------------------------------------------------------------------------- */

/*
  REQ-01 y REQ-09: un requerimiento vincula UNO O MAS pedidos SIGA, y esos
  pedidos se reflejan en los documentos tecnicos sin volver a capturarse.

  SOBRE LA VALIDACION CONTRA SIGA
  Las columnas AnoEje, SecEjec y NumeroPedido son la clave del pedido en SIGA.
  Hoy no hay vista que permita comprobarlas: cuando exista siga.vwPedido, la
  rutina de registro debera validar contra ella igual que cmn.paRegistrarSolicitud
  valida contra siga.vwCatalogoItem. Hasta entonces se capturan y se marcan como
  no verificadas con Verificado = 0.
*/
IF OBJECT_ID(N'requerimiento.RequerimientoPedido', N'U') IS NULL
CREATE TABLE requerimiento.RequerimientoPedido (
    IdRequerimientoPedido uniqueidentifier NOT NULL
                    CONSTRAINT DF_req_Pedido_Id DEFAULT (NEWSEQUENTIALID())
                    CONSTRAINT PK_req_Pedido PRIMARY KEY,
    IdRequerimiento uniqueidentifier NOT NULL
                    CONSTRAINT FK_req_Pedido_Requerimiento REFERENCES requerimiento.Requerimiento(IdRequerimiento) ON DELETE CASCADE,

    AnoEje          smallint    NOT NULL,
    SecEjec         int         NOT NULL,
    NumeroPedido    varchar(20) NOT NULL,
    SecPedido       bigint      NULL,
    FechaPedido     date        NULL,
    CentroCosto     varchar(15) NULL,

    /* Clasificacion presupuestal que trae el pedido, para reflejarla en el
       documento tecnico sin volver a pedirla. */
    SecFunc         int         NULL,
    Origen          varchar(1)  NULL,
    FuenteFinanc    varchar(2)  NULL,
    Clasificador    varchar(20) NULL,

    Verificado      bit NOT NULL CONSTRAINT DF_req_Pedido_Verificado DEFAULT (0),

    Activo          bit NOT NULL CONSTRAINT DF_req_Pedido_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_req_Pedido_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,
    UsuarioEliminacionAuditoria   varchar(30)  NULL,
    FechaEliminacionAuditoria     datetime     NULL,
    EquipoEliminacionAuditoria    varchar(50)  NULL,
    ProgramaEliminacionAuditoria  varchar(50)  NULL,

    CONSTRAINT UQ_req_Pedido_Numero UNIQUE (IdRequerimiento, AnoEje, NumeroPedido)
);
GO

/* -------------------------------------------------------------------------- */
/* 4. Items del requerimiento                                                 */
/* -------------------------------------------------------------------------- */

/*
  Lo que se contrata, linea por linea. El item se identifica con la misma clave
  de cinco partes del catalogo de SIGA que usa el CMN, para que las dos tablas
  hablen del mismo bien.

  DescripcionServicio existe porque un servicio o una consultoria puede no estar
  en el catalogo de bienes y se describe en texto; en ese caso las cinco partes
  van nulas.
*/
IF OBJECT_ID(N'requerimiento.RequerimientoItem', N'U') IS NULL
CREATE TABLE requerimiento.RequerimientoItem (
    IdRequerimientoItem uniqueidentifier NOT NULL
                    CONSTRAINT DF_req_Item_Id DEFAULT (NEWSEQUENTIALID())
                    CONSTRAINT PK_req_Item PRIMARY KEY,
    IdRequerimiento uniqueidentifier NOT NULL
                    CONSTRAINT FK_req_Item_Requerimiento REFERENCES requerimiento.Requerimiento(IdRequerimiento) ON DELETE CASCADE,
    IdRequerimientoPedido uniqueidentifier NULL
                    CONSTRAINT FK_req_Item_Pedido REFERENCES requerimiento.RequerimientoPedido(IdRequerimientoPedido),

    Orden           int         NOT NULL,

    TipoBien        char(1)     NULL,
    GrupoBien       varchar(2)  NULL,
    ClaseBien       varchar(2)  NULL,
    FamiliaBien     varchar(4)  NULL,
    ItemBien        varchar(4)  NULL,
    DescripcionServicio varchar(350) NULL,

    UnidadMedida    int         NULL,
    Cantidad        decimal(18,2) NOT NULL,
    PrecioUnitario  decimal(16,6) NOT NULL,
    Monto           AS (CONVERT(decimal(18,2), ROUND(Cantidad * PrecioUnitario, 2))) PERSISTED,

    Activo          bit NOT NULL CONSTRAINT DF_req_Item_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30)  NULL,
    FechaCreacionAuditoria        datetime     NULL CONSTRAINT DF_req_Item_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50)  NULL,
    ProgramaCreacionAuditoria     varchar(50)  NULL,
    UsuarioModificacionAuditoria  varchar(30)  NULL,
    FechaModificacionAuditoria    datetime     NULL,
    EquipoModificacionAuditoria   varchar(50)  NULL,
    ProgramaModificacionAuditoria varchar(50)  NULL,
    UsuarioEliminacionAuditoria   varchar(30)  NULL,
    FechaEliminacionAuditoria     datetime     NULL,
    EquipoEliminacionAuditoria    varchar(50)  NULL,
    ProgramaEliminacionAuditoria  varchar(50)  NULL,

    CONSTRAINT UQ_req_Item_Orden UNIQUE (IdRequerimiento, Orden),
    CONSTRAINT CK_req_Item_Cantidad CHECK (Cantidad > 0),
    CONSTRAINT CK_req_Item_Precio   CHECK (PrecioUnitario > 0),
    /* O es un item del catalogo, o es un servicio descrito. Nunca ninguno. */
    CONSTRAINT CK_req_Item_Identificacion
        CHECK (ItemBien IS NOT NULL OR DescripcionServicio IS NOT NULL)
);
GO

/* -------------------------------------------------------------------------- */
/* 5. Vista de resumen                                                        */
/* -------------------------------------------------------------------------- */

/* El monto y el conteo de items en un solo lugar, para que la bandeja y el
   visor no repitan la suma. */
CREATE OR ALTER VIEW requerimiento.vwRequerimientoResumen
AS
SELECT r.IdRequerimiento,
       r.IdExpediente,
       r.Codigo,
       r.AnoEje,
       r.CentroCosto,
       r.Denominacion,
       r.CodigoTipoContratacion,
       r.CodigoDec,
       r.CondicionCmn,
       r.Monto,
       r.PlazoDias,
       r.FechaInicioPrevisto,
       Items       = (SELECT COUNT(*) FROM requerimiento.RequerimientoItem AS i
                       WHERE i.IdRequerimiento = r.IdRequerimiento AND i.Activo = 1),
       MontoItems  = ISNULL((SELECT SUM(i.Monto) FROM requerimiento.RequerimientoItem AS i
                              WHERE i.IdRequerimiento = r.IdRequerimiento AND i.Activo = 1), 0),
       Pedidos     = (SELECT COUNT(*) FROM requerimiento.RequerimientoPedido AS p
                       WHERE p.IdRequerimiento = r.IdRequerimiento AND p.Activo = 1)
  FROM requerimiento.Requerimiento AS r
 WHERE r.Activo = 1;
GO

PRINT 'V009 aplicada: modulo Requerimiento, nucleo del registro.';
GO
