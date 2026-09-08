/*
===============================================================================
  SIGCM - Semilla S033 : Secretaria de area usuaria
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Perfil que trabaja al lado del jefe del area usuaria: ve su misma bandeja,
  recibe lo que llega a la unidad y deriva al coordinador o al especialista.
  Idempotente.

  ---------------------------------------------------------------------------
  LAS DOS REGLAS QUE LO DEFINEN
  ---------------------------------------------------------------------------
  1. VE Y HACE LO MISMO QUE EL JEFE. Los permisos se copian de AREA_JEFE en vez
     de escribirse a mano: asi, cuando manana el jefe gane o pierda una accion,
     basta reejecutar esta semilla y la secretaria queda al dia. Escribir la
     lista literal obligaria a acordarse de los dos sitios.

     La bandeja no necesita nada aparte: filtra por UNIDAD, no por rol, asi que
     con el mismo acceso a modulos la secretaria ve lo mismo que su jefe.

  2. NO APARECE EN LAS DERIVACIONES DEL JEFE. En sigcm.RolDerivacion la
     secretaria existe como ORIGEN -deriva al coordinador y al especialista-
     pero nunca como DESTINO. El combo «Derivar a» se arma con ese cuadro, asi
     que el jefe no la vera en su lista. Se borra ademas cualquier arista que
     la tenga como destino, por si quedo de una corrida anterior.

  ---------------------------------------------------------------------------
  LO QUE NO HEREDA: LA FIRMA
  ---------------------------------------------------------------------------
  De las acciones del jefe se excluyen las que exigen firma digital
  (CMN_FIRMAR_A3, REQ_FIRMAR_AU, PAG_FIRMAR_ANEXO11 y las demas con
  RequiereFirma = 1). No es una limitacion tecnica: la firma es un acto personal
  del titular, y darsela a la secretaria significaria que ella firma el Anexo 3
  o el Acta de Conformidad con su propio certificado, en nombre del jefe.

  Es el mismo criterio con el que S021 creo ABAST_SECRETARIA -"recibe y deriva;
  no firma documentos"-. Si el negocio decide otra cosa, se quita el filtro
  RequiereFirma = 0 del INSERT de abajo y se vuelve a correr.

  ---------------------------------------------------------------------------
  EL PERFIL EN EL SSO
  ---------------------------------------------------------------------------
  Esta semilla traduce a rol; no crea el perfil. Los codigos PE100 SECRETARIA
  OFICINA y PE101 SECRETARIA UNIDAD los crea sso/S03__perfil_secretaria_area_
  usuaria.sql, que corre en la base del SSO. Sin ese script la persona no puede
  entrar con este perfil por mas que el mapeo este sembrado.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. El rol                                                                  */
/* -------------------------------------------------------------------------- */

MERGE sigcm.Rol AS d
USING (VALUES
  ('AREA_SECRETARIA', 'Area usuaria - Secretaria',
   'Ve la bandeja del jefe del area usuaria y deriva al coordinador o al especialista; no firma documentos',
   CAST(0 AS bit))
) AS s(CodigoRol, Nombre, Descripcion, EsTecnico)
ON d.CodigoRol = s.CodigoRol
WHEN MATCHED THEN
  UPDATE SET Nombre = s.Nombre, Descripcion = s.Descripcion, EsTecnico = s.EsTecnico, Activo = 1
WHEN NOT MATCHED THEN
  INSERT (CodigoRol, Nombre, Descripcion, EsTecnico, Activo)
  VALUES (s.CodigoRol, s.Nombre, s.Descripcion, s.EsTecnico, 1);
GO

/* -------------------------------------------------------------------------- */
/* 2. Los modulos a los que entra: los mismos del jefe                        */
/* -------------------------------------------------------------------------- */

INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT 'AREA_SECRETARIA', rm.CodigoModulo
  FROM sigcm.RolModulo AS rm
 WHERE rm.CodigoRol = 'AREA_JEFE'
   AND NOT EXISTS (SELECT 1 FROM sigcm.RolModulo AS d
                    WHERE d.CodigoRol = 'AREA_SECRETARIA'
                      AND d.CodigoModulo = rm.CodigoModulo);
GO

/* -------------------------------------------------------------------------- */
/* 3. Las acciones del jefe, menos las que exigen firma                       */
/* -------------------------------------------------------------------------- */

INSERT INTO sigcm.TransicionRol (CodigoTransicion, CodigoRol)
SELECT tr.CodigoTransicion, 'AREA_SECRETARIA'
  FROM sigcm.TransicionRol AS tr
  JOIN sigcm.Transicion AS t
    ON t.CodigoTransicion = tr.CodigoTransicion
   AND t.Activo = 1
   AND t.RequiereFirma = 0
 WHERE tr.CodigoRol = 'AREA_JEFE'
   AND NOT EXISTS (SELECT 1 FROM sigcm.TransicionRol AS d
                    WHERE d.CodigoTransicion = tr.CodigoTransicion
                      AND d.CodigoRol = 'AREA_SECRETARIA');
GO

/* Si una accion del jefe pasa a exigir firma despues de sembrar esto, la
   secretaria se queda con un permiso que ya no le toca. Se retira. */
DELETE tr
  FROM sigcm.TransicionRol AS tr
  JOIN sigcm.Transicion AS t ON t.CodigoTransicion = tr.CodigoTransicion
 WHERE tr.CodigoRol = 'AREA_SECRETARIA'
   AND t.RequiereFirma = 1;

/* No firma ningun documento. */
DELETE FROM sigcm.TipoDocumentoFirma WHERE CodigoRol = 'AREA_SECRETARIA';
GO

/* -------------------------------------------------------------------------- */
/* 4. Derivaciones: origen si, destino no                                     */
/* -------------------------------------------------------------------------- */

/* Deriva a donde deriva el jefe -coordinador y especialista, en su unidad-, y
   en los mismos modulos. */
INSERT INTO sigcm.RolDerivacion
      (CodigoModulo, CodigoRolOrigen, CodigoRolDestino, Alcance, Orden, Descripcion, Activo)
SELECT rd.CodigoModulo, 'AREA_SECRETARIA', rd.CodigoRolDestino, rd.Alcance, rd.Orden,
       N'Secretaria del area usuaria: deriva igual que el jefe, dentro de su unidad.', 1
  FROM sigcm.RolDerivacion AS rd
 WHERE rd.CodigoRolOrigen = 'AREA_JEFE'
   AND rd.Activo = 1
   AND NOT EXISTS (SELECT 1 FROM sigcm.RolDerivacion AS d
                    WHERE d.CodigoModulo = rd.CodigoModulo
                      AND d.CodigoRolOrigen = 'AREA_SECRETARIA'
                      AND d.CodigoRolDestino = rd.CodigoRolDestino);
GO

/* Y no es destino de nadie: el combo «Derivar a» del jefe no debe ofrecerla. */
DELETE FROM sigcm.RolDerivacion WHERE CodigoRolDestino = 'AREA_SECRETARIA';
GO

/* -------------------------------------------------------------------------- */
/* 5. Traduccion desde el SSO                                                 */
/* -------------------------------------------------------------------------- */

/* Los dos codigos que crea sso/S03. Igual que el jefe, que entra con PE079
   (oficina) o PE091 (unidad), la secretaria entra con PE100 o PE101. */
MERGE sigcm.PerfilSso AS d
USING (VALUES
  ('PE100', 'SECRETARIA OFICINA', 'AREA_SECRETARIA',
   N'Secretaria de una oficina que actua como area usuaria.'),
  ('PE101', 'SECRETARIA UNIDAD',  'AREA_SECRETARIA',
   N'Secretaria de una unidad que actua como area usuaria.')
) AS s(CodigoPerfilSso, NombreSso, CodigoRol, Observacion)
ON d.CodigoPerfilSso = s.CodigoPerfilSso
WHEN MATCHED THEN
  UPDATE SET NombreSso = s.NombreSso, CodigoRol = s.CodigoRol,
             Observacion = s.Observacion, Activo = 1
WHEN NOT MATCHED THEN
  INSERT (CodigoPerfilSso, NombreSso, CodigoRol, Observacion, Activo)
  VALUES (s.CodigoPerfilSso, s.NombreSso, s.CodigoRol, s.Observacion, 1);
GO

PRINT 'S033 aplicada: AREA_SECRETARIA con los permisos del jefe sin firma, sin ser destino de derivacion.';
GO
