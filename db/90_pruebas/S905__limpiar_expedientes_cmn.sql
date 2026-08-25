/*
===============================================================================
  SIGCM - S905 : Retirar los expedientes CMN de prueba
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750

  FUERA DE LA SERIE. No es una migracion y el instalador no lo ejecuta: se corre
  a mano, en la maquina de desarrollo, cuando se quiere partir de cero.

  ---------------------------------------------------------------------------
  QUE BORRA Y QUE NO
  ---------------------------------------------------------------------------
  Borra TODO rastro de los expedientes del modulo CMN dentro de DBSIGCM:
  solicitudes, items, periodos, paquetes de Anexo 4, documentos y sus versiones,
  firmas, observaciones, plazos, historial, cola hacia SIGA y mapeos. Reinicia
  ademas el correlativo, de modo que el proximo Anexo 3 vuelva a ser el 000001.

  NO borra nada de SIGA_1750, y no puede hacerlo: sobre SIGA solo escribe el
  flujo, a traves de los usp_ext_* homologados. Las lineas que la integracion ya
  registro en el cuadro modificado SE QUEDAN donde estan. Es lo correcto: una
  fila mala se deja y el caso se rehace: ver CONTEXTO.md, seccion 5.

  Consecuencia a tener presente: al borrar integracion.Operacion y
  integracion.MapeoCmn se pierde el rastro de QUE se escribio en SIGA y con que
  clave de idempotencia. Lo escrito sigue ahi, pero este sistema ya no sabra que
  fue suyo. Por eso el script exige confirmacion explicita y por eso no se corre
  contra nada que no sea la maquina del programador.

  ---------------------------------------------------------------------------
  USO
  ---------------------------------------------------------------------------
    sqlcmd -S "localhost\SQLSERVER25" -d DBSIGCM -E -b -I ^
           -v confirmar="SI" -i db/90_pruebas/S905__limpiar_expedientes_cmn.sql

  Sin esa variable sqlcmd aborta con "scripting variable not defined" y no
  ejecuta nada, igual que C001R. Abrirlo en SSMS sin el modo SQLCMD tambien
  falla, que es lo que se quiere de un script destructivo.

  Los usuarios, unidades y perfiles de /acceso-local (S900) NO se tocan: son la
  semilla con la que se vuelve a recorrer el flujo.
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @confirmar varchar(10) = '$(confirmar)';

DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY);
INSERT INTO @Exp (IdExpediente)
SELECT IdExpediente FROM sigcm.Expediente WHERE CodigoModulo = 'CMN';

DECLARE @cuantos int = (SELECT COUNT(*) FROM @Exp);

PRINT '===========================================================';
PRINT ' S905 - Limpieza de expedientes CMN';
PRINT '===========================================================';
PRINT '  Expedientes CMN en la base: ' + CONVERT(varchar(10), @cuantos);

IF UPPER(@confirmar) <> 'SI'
BEGIN
    PRINT '';
    PRINT '  No se borro nada. Para hacerlo, reejecuta con -v confirmar="SI".';
    SET NOEXEC ON;
END
GO

SET NOCOUNT ON;

DECLARE @Exp TABLE (IdExpediente uniqueidentifier PRIMARY KEY);
INSERT INTO @Exp (IdExpediente)
SELECT IdExpediente FROM sigcm.Expediente WHERE CodigoModulo = 'CMN';

DECLARE @Doc TABLE (IdDocumento uniqueidentifier PRIMARY KEY);
INSERT INTO @Doc (IdDocumento)
SELECT DISTINCT de.IdDocumento
  FROM sigcm.DocumentoExpediente AS de
  JOIN @Exp AS e ON e.IdExpediente = de.IdExpediente;

DECLARE @Sol TABLE (IdSolicitud uniqueidentifier PRIMARY KEY);
INSERT INTO @Sol (IdSolicitud)
SELECT s.IdSolicitud FROM cmn.Solicitud AS s JOIN @Exp AS e ON e.IdExpediente = s.IdExpediente;

BEGIN TRANSACTION;

/* El orden es el de las dependencias: primero lo que cuelga, al final el
   expediente. Varias claves foraneas ya cascadean, pero se borra explicitamente
   para que este script siga funcionando si alguna deja de hacerlo. */

DELETE o FROM integracion.Operacion  AS o JOIN @Exp AS e ON e.IdExpediente = o.IdExpediente;
DELETE m FROM integracion.MapeoCmn   AS m JOIN @Sol AS s ON s.IdSolicitud  = m.IdSolicitud;
/* La conciliacion no lleva modulo: es un contraste por centro de costo y solo
   la produce el CMN, asi que se vacia entera. */
DELETE FROM integracion.Conciliacion;

DELETE ps FROM cmn.PaqueteSolicitud AS ps JOIN @Sol AS s ON s.IdSolicitud = ps.IdSolicitud;
DELETE FROM cmn.Paquete
 WHERE NOT EXISTS (SELECT 1 FROM cmn.PaqueteSolicitud AS ps WHERE ps.IdPaquete = cmn.Paquete.IdPaquete);

DELETE p FROM cmn.SolicitudItemPeriodo AS p
  JOIN cmn.SolicitudItem AS i ON i.IdSolicitudItem = p.IdSolicitudItem
  JOIN @Sol AS s ON s.IdSolicitud = i.IdSolicitud;
DELETE i FROM cmn.SolicitudItem AS i JOIN @Sol AS s ON s.IdSolicitud = i.IdSolicitud;
DELETE c FROM cmn.Solicitud     AS c JOIN @Sol AS s ON s.IdSolicitud = c.IdSolicitud;

DELETE f  FROM sigcm.Firma AS f
  JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumentoVersion = f.IdDocumentoVersion
  JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
DELETE dv FROM sigcm.DocumentoVersion   AS dv JOIN @Doc AS d ON d.IdDocumento = dv.IdDocumento;
DELETE de FROM sigcm.DocumentoExpediente AS de JOIN @Doc AS d ON d.IdDocumento = de.IdDocumento;
DELETE dc FROM sigcm.Documento          AS dc JOIN @Doc AS d ON d.IdDocumento = dc.IdDocumento;

DELETE ob FROM sigcm.Observacion AS ob JOIN @Exp AS e ON e.IdExpediente = ob.IdExpediente;
DELETE pl FROM sigcm.Plazo       AS pl JOIN @Exp AS e ON e.IdExpediente = pl.IdExpediente;
DELETE h  FROM sigcm.Historial   AS h  JOIN @Exp AS e ON e.IdExpediente = h.IdExpediente;

DELETE ex FROM sigcm.Expediente AS ex JOIN @Exp AS e ON e.IdExpediente = ex.IdExpediente;

/* La auditoria del modulo se va con sus expedientes: conservarla dejaria un
   registro de acciones sobre codigos que ya no existen. */
DELETE FROM sigcm.EventoAuditoria WHERE CodigoModulo = 'CMN';

/* Que el proximo Anexo 3 vuelva a ser el 000001 y el proximo Anexo 4 el 000001. */
DELETE FROM sigcm.Correlativo WHERE Nombre IN (N'cmn.SeqSolicitud', N'cmn.SeqPaquete');

COMMIT TRANSACTION;

DECLARE @quedanExp int = (SELECT COUNT(*) FROM sigcm.Expediente WHERE CodigoModulo = 'CMN');
DECLARE @quedanSol int = (SELECT COUNT(*) FROM cmn.Solicitud);

PRINT '';
PRINT '  Listo. Expedientes CMN restantes: ' + CONVERT(varchar(10), @quedanExp);
PRINT '  Solicitudes restantes:            ' + CONVERT(varchar(10), @quedanSol);
PRINT '';
PRINT '  Lo que la integracion ya escribio en SIGA_1750 SIGUE AHI, a proposito.';
PRINT '  Los usuarios y unidades de /acceso-local no se tocaron.';
GO

SET NOEXEC OFF;
GO
