/*
===============================================================================
  SIGCM - Migracion V030 : Vista de la orden de servicio en SIGA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: 00_servidor/C003__sinonimos_siga.sql (SIG_ORDEN_ADQUISICION,
            SIG_ORDEN_INTERFASE)

  AUTORIDAD: SIGA. Solo lectura, por construccion.

  POR QUE EXISTE
  W002 crea la orden en SIGA y la deja PENDIENTE (ESTADO='0', ESTADO_SIAF='0');
  su cabecera lo dice: no certifica, no compromete y no inserta la interfase.
  Quien la aprueba y la compromete en SIAF es una persona dentro de SIGA. Hasta
  hoy el SIGCM no tenia por donde enterarse, y notificaba la orden al locador
  sin saber si en SIGA seguia pendiente.

  QUE SIGNIFICAN LOS ESTADOS (verificado en SIGA_1750, 2026, ejecutora 1750,
  tipo de bien S, sobre 3 803 ordenes):

    ESTADO       '1' emitida (3 745)   '4' anulada (58)
    ESTADO_SIAF  '2' comprometida (3 801)   '0' sin compromiso (2)
    NO existe una sola orden en ESTADO '0': ese es el estado en que la deja
    W002, y lo mueve la persona en SIGA.

  Los tres datos que el SIGCM necesita de vuelta y hoy teclea a mano:
    EXP_SIAF       expediente SIAF        poblado en 3 801 de 3 803
    NRO_CERTIFICA  certificacion          poblado en 3 803 de 3 803
    FLAG_RECEPCION 'S' con FECHA_RECEPCION cuando hay recepcion conforme (82)

  Sin NOLOCK: las ordenes se mueven. LOCK_TIMEOUT y DEADLOCK_PRIORITY viven en
  quien consulta, igual que con siga.vwPedido.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW siga.vwOrdenServicioSiga
AS
SELECT
    AnoEje          = CONVERT(smallint, o.ANO_EJE),
    SecEjec         = CONVERT(int,      o.SEC_EJEC),
    NumeroOrden     = CONVERT(varchar(20), CONVERT(bigint, o.NRO_ORDEN)) COLLATE DATABASE_DEFAULT,
    TipoBien        = CONVERT(char(1),  o.TIPO_BIEN)  COLLATE DATABASE_DEFAULT,
    SecCuadro       = CONVERT(bigint,   o.SEC_CUADRO),
    Proveedor       = CONVERT(int,      o.PROVEEDOR),
    FechaOrden      = CONVERT(date,     o.FECHA_ORDEN),

    /* '1' emitida, '4' anulada. '0' es la que dejo W002 y nadie ha aprobado. */
    Estado          = CONVERT(char(1),  o.ESTADO)      COLLATE DATABASE_DEFAULT,
    /* '2' comprometida en SIAF, '0' sin compromiso. */
    EstadoSiaf      = CONVERT(char(1),  o.ESTADO_SIAF) COLLATE DATABASE_DEFAULT,

    ExpedienteSiaf  = CONVERT(varchar(20), LTRIM(RTRIM(o.EXP_SIAF)))  COLLATE DATABASE_DEFAULT,
    NroCertifica    = CONVERT(bigint,   o.NRO_CERTIFICA),

    FlagRecepcion   = CONVERT(char(1),  o.FLAG_RECEPCION) COLLATE DATABASE_DEFAULT,
    FechaRecepcion  = CONVERT(date,     o.FECHA_RECEPCION),

    MontoTotal      = CONVERT(decimal(18,2), o.TOTAL_FACT_SOLES),

    /* La interfase vive en tabla aparte: en la cabecera intf_cer esta vacio en
       las 3 803 ordenes del 2026, y SIG_ORDEN_INTERFASE tiene 3 898 filas. */
    TieneInterfase  = CONVERT(bit, CASE WHEN EXISTS (
                          SELECT 1 FROM siga.SIG_ORDEN_INTERFASE AS i
                           WHERE i.ANO_EJE   = o.ANO_EJE
                             AND i.SEC_EJEC  = o.SEC_EJEC
                             AND i.NRO_ORDEN = o.NRO_ORDEN
                             AND i.TIPO_BIEN = o.TIPO_BIEN) THEN 1 ELSE 0 END),

    /* Lo que el SIGCM pregunta de verdad: se puede seguir con esta orden. */
    Aprobada        = CONVERT(bit, CASE WHEN o.ESTADO = '1' AND o.ESTADO_SIAF = '2'
                                        THEN 1 ELSE 0 END)
  FROM siga.SIG_ORDEN_ADQUISICION AS o;
GO

PRINT 'V030 aplicada: siga.vwOrdenServicioSiga sobre SIG_ORDEN_ADQUISICION.';
GO
