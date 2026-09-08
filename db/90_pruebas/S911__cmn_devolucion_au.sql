/*
===============================================================================
  SIGCM - S911 : Dos CMN listos para devolverse al Jefe del area usuaria
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750

  FUERA DE LA SERIE. Repetible y se limpia solo, igual que S909 y S910.

  ---------------------------------------------------------------------------
  QUE PRUEBA
  ---------------------------------------------------------------------------
  Los dos caminos por los que un CMN vuelve al area usuaria. Los dos terminan en
  el MISMO estado -CMN_OBS_AU_JEFE- y los dos van DIRECTO al jefe, sin escalones
  intermedios:

    A) Desde Administracion
       CMN_EN_EVAL_OA --CMN_OA_OBSERVAR--> CMN_OBS_AU_JEFE
       La ejecuta OA (46025999). Exige comentario.

    B) Desde Abastecimiento
       CMN_EN_ABAST_JEFE --CMN_ABAST_JEFE_OBSERVAR--> CMN_OBS_AU_JEFE
       La ejecutan ABAST_JEFE (09086695) o ABAST_SECRETARIA (46970816).
       Exige comentario.

  Ojo con B: NO es el camino largo del especialista -observar, elevar al
  coordinador, devolver-, que sigue existiendo y termina en el mismo sitio.
  Este es el atajo del jefe de Abastecimiento, que sembro S030.

  ---------------------------------------------------------------------------
  QUE DEJA
  ---------------------------------------------------------------------------
    Expediente A  en CMN_EN_EVAL_OA        -> bandeja de ADMINISTRACION (46025999)
    Expediente B  en CMN_EN_ABAST_JEFE     -> bandeja de ABASTECIMIENTO (09086695)

  Los dos recorrieron el flujo de verdad hasta ahi: se registro la solicitud con
  cmn.paRegistrarSolicitud, se genero el Anexo 3, se registro su PDF, lo firmo
  el jefe del area usuaria y la firma movio el expediente. No hay un solo UPDATE
  de estado a mano, asi que la trazabilidad que se ve en pantalla es la real.

  NO ESCRIBEN EN SIGA. La escritura ocurre recien en CMN_ABAST_JEFE_FIRMAR_A3,
  que esta mas adelante que donde se detienen estos dos.

  ---------------------------------------------------------------------------
  COMO SE USA
  ---------------------------------------------------------------------------
      sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I \
             -i db/90_pruebas/S911__cmn_devolucion_au.sql

  Vuelve a correrlo cuantas veces quieras: borra lo suyo y lo rehace. Reconoce
  lo suyo por el sustento, que empieza con la marca S911.

  DESPUES DE CORRERLO
  -------------------
    1. Entra con 46025999 (Administracion), abre el expediente A y usa
       "Observar desde la Oficina de Administracion" con un comentario.
    2. Entra con 09086695 -o con 46970816, la secretaria- abre el B y usa
       "Observar y devolver al Jefe del Area usuaria".
    3. Entra con 44687266 (Jefe del area usuaria): los dos tienen que estar en
       su bandeja, en "Observado - Jefe del area usuaria".
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Marca varchar(20) = 'S911';

/* Las cuentas reales del SSO, no las locales de S900: el expediente tiene que
   caer en la bandeja que se va a abrir para probarlo. */
DECLARE @ActorEsp  nvarchar(400) = N'"Actor":{"Usuario":"46183970","Rol":"AREA_ESPECIALISTA","Unidad":"UO-OTI","Equipo":"S911","Programa":"S911"}';
DECLARE @ActorJefe nvarchar(400) = N'"Actor":{"Usuario":"44687266","Rol":"AREA_JEFE","Unidad":"UO-OTI","Equipo":"S911","Programa":"S911"}';
DECLARE @ActorOA   nvarchar(400) = N'"Actor":{"Usuario":"46025999","Rol":"OA","Unidad":"D0011","Equipo":"S911","Programa":"S911"}';

DECLARE @CentroCosto varchar(15) = '01.07.05.03';   /* OTI */
DECLARE @AnoEje int = 2026, @SecEjec int = 1750;
DECLARE @SecFunc int = 15, @Clasificador varchar(20) = '2.3. 2  9. 1  1';

/* -------------------------------------------------------------------------- */
/* 1. Limpieza de la corrida anterior                                         */
/* -------------------------------------------------------------------------- */

DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY);
INSERT INTO @Exp (IdExpediente)
SELECT s.IdExpediente FROM cmn.Solicitud AS s WHERE s.Sustento LIKE @Marca + ':%';

IF EXISTS (SELECT 1 FROM @Exp)
BEGIN
    DECLARE @Sol TABLE (IdSolicitud uniqueidentifier PRIMARY KEY);
    INSERT INTO @Sol (IdSolicitud)
    SELECT s.IdSolicitud FROM cmn.Solicitud AS s JOIN @Exp AS e ON e.IdExpediente = s.IdExpediente;

    DECLARE @Doc TABLE (IdDocumento uniqueidentifier PRIMARY KEY);
    INSERT INTO @Doc (IdDocumento)
    SELECT DISTINCT de.IdDocumento
      FROM sigcm.DocumentoExpediente AS de JOIN @Exp AS e ON e.IdExpediente = de.IdExpediente;

    BEGIN TRANSACTION;

    DELETE o  FROM integracion.Operacion AS o JOIN @Exp AS e ON e.IdExpediente = o.IdExpediente;
    DELETE m  FROM integracion.MapeoCmn  AS m JOIN @Sol AS s ON s.IdSolicitud  = m.IdSolicitud;

    DELETE ps FROM cmn.PaqueteSolicitud AS ps JOIN @Sol AS s ON s.IdSolicitud = ps.IdSolicitud;
    DELETE p  FROM cmn.SolicitudItemPeriodo AS p
      JOIN cmn.SolicitudItem AS i ON i.IdSolicitudItem = p.IdSolicitudItem
      JOIN @Sol AS s ON s.IdSolicitud = i.IdSolicitud;
    DELETE i  FROM cmn.SolicitudItem AS i JOIN @Sol AS s ON s.IdSolicitud = i.IdSolicitud;
    DELETE c  FROM cmn.Solicitud     AS c JOIN @Sol AS s ON s.IdSolicitud = c.IdSolicitud;

    DELETE f  FROM sigcm.Firma AS f
      JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumentoVersion = f.IdDocumentoVersion
      JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
    DELETE o  FROM sigcm.Observacion AS o JOIN @Exp AS e ON e.IdExpediente = o.IdExpediente;
    DELETE dv FROM sigcm.DocumentoVersion   AS dv JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
    DELETE de FROM sigcm.DocumentoExpediente AS de JOIN @Exp AS e ON e.IdExpediente = de.IdExpediente;
    DELETE dd FROM sigcm.Documento AS dd JOIN @Doc AS d ON d.IdDocumento = dd.IdDocumento;

    DELETE pl FROM sigcm.Plazo     AS pl JOIN @Exp AS e ON e.IdExpediente = pl.IdExpediente;
    DELETE h  FROM sigcm.Historial AS h  JOIN @Exp AS e ON e.IdExpediente = h.IdExpediente;
    DELETE ex FROM sigcm.Expediente AS ex JOIN @Exp AS e ON e.IdExpediente = ex.IdExpediente;

    COMMIT TRANSACTION;
    PRINT 'S911: limpiada la corrida anterior.';
END
GO

/* -------------------------------------------------------------------------- */
/* 2. Los dos expedientes, por las rutinas reales                             */
/* -------------------------------------------------------------------------- */

SET NOCOUNT ON;

DECLARE @Marca varchar(20) = 'S911';
DECLARE @ActorEsp  nvarchar(400) = N'"Actor":{"Usuario":"46183970","Rol":"AREA_ESPECIALISTA","Unidad":"UO-OTI","Equipo":"S911","Programa":"S911"}';
DECLARE @ActorJefe nvarchar(400) = N'"Actor":{"Usuario":"44687266","Rol":"AREA_JEFE","Unidad":"UO-OTI","Equipo":"S911","Programa":"S911"}';
DECLARE @ActorOA   nvarchar(400) = N'"Actor":{"Usuario":"46025999","Rol":"OA","Unidad":"D0011","Equipo":"S911","Programa":"S911"}';
DECLARE @CentroCosto varchar(15) = '01.07.05.03';
DECLARE @SecFunc int = 15, @Clasificador varchar(20) = '2.3. 2  9. 1  1';

/* La tarea y el item se toman del cuadro real del centro, como hace S901: si se
   fijan a mano, el dia que cambie el cuadro la solicitud no valida. */
DECLARE @TipoTarea varchar(1), @NivelTarea varchar(1), @CodigoTarea int;
DECLARE @GrupoBien varchar(2), @ClaseBien varchar(2), @FamiliaBien varchar(4), @ItemBien varchar(4);

SELECT TOP 1
       @TipoTarea = d.TIPO_TAREA, @NivelTarea = d.NIVEL_TAREA, @CodigoTarea = d.CODIGO_TAREA,
       @GrupoBien = d.GRUPO_BIEN, @ClaseBien = d.CLASE_BIEN,
       @FamiliaBien = d.FAMILIA_BIEN, @ItemBien = d.ITEM_BIEN
  FROM siga.SIG_CUADRO_MODIFICADO_DET AS d
 WHERE d.ANNO_PROG = 2026 AND d.SEC_EJEC = 1750
   AND d.CENTRO_COSTO = @CentroCosto
   AND d.SEC_FUNC = @SecFunc AND d.CLASIFICADOR = @Clasificador
   AND d.TIPO_BIEN = 'S'
 ORDER BY d.SEC_ITEM;

IF @TipoTarea IS NULL
    THROW 59110, 'NO_ENCONTRADO: no hay un item de referencia en el cuadro de OTI. Revise el centro de costo.', 1;

DECLARE @r TABLE (j nvarchar(max));
DECLARE @j nvarchar(max), @p nvarchar(max);
DECLARE @IdExpediente varchar(50), @Codigo varchar(40), @Version int;
DECLARE @caso int = 1, @Destino varchar(40), @Etiqueta varchar(60);

WHILE @caso <= 2
BEGIN
    SET @Etiqueta = CASE WHEN @caso = 1
                         THEN 'devolucion desde Administracion'
                         ELSE 'devolucion desde Abastecimiento' END;

    /* ---- Anexo 3 ------------------------------------------------------ */
    SET @p = N'{' + @ActorEsp + N',
      "Solicitud": { "AnoEje": 2026, "SecEjec": 1750, "CentroCosto": "' + @CentroCosto + N'",
                     "TipoOperacion": "MODIFICACION",
                     "Sustento": "' + @Marca + N': caso ' + CONVERT(varchar(2), @caso) + N' - ' + @Etiqueta + N'.",
                     "TipoInclusion": "EXTRAORDINARIA",
                     "JustificacionUrgencia": "' + @Marca + N': expediente sembrado para probar la devolucion al jefe del area usuaria." },
      "Items": [ { "TipoMovimiento": "INCLUSION",
                   "TipoTarea": "' + @TipoTarea + N'", "NivelTarea": "' + @NivelTarea + N'",
                   "CodigoTarea": ' + CONVERT(varchar(10), @CodigoTarea) + N', "SecFunc": ' + CONVERT(varchar(10), @SecFunc) + N',
                   "Origen": "1", "FuenteFinanc": "00", "Clasificador": "' + @Clasificador + N'",
                   "TipoRecurso": "1", "TipoPpto": 1, "TipoUso": "C",
                   "TipoBien": "S", "GrupoBien": "' + @GrupoBien + N'", "ClaseBien": "' + @ClaseBien + N'",
                   "FamiliaBien": "' + @FamiliaBien + N'", "ItemBien": "' + @ItemBien + N'",
                   "PrecioUnitario": 1.00,
                   "Periodos": [ {"AnoOffset":0,"Mes":11,"Cantidad":500},
                                 {"AnoOffset":0,"Mes":12,"Cantidad":500} ] } ] }';

    DELETE FROM @r; INSERT INTO @r EXEC cmn.paRegistrarSolicitud @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j, '$.estado') <> '1'
        THROW 59111, 'No se pudo registrar la solicitud del caso sembrado.', 1;

    SET @IdExpediente = JSON_VALUE(@j, '$.IdExpediente');
    SET @Codigo       = JSON_VALUE(@j, '$.Codigo');
    SET @Version      = 1;

    /* ---- Generar el Anexo 3 ------------------------------------------- */
    SET @p = N'{' + @ActorEsp + N',"IdExpediente":"' + @IdExpediente
           + N'","CodigoTransicion":"CMN_GENERAR_A3","Version":' + CONVERT(varchar(10), @Version) + N'}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1' THROW 59112, 'Fallo CMN_GENERAR_A3.', 1;
    SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));

    /* ---- El PDF del Anexo 3 -------------------------------------------- */
    /* El identificador es un marcador: en el file server no hay nada detras, y
       eso es lo esperado en un expediente sembrado. La rutina solo exige que
       venga. */
    SET @p = N'{' + @ActorEsp + N',"IdExpediente":"' + @IdExpediente + N'",
      "CodigoTipoDocumento":"CMN_ANEXO_3_SOLICITUD_MODIFICACION",
      "GeneradoDocumento":"' + @Marca + N'-' + @Codigo + N'-anexo3.pdf",
      "NombreDocumento":"Anexo 3 - ' + @Codigo + N'.pdf"}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paRegistrarDocumento @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1' THROW 59113, 'Fallo al registrar el PDF del Anexo 3.', 1;

    /* ---- Firma del jefe del area usuaria ------------------------------- */
    SET @p = N'{' + @ActorJefe + N',"IdExpediente":"' + @IdExpediente + N'",
      "CodigoTipoDocumento":"CMN_ANEXO_3_SOLICITUD_MODIFICACION"}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paFirmarDocumento @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1' THROW 59114, 'Fallo la firma del Anexo 3.', 1;

    SET @p = N'{' + @ActorJefe + N',"IdExpediente":"' + @IdExpediente
           + N'","CodigoTransicion":"CMN_FIRMAR_A3","Version":' + CONVERT(varchar(10), @Version) + N'}';
    DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
    SELECT @j = j FROM @r;
    IF JSON_VALUE(@j,'$.estado') <> '1' THROW 59115, 'Fallo CMN_FIRMAR_A3.', 1;
    SET @Version = CONVERT(int, JSON_VALUE(@j,'$.Version'));

    /* ---- El caso 2 sigue hasta Abastecimiento -------------------------- */
    IF @caso = 2
    BEGIN
        SET @p = N'{' + @ActorOA + N',"IdExpediente":"' + @IdExpediente
               + N'","CodigoTransicion":"CMN_OA_DERIVAR","Version":' + CONVERT(varchar(10), @Version) + N'}';
        DELETE FROM @r; INSERT INTO @r EXEC sigcm.paEjecutarTransicion @p;
        SELECT @j = j FROM @r;
        IF JSON_VALUE(@j,'$.estado') <> '1' THROW 59116, 'Fallo CMN_OA_DERIVAR.', 1;
    END

    SET @caso = @caso + 1;
END
GO

/* -------------------------------------------------------------------------- */
/* 3. Resultado                                                               */
/* -------------------------------------------------------------------------- */

SELECT expediente = e.Codigo,
       estado     = w.Nombre,
       codigo_estado = e.CodigoEstado,
       bandeja    = un.Sigla,
       le_toca_a  = w.RolResponsable,
       accion_a_probar = (SELECT TOP 1 t.NombreAccion
                            FROM sigcm.Transicion AS t
                           WHERE t.CodigoEstadoOrigen = e.CodigoEstado
                             AND t.CodigoEstadoDestino = 'CMN_OBS_AU_JEFE'
                             AND t.Activo = 1),
       sustento   = LEFT(s.Sustento, 60)
  FROM cmn.Solicitud AS s
  JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
  JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
  JOIN sigcm.Unidad AS un ON un.IdUnidad = e.IdUnidadActual
 WHERE s.Sustento LIKE 'S911:%'
 ORDER BY s.Sustento;
GO

PRINT 'S911 aplicada: un CMN en la bandeja de Administracion y otro en la de Abastecimiento, listos para devolver al Jefe del area usuaria.';
GO
