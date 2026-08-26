/*
===============================================================================
  SIGCM - Migracion V015 : Tipificacion de la solicitud de modificacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Requiere: V005 (cmn.Solicitud), V011 (cmn.Paquete)

  ---------------------------------------------------------------------------
  QUE PIDIO EL NEGOCIO
  ---------------------------------------------------------------------------
  Que el caracter de la solicitud -ordinaria o extraordinaria- se declare DESDE
  EL INICIO y lo declare el AREA USUARIA, no Abastecimiento al evaluarla; que
  una solicitud extraordinaria exija justificar por escrito la urgencia segun
  las directivas del MEF; y que se pueda adjuntar el sustento -informe, nota
  tecnica, expediente- para que Abastecimiento valide esa urgencia.

  ---------------------------------------------------------------------------
  POR QUE SE RENOMBRA URGENTE -> EXTRAORDINARIA
  ---------------------------------------------------------------------------
  Es el mismo eje con dos nombres. La columna nacio en V005 para la regla del
  viernes del Anexo 4 ("lo ordinario se agrupa los viernes, lo urgente cualquier
  dia") y el negocio la nombra como la Directiva: ordinaria / extraordinaria.
  Mantener los dos vocabularios obligaria a traducir entre la pantalla y la
  tabla, que es exactamente lo que ESTANDARES.md prohibe. Se renombra el valor,
  no la columna: TipoInclusion sigue siendo la marca de la que depende la regla
  del calendario, y esa regla no cambia.

  Alcance del renombrado: cmn.Solicitud y cmn.Paquete, que son las dos tablas
  con el dominio. El resto (F004, F007, el PDF del Anexo 4) sigue el valor.

  ---------------------------------------------------------------------------
  POR QUE TipoInclusion SIGUE ADMITIENDO NULO
  ---------------------------------------------------------------------------
  Desde ahora cmn.paRegistrarSolicitud lo exige, de modo que ninguna solicitud
  nueva nace sin tipo. Pero las ya registradas bajo el flujo anterior -donde la
  marca la ponia Abastecimiento al conformar el Anexo 3- estan en el area
  usuaria todavia sin valor, y volver la columna NOT NULL exigiria inventarles
  uno. Un dato inventado en una columna que decide un plazo es peor que un nulo
  que la rutina rechaza al primer intento de avanzar.

  Por la misma razon la restriccion de la justificacion entra WITH NOCHECK:
  vale para lo que se registre de aqui en adelante y no reescribe la historia.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. La justificacion de la urgencia                                         */
/* -------------------------------------------------------------------------- */

/* Texto libre y no un catalogo: la Directiva pide el "por que" sustentado, y
   una lista de motivos preseleccionados convertiria el sustento en un clic. */
IF COL_LENGTH(N'cmn.Solicitud', N'JustificacionUrgencia') IS NULL
    ALTER TABLE cmn.Solicitud ADD JustificacionUrgencia nvarchar(max) NULL;
GO

/* -------------------------------------------------------------------------- */
/* 2. URGENTE pasa a llamarse EXTRAORDINARIA                                  */
/* -------------------------------------------------------------------------- */

/* El orden importa: primero se retira la restriccion, luego se migran los
   valores y recien entonces se declara el dominio nuevo. Al reves, el UPDATE
   chocaria contra el CHECK vigente. */

IF EXISTS (SELECT 1 FROM sys.check_constraints
            WHERE name = N'CK_cmn_Solicitud_Inclusion'
              AND parent_object_id = OBJECT_ID(N'cmn.Solicitud'))
    ALTER TABLE cmn.Solicitud DROP CONSTRAINT CK_cmn_Solicitud_Inclusion;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints
            WHERE name = N'CK_cmn_Paquete_Inclusion'
              AND parent_object_id = OBJECT_ID(N'cmn.Paquete'))
    ALTER TABLE cmn.Paquete DROP CONSTRAINT CK_cmn_Paquete_Inclusion;
GO

UPDATE cmn.Solicitud SET TipoInclusion = 'EXTRAORDINARIA' WHERE TipoInclusion = 'URGENTE';
UPDATE cmn.Paquete   SET TipoInclusion = 'EXTRAORDINARIA' WHERE TipoInclusion = 'URGENTE';
GO

ALTER TABLE cmn.Solicitud WITH CHECK ADD CONSTRAINT CK_cmn_Solicitud_Inclusion
    CHECK (TipoInclusion IS NULL OR TipoInclusion IN ('ORDINARIA','EXTRAORDINARIA'));
GO

ALTER TABLE cmn.Paquete WITH CHECK ADD CONSTRAINT CK_cmn_Paquete_Inclusion
    CHECK (TipoInclusion IN ('ORDINARIA','EXTRAORDINARIA'));
GO

/* -------------------------------------------------------------------------- */
/* 3. Una extraordinaria no existe sin su justificacion                       */
/* -------------------------------------------------------------------------- */

/* La rutina ya lo valida y devuelve un mensaje que el usuario entiende; esto es
   la red del motor, para que ningun camino futuro pueda dejar una solicitud
   extraordinaria sin el "por que" que Abastecimiento tiene que leer.

   WITH NOCHECK por lo explicado en la cabecera: las solicitudes que Abasteci-
   miento marco urgentes bajo el flujo anterior nunca tuvieron donde escribirlo. */
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
                WHERE name = N'CK_cmn_Solicitud_Justificacion'
                  AND parent_object_id = OBJECT_ID(N'cmn.Solicitud'))
    ALTER TABLE cmn.Solicitud WITH NOCHECK ADD CONSTRAINT CK_cmn_Solicitud_Justificacion
        CHECK (TipoInclusion <> 'EXTRAORDINARIA'
               OR LEN(LTRIM(RTRIM(ISNULL(JustificacionUrgencia, N'')))) > 0);
GO

PRINT 'V015 aplicada: tipificacion ordinaria / extraordinaria con justificacion.';
GO
