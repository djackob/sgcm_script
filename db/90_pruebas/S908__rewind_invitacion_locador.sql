/*
===============================================================================
  SIGCM - S908 : Devolver un expediente de locacion al hito de invitacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO TOCA SIGA_1750

  FUERA DE LA SERIE. Homologacion local: deja REQ-2026-01070503017001 en
  REQ_EN_EVAL_DEC, con Anexo 5 y Anexo 3 firmados, para que la conformidad de
  la DEC dispare la indagacion uno a uno (correo al locador del Anexo 5).

  Quita de SGCM lo posterior a la conformidad (filtros, CCP, O/S y sus PDFs).
  El historial se conserva. La cola hacia SIGA se deja: ya escribio el cuadro
  y la O/S 3534; no se borra en SIGA.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Codigo varchar(40) = 'REQ-2026-01070503017001';
DECLARE @IdExpediente uniqueidentifier;
DECLARE @IdRequerimiento uniqueidentifier;
DECLARE @IdActor uniqueidentifier;
DECLARE @ActorRol varchar(40);
DECLARE @IdUnidad uniqueidentifier;
DECLARE @Ahora datetime = GETDATE();

SELECT @IdExpediente = r.IdExpediente,
       @IdRequerimiento = r.IdRequerimiento
  FROM requerimiento.Requerimiento AS r
 WHERE r.Codigo = @Codigo AND r.Activo = 1;

IF @IdExpediente IS NULL
    THROW 59080, 'NO_ENCONTRADO: no existe REQ-2026-01070503017001.', 1;

SELECT TOP 1 @IdActor = h.IdActor, @ActorRol = h.ActorRol, @IdUnidad = h.IdActorUnidad
  FROM sigcm.Historial AS h
 WHERE h.IdExpediente = @IdExpediente
 ORDER BY h.OcurridoEn DESC, h.IdHistorial DESC;

BEGIN TRANSACTION;

UPDATE sigcm.Expediente
   SET CodigoEstado = 'REQ_EN_EVAL_DEC',
       Version = Version + 1,
       CerradoEn = NULL,
       IdResponsableActual = NULL,
       FechaModificacionAuditoria = @Ahora,
       UsuarioModificacionAuditoria = 'S908',
       ProgramaModificacionAuditoria = 'S908__rewind_invitacion_locador'
 WHERE IdExpediente = @IdExpediente;

DELETE FROM requerimiento.FiltroIdoneidad WHERE IdRequerimiento = @IdRequerimiento;
DELETE FROM requerimiento.CertificacionCcp WHERE IdRequerimiento = @IdRequerimiento;
DELETE FROM requerimiento.OrdenServicio WHERE IdRequerimiento = @IdRequerimiento;

IF OBJECT_ID(N'requerimiento.InvitacionCotizacion', N'U') IS NOT NULL
    DELETE FROM requerimiento.InvitacionCotizacion WHERE IdRequerimiento = @IdRequerimiento;

UPDATE sigcm.Plazo
   SET Estado = 'ANULADO', Activo = 0,
       FechaModificacionAuditoria = @Ahora,
       ProgramaModificacionAuditoria = 'S908__rewind_invitacion_locador'
 WHERE IdExpediente = @IdExpediente
   AND Estado = 'EN_CURSO' AND Activo = 1;

UPDATE d
   SET d.Anulado = 1, d.Activo = 0,
       d.FechaModificacionAuditoria = @Ahora,
       d.ProgramaModificacionAuditoria = 'S908__rewind_invitacion_locador'
  FROM sigcm.Documento AS d
  JOIN sigcm.DocumentoExpediente AS de ON de.IdDocumento = d.IdDocumento
 WHERE de.IdExpediente = @IdExpediente
   AND d.CodigoTipoDocumento IN (
        'REQ_CCP', 'REQ_MEMO_CCP', 'REQ_MEMO_UP_CCP', 'REQ_PREVISION_PRESUP',
        'REQ_ORDEN_SERVICIO', 'REQ_COTIZACION_ANEXO6', 'REQ_DJ_ANEXO7',
        'REQ_PAQUETE_INTEGRIDAD', 'REQ_ANEXO_8_COTIZACIONES');

INSERT INTO sigcm.Historial
    (IdExpediente, CodigoEstadoOrigen, CodigoEstadoDestino, CodigoTransicion,
     Comentario, IdActor, ActorRol, IdActorUnidad, Metadata,
     UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES
    (@IdExpediente, 'REQ_OS_EMITIDA', 'REQ_EN_EVAL_DEC', NULL,
     N'Homologacion: se devolvio el expediente al hito de invitacion al locador (conformidad DEC). SIGA conserva cuadro 3563 y O/S 3534.',
     @IdActor, ISNULL(@ActorRol, 'ABAST_ESPECIALISTA'), @IdUnidad,
     N'{"Origen":"S908","Motivo":"rewind_invitacion_locador"}',
     'S908', HOST_NAME(), 'S908__rewind_invitacion_locador');

COMMIT TRANSACTION;

SELECT e.Codigo, e.CodigoEstado, e.Version, w.Nombre AS Estado,
       d.CodigoTipoDocumento, dv.Estado AS EstadoDoc
  FROM sigcm.Expediente AS e
  JOIN sigcm.Estado AS w ON w.CodigoEstado = e.CodigoEstado
  JOIN requerimiento.Requerimiento AS r ON r.IdExpediente = e.IdExpediente
  JOIN sigcm.DocumentoExpediente AS de ON de.IdExpediente = e.IdExpediente
  JOIN sigcm.Documento AS d ON d.IdDocumento = de.IdDocumento AND d.Activo = 1 AND d.Anulado = 0
  JOIN sigcm.DocumentoVersion AS dv ON dv.IdDocumento = d.IdDocumento AND dv.Version = d.VersionVigente
 WHERE r.Codigo = @Codigo
 ORDER BY d.CodigoTipoDocumento;

PRINT 'S908: expediente en REQ_EN_EVAL_DEC, listo para declarar conforme e invitar al locador.';
GO
