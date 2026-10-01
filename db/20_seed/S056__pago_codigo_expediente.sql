/*
===============================================================================
  SIGCM - S056 : Codigo de expediente de pago PAGO_(OS|OC)(orden)_(entregable)
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Requiere F023 (pago.fnCodigoExpedientePago y pago.paRecodificarExpedientePago).
  Recodifica los pagos ya abiertos: los del formato anterior (000016-OS_1532_3)
  y los provisionales PAG-AAAA-NNNNNN cuya orden ya tiene numero en SIGA.
  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

DECLARE @IdReq uniqueidentifier;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT p.IdRequerimiento
      FROM pago.ExpedientePago AS p
     WHERE p.Activo = 1;
OPEN c;
FETCH NEXT FROM c INTO @IdReq;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC pago.paRecodificarExpedientePago @IdRequerimiento = @IdReq;
    FETCH NEXT FROM c INTO @IdReq;
END
CLOSE c;
DEALLOCATE c;
GO

PRINT 'S056 aplicada: expedientes de pago con codigo PAGO_(OS|OC)(orden)_(entregable).';
GO
