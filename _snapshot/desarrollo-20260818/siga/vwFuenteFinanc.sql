/*
  Base    : DBSIGCM
  Esquema : siga
  Objeto  : siga.vwFuenteFinanc
  Tipo    : VIEW
  Extraido: 2026-08-18 11:59:34
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 3. Fuente de financiamiento                                               */
/*    <- dbo.FUENTE_FINANC_EJEC (monto y estado) x dbo.FUENTE_FINANC (nombre) */
/* ========================================================================== */

/* El espejo declaraba descripcion varchar(250) sobre FUENTE_FINANC_EJEC, que no
   tiene ninguna columna de nombre. La descripcion esta en FUENTE_FINANC, que la
   lleva por (ANO_EJE, ORIGEN, FUENTE_FINANC), sin SEC_EJEC. */
CREATE   VIEW siga.vwFuenteFinanc
AS
SELECT
    AnoEje        = CONVERT(smallint, fe.ANO_EJE),
    SecEjec       = CONVERT(int,      fe.SEC_EJEC),
    Origen        = CONVERT(varchar(1), fe.ORIGEN)        COLLATE DATABASE_DEFAULT,
    FuenteFinanc  = CONVERT(varchar(2), fe.FUENTE_FINANC) COLLATE DATABASE_DEFAULT,
    Descripcion   = CONVERT(varchar(250), f.nombre)       COLLATE DATABASE_DEFAULT,
    MontoAsignado = CONVERT(decimal(18,2), fe.monto_asignado),
    Estado        = CONVERT(varchar(1), fe.estado)        COLLATE DATABASE_DEFAULT,
    Activo        = CONVERT(bit, CASE WHEN fe.estado = 'A' THEN 1 ELSE 0 END)
FROM siga.FUENTE_FINANC_EJEC AS fe WITH (NOLOCK)
LEFT JOIN siga.FUENTE_FINANC AS f WITH (NOLOCK)
       ON  f.ANO_EJE       = fe.ANO_EJE
       AND f.ORIGEN        = fe.ORIGEN
       AND f.FUENTE_FINANC = fe.FUENTE_FINANC;
GO
