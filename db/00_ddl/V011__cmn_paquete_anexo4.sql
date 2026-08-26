/*
===============================================================================
  SIGCM - V011 : Anexo 4 multiple (paquete) y firma en varios pasos
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  ---------------------------------------------------------------------------
  QUE CAMBIA EN EL FLUJO Y POR QUE HACE FALTA ESTE SCRIPT
  ---------------------------------------------------------------------------
  Hasta V010 el Anexo 4 era 1:1 con el Anexo 3: un expediente, un Anexo 3, un
  Anexo 4. El flujo aprobado por Abastecimiento cambia dos cosas de fondo:

  1. UN ANEXO 4 AGRUPA VARIOS ANEXOS 3, de areas usuarias distintas. El
     especialista de Abastecimiento marca con un check los Anexos 3 ya firmados
     y genera un solo Anexo 4 para todos.

  2. LOS ANEXOS SE FIRMAN EN VARIOS PASOS. El Anexo 3 lo firma el jefe del area
     usuaria y despues, en cadena, el especialista, el coordinador y el jefe de
     Abastecimiento. El Anexo 4 lo firman el especialista, el coordinador y el
     jefe. Antes cada documento tenia un firmante y la version se cerraba con
     esa unica firma.

  ---------------------------------------------------------------------------
  LO QUE NO HIZO FALTA CREAR
  ---------------------------------------------------------------------------
  Casi todo estaba previsto y se reutiliza tal cual:

  - sigcm.DocumentoExpediente ya es N:M y su comentario ya decia "un Anexo 4
    consolidado cubre varias solicitudes". El documento del paquete se enlaza a
    los N expedientes por esa tabla; no hay documento por expediente.
  - sigcm.Documento.Consolidado y sigcm.TipoDocumento.AdmiteConsolidado ya
    existian y ya venian sembrados en 1 para el Anexo 4.
  - sigcm.Firma ya cuelga de la VERSION con UNIQUE (version, rol): estaba
    disenada para varias firmas por version. Lo que faltaba era que
    sigcm.paFirmarDocumento la usara, cosa que hasta ahora no hacia.
  - cmn.Solicitud.TipoInclusion ya admitia ORDINARIA / URGENTE, que es
    exactamente la decision del paso 6 del flujo.

  Por eso este script es corto: dos tablas de agrupacion y dos ajustes.

  ---------------------------------------------------------------------------
  POR QUE EL PAQUETE NO TIENE EXPEDIENTE PROPIO
  ---------------------------------------------------------------------------
  Se evaluo darle uno. No conviene: el expediente es la unidad de trazabilidad
  frente al area usuaria, y el area usuaria sigue preguntando por SU Anexo 3.
  Si el Anexo 4 tuviera expediente propio, el expediente del area quedaria
  detenido en un estado ciego mientras el tramite real ocurre en otro numero
  que ella no conoce.

  El paquete es entonces una CABECERA DE AGRUPACION, y la maquina de estados
  sigue corriendo sobre los expedientes de los Anexos 3, todos a la vez: cuando
  el coordinador firma el Anexo 4, los N expedientes avanzan en la misma
  transaccion. Eso es lo que resuelve sigcm.paEjecutarTransicion cuando recibe
  IdExpedientes en lugar de IdExpediente.

  Idempotente: se puede reejecutar.
===============================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Paquete = cabecera de un Anexo 4                                        */
/* -------------------------------------------------------------------------- */

/*
  TipoInclusion se copia aqui desde las solicitudes y no se recalcula: es la
  decision del especialista y es la que gobierna la regla del viernes. Un
  paquete es ORDINARIO o URGENTE entero; mezclar los dos dejaria sin sentido la
  restriccion de fecha, porque bastaria con colar un item urgente para generar
  cualquier dia todo lo ordinario.
*/
IF OBJECT_ID(N'cmn.Paquete', N'U') IS NULL
CREATE TABLE cmn.Paquete (
    IdPaquete        uniqueidentifier NOT NULL
                     CONSTRAINT DF_cmn_Paquete_Id DEFAULT (NEWSEQUENTIALID())
                     CONSTRAINT PK_cmn_Paquete PRIMARY KEY,
    Codigo           varchar(40) NOT NULL CONSTRAINT UQ_cmn_Paquete_Codigo UNIQUE,

    AnoEje           smallint    NOT NULL,
    SecEjec          int         NOT NULL,
    TipoInclusion    varchar(15) NOT NULL,

    /* Quien lo armo. Es el especialista de Abastecimiento; queda registrado
       porque es el responsable de la seleccion de Anexos 3 que lo compone. */
    IdUsuarioGenera  uniqueidentifier NOT NULL
                     CONSTRAINT FK_cmn_Paquete_Usuario REFERENCES sigcm.Usuario(IdUsuario),
    IdUnidadGenera   uniqueidentifier NOT NULL
                     CONSTRAINT FK_cmn_Paquete_Unidad REFERENCES sigcm.Unidad(IdUnidad),

    Sustento         nvarchar(max) NULL,
    DatosAdicionales nvarchar(max) NOT NULL CONSTRAINT DF_cmn_Paquete_Datos DEFAULT (N'{}'),

    Anulado          bit NOT NULL CONSTRAINT DF_cmn_Paquete_Anulado DEFAULT (0),
    MotivoAnulacion  nvarchar(max) NULL,
    Activo           bit NOT NULL CONSTRAINT DF_cmn_Paquete_Activo DEFAULT (1),

    UsuarioCreacionAuditoria      varchar(30) NULL,
    FechaCreacionAuditoria        datetime    NULL CONSTRAINT DF_cmn_Paquete_FecCre DEFAULT (GETDATE()),
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

    /* V015 sustituye URGENTE por EXTRAORDINARIA en esta misma restriccion. */
    CONSTRAINT CK_cmn_Paquete_Inclusion CHECK (TipoInclusion IN ('ORDINARIA','URGENTE')),
    CONSTRAINT CK_cmn_Paquete_Ano       CHECK (AnoEje BETWEEN 2020 AND 2100),
    CONSTRAINT CK_cmn_Paquete_Datos     CHECK (ISJSON(DatosAdicionales) = 1),
    CONSTRAINT CK_cmn_Paquete_Anulado   CHECK (Anulado = 0 OR MotivoAnulacion IS NOT NULL)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cmn_Paquete_Ano' AND object_id = OBJECT_ID(N'cmn.Paquete'))
CREATE NONCLUSTERED INDEX IX_cmn_Paquete_Ano
    ON cmn.Paquete(AnoEje, SecEjec)
    WHERE Anulado = 0 AND Activo = 1;
GO

/* -------------------------------------------------------------------------- */
/* 2. Que Anexos 3 componen el paquete                                        */
/* -------------------------------------------------------------------------- */

/*
  Orden fija la secuencia con que las solicitudes se imprimen en el Anexo 4. Se
  guarda en vez de ordenar por codigo al vuelo porque el documento firmado debe
  poder reconstruirse identico, y un ordenamiento calculado cambia si manana se
  cambia el criterio.

  El indice unico filtrado sobre IdSolicitud es la regla de negocio central de
  esta tabla: UN ANEXO 3 NO PUEDE ESTAR EN DOS ANEXOS 4. Sin el, dos
  especialistas trabajando a la vez podrian incluir la misma solicitud en dos
  paquetes y SIGA recibiria la aprobacion dos veces. Es filtrado por Activo
  para que anular un paquete libere sus solicitudes.
*/
IF OBJECT_ID(N'cmn.PaqueteSolicitud', N'U') IS NULL
CREATE TABLE cmn.PaqueteSolicitud (
    IdPaquete   uniqueidentifier NOT NULL
                CONSTRAINT FK_cmn_PaqSol_Paquete REFERENCES cmn.Paquete(IdPaquete) ON DELETE CASCADE,
    IdSolicitud uniqueidentifier NOT NULL
                CONSTRAINT FK_cmn_PaqSol_Solicitud REFERENCES cmn.Solicitud(IdSolicitud),
    Orden       int NOT NULL CONSTRAINT DF_cmn_PaqSol_Orden DEFAULT (1),
    Activo      bit NOT NULL CONSTRAINT DF_cmn_PaqSol_Activo DEFAULT (1),

    UsuarioCreacionAuditoria  varchar(30) NULL,
    FechaCreacionAuditoria    datetime    NULL CONSTRAINT DF_cmn_PaqSol_FecCre DEFAULT (GETDATE()),
    EquipoCreacionAuditoria   varchar(50) NULL,
    ProgramaCreacionAuditoria varchar(50) NULL,

    CONSTRAINT PK_cmn_PaqueteSolicitud PRIMARY KEY (IdPaquete, IdSolicitud)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_cmn_PaqSol_SolicitudUnica' AND object_id = OBJECT_ID(N'cmn.PaqueteSolicitud'))
CREATE UNIQUE NONCLUSTERED INDEX UQ_cmn_PaqSol_SolicitudUnica
    ON cmn.PaqueteSolicitud(IdSolicitud)
    WHERE Activo = 1;
GO

/* -------------------------------------------------------------------------- */
/* 3. La version del documento admite firma parcial                           */
/* -------------------------------------------------------------------------- */

/*
  Estado PARCIAL: hay al menos una firma registrada pero faltan firmantes.

  Sin este estado el motor no puede distinguir "lo firmo el jefe del area
  usuaria y va camino a Abastecimiento" de "lo firmaron los cuatro". Con un
  solo estado FIRMADO habria que elegir entre dar por cerrado el documento en
  la primera firma —que es el defecto que tenia sigcm.paFirmarDocumento— o
  bloquear el flujo hasta la ultima, que dejaria al Anexo 3 sin poder salir del
  area usuaria.

  BORRADOR -> PARCIAL -> FIRMADO, y cualquiera de ellos -> ANULADA / SUPERADA.
*/
IF EXISTS (SELECT 1 FROM sys.check_constraints
            WHERE name = N'CK_sigcm_DocVersion_Estado'
              AND parent_object_id = OBJECT_ID(N'sigcm.DocumentoVersion'))
    ALTER TABLE sigcm.DocumentoVersion DROP CONSTRAINT CK_sigcm_DocVersion_Estado;
GO

ALTER TABLE sigcm.DocumentoVersion WITH CHECK
    ADD CONSTRAINT CK_sigcm_DocVersion_Estado
    CHECK (Estado IN ('BORRADOR','PARCIAL','FIRMADO','SUPERADA','ANULADA'));
GO

/* -------------------------------------------------------------------------- */
/* 4. Una transicion puede exigir la firma de UN rol, no el documento entero   */
/* -------------------------------------------------------------------------- */

/*
  sigcm.Transicion.DocumentoRequerido significaba "el documento existe y su
  version vigente esta FIRMADA". Con firma en cadena eso deja de alcanzar: el
  jefe del area usuaria envia a la Oficina de Administracion un Anexo 3 que el
  firmo y que todavia le faltan tres firmas.

  RolFirmaRequerida precisa la exigencia:

    NULL  -> comportamiento anterior: la version vigente debe estar FIRMADO,
             es decir, con TODAS las firmas declaradas. Es lo que corresponde
             al envio del Anexo 4 al area usuaria, que ya no admite pendientes.
    <rol> -> basta con que ESE rol tenga su firma vigente sobre la version.
             Es lo que corresponde a cada paso de la cadena.

  Se modela como dato y no como condicional en el motor por la misma razon que
  el resto de la maquina de estados: incorporar un firmante nuevo debe ser una
  fila, no un despliegue.
*/
IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID(N'sigcm.Transicion')
                  AND name = N'RolFirmaRequerida')
BEGIN
    ALTER TABLE sigcm.Transicion ADD RolFirmaRequerida varchar(40) NULL;
    PRINT '  sigcm.Transicion.RolFirmaRequerida agregada.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_sigcm_Transicion_RolFirma')
    ALTER TABLE sigcm.Transicion
        ADD CONSTRAINT FK_sigcm_Transicion_RolFirma
        FOREIGN KEY (RolFirmaRequerida) REFERENCES sigcm.Rol(CodigoRol);
GO

/* -------------------------------------------------------------------------- */
/* 5. Correlativo del Anexo 4                                                 */
/* -------------------------------------------------------------------------- */

/*
  Serie propia: el Anexo 4 ya no se numera con el codigo del expediente porque
  puede cubrir varios. Se siembra desde lo emitido, con el mismo criterio de
  V010, para que reinstalar no choque contra UQ_cmn_Paquete_Codigo.
*/
MERGE sigcm.Correlativo AS destino
USING (
    SELECT Nombre = N'cmn.SeqPaquete',
           Valor  = ISNULL((SELECT MAX(TRY_CONVERT(bigint, RIGHT(p.Codigo, 6)))
                              FROM cmn.Paquete AS p
                             WHERE p.Codigo LIKE 'A4-%'
                               AND LEN(p.Codigo) >= 7
                               AND TRY_CONVERT(bigint, RIGHT(p.Codigo, 6)) IS NOT NULL), 0)
) AS origen
ON destino.Nombre = origen.Nombre
WHEN MATCHED AND destino.Valor < origen.Valor
    THEN UPDATE SET Valor = origen.Valor
WHEN NOT MATCHED BY TARGET
    THEN INSERT (Nombre, Valor) VALUES (origen.Nombre, origen.Valor);
GO

PRINT 'V011 aplicada: cmn.Paquete, cmn.PaqueteSolicitud, firma parcial y RolFirmaRequerida.';
GO
