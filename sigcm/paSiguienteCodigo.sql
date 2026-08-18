/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paSiguienteCodigo
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE sigcm.paSiguienteCodigo
    @Prefijo   varchar(10),
    @AnoEje    smallint,
    @Secuencia nvarchar(128),          /* p.ej. N'cmn.SeqSolicitud' */
    @Codigo    varchar(40) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Valor bigint;

    IF NULLIF(LTRIM(RTRIM(@Secuencia)), '') IS NULL
    BEGIN
        RAISERROR('No se indico el nombre del correlativo.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM sigcm.Correlativo WITH (UPDLOCK, HOLDLOCK)
         WHERE Nombre = @Secuencia)
        INSERT INTO sigcm.Correlativo (Nombre, Valor) VALUES (@Secuencia, 0);

    UPDATE sigcm.Correlativo
       SET @Valor = Valor = Valor + 1
     WHERE Nombre = @Secuencia;

    COMMIT TRANSACTION;

    SET @Codigo = @Prefijo + '-' + CONVERT(varchar(4), @AnoEje) + '-'
                + RIGHT('000000' + CONVERT(varchar(20), @Valor), 6);
END
GO
