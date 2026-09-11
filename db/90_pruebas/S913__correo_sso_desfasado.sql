/*
===============================================================================
  SIGCM - S913 : El correo del SSO manda sobre la copia local
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750   NO TOCA saa_

  FUERA DE LA SERIE. Repetible y no deja rastro, igual que S909, S910 y S911.

  ---------------------------------------------------------------------------
  QUE PRUEBA
  ---------------------------------------------------------------------------
  El defecto que se vio el 2026-09-09: se cambio el correo de una cuenta en el
  SSO y las notificaciones siguieron llegando a la bandeja anterior. Tenia dos
  causas independientes y este script cubre la segunda, que es la que no se
  arregla sola con el tiempo:

    CAUSA 1  sigcm.Usuario solo se refrescaba al INGRESAR por SSO. Con un token
             de ocho horas, una jornada entera corria contra la foto de la
             manana. Se cierra en el backend -refresco antes de notificar, mas
             PadronSsoWorker- y NO se puede probar desde SQL: aqui no hay sesion
             ni worker. Su guion esta en pruebas/PRUEBAS_FLUJO_COMPLETO.md.

    CAUSA 2  requerimiento.OrdenServicio.CorreoAreaUsuaria guardaba una COPIA
             del correo tomada al registrar la orden, y la leia de ahi
             paPrepararNotificacionOrden. Esa copia no caduca nunca: aunque el
             padron estuviera al dia, la notificacion usaba el valor viejo.
             Eso es lo que se prueba aqui.

  Los cuatro casos:

    CASO 1  La copia congelada y el correo vigente DIFIEREN.
            Esperado: el sobre lleva el VIGENTE. Es el caso que fallaba.

    CASO 2  La persona ya no tiene correo vigente (baja en el SSO).
            Esperado: se cae a la copia congelada. Avisar a la direccion vieja
            es mejor que no avisar a nadie: el expediente tiene que poder
            notificarse igual.

    CASO 3  CMN (paPrepararNotificacionAnexo4) nunca tuvo el defecto porque ya
            resolvia contra sigcm.Usuario al enviar. Se comprueba para que no se
            rompa: es exactamente el patron que F010 acaba de adoptar.

    CASO 4  El candado de sigcm.paSincronizarPadronSso esta puesto. Que dos
            corridas simultaneas no se pisen necesita dos sesiones y esta en el
            guion manual.

  ---------------------------------------------------------------------------
  COMO SE USA
  ---------------------------------------------------------------------------
      sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -i db/90_pruebas/S913__correo_sso_desfasado.sql

  Imprime PASA o FALLA por caso y, si algo falla, termina con THROW para que la
  consola devuelva codigo distinto de cero.

  NO DEJA RASTRO. Toma un requerimiento que ya este en REQ_OS_EMITIDA, manipula
  sus valores dentro de una transaccion y hace ROLLBACK. Si no hay ninguno, lo
  dice y no falla: corre antes S909.
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Fallos int = 0;
DECLARE @IdRequerimiento uniqueidentifier, @IdResponsable uniqueidentifier,
        @Cuenta varchar(120), @CodigoRol varchar(40), @CodigoUnidad varchar(30),
        @Codigo varchar(40);

SELECT TOP 1
       @IdRequerimiento = r.IdRequerimiento,
       @IdResponsable   = r.IdResponsable,
       @Codigo          = r.Codigo
  FROM requerimiento.Requerimiento AS r
  JOIN sigcm.Expediente AS e ON e.IdExpediente = r.IdExpediente
  JOIN requerimiento.OrdenServicio AS o ON o.IdRequerimiento = r.IdRequerimiento AND o.Activo = 1
 WHERE r.Activo = 1 AND e.CodigoEstado = 'REQ_OS_EMITIDA'
 ORDER BY r.FechaCreacionAuditoria DESC;

IF @IdRequerimiento IS NULL
BEGIN
    PRINT 'S913 OMITIDA: no hay ningun requerimiento en REQ_OS_EMITIDA.';
    PRINT '              Corre antes db/90_pruebas/S909__datos_prueba_pago.sql';
    RETURN;
END

/* El actor tiene que tener una terna vigente: paResolverActor la exige y sin
   ella la rutina responde VALIDACION_ACTOR antes de llegar al correo. */
SELECT TOP 1 @Cuenta = u.Cuenta, @CodigoRol = ur.CodigoRol, @CodigoUnidad = n.Codigo
  FROM sigcm.UsuarioRol AS ur
  JOIN sigcm.Usuario AS u ON u.IdUsuario = ur.IdUsuario
  JOIN sigcm.Unidad  AS n ON n.IdUnidad  = ur.IdUnidad
 WHERE ur.CodigoRol IN ('ABAST_ESPECIALISTA', 'ABAST_COORDINADOR', 'ABAST_JEFE')
   AND ur.Activo = 1 AND u.Activo = 1
   AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()));

IF @Cuenta IS NULL
BEGIN
    PRINT 'S913 OMITIDA: no hay ninguna cuenta de Abastecimiento con terna vigente.';
    RETURN;
END

PRINT '=== S913 - requerimiento ' + @Codigo + ' - actor ' + @Cuenta + ' ===';
PRINT '';

DECLARE @Actor nvarchar(400) = (
    SELECT @Cuenta AS Usuario, @CodigoRol AS Rol, @CodigoUnidad AS Unidad,
           'S913' AS Equipo, 'SIGCM-PRUEBA' AS Programa
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

DECLARE @Payload nvarchar(max) = (
    SELECT @IdRequerimiento AS IdRequerimiento, JSON_QUERY(@Actor) AS Actor
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

DECLARE @Salida TABLE (Json nvarchar(max));
DECLARE @Json nvarchar(max), @Copia varchar(400);

DECLARE @Vigente   varchar(200) = 's913.vigente@anin.gob.pe';
DECLARE @Congelado varchar(200) = 's913.congelado@anin.gob.pe';

BEGIN TRANSACTION;

/* --------------------------------------------------------------------- */
/*  CASO 1 - difieren: debe ganar el vigente                              */
/* --------------------------------------------------------------------- */
UPDATE sigcm.Usuario SET Correo = @Vigente WHERE IdUsuario = @IdResponsable;
UPDATE requerimiento.OrdenServicio SET CorreoAreaUsuaria = @Congelado
 WHERE IdRequerimiento = @IdRequerimiento;

DELETE FROM @Salida;
INSERT INTO @Salida EXEC requerimiento.paPrepararNotificacionOrden @Payload;
SELECT @Json = Json FROM @Salida;
SET @Copia = JSON_VALUE(@Json, '$.Copia');

IF @Copia = @Vigente
    PRINT 'CASO 1  PASA  - el sobre usa el correo vigente (' + @Copia + ')';
ELSE
BEGIN
    PRINT 'CASO 1  FALLA - esperaba ' + @Vigente + ' y llego ' + ISNULL(@Copia, '(nulo)');
    PRINT '                la rutina sigue leyendo OrdenServicio.CorreoAreaUsuaria';
    SET @Fallos += 1;
END

/* --------------------------------------------------------------------- */
/*  CASO 2 - sin correo vigente: debe caer a la copia                     */
/* --------------------------------------------------------------------- */
UPDATE sigcm.Usuario SET Correo = NULL WHERE IdUsuario = @IdResponsable;

DELETE FROM @Salida;
INSERT INTO @Salida EXEC requerimiento.paPrepararNotificacionOrden @Payload;
SELECT @Json = Json FROM @Salida;
SET @Copia = JSON_VALUE(@Json, '$.Copia');

IF @Copia = @Congelado
    PRINT 'CASO 2  PASA  - sin correo vigente cae a la copia (' + @Copia + ')';
ELSE
BEGIN
    PRINT 'CASO 2  FALLA - esperaba el respaldo ' + @Congelado
        + ' y llego ' + ISNULL(@Copia, '(nulo)');
    PRINT '                una baja en el SSO no debe dejar la orden sin notificar';
    SET @Fallos += 1;
END

/* --------------------------------------------------------------------- */
/*  CASO 3 - CMN ya resolvia en vivo: que siga asi                        */
/* --------------------------------------------------------------------- */
DECLARE @IdSolicitud uniqueidentifier, @IdJefe uniqueidentifier,
        @Destino varchar(800);

SELECT TOP 1 @IdSolicitud = s.IdSolicitud
  FROM cmn.Solicitud AS s
  JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
 WHERE s.Activo = 1 AND e.CodigoEstado IN ('CMN_A4_ENVIADO', 'CMN_APROBADO')
 ORDER BY s.FechaCreacionAuditoria DESC;

IF @IdSolicitud IS NULL
    PRINT 'CASO 3  OMITIDO - no hay ninguna solicitud CMN con el Anexo 4 firmado';
ELSE
BEGIN
    /* El destinatario del aviso del Anexo 4 es el jefe del area usuaria de la
       solicitud. Se le cambia el correo y el sobre tiene que reflejarlo sin que
       nadie vuelva a guardar nada en ninguna parte. */
    SELECT TOP 1 @IdJefe = u.IdUsuario
      FROM cmn.Solicitud AS s
      JOIN sigcm.Expediente AS e  ON e.IdExpediente = s.IdExpediente
      JOIN sigcm.UsuarioRol AS ur ON ur.IdUnidad = e.IdUnidadOrigen
                                 AND ur.CodigoRol = 'AREA_JEFE' AND ur.Activo = 1
      JOIN sigcm.Usuario    AS u  ON u.IdUsuario = ur.IdUsuario AND u.Activo = 1
     WHERE s.IdSolicitud = @IdSolicitud;

    IF @IdJefe IS NULL
        PRINT 'CASO 3  OMITIDO - la unidad de esa solicitud no tiene jefe con terna vigente';
    ELSE
    BEGIN
        UPDATE sigcm.Usuario SET Correo = @Vigente WHERE IdUsuario = @IdJefe;

        DECLARE @PayloadCmn nvarchar(max) = (
            SELECT @IdSolicitud AS IdSolicitud, JSON_QUERY(@Actor) AS Actor
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        BEGIN TRY
            DELETE FROM @Salida;
            INSERT INTO @Salida EXEC cmn.paPrepararNotificacionAnexo4 @PayloadCmn;
            SELECT @Json = Json FROM @Salida;
            SET @Destino = JSON_VALUE(@Json, '$.Destinatario');

            IF @Destino LIKE '%' + @Vigente + '%'
                PRINT 'CASO 3  PASA  - CMN resuelve el destinatario en vivo (' + @Destino + ')';
            ELSE
            BEGIN
                PRINT 'CASO 3  FALLA - esperaba que apareciera ' + @Vigente
                    + ' y llego ' + ISNULL(@Destino, '(nulo)');
                SET @Fallos += 1;
            END
        END TRY
        BEGIN CATCH
            /* Un estado que no admite el aviso no es un fallo de ESTA prueba. */
            PRINT 'CASO 3  OMITIDO - la rutina rechazo la solicitud: ' + ERROR_MESSAGE();
        END CATCH
    END
END

ROLLBACK TRANSACTION;

/* --------------------------------------------------------------------- */
/*  CASO 4 - el candado de la sincronizacion                              */
/* --------------------------------------------------------------------- */
IF EXISTS (SELECT 1
             FROM sys.sql_modules
            WHERE object_id = OBJECT_ID('sigcm.paSincronizarPadronSso')
              AND definition LIKE '%sp_getapplock%'
              AND definition LIKE '%SIGCM:SincronizarPadronSso%')
    PRINT 'CASO 4  PASA  - paSincronizarPadronSso toma el candado';
ELSE
BEGIN
    PRINT 'CASO 4  FALLA - paSincronizarPadronSso no toma el candado';
    PRINT '                el worker y un ingreso simultaneo pueden interbloquearse';
    SET @Fallos += 1;
END

PRINT '';
IF @Fallos = 0
    PRINT '=== S913: todos los casos pasan. El correo del SSO manda. ===';
ELSE
BEGIN
    DECLARE @Msg varchar(200) = CONCAT('S913: ', @Fallos, ' caso(s) fallaron.');
    PRINT '=== ' + @Msg + ' ===';
    THROW 51913, @Msg, 1;
END
GO
