/*
===============================================================================
  SIGCM - V010 : Correlativos de codigo de expediente
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  ---------------------------------------------------------------------------
  POR QUE UNA TABLA Y NO UNA SEQUENCE
  ---------------------------------------------------------------------------
  Hasta V009 el codigo visible del expediente (CMN-2026-000123) salia de una
  SEQUENCE. Funciona, pero una secuencia entrega el numero FUERA de la
  transaccion: si la transaccion que lo pidio se deshace, ese numero no vuelve.
  El resultado son huecos en la numeracion.

  Para un consecutivo interno eso da igual. Para el codigo de un expediente de
  contratacion no: es el numero con el que el expediente se cita en oficios y
  con el que un auditor lo pide. Un salto obliga a explicar que paso con el
  CMN-2026-000007 que no existe, y la respuesta "se cayo una transaccion" no es
  satisfactoria.

  La tabla entrega el numero DENTRO de la transaccion. Si esta se deshace, el
  contador tambien: no hay huecos. Se paga con serializacion —dos registros
  simultaneos del mismo modulo se turnan— pero el bloqueo dura lo que dura un
  UPDATE de una fila, y estos volumenes no son de miles por segundo.

  Es tambien la forma en que el entorno de desarrollo ya venia trabajando.

  ---------------------------------------------------------------------------
  MIGRACION SIN COLISIONES
  ---------------------------------------------------------------------------
  Este script NO arranca los contadores en cero: los siembra a partir del codigo
  mas alto que ya exista en sigcm.Expediente. Si no lo hiciera, en un entorno
  con expedientes registrados el primer codigo nuevo seria el 000001 y chocaria
  contra UQ_sigcm_Expediente_Codigo.

  Por eso este script es el que habilita instalar la serie en desarrollo, donde
  ya hay expedientes.

  Idempotente: se puede reejecutar. La siembra nunca baja un contador.
===============================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. La tabla                                                                */
/* -------------------------------------------------------------------------- */

IF OBJECT_ID(N'sigcm.Correlativo', N'U') IS NULL
BEGIN
    CREATE TABLE sigcm.Correlativo (
        Nombre nvarchar(128) NOT NULL,
        Valor  bigint        NOT NULL,
        CONSTRAINT PK_sigcm_Correlativo PRIMARY KEY (Nombre ASC),
        CONSTRAINT CK_sigcm_Correlativo_Valor CHECK (Valor >= 0)
    );

    PRINT '  sigcm.Correlativo creada.';
END
ELSE
    PRINT '  sigcm.Correlativo ya existe.';
GO

/* -------------------------------------------------------------------------- */
/* 2. Siembra desde los codigos ya emitidos                                   */
/* -------------------------------------------------------------------------- */

/*
  El codigo tiene la forma PREFIJO-ANIO-NNNNNN. El contador es global por
  modulo, no por anio: se toma el mayor NNNNNN emitido, sin importar el
  ejercicio, que es como se comportaba la SEQUENCE que se reemplaza.

  El nombre del contador es el mismo texto que ya reciben las rutinas que
  llaman a paSiguienteCodigo, para no tocar sus llamadas.
*/

DECLARE @contadores TABLE (
    Nombre  nvarchar(128) NOT NULL PRIMARY KEY,
    Prefijo varchar(10)   NOT NULL
);

INSERT INTO @contadores (Nombre, Prefijo) VALUES
    (N'cmn.SeqSolicitud',              'CMN'),
    (N'requerimiento.SeqRequerimiento', 'REQ');

MERGE sigcm.Correlativo AS destino
USING (
    SELECT c.Nombre,
           Valor = ISNULL(
               (SELECT MAX(TRY_CONVERT(bigint, RIGHT(e.Codigo, 6)))
                  FROM sigcm.Expediente AS e
                 WHERE e.Codigo LIKE c.Prefijo + '-%'
                   AND LEN(e.Codigo) >= 7
                   AND TRY_CONVERT(bigint, RIGHT(e.Codigo, 6)) IS NOT NULL), 0)
      FROM @contadores AS c
) AS origen
ON destino.Nombre = origen.Nombre
WHEN MATCHED AND destino.Valor < origen.Valor
    /* Nunca se baja un contador: si ya iba mas alto, se respeta. */
    THEN UPDATE SET Valor = origen.Valor
WHEN NOT MATCHED BY TARGET
    THEN INSERT (Nombre, Valor) VALUES (origen.Nombre, origen.Valor);

SELECT Nombre AS contador,
       Valor  AS ultimo_emitido,
       Valor + 1 AS proximo
  FROM sigcm.Correlativo
 ORDER BY Nombre;
GO

/* -------------------------------------------------------------------------- */
/* 3. Retiro de las secuencias                                                */
/* -------------------------------------------------------------------------- */

/*
  Se eliminan para que no queden dos fuentes de numeracion. Mientras existan,
  una reinstalacion parcial podria dejar a paSiguienteCodigo tomando de la
  secuencia vieja y emitiendo codigos ya usados.
*/

IF OBJECT_ID(N'cmn.SeqSolicitud', N'SO') IS NOT NULL
BEGIN
    DROP SEQUENCE cmn.SeqSolicitud;
    PRINT '  cmn.SeqSolicitud retirada; la reemplaza sigcm.Correlativo.';
END

IF OBJECT_ID(N'requerimiento.SeqRequerimiento', N'SO') IS NOT NULL
BEGIN
    DROP SEQUENCE requerimiento.SeqRequerimiento;
    PRINT '  requerimiento.SeqRequerimiento retirada; la reemplaza sigcm.Correlativo.';
END
GO
