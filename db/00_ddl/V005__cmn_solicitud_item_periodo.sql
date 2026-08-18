/*
===============================================================================
  SIGCM - Migracion V005 : Modulo Gestion CMN
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Alcance (ADR-002): MODIFICACION del Cuadro Multianual de Necesidades.
      Anexo 3 = solicitud de modificacion
      Anexo 4 = aprobacion de modificaciones
      Directiva 0007-2025-EF/54.01

  Port de SIGCM/db/00_ddl/V005__cmn_solicitud_item_periodo.sql.

  DECISION DE GRANO (se conserva intacta)
  ---------------------------------------
  La estructura presupuestal (tarea, meta, fuente, clasificador, tipo de uso)
  vive en el ITEM, no en la cabecera.

  Motivo: un Anexo 3 real abarca varias metas y clasificadores y se firma una
  sola vez. En SIGA, en cambio, la cabecera esta definida por esa combinacion, de
  modo que un mismo Anexo 3 corresponde a N cabeceras SIGA. Poner la estructura
  en la cabecera del SIGCM obligaria a partir un Anexo 3 en N solicitudes con N
  firmas.

  La proyeccion hacia SIGA deja de ser una copia y pasa a ser una agregacion.
  Ver cmn.vwAgrupacionSiga al final de este archivo.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = N'SeqSolicitud' AND schema_id = SCHEMA_ID(N'cmn'))
    CREATE SEQUENCE cmn.SeqSolicitud AS bigint START WITH 1 INCREMENT BY 1;
GO

/* -------------------------------------------------------------------------- */
/* 1. Solicitud = Anexo 3                                                     */
/* -------------------------------------------------------------------------- */

/* TipoOperacion: la v1 solo habilita MODIFICACION (ADR-002). FORMULACION queda
   declarado porque usa tablas distintas en SIGA (SIG_CUADRO_NECESIDAD frente a
   SIG_CUADRO_MODIFICADO) y por tanto un procedimiento de integracion distinto;
   dejarlo modelado evita rehacer el esquema si la ANIN lo incorpora despues. */
IF OBJECT_ID(N'cmn.Solicitud', N'U') IS NULL
CREATE TABLE cmn.Solicitud (
    IdSolicitud      uniqueidentifier NOT NULL
                     CONSTRAINT DF_cmn_Solicitud_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_cmn_Solicitud PRIMARY KEY,
    /* 1:1 con el expediente: bandejas, plazos, documentos y trazabilidad son
       transversales y no se reimplementan por modulo. */
    IdExpediente     uniqueidentifier NOT NULL
                     CONSTRAINT UQ_cmn_Solicitud_Expediente UNIQUE
                     CONSTRAINT FK_cmn_Solicitud_Expediente REFERENCES sigcm.Expediente(IdExpediente) ON DELETE CASCADE,
    Codigo           varchar(40) NOT NULL CONSTRAINT UQ_cmn_Solicitud_Codigo UNIQUE,

    /* Coordenadas del cuadro que se modifica */
    AnoEje           smallint    NOT NULL,
    SecEjec          int         NOT NULL,
    CentroCosto      varchar(15) NOT NULL,

    TipoOperacion    varchar(20) NOT NULL CONSTRAINT DF_cmn_Solicitud_Operacion DEFAULT ('MODIFICACION'),
    /* Ordinaria o urgente: lo determina Abastecimiento durante la evaluacion,
       por eso admite nulo mientras el expediente esta en el area usuaria. */
    TipoInclusion    varchar(15)     NULL,

    Sustento         nvarchar(max) NOT NULL,
    FechaSolicitud   date NOT NULL CONSTRAINT DF_cmn_Solicitud_Fecha DEFAULT (CONVERT(date, GETDATE())),

    /* Responsable que figura impreso en el Anexo 3 */
    IdResponsable    uniqueidentifier NOT NULL
                     CONSTRAINT FK_cmn_Solicitud_Responsable REFERENCES sigcm.Usuario(IdUsuario),

    DatosAdicionales nvarchar(max) NOT NULL CONSTRAINT DF_cmn_Solicitud_Datos DEFAULT (N'{}'),
    Activo           bit NOT NULL CONSTRAINT DF_cmn_Solicitud_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_cmn_Solicitud_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,
    UsuarioEliminacionAuditoria   varchar(30) NULL,
    FechaEliminacionAuditoria     datetime    NULL,
    EquipoEliminacionAuditoria    varchar(50) NULL,
    ProgramaEliminacionAuditoria  varchar(50) NULL,

    CONSTRAINT CK_cmn_Solicitud_Operacion
        CHECK (TipoOperacion IN ('MODIFICACION','FORMULACION')),
    CONSTRAINT CK_cmn_Solicitud_Inclusion
        CHECK (TipoInclusion IS NULL OR TipoInclusion IN ('ORDINARIA','URGENTE')),
    CONSTRAINT CK_cmn_Solicitud_Ano      CHECK (AnoEje BETWEEN 2020 AND 2100),
    CONSTRAINT CK_cmn_Solicitud_Sustento CHECK (LEN(TRIM(Sustento)) > 0),
    CONSTRAINT CK_cmn_Solicitud_Datos    CHECK (ISJSON(DatosAdicionales) = 1)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cmn_Solicitud_Centro' AND object_id = OBJECT_ID(N'cmn.Solicitud'))
CREATE NONCLUSTERED INDEX IX_cmn_Solicitud_Centro
    ON cmn.Solicitud(AnoEje, SecEjec, CentroCosto);
GO

/* -------------------------------------------------------------------------- */
/* 2. Item = una linea del Anexo 3                                            */
/* -------------------------------------------------------------------------- */

/* Inclusion y exclusion son excluyentes por linea (regla del mockup).
   MODIFICACION cambia cantidades de un item ya aprobado. */
IF OBJECT_ID(N'cmn.SolicitudItem', N'U') IS NULL
CREATE TABLE cmn.SolicitudItem (
    IdSolicitudItem     uniqueidentifier NOT NULL
                        CONSTRAINT DF_cmn_SolicitudItem_Id DEFAULT (NEWSEQUENTIALID())
                        CONSTRAINT PK_cmn_SolicitudItem PRIMARY KEY,
    IdSolicitud         uniqueidentifier NOT NULL
                        CONSTRAINT FK_cmn_SolicitudItem_Solicitud REFERENCES cmn.Solicitud(IdSolicitud) ON DELETE CASCADE,
    Orden               int NOT NULL,

    TipoMovimiento      varchar(15) NOT NULL,

    /* --- Estructura presupuestal: vive aqui, no en la cabecera --- */
    TipoTarea           char(1)     NOT NULL,
    NivelTarea          char(1)     NOT NULL,
    CodigoTarea         bigint      NOT NULL,
    SecFunc             int         NOT NULL,
    SecFuncProp         int             NULL,
    Origen              varchar(1)  NOT NULL CONSTRAINT DF_cmn_SolItem_Origen  DEFAULT ('1'),
    FuenteFinanc        varchar(2)  NOT NULL CONSTRAINT DF_cmn_SolItem_Fuente  DEFAULT ('00'),
    Clasificador        varchar(20) NOT NULL,
    TipoRecurso         varchar(2)  NOT NULL CONSTRAINT DF_cmn_SolItem_Recurso DEFAULT ('1'),
    TipoPpto            smallint    NOT NULL CONSTRAINT DF_cmn_SolItem_Ppto    DEFAULT (1),
    TipoUso             varchar(1)  NOT NULL CONSTRAINT DF_cmn_SolItem_Uso     DEFAULT ('C'),

    /* --- Catalogo --- */
    TipoBien            char(1)       NOT NULL,
    GrupoBien           varchar(2)    NOT NULL,
    ClaseBien           varchar(2)    NOT NULL,
    FamiliaBien         varchar(4)    NOT NULL,
    ItemBien            varchar(4)    NOT NULL,
    DescripcionServicio varchar(350)      NULL,
    UnidadMedida        int           NOT NULL,
    PrecioUnitario      decimal(16,6) NOT NULL,

    /* --- Referencia al item vigente en SIGA, para exclusion y modificacion --- */
    RefSecCuadro        bigint NULL,
    RefSecItem          bigint NULL,
    Activo              bit NOT NULL CONSTRAINT DF_cmn_SolItem_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_cmn_SolItem_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,

    CONSTRAINT UQ_cmn_SolItem_Orden UNIQUE (IdSolicitud, Orden),
    CONSTRAINT CK_cmn_SolItem_Movimiento
        CHECK (TipoMovimiento IN ('INCLUSION','EXCLUSION','MODIFICACION')),
    CONSTRAINT CK_cmn_SolItem_Precio   CHECK (PrecioUnitario > 0),
    CONSTRAINT CK_cmn_SolItem_TipoBien CHECK (TipoBien IN ('B','S','O')),
    /* Excluir o modificar exige senialar cual item del cuadro vigente se toca */
    CONSTRAINT CK_cmn_SolItem_Referencia CHECK (
        TipoMovimiento = 'INCLUSION'
        OR (RefSecCuadro IS NOT NULL AND RefSecItem IS NOT NULL)
    )
);
GO

/* El mismo item de catalogo no puede pedirse dos veces con la misma estructura
   presupuestal dentro de una solicitud: en SIGA colisionarian en la misma
   cabecera y el registro seria rechazado. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_cmn_SolItem_Unico' AND object_id = OBJECT_ID(N'cmn.SolicitudItem'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_cmn_SolItem_Unico
    ON cmn.SolicitudItem(
        IdSolicitud, TipoTarea, NivelTarea, CodigoTarea, SecFunc,
        Origen, FuenteFinanc, Clasificador, TipoUso,
        TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cmn_SolItem_Solicitud' AND object_id = OBJECT_ID(N'cmn.SolicitudItem'))
CREATE NONCLUSTERED INDEX IX_cmn_SolItem_Solicitud
    ON cmn.SolicitudItem(IdSolicitud, Orden);
GO

/* -------------------------------------------------------------------------- */
/* 3. Programacion: 48 periodos por item                                      */
/* -------------------------------------------------------------------------- */

/* Exactamente 48 filas por item: 4 anios x 12 meses. Los meses no informados se
   materializan en cero, nunca se omiten (criterio de aceptacion del MVP).

   La forma normalizada proyecta sin rediseno hacia las DOS representaciones de
   SIGA, que son distintas entre si:
     SIG_CUADRO_NECESIDAD_DET  -> 1 fila x 48 columnas (CANT_01..12, _ANNO_01..03)
     SIG_CUADRO_MODIFICADO_DET -> 4 filas x 12 columnas (una por ANNO_PROG)

   La segunda es la del MVP, y siga.vwCuadroVigenteItem ya la lee pivotada a
   CantAno0..3 con la misma convencion de desplazamiento que AnoOffset.

   Sin cuarteto de auditoria: es una tabla de detalle que se reescribe en bloque
   junto con su item; la autoria la lleva cmn.SolicitudItem. */
IF OBJECT_ID(N'cmn.SolicitudItemPeriodo', N'U') IS NULL
CREATE TABLE cmn.SolicitudItemPeriodo (
    IdSolicitudItem uniqueidentifier NOT NULL
                    CONSTRAINT FK_cmn_Periodo_Item REFERENCES cmn.SolicitudItem(IdSolicitudItem) ON DELETE CASCADE,
    AnoOffset       smallint NOT NULL,
    Mes             smallint NOT NULL,
    Cantidad        decimal(18,2) NOT NULL CONSTRAINT DF_cmn_Periodo_Cantidad DEFAULT (0),
    Monto           decimal(18,2) NOT NULL CONSTRAINT DF_cmn_Periodo_Monto    DEFAULT (0),
    CONSTRAINT PK_cmn_SolicitudItemPeriodo PRIMARY KEY (IdSolicitudItem, AnoOffset, Mes),
    CONSTRAINT CK_cmn_Periodo_Offset  CHECK (AnoOffset BETWEEN 0 AND 3),
    CONSTRAINT CK_cmn_Periodo_Mes     CHECK (Mes BETWEEN 1 AND 12),
    CONSTRAINT CK_cmn_Periodo_Valores CHECK (Cantidad >= 0 AND Monto >= 0)
);
GO

/* -------------------------------------------------------------------------- */
/* 4. Vista de resumen por item                                               */
/* -------------------------------------------------------------------------- */

/* LEFT JOIN contra los maestros a proposito: si el catalogo de SIGA deja de
   ofrecer un item, la solicitud debe seguir siendo consultable e imprimible. En
   PostgreSQL el motivo era una recarga del espejo; aqui, que SIGA de baja el
   item. El efecto buscado es el mismo.

   SUM(x) FILTER (WHERE ...) de PostgreSQL se traduce a SUM(CASE WHEN ...). */
CREATE OR ALTER VIEW cmn.vwItemResumen
AS
SELECT
    IdSolicitudItem   = i.IdSolicitudItem,
    IdSolicitud       = i.IdSolicitud,
    Orden             = i.Orden,
    TipoMovimiento    = i.TipoMovimiento,
    TipoBien          = i.TipoBien,
    GrupoBien         = i.GrupoBien,
    ClaseBien         = i.ClaseBien,
    FamiliaBien       = i.FamiliaBien,
    ItemBien          = i.ItemBien,
    CodigoItem        = CONVERT(varchar(20),
                            CONCAT_WS('.', i.TipoBien, i.GrupoBien, i.ClaseBien,
                                           i.FamiliaBien, i.ItemBien)),
    Descripcion       = COALESCE(i.DescripcionServicio, c.Descripcion),
    UnidadMedida      = i.UnidadMedida,
    UnidadAbreviatura = u.Abreviatura,
    PrecioUnitario    = i.PrecioUnitario,
    SecFunc           = i.SecFunc,
    Clasificador      = i.Clasificador,
    RefSecCuadro      = i.RefSecCuadro,
    RefSecItem        = i.RefSecItem,
    CantidadAno0 = SUM(CASE WHEN p.AnoOffset = 0 THEN p.Cantidad ELSE 0 END),
    CantidadAno1 = SUM(CASE WHEN p.AnoOffset = 1 THEN p.Cantidad ELSE 0 END),
    CantidadAno2 = SUM(CASE WHEN p.AnoOffset = 2 THEN p.Cantidad ELSE 0 END),
    CantidadAno3 = SUM(CASE WHEN p.AnoOffset = 3 THEN p.Cantidad ELSE 0 END),
    MontoAno0    = SUM(CASE WHEN p.AnoOffset = 0 THEN p.Monto ELSE 0 END),
    MontoAno1    = SUM(CASE WHEN p.AnoOffset = 1 THEN p.Monto ELSE 0 END),
    MontoAno2    = SUM(CASE WHEN p.AnoOffset = 2 THEN p.Monto ELSE 0 END),
    MontoAno3    = SUM(CASE WHEN p.AnoOffset = 3 THEN p.Monto ELSE 0 END),
    CantidadTotal = SUM(p.Cantidad),
    MontoTotal    = SUM(p.Monto),
    Periodos      = COUNT_BIG(*)
FROM cmn.SolicitudItem AS i
JOIN cmn.Solicitud AS s
  ON s.IdSolicitud = i.IdSolicitud
LEFT JOIN siga.vwCatalogoItem AS c
       ON  c.SecEjec     = s.SecEjec
       AND c.TipoBien    = i.TipoBien
       AND c.GrupoBien   = i.GrupoBien
       AND c.ClaseBien   = i.ClaseBien
       AND c.FamiliaBien = i.FamiliaBien
       AND c.ItemBien    = i.ItemBien
LEFT JOIN siga.vwUnidadMedida AS u
       ON u.UnidadMedida = i.UnidadMedida
JOIN cmn.SolicitudItemPeriodo AS p
  ON p.IdSolicitudItem = i.IdSolicitudItem
GROUP BY
    i.IdSolicitudItem, i.IdSolicitud, i.Orden, i.TipoMovimiento,
    i.TipoBien, i.GrupoBien, i.ClaseBien, i.FamiliaBien, i.ItemBien,
    i.DescripcionServicio, c.Descripcion, i.UnidadMedida, u.Abreviatura,
    i.PrecioUnitario, i.SecFunc, i.Clasificador, i.RefSecCuadro, i.RefSecItem;
GO

/* -------------------------------------------------------------------------- */
/* 5. Vista de proyeccion hacia cabeceras SIGA                                */
/* -------------------------------------------------------------------------- */

/* Cada fila corresponde a una cabecera de SIGA. Es el punto exacto donde el
   modelo institucional del SIGCM se traduce al modelo del producto SIGA, y el
   unico lugar del sistema donde esa correspondencia esta escrita.

   array_agg(i.id ORDER BY i.orden) de PostgreSQL se traduce con STRING_AGG ...
   WITHIN GROUP (ORDER BY ...), que es el equivalente exacto. */
CREATE OR ALTER VIEW cmn.vwAgrupacionSiga
AS
SELECT
    IdSolicitud  = s.IdSolicitud,
    AnoEje       = s.AnoEje,
    SecEjec      = s.SecEjec,
    CentroCosto  = s.CentroCosto,
    TipoTarea    = i.TipoTarea,
    NivelTarea   = i.NivelTarea,
    CodigoTarea  = i.CodigoTarea,
    SecFunc      = i.SecFunc,
    SecFuncProp  = i.SecFuncProp,
    Origen       = i.Origen,
    FuenteFinanc = i.FuenteFinanc,
    Clasificador = i.Clasificador,
    TipoRecurso  = i.TipoRecurso,
    TipoPpto     = i.TipoPpto,
    TipoUso      = i.TipoUso,
    TipoBien     = i.TipoBien,
    Items        = COUNT_BIG(*),
    ItemIds      = STRING_AGG(CONVERT(varchar(36), i.IdSolicitudItem), ',')
                       WITHIN GROUP (ORDER BY i.Orden)
FROM cmn.Solicitud AS s
JOIN cmn.SolicitudItem AS i
  ON i.IdSolicitud = s.IdSolicitud
GROUP BY
    s.IdSolicitud, s.AnoEje, s.SecEjec, s.CentroCosto,
    i.TipoTarea, i.NivelTarea, i.CodigoTarea,
    i.SecFunc, i.SecFuncProp, i.Origen, i.FuenteFinanc,
    i.Clasificador, i.TipoRecurso, i.TipoPpto, i.TipoUso, i.TipoBien;
GO

PRINT 'V005 aplicada.';
GO
