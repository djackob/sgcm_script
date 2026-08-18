/*
===============================================================================
  SIGCM - Migracion V006 : Frontera de integracion con SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Port de SIGCM/db/00_ddl/V006__integracion_outbox_mapeo.sql.

  POR QUE SE CONSERVA EL OUTBOX AUNQUE AHORA COMPARTAN INSTANCIA
  -------------------------------------------------------------
  En PostgreSQL el outbox era inevitable: los dos motores estaban separados. Aqui
  DBSIGCM y la base SIGA viven en el mismo servidor, asi que tecnicamente una
  sola transaccion podria escribir en ambas por nombre de tres partes. Se decidio
  NO hacerlo, por cuatro razones:

  1. Una transaccion entre bases acopla el log de las dos. Restaurar o migrar
     SIGA por su cuenta deja de ser una operacion independiente.
  2. Se perderia la idempotencia. La clave determinista de abajo es lo unico que
     impide que un reintento duplique un item en SIGA.
  3. Se perderian los reintentos con espera y el estado CONCILIAR.
  4. Se perderia el modo simulacion, que es la forma en que ADR-003 permite
     construir la cadena completa sin escribir todavia en SIGA.

  A eso se suma que el planeamiento (§9.8) prohibe escribir en tablas oficiales
  de SIGA sin procedimiento homologado, y esa homologacion no existe aun.

  POR QUE UN OUTBOX Y NO UNA COLA EXTERNA
  ---------------------------------------
  El backend .NET actua como puente: abre conexion, ejecuta UNA sentencia y
  cierra. Una llamada = una transaccion. Cuando la rutina de negocio cambia el
  estado del expediente e inserta las filas de integracion.Operacion en esa misma
  sentencia, la atomicidad es gratuita: no puede quedar aprobado sin encolar ni
  encolado sin aprobar. Con un broker externo habria que resolver ese commit en
  dos fases a mano.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Outbox                                                                  */
/* -------------------------------------------------------------------------- */

/* Operacion: CONSOLIDAR_CMN corresponde al Anexo 4 y escribe en
   SIG_CUADRO_MODIFICADO_CMN. Las otras tres corresponden al Anexo 3 validado y
   escriben en SIG_CUADRO_MODIFICADO_DET y _SALDO. Son dos escalones distintos
   del flujo, y por eso son operaciones distintas y no una sola escritura.

   Estado: CONCILIAR marca la operacion que agoto reintentos o cuya respuesta fue
   ambigua: hay que mirar SIGA antes de decidir. No es un error definitivo, es
   una peticion de intervencion humana.

   ModoEjecucion: se graba lo que EFECTIVAMENTE se hizo, no lo que estaba
   configurado al encolar (ADR-003). */
IF OBJECT_ID(N'integracion.Operacion', N'U') IS NULL
CREATE TABLE integracion.Operacion (
    IdOperacion       uniqueidentifier NOT NULL
                      CONSTRAINT DF_integracion_Operacion_Id DEFAULT (NEWSEQUENTIALID())
                      CONSTRAINT PK_integracion_Operacion PRIMARY KEY,

    /* Determinista: {solicitud}:{item}:{version}:{operacion}.
       Un reintento con la misma clave no puede duplicar el registro en SIGA. */
    IdempotenciaKey   varchar(200) NOT NULL CONSTRAINT UQ_integracion_Operacion_Idempotencia UNIQUE,

    IdExpediente      uniqueidentifier NOT NULL CONSTRAINT FK_integracion_Operacion_Expediente REFERENCES sigcm.Expediente(IdExpediente),
    IdSolicitud       uniqueidentifier NOT NULL CONSTRAINT FK_integracion_Operacion_Solicitud  REFERENCES cmn.Solicitud(IdSolicitud),
    IdSolicitudItem   uniqueidentifier     NULL CONSTRAINT FK_integracion_Operacion_Item       REFERENCES cmn.SolicitudItem(IdSolicitudItem),

    Operacion         varchar(30)  NOT NULL,
    Procedimiento     varchar(128) NOT NULL,

    /* Orden de ejecucion dentro de la misma solicitud. Las operaciones de una
       solicitud se procesan en serie: el procedimiento de SIGA crea la cabecera
       si no existe, de modo que dos items en paralelo competirian por ella. */
    Secuencia         int NOT NULL CONSTRAINT DF_integracion_Operacion_Secuencia DEFAULT (1),

    Estado            varchar(20) NOT NULL CONSTRAINT DF_integracion_Operacion_Estado DEFAULT ('PENDIENTE'),
    RequestJson       nvarchar(max) NOT NULL,
    ResponseJson      nvarchar(max)     NULL,
    ErrorCodigo       varchar(80)       NULL,
    ErrorMensaje      nvarchar(max)     NULL,

    Intentos          int NOT NULL CONSTRAINT DF_integracion_Operacion_Intentos DEFAULT (0),
    MaxIntentos       int NOT NULL CONSTRAINT DF_integracion_Operacion_Max      DEFAULT (5),
    ProximoIntentoEn  datetime NOT NULL CONSTRAINT DF_integracion_Operacion_Proximo DEFAULT (GETDATE()),

    /* Toma exclusiva por un worker concreto */
    BloqueoToken      uniqueidentifier NULL,
    BloqueadoEn       datetime         NULL,
    BloqueadoPor      varchar(80)      NULL,

    ModoEjecucion     varchar(15)      NULL,
    CompletadoEn      datetime         NULL,
    Activo            bit NOT NULL CONSTRAINT DF_integracion_Operacion_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_integracion_Operacion_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria       varchar(50) NULL,
    ProgramaCreacionAuditoria     varchar(50) NULL,
    UsuarioModificacionAuditoria  varchar(30) NULL,
    FechaModificacionAuditoria    datetime    NULL,
    EquipoModificacionAuditoria   varchar(50) NULL,
    ProgramaModificacionAuditoria varchar(50) NULL,

    CONSTRAINT CK_integracion_Operacion_Estado CHECK (Estado IN
        ('PENDIENTE','EN_PROCESO','REINTENTO','COMPLETADO','ERROR','CONCILIAR','ANULADO')),
    CONSTRAINT CK_integracion_Operacion_Operacion CHECK (Operacion IN
        ('INCLUIR_ITEM','EXCLUIR_ITEM','MODIFICAR_CANTIDADES','CONSOLIDAR_CMN')),
    CONSTRAINT CK_integracion_Operacion_Intentos CHECK (Intentos >= 0 AND MaxIntentos > 0),
    CONSTRAINT CK_integracion_Operacion_Modo
        CHECK (ModoEjecucion IS NULL OR ModoEjecucion IN ('simulacion','real')),
    CONSTRAINT CK_integracion_Operacion_Request  CHECK (ISJSON(RequestJson) = 1),
    CONSTRAINT CK_integracion_Operacion_Response CHECK (ResponseJson IS NULL OR ISJSON(ResponseJson) = 1)
);
GO

/* Indice de drenaje: solo lo pendiente y vencido. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_integracion_Operacion_Pendiente' AND object_id = OBJECT_ID(N'integracion.Operacion'))
CREATE NONCLUSTERED INDEX IX_integracion_Operacion_Pendiente
    ON integracion.Operacion(ProximoIntentoEn, Secuencia, FechaCreacionAuditoria)
    WHERE Estado IN ('PENDIENTE','REINTENTO');
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_integracion_Operacion_Solicitud' AND object_id = OBJECT_ID(N'integracion.Operacion'))
CREATE NONCLUSTERED INDEX IX_integracion_Operacion_Solicitud
    ON integracion.Operacion(IdSolicitud, Secuencia);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_integracion_Operacion_Atencion' AND object_id = OBJECT_ID(N'integracion.Operacion'))
CREATE NONCLUSTERED INDEX IX_integracion_Operacion_Atencion
    ON integracion.Operacion(Estado, FechaModificacionAuditoria DESC)
    WHERE Estado IN ('ERROR','CONCILIAR');
GO

/* -------------------------------------------------------------------------- */
/* 2. Correspondencia de identificadores                                      */
/* -------------------------------------------------------------------------- */

/* Los identificadores de SIGA NUNCA reemplazan las claves internas del SIGCM: se
   conservan aqui. Si maniana SIGA se restaura o renumera, se pierde el mapeo, no
   el expediente institucional.

   SecCuaModSal es la secuencia devuelta por SIGA que enlaza
   SIG_CUADRO_MODIFICADO_DET con _SALDO y _CMN. Se asigna en bloques de cuatro,
   uno por anio programado; se guarda el del anio base. */
IF OBJECT_ID(N'integracion.MapeoCmn', N'U') IS NULL
CREATE TABLE integracion.MapeoCmn (
    IdSolicitudItem    uniqueidentifier NOT NULL
                       CONSTRAINT PK_integracion_MapeoCmn PRIMARY KEY
                       CONSTRAINT FK_integracion_MapeoCmn_Item REFERENCES cmn.SolicitudItem(IdSolicitudItem),
    IdSolicitud        uniqueidentifier NOT NULL
                       CONSTRAINT FK_integracion_MapeoCmn_Solicitud REFERENCES cmn.Solicitud(IdSolicitud),

    /* Clave natural del item en SIGA */
    AnoEje             smallint    NOT NULL,
    SecEjec            int         NOT NULL,
    CentroCosto        varchar(15) NOT NULL,
    SecCuadro          bigint      NOT NULL,
    SecItem            bigint      NOT NULL,
    SecCuaModSal       bigint          NULL,

    EstadoSiga         varchar(2)  NOT NULL,
    MotivoSolicitud    varchar(1)      NULL,

    IdempotenciaKey    varchar(200) NOT NULL,
    RegistradoEnSiga   datetime NOT NULL CONSTRAINT DF_integracion_MapeoCmn_Registrado DEFAULT (GETDATE()),
    UltimaConciliacion datetime NULL,
    ConciliacionOk     bit      NULL,

    PayloadRespuesta   nvarchar(max) NOT NULL,

    UsuarioCreacionAuditoria  varchar(30) NULL,
    EquipoCreacionAuditoria   varchar(50) NULL,
    ProgramaCreacionAuditoria varchar(50) NULL,

    CONSTRAINT UQ_integracion_MapeoCmn_Natural UNIQUE (AnoEje, SecEjec, CentroCosto, SecCuadro, SecItem),
    CONSTRAINT CK_integracion_MapeoCmn_Payload CHECK (ISJSON(PayloadRespuesta) = 1)
);
GO

/* -------------------------------------------------------------------------- */
/* 3. Conciliacion                                                            */
/* -------------------------------------------------------------------------- */

/* Sin conciliacion periodica, "consistencia eventual" es solo un eufemismo:
   nadie sabria que el SIGCM y SIGA divergieron hasta que un area usuaria lo
   reclame. */
IF OBJECT_ID(N'integracion.Conciliacion', N'U') IS NULL
CREATE TABLE integracion.Conciliacion (
    IdConciliacion  bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_integracion_Conciliacion PRIMARY KEY,
    EjecutadoEn     datetime NOT NULL CONSTRAINT DF_integracion_Conciliacion_Ejecutado DEFAULT (GETDATE()),
    AnoEje          smallint    NOT NULL,
    SecEjec         int         NOT NULL,
    CentroCosto     varchar(15)     NULL,

    ItemsSigcm      int NOT NULL CONSTRAINT DF_integracion_Conciliacion_Sigcm DEFAULT (0),
    ItemsSiga       int NOT NULL CONSTRAINT DF_integracion_Conciliacion_Siga  DEFAULT (0),
    Coincidentes    int NOT NULL CONSTRAINT DF_integracion_Conciliacion_Coinc DEFAULT (0),
    /* Mapeado en SIGCM pero ausente en SIGA */
    HuerfanosSigcm  int NOT NULL CONSTRAINT DF_integracion_Conciliacion_HuerfSigcm DEFAULT (0),
    /* Presente en SIGA sin correspondencia local */
    HuerfanosSiga   int NOT NULL CONSTRAINT DF_integracion_Conciliacion_HuerfSiga  DEFAULT (0),
    Diferencias     nvarchar(max) NOT NULL CONSTRAINT DF_integracion_Conciliacion_Diferencias DEFAULT (N'[]'),
    Resultado       varchar(15)   NOT NULL CONSTRAINT DF_integracion_Conciliacion_Resultado   DEFAULT ('OK'),

    UsuarioCreacionAuditoria  varchar(30) NULL,
    EquipoCreacionAuditoria   varchar(50) NULL,
    ProgramaCreacionAuditoria varchar(50) NULL,

    CONSTRAINT CK_integracion_Conciliacion_Resultado   CHECK (Resultado IN ('OK','DIFERENCIAS','ERROR')),
    CONSTRAINT CK_integracion_Conciliacion_Diferencias CHECK (ISJSON(Diferencias) = 1)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_integracion_Conciliacion_Fecha' AND object_id = OBJECT_ID(N'integracion.Conciliacion'))
CREATE NONCLUSTERED INDEX IX_integracion_Conciliacion_Fecha
    ON integracion.Conciliacion(EjecutadoEn DESC);
GO

/* -------------------------------------------------------------------------- */
/* 4. Vista operativa de la cola                                              */
/* -------------------------------------------------------------------------- */

CREATE OR ALTER VIEW integracion.vwEstadoCola
AS
SELECT
    Estado               = o.Estado,
    Operacion            = o.Operacion,
    Operaciones          = COUNT_BIG(*),
    MasAntigua           = MIN(o.FechaCreacionAuditoria),
    MaxIntentosAlcanzado = MAX(o.Intentos),
    Agotadas             = SUM(CASE WHEN o.Intentos >= o.MaxIntentos THEN 1 ELSE 0 END)
FROM integracion.Operacion AS o
GROUP BY o.Estado, o.Operacion;
GO

PRINT 'V006 aplicada.';
GO
