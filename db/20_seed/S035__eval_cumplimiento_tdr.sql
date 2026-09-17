/*
  Seed: tipo documento Evaluacion de Cumplimiento de Requisitos del TDR
*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM sigcm.TipoDocumento
     WHERE CodigoTipoDocumento = N'REQ_EVAL_CUMPLIMIENTO_TDR')
BEGIN
    INSERT INTO sigcm.TipoDocumento
        (CodigoTipoDocumento, CodigoModulo, Nombre, NumeracionVisible, AdmiteConsolidado)
    VALUES
        (N'REQ_EVAL_CUMPLIMIENTO_TDR', N'REQUERIMIENTO',
         N'Evaluacion de Cumplimiento de Requisitos del TDR', N'EVAL TDR', 0);
END
ELSE
BEGIN
    UPDATE sigcm.TipoDocumento
       SET Nombre = N'Evaluacion de Cumplimiento de Requisitos del TDR',
           NumeracionVisible = N'EVAL TDR'
     WHERE CodigoTipoDocumento = N'REQ_EVAL_CUMPLIMIENTO_TDR';
END
GO

PRINT 'S035: tipo REQ_EVAL_CUMPLIMIENTO_TDR disponible.';
GO
