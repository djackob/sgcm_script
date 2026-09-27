/*
===============================================================================
  SIGCM - Migracion V031 : Estado de la CCP tal como lo devolvio el SIAF
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: 00_servidor/C003__sinonimos_siga.sql (SIG_CERTIFICACION)

  AUTORIDAD: SIGA, solo lectura. El SIAF web no se consulta por HTTP: la letra
  que pinta la grilla (A en el certificado 05619 de la figura) llega a SIGA
  cuando se ejecuta Respuesta SIAF, y queda en ESTADO_CERTIFICA_SIAF.

  Codigos vistos en SIGA_1750 (2026) y la letra de la grilla del SIAF web:

      NULL   sin respuesta de SIAF
      2      Rechazado     letra R
      3      Aprobado      letra A     (la de la figura; es el caso comun)
      4      Anulado       letra N

  NRO_CERTIFICA_SIAF es el CERTIFICADO N.° del SIAF web (05619).
  NRO_CERTIFICA es el "Certificado SIGA" de la misma pantalla (05023).
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW siga.vwCertificacionSiaf
AS
SELECT
    AnoEje              = CONVERT(smallint, c.ANO_EJE),
    SecEjec             = CONVERT(int,      c.SEC_EJEC),
    NumeroCertificaSiga = CONVERT(bigint,   c.NRO_CERTIFICA),
    NumeroCcp           = CONVERT(bigint,   c.NRO_CERTIFICA_SIAF),
    Fecha               = CONVERT(date,     c.FECHA),
    CodigoInterfase     = CONVERT(varchar(1), NULLIF(LTRIM(RTRIM(c.ESTADO_CERTIFICA_SIAF)), ''))
                          COLLATE DATABASE_DEFAULT,
    AnuladoSiga         = CONVERT(char(1), c.ANULADO) COLLATE DATABASE_DEFAULT,
    Estado              = CONVERT(char(1),
                          CASE NULLIF(LTRIM(RTRIM(c.ESTADO_CERTIFICA_SIAF)), '')
                               WHEN '3' THEN 'A'
                               WHEN '2' THEN 'R'
                               WHEN '4' THEN 'N'
                               WHEN '1' THEN 'E'
                               WHEN '0' THEN 'P'
                               ELSE NULL
                          END) COLLATE DATABASE_DEFAULT,
    NombreEstado        = CONVERT(varchar(40),
                          CASE NULLIF(LTRIM(RTRIM(c.ESTADO_CERTIFICA_SIAF)), '')
                               WHEN '3' THEN 'Aprobado'
                               WHEN '2' THEN 'Rechazado'
                               WHEN '4' THEN 'Anulado'
                               WHEN '1' THEN 'Enviado'
                               WHEN '0' THEN 'Por enviar'
                               ELSE 'Sin respuesta SIAF'
                          END) COLLATE DATABASE_DEFAULT
  FROM siga.SIG_CERTIFICACION AS c;
GO

PRINT 'V031 aplicada: siga.vwCertificacionSiaf sobre SIG_CERTIFICACION.';
GO
