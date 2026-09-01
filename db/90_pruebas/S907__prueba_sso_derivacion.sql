/*
===============================================================================
  SIGCM - Prueba S907 : Sincronizacion del padron SSO y arbol de derivacion
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  QUE PRUEBA  (15 comprobaciones)
  ----------
   El padron se aplana por PUESTO: un acceso con dos centros de costo produce
   dos ternas, no una.  Las unidades nacen del SSO, con su arbol y con
   EsAreaUsuaria curado por sigcm.UnidadTramitadora.  Un cod_perfil sin mapear
   no entra y queda reportado en Descartes.

   El arbol: en CMN el area usuaria NO ofrece coordinador y en Requerimiento SI;
   un puesto con dos ocupantes los lista a los dos; el jefe puede saltar directo
   al especialista.

   LA BAJA -el caso que motivo todo el disenio-: quien desaparece del padron
   pierde su asignacion vigente y deja de aparecer como destinatario.  EL
   RE-ALTA abre una asignacion NUEVA y conserva la cerrada.  Baja y re-alta el
   mismo dia no duplican la terna.  Las cuentas que no vienen del SSO (S900,
   tecnicas) NO se dan de baja.  Un padron vacio se rechaza sin tocar nada.

   Y la derivacion a persona de punta a punta: paEjecutarTransicion acepta al
   destinatario que el arbol habilita y rechaza al que no, sin mover el
   expediente.

  NO TOCA SIGA y SE LIMPIA SOLA: todo corre dentro de una transaccion que
  termina en ROLLBACK. Es repetible tantas veces como haga falta y no deja
  rastro, ni siquiera en la bitacora de sincronizaciones.

  Por eso mismo usa un padron SINTETICO y no el del SSO real: la prueba no puede
  depender de que haya red hasta 192.168.20.111, ni de quien este dado de alta
  esta semana.

  EL ORDEN DE LAS SECCIONES NO ES LIBRE
  Las dos comprobaciones que hacen fallar a una rutina -derivar fuera del arbol y
  el padron vacio- van AL FINAL. Con XACT_ABORT ON un THROW deja la transaccion
  no confirmable, y a partir de ahi cualquier escritura muere con un 3930 que no
  dice nada del defecto que se buscaba. Todo lo que escribe va antes.

  Uso:
    sqlcmd -S 192.168.40.75 -U developer_anin -P ... -d DBSIGCM -b -I \
           -i db/90_pruebas/S907__prueba_sso_derivacion.sql
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Fallas int = 0;
DECLARE @msg nvarchar(400);

/* Centros de costo inventados, fuera del rango real de la ANIN, para que la
   prueba no se cruce con ninguna unidad existente aunque algo saliera mal. */
DECLARE @Dependencia nvarchar(max) = N'[
  {"id_dependencia":990001,"id_padre":null,"cod_dependencia":"T9001","siglas":"TUA",
   "descripcion":"UNIDAD DE PRUEBA S907 - ABASTECIMIENTO","centro_costo":"99.90.01"},
  {"id_dependencia":990002,"id_padre":990001,"cod_dependencia":"T9002","siglas":"TAU",
   "descripcion":"UNIDAD DE PRUEBA S907 - AREA USUARIA","centro_costo":"99.90.02"}
]';

/* El padron completo. Notese la ultima fila: un cod_perfil que no existe en
   sigcm.PerfilSso, para comprobar que se descarta con motivo en vez de entrar
   con un rol inventado. */
DECLARE @PadronCompleto nvarchar(max) = N'{"cantidad":8,"usuario":[
  {"id_usuario":990101,"dni":"90000001","usuario":"s907.jefe.ua","nombre":"JEFE",
   "apellido_paterno":"PRUEBA","apellido_materno":"UA","correo":"s907jefe@anin.gob.pe",
   "cod_perfil":"PE082","perfil":"JEFE UA","centro_costo":"99.90.01"},
  {"id_usuario":990102,"dni":"90000002","usuario":"s907.coord.ua","nombre":"COORDINADOR",
   "apellido_paterno":"PRUEBA","apellido_materno":"UA","correo":"s907coord@anin.gob.pe",
   "cod_perfil":"PE083","perfil":"COORDINADOR UA","centro_costo":"99.90.01"},
  {"id_usuario":990103,"dni":"90000003","usuario":"s907.esp.ua","nombre":"ESPECIALISTA",
   "apellido_paterno":"PRUEBA","apellido_materno":"UA","correo":"s907esp@anin.gob.pe",
   "cod_perfil":"PE084","perfil":"ESPECIALISTA UA","centro_costo":"99.90.01"},
  {"id_usuario":990104,"dni":"90000004","usuario":"s907.jefe.au","nombre":"JEFE",
   "apellido_paterno":"PRUEBA","apellido_materno":"AU","correo":"s907jefeau@anin.gob.pe",
   "cod_perfil":"PE091","perfil":"JEFE DE UNIDAD","centro_costo":"99.90.02"},
  {"id_usuario":990105,"dni":"90000005","usuario":"s907.esp.au","nombre":"ESPECIALISTA",
   "apellido_paterno":"PRUEBA","apellido_materno":"AU","correo":"s907espau@anin.gob.pe",
   "cod_perfil":"PE092","perfil":"ESPECIALISTA UNIDAD","centro_costo":"99.90.02"},
  {"id_usuario":990108,"dni":"90000008","usuario":"s907.coord.au","nombre":"COORDINADOR",
   "apellido_paterno":"PRUEBA","apellido_materno":"AU","correo":"s907coordau@anin.gob.pe",
   "cod_perfil":"ZZ083","perfil":"COORDINADOR DE UNIDAD","centro_costo":"99.90.02"},
  {"id_usuario":990106,"dni":"90000006","usuario":"s907.doble","nombre":"DOBLE",
   "apellido_paterno":"PRUEBA","apellido_materno":"TERNA","correo":"s907doble@anin.gob.pe",
   "cod_perfil":"PE083","perfil":"COORDINADOR UA","centro_costo":"99.90.01; 99.90.02"},
  {"id_usuario":990107,"dni":"90000007","usuario":"s907.sinmapa","nombre":"SIN",
   "apellido_paterno":"PRUEBA","apellido_materno":"MAPEO","correo":"s907sm@anin.gob.pe",
   "cod_perfil":"ZZ999","perfil":"PERFIL INEXISTENTE","centro_costo":"99.90.01"}
]}';

/* El mismo padron sin el especialista de Abastecimiento. Asi es como el SSO
   comunica una baja: la persona NO llega marcada como inactiva, desaparece. */
DECLARE @PadronSinEspecialista nvarchar(max) =
    REPLACE(@PadronCompleto,
      N'{"id_usuario":990103,"dni":"90000003","usuario":"s907.esp.ua","nombre":"ESPECIALISTA",
   "apellido_paterno":"PRUEBA","apellido_materno":"UA","correo":"s907esp@anin.gob.pe",
   "cod_perfil":"PE084","perfil":"ESPECIALISTA UA","centro_costo":"99.90.01"},', N'');

DECLARE @Respuesta nvarchar(max), @Salida nvarchar(max);

PRINT '===========================================================================';
PRINT '  S907 - Padron del SSO y arbol de derivacion';
PRINT '===========================================================================';

BEGIN TRANSACTION;

/*
  El SSO de hoy NO TIENE un perfil de coordinador de area usuaria: su unico
  COORDINADOR es PE083, que es de Abastecimiento. Por eso el escalon intermedio
  de Requerimiento no se puede ejercer con el padron real, y esta prueba lo
  agrega aqui dentro.

  No es un truco para que la prueba pase: es la demostracion de que incorporarlo
  cuesta UNA FILA, sin tocar codigo. Cuando el SSO cree ese perfil, esta misma
  fila entra en S005 y el escalon queda habilitado.

  Va dentro de la transaccion, asi que el ROLLBACK final se la lleva.
*/
INSERT INTO sigcm.PerfilSso (CodigoPerfilSso, NombreSso, CodigoRol, Observacion)
VALUES ('ZZ083', 'COORDINADOR DE UNIDAD', 'AREA_COORDINADOR',
        N'S907: perfil hipotetico. El SSO todavia no declara un coordinador de area usuaria.');

/* ========================================================================== */
/* 1. Alta: el padron completo entra                                          */
/* ========================================================================== */

SET @Salida = N'{"Disparador":"MANTENIMIENTO","Cuenta":"s907","Completo":true,'
            + N'"Equipo":"s907","Programa":"S907",'
            + N'"Dependencia":' + @Dependencia + N',"Padron":' + @PadronCompleto + N'}';

DECLARE @Resultado TABLE (Payload nvarchar(max));
DELETE FROM @Resultado;
INSERT INTO @Resultado EXEC sigcm.paSincronizarPadronSso @Salida;
SELECT @Respuesta = Payload FROM @Resultado;

IF JSON_VALUE(@Respuesta, '$.estado') <> '1'
BEGIN
    PRINT '  [FALLA] 1. La sincronizacion no respondio estado 1.';
    PRINT '          ' + LEFT(@Respuesta, 300);
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    1. Sincronizacion aplicada.';

/* Un acceso con dos centros de costo tiene que producir DOS ternas. */
IF (SELECT COUNT(*) FROM sigcm.UsuarioRol ur
      JOIN sigcm.Usuario u ON u.IdUsuario = ur.IdUsuario
     WHERE u.IdUsuarioSso = 990106 AND ur.VigenteHasta IS NULL) <> 2
BEGIN
    PRINT '  [FALLA] 2. El acceso con dos centros de costo no produjo dos ternas.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    2. Dos centros de costo producen dos ternas.';

/* Las unidades nacen del SSO, con su arbol. */
IF NOT EXISTS (SELECT 1 FROM sigcm.Unidad h
                JOIN sigcm.Unidad p ON p.IdUnidad = h.IdUnidadPadre
               WHERE h.IdDependenciaSso = 990002 AND p.IdDependenciaSso = 990001)
BEGIN
    PRINT '  [FALLA] 3. No se reconstruyo el arbol de unidades del SSO.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    3. El arbol de unidades se reconstruye desde el SSO.';

/* El perfil sin mapear no entra, y queda dicho por que. */
IF EXISTS (SELECT 1 FROM sigcm.Usuario WHERE IdUsuarioSso = 990107
            AND EXISTS (SELECT 1 FROM sigcm.UsuarioRol ur
                         WHERE ur.IdUsuario = sigcm.Usuario.IdUsuario
                           AND ur.VigenteHasta IS NULL))
BEGIN
    PRINT '  [FALLA] 4. Un cod_perfil sin mapear obtuvo una asignacion.';
    SET @Fallas += 1;
END
ELSE IF @Respuesta NOT LIKE '%ZZ999%'
BEGIN
    PRINT '  [FALLA] 4. El cod_perfil sin mapear no se reporto en Descartes.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    4. El cod_perfil sin mapear se descarta y se reporta.';

/* ========================================================================== */
/* 2. El arbol: CMN salta al coordinador del area usuaria, Requerimiento no    */
/* ========================================================================== */

DECLARE @CodUnidadAU varchar(30) = (SELECT Codigo FROM sigcm.Unidad WHERE IdDependenciaSso = 990002);
DECLARE @CodUnidadUA varchar(30) = (SELECT Codigo FROM sigcm.Unidad WHERE IdDependenciaSso = 990001);

DECLARE @ActorJefeAU nvarchar(max) =
    N'{"Actor":{"Usuario":"s907.jefe.au","Rol":"AREA_JEFE","Unidad":"' + @CodUnidadAU
  + N'","Ip":"127.0.0.1","Equipo":"s907","Programa":"S907"},"CodigoModulo":"';

DECLARE @Param nvarchar(max);

SET @Param = @ActorJefeAU + N'CMN"}';
DELETE FROM @Resultado;
INSERT INTO @Resultado EXEC sigcm.paListarDestinatarioDerivacion @Param;
SELECT @Respuesta = Payload FROM @Resultado;

IF @Respuesta LIKE '%AREA_COORDINADOR%'
BEGIN
    PRINT '  [FALLA] 5. En CMN el area usuaria ofrecio coordinador.';
    SET @Fallas += 1;
END
ELSE IF @Respuesta NOT LIKE '%AREA_ESPECIALISTA%'
BEGIN
    PRINT '  [FALLA] 5. En CMN el area usuaria no ofrecio especialista.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    5. En CMN el area usuaria deriva directo al especialista.';

SET @Param = @ActorJefeAU + N'REQUERIMIENTO"}';
DELETE FROM @Resultado;
INSERT INTO @Resultado EXEC sigcm.paListarDestinatarioDerivacion @Param;
SELECT @Respuesta = Payload FROM @Resultado;

IF @Respuesta NOT LIKE '%AREA_COORDINADOR%' OR @Respuesta NOT LIKE '%AREA_ESPECIALISTA%'
BEGIN
    PRINT '  [FALLA] 6. En Requerimiento faltan escalones del area usuaria.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    6. En Requerimiento pasa por coordinador y admite el salto.';

/* El jefe de Abastecimiento ve a sus dos coordinadores y a su especialista. */
SET @Param = N'{"Actor":{"Usuario":"s907.jefe.ua","Rol":"ABAST_JEFE","Unidad":"' + @CodUnidadUA
           + N'","Ip":"127.0.0.1","Equipo":"s907","Programa":"S907"},"CodigoModulo":"CMN"}';
DELETE FROM @Resultado;
INSERT INTO @Resultado EXEC sigcm.paListarDestinatarioDerivacion @Param;
SELECT @Respuesta = Payload FROM @Resultado;

IF @Respuesta NOT LIKE '%s907.coord.ua%' OR @Respuesta NOT LIKE '%s907.doble%'
BEGIN
    PRINT '  [FALLA] 7. El puesto de coordinador no listo a sus dos ocupantes.';
    SET @Fallas += 1;
END
ELSE IF @Respuesta NOT LIKE '%s907.esp.ua%'
BEGIN
    PRINT '  [FALLA] 7. El salto directo del jefe al especialista no se ofrecio.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    7. Dos coordinadores en el puesto y salto directo disponible.';

/* ========================================================================== */
/* 3. LA BAJA: el que desaparece del padron deja de estar disponible           */
/* ========================================================================== */

SET @Salida = N'{"Disparador":"MANTENIMIENTO","Cuenta":"s907","Completo":true,'
            + N'"Equipo":"s907","Programa":"S907",'
            + N'"Dependencia":' + @Dependencia + N',"Padron":' + @PadronSinEspecialista + N'}';

DELETE FROM @Resultado;
INSERT INTO @Resultado EXEC sigcm.paSincronizarPadronSso @Salida;

IF EXISTS (SELECT 1 FROM sigcm.UsuarioRol ur
             JOIN sigcm.Usuario u ON u.IdUsuario = ur.IdUsuario
            WHERE u.IdUsuarioSso = 990103 AND ur.VigenteHasta IS NULL)
BEGIN
    PRINT '  [FALLA] 8. La persona ausente del padron conservo su asignacion vigente.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    8. La ausencia en el padron cierra la asignacion.';

SET @Param = N'{"Actor":{"Usuario":"s907.jefe.ua","Rol":"ABAST_JEFE","Unidad":"' + @CodUnidadUA
           + N'","Ip":"127.0.0.1","Equipo":"s907","Programa":"S907"},"CodigoModulo":"CMN"}';
DELETE FROM @Resultado;
INSERT INTO @Resultado EXEC sigcm.paListarDestinatarioDerivacion @Param;
SELECT @Respuesta = Payload FROM @Resultado;

IF @Respuesta LIKE '%s907.esp.ua%'
BEGIN
    PRINT '  [FALLA] 9. El especialista dado de baja sigue siendo destinatario.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    9. El dado de baja desaparece de la lista de derivacion.';

/* Las cuentas que no vienen del SSO no las gobierna el SSO. */
IF EXISTS (SELECT 1 FROM sigcm.Usuario u
            WHERE u.IdUsuarioSso IS NULL AND u.Cuenta LIKE 'prueba.%' AND u.Activo = 0)
BEGIN
    PRINT '  [FALLA] 10. La reconciliacion desactivo cuentas ajenas al SSO.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    10. Las cuentas ajenas al SSO quedan intactas.';

/* ========================================================================== */
/* 4. EL RE-ALTA: vuelve al padron y vuelve a estar disponible                 */
/* ========================================================================== */

SET @Salida = N'{"Disparador":"MANTENIMIENTO","Cuenta":"s907","Completo":true,'
            + N'"Equipo":"s907","Programa":"S907",'
            + N'"Dependencia":' + @Dependencia + N',"Padron":' + @PadronCompleto + N'}';

DELETE FROM @Resultado;
INSERT INTO @Resultado EXEC sigcm.paSincronizarPadronSso @Salida;

IF NOT EXISTS (SELECT 1 FROM sigcm.UsuarioRol ur
                 JOIN sigcm.Usuario u ON u.IdUsuario = ur.IdUsuario
                WHERE u.IdUsuarioSso = 990103 AND ur.VigenteHasta IS NULL)
BEGIN
    PRINT '  [FALLA] 11. El re-alta no devolvio la asignacion vigente.';
    SET @Fallas += 1;
END
ELSE IF (SELECT COUNT(*) FROM sigcm.UsuarioRol ur
           JOIN sigcm.Usuario u ON u.IdUsuario = ur.IdUsuario
          WHERE u.IdUsuarioSso = 990103) < 2
BEGIN
    PRINT '  [FALLA] 11. El re-alta piso la asignacion cerrada en vez de agregar una.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    11. El re-alta abre una nueva y conserva la cerrada.';

/*
  Regresion. La baja y el re-alta EL MISMO DIA llegaron a duplicar a la persona
  en la lista de derivacion: el predicado de vigencia es "VigenteHasta >= hoy",
  asi que la fila cerrada hoy seguia calificando junto con la nueva. Se cierra
  tambien con Activo = 0; esta comprobacion existe para que no vuelva.
*/
IF (SELECT COUNT(*) FROM sigcm.UsuarioRol ur
      JOIN sigcm.Usuario u ON u.IdUsuario = ur.IdUsuario
     WHERE u.IdUsuarioSso = 990103
       AND ur.Activo = 1
       AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= CONVERT(date, GETDATE()))) <> 1
BEGIN
    PRINT '  [FALLA] 12. La baja y el re-alta el mismo dia dejaron dos ternas vigentes.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    12. Baja y re-alta el mismo dia no duplican la terna.';

/* ========================================================================== */
/* 5. La derivacion a persona: F004 valida contra el mismo arbol               */
/* ========================================================================== */

/*
  Un expediente minimo, puesto a mano en el estado donde el jefe de
  Abastecimiento decide a quien derivarlo. No pasa por cmn.paRegistrarSolicitud
  porque lo que se prueba aqui es el motor de transiciones, no el registro:
  armar un Anexo 3 valido exigiria maestros de SIGA y no agregaria nada.
*/
/*
  DOS expedientes y en este orden, y no es capricho.

  El caso ilegitimo tiene que hacer fallar a la rutina, y una rutina con
  XACT_ABORT ON que lanza THROW deja la transaccion NO CONFIRMABLE: a partir de
  ahi cualquier escritura muere con un 3930 que no dice nada del defecto que se
  buscaba. Es la restriccion documentada en CONTEXTO.md, seccion 5.

  Por eso todo lo que escribe va PRIMERO, el rechazo va al final, y despues del
  rechazo solo quedan lecturas -que si estan permitidas- y el ROLLBACK, que era
  el destino de todos modos.
*/
DECLARE @IdExpOk uniqueidentifier = NEWID();
DECLARE @IdExpNo uniqueidentifier = NEWID();
DECLARE @IdUnidadUA uniqueidentifier = (SELECT IdUnidad FROM sigcm.Unidad WHERE IdDependenciaSso = 990001);

INSERT INTO sigcm.Expediente
      (IdExpediente, Codigo, CodigoModulo, AnoEje, IdUnidadOrigen,
       CodigoEstado, IdUnidadActual, Version,
       UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
VALUES (@IdExpOk, 'S907-DERIV-OK', 'CMN', YEAR(GETDATE()), @IdUnidadUA,
        'CMN_EN_ABAST_JEFE', @IdUnidadUA, 1, 's907', 's907', 'S907'),
       (@IdExpNo, 'S907-DERIV-NO', 'CMN', YEAR(GETDATE()), @IdUnidadUA,
        'CMN_EN_ABAST_JEFE', @IdUnidadUA, 1, 's907', 's907', 'S907');

DECLARE @IdCoord uniqueidentifier = (SELECT u.IdUsuario FROM sigcm.Usuario u WHERE u.IdUsuarioSso = 990102);
DECLARE @IdEspAU uniqueidentifier = (SELECT u.IdUsuario FROM sigcm.Usuario u WHERE u.IdUsuarioSso = 990105);

DECLARE @ActorJefeUA nvarchar(max) =
    N'{"Actor":{"Usuario":"s907.jefe.ua","Rol":"ABAST_JEFE","Unidad":"' + @CodUnidadUA
  + N'","Ip":"127.0.0.1","Equipo":"s907","Programa":"S907"},"Version":1,'
  + N'"CodigoTransicion":"CMN_ABAST_JEFE_DERIVAR","IdExpediente":"';

/* Caso legitimo: su propio coordinador. Va primero porque escribe. */
SET @Param = @ActorJefeUA + CONVERT(varchar(50), @IdExpOk)
           + N'","IdResponsableDestino":"' + CONVERT(varchar(50), @IdCoord) + N'"}';

DELETE FROM @Resultado;
INSERT INTO @Resultado EXEC sigcm.paEjecutarTransicion @Param;
SELECT @Respuesta = Payload FROM @Resultado;

IF JSON_VALUE(@Respuesta, '$.estado') <> '1'
BEGIN
    PRINT '  [FALLA] 13. La derivacion legitima fue rechazada.';
    PRINT '          ' + LEFT(@Respuesta, 300);
    SET @Fallas += 1;
END
ELSE IF (SELECT IdResponsableActual FROM sigcm.Expediente WHERE IdExpediente = @IdExpOk) <> @IdCoord
BEGIN
    PRINT '  [FALLA] 13. El expediente no quedo a nombre del coordinador elegido.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    13. El jefe deriva a su coordinador y queda a su nombre.';

/*
  Caso ilegitimo: derivar a un especialista de OTRA unidad. Esta en el padron y
  es una persona real, pero el arbol no lo alcanza desde este actor.

  A PARTIR DE AQUI NO SE PUEDE ESCRIBIR NADA MAS.
*/
SET @Param = @ActorJefeUA + CONVERT(varchar(50), @IdExpNo)
           + N'","IdResponsableDestino":"' + CONVERT(varchar(50), @IdEspAU) + N'"}';

BEGIN TRY
    EXEC sigcm.paEjecutarTransicion @Param;
END TRY
BEGIN CATCH
END CATCH

IF EXISTS (SELECT 1 FROM sigcm.Expediente
            WHERE IdExpediente = @IdExpNo
              AND (IdResponsableActual = @IdEspAU OR CodigoEstado <> 'CMN_EN_ABAST_JEFE'))
BEGIN
    PRINT '  [FALLA] 14. Se acepto derivar a alguien fuera del arbol.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    14. Derivar fuera del arbol se rechaza y no mueve nada.';

/* ========================================================================== */
/* 6. Salvaguarda: un padron vacio no da de baja a nadie                       */
/* ========================================================================== */

/*
  VA AL FINAL, y por la misma razon que el caso ilegitimo de arriba: esta
  llamada tiene que fallar, y con XACT_ABORT ON un THROW deja la transaccion no
  confirmable. Puesta antes, mataba las escrituras de la seccion 5 con un 3930
  que no decia nada -paso, y asi se descubrio-.

  EXEC a secas y no INSERT ... EXEC, por lo mismo. Se comprueba el EFECTO -que no
  dio de baja a nadie-, que es lo que importa.
*/
SET @Salida = N'{"Disparador":"MANTENIMIENTO","Cuenta":"s907","Completo":true,'
            + N'"Dependencia":' + @Dependencia + N',"Padron":{"usuario":[],"cantidad":0}}';

BEGIN TRY
    EXEC sigcm.paSincronizarPadronSso @Salida;
END TRY
BEGIN CATCH
END CATCH

IF NOT EXISTS (SELECT 1 FROM sigcm.UsuarioRol ur
                 JOIN sigcm.Usuario u ON u.IdUsuario = ur.IdUsuario
                WHERE u.IdUsuarioSso = 990101 AND ur.VigenteHasta IS NULL)
BEGIN
    PRINT '  [FALLA] 15. Un padron vacio alcanzo a dar de baja.';
    SET @Fallas += 1;
END
ELSE
    PRINT '  [OK]    15. Un padron vacio se rechaza sin tocar nada.';

/* ========================================================================== */

ROLLBACK TRANSACTION;

PRINT '---------------------------------------------------------------------------';
IF @Fallas = 0
    PRINT '  S907: 15 comprobaciones en verde. La base quedo como estaba.';
ELSE
BEGIN
    SET @msg = '  S907: ' + CONVERT(varchar(10), @Fallas) + ' comprobacion(es) en rojo.';
    PRINT @msg;
END
PRINT '===========================================================================';
GO
