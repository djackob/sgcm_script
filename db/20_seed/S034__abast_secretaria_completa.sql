/*
===============================================================================
  SIGCM - Semilla S034 : Completa ABAST_SECRETARIA
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  S021 creo el rol ABAST_SECRETARIA y le dio cuatro derivaciones de CMN, pero el
  perfil quedo inutilizable: sin fila en sigcm.PerfilSso el padron descarta a la
  persona con "el cod_perfil no esta mapeado", y sin sigcm.RolModulo no veria un
  solo modulo aunque lograra entrar. Esta semilla cierra los dos huecos y le da
  el mismo trato que S033 le dio a la secretaria del area usuaria. Idempotente.

  ---------------------------------------------------------------------------
  QUE HACE, Y POR QUE ASI
  ---------------------------------------------------------------------------
  1. MODULOS Y ACCIONES DEL JEFE, MENOS LA FIRMA. Igual que S033: se copian de
     ABAST_JEFE en vez de escribirse a mano, para que no haya dos listas que
     mantener. Las cuatro transiciones de S021 se conservan -son derivaciones
     del coordinador que el jefe no tiene- y se suman a las heredadas.

     La firma queda fuera (CMN_ABAST_JEFE_FIRMAR_A3 y _A4): es un acto personal
     del titular y darsela significaria que la secretaria firma el Anexo 3 o el
     Anexo 4 con su propio certificado, en nombre del jefe.

  2. NO APARECE EN LAS DERIVACIONES DEL JEFE. Existe como ORIGEN -deriva al
     coordinador y al especialista de Abastecimiento- y nunca como DESTINO, que
     es de donde sale el combo "Derivar a".

  3. TRADUCCION DESDE EL SSO. El codigo PE102 SECRETARIA ABASTECIMIENTO lo crea
     sso/S04__perfil_secretaria_abastecimiento.sql, que corre en la base del SSO.
     Sin ese script la persona no puede entrar por mas que el mapeo este aqui.

  ---------------------------------------------------------------------------
  LO QUE HAY QUE MIRAR ANTES DE DARLE ESTE PERFIL A ALGUIEN
  ---------------------------------------------------------------------------
  Heredar del jefe le trae dos acciones que no son "recibir y derivar":
  REQ_REGISTRAR_CCP (cargar la certificacion presupuestaria) y
  REQ_CONFIRMAR_FILTROS (cerrar los filtros de idoneidad). Ninguna exige firma,
  asi que pasan el filtro, pero son actos de fondo del tramite. Si el negocio
  las quiere fuera, se agregan al DELETE del final; queda anotado aqui para que
  la decision se tome mirandolas, no por descuido.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. Los modulos a los que entra: los mismos del jefe                        */
/* -------------------------------------------------------------------------- */

INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT 'ABAST_SECRETARIA', rm.CodigoModulo
  FROM sigcm.RolModulo AS rm
 WHERE rm.CodigoRol = 'ABAST_JEFE'
   AND NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS d
                    WHERE d.CodigoRol = 'ABAST_SECRETARIA'
                      AND d.CodigoModulo = rm.CodigoModulo);
GO

/* -------------------------------------------------------------------------- */
/* 2. Las acciones del jefe, menos las que exigen firma                       */
/* -------------------------------------------------------------------------- */

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT tr.CodigoTransicion, 'ABAST_SECRETARIA'
  FROM sigcm.TransicionRol AS tr
  JOIN sigcm.Transicion AS t
    ON t.CodigoTransicion = tr.CodigoTransicion
   AND t.Activo = 1
   AND t.RequiereFirma = 0
 WHERE tr.CodigoRol = 'ABAST_JEFE'
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = tr.CodigoTransicion
                      AND d.CodigoRol = 'ABAST_SECRETARIA');
GO

/* Si una accion del jefe pasa a exigir firma despues de sembrar esto, la
   secretaria se queda con un permiso que ya no le toca. Se retira. */
DELETE tr
  FROM sigcm.TransicionRol AS tr
  JOIN sigcm.Transicion AS t ON t.CodigoTransicion = tr.CodigoTransicion
 WHERE tr.CodigoRol = 'ABAST_SECRETARIA'
   AND t.RequiereFirma = 1;

/* No firma ningun documento. */
DELETE FROM sigcm.TipoDocumentoFirma WHERE CodigoRol = 'ABAST_SECRETARIA';
GO

/* -------------------------------------------------------------------------- */
/* 3. Derivaciones: origen si, destino no                                     */
/* -------------------------------------------------------------------------- */

INSERT INTO sigcm.RolDerivacion
      (CodigoModulo, CodigoRolOrigen, CodigoRolDestino, Alcance, Orden, Descripcion, Activo)
SELECT rd.CodigoModulo, 'ABAST_SECRETARIA', rd.CodigoRolDestino, rd.Alcance, rd.Orden,
       N'Secretaria de Abastecimiento: deriva igual que el jefe, dentro de su unidad.', 1
  FROM sigcm.RolDerivacion AS rd
 WHERE rd.CodigoRolOrigen = 'ABAST_JEFE'
   AND rd.Activo = 1
   AND NOT EXISTS (SELECT 1 FROM sigcm.RolDerivacion AS d
                    WHERE d.CodigoModulo = rd.CodigoModulo
                      AND d.CodigoRolOrigen = 'ABAST_SECRETARIA'
                      AND d.CodigoRolDestino = rd.CodigoRolDestino);
GO

DELETE FROM sigcm.RolDerivacion WHERE CodigoRolDestino = 'ABAST_SECRETARIA';
GO

/* -------------------------------------------------------------------------- */
/* 4. Traduccion desde el SSO                                                 */
/* -------------------------------------------------------------------------- */

MERGE sigcm.PerfilSso AS d
USING (VALUES
  ('PE102', 'SECRETARIA ABASTECIMIENTO', 'ABAST_SECRETARIA',
   N'Secretaria de la Unidad de Abastecimiento: recibe y deriva, no firma.')
) AS s(CodigoPerfilSso, NombreSso, CodigoRol, Observacion)
ON d.CodigoPerfilSso = s.CodigoPerfilSso
WHEN MATCHED THEN
  UPDATE SET NombreSso = s.NombreSso, CodigoRol = s.CodigoRol,
             Observacion = s.Observacion, Activo = 1
WHEN NOT MATCHED THEN
  INSERT (CodigoPerfilSso, NombreSso, CodigoRol, Observacion, Activo)
  VALUES (s.CodigoPerfilSso, s.NombreSso, s.CodigoRol, s.Observacion, 1);
GO

PRINT 'S034 aplicada: ABAST_SECRETARIA con modulos, acciones del jefe sin firma y traduccion PE102.';
GO
