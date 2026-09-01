/*
===============================================================================
  SIGCM - Semilla S007 : Panel del SSO y el administrador del sistema
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]

  Tres cosas, en este orden:
    1. El modulo ADMIN_SSO, para que el panel tenga entrada en el menu.
    2. Su permiso: solo ADMIN_SISTEMA.
    3. Como se entra: el mapeo del perfil P0001 del SSO, y una cuenta local de
       respaldo.

  EL PROBLEMA DE HUEVO Y GALLINA
  -----------------------------
  El panel es del administrador del sistema, y al 2026-08-27 NO HABIA NINGUNO:
  sigcm.UsuarioRol no tenia una sola fila con ADMIN_SISTEMA. Sin administrador
  no hay quien abra el panel; sin panel no hay donde ver por que nadie entra.

  El SSO ya trae la mitad de la solucion: el perfil P0001 ADMINISTRADOR existe y
  ya esta ligado al sistema 73 (SGCM-I). Lo que le falta es que alguien lo tenga
  ACTIVO -sus dos accesos, los de 32885691 y 43552822, estan en activo = false-.
  Eso se resuelve en el SSO, no aqui.

  Este script deja las dos puertas listas para cuando eso ocurra, y una tercera
  mientras tanto. Ver la seccion 3.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -------------------------------------------------------------------------- */
/* 1. El modulo                                                               */
/* -------------------------------------------------------------------------- */

/*
  Es un modulo de sigcm.Modulo como CMN o Requerimiento, y no una opcion suelta
  del menu, porque el menu de la sesion se arma EXCLUSIVAMENTE de
  sigcm.RolModulo cruzado con sigcm.Modulo (F006). Una opcion que no fuera
  modulo necesitaria una segunda lista paralela, y esa lista se desincroniza.

  Orden 90 para que quede al final, despues de los seis modulos del proceso.
*/
DECLARE @Modulo TABLE (CodigoModulo varchar(30), Nombre varchar(150), Orden int,
                       Activo bit, Ruta varchar(100), Icono varchar(60));
INSERT INTO @Modulo VALUES
  ('ADMIN_SSO', 'Accesos y perfiles', 90, 1, 'mantenimiento-sso', 'mdi mdi-account-key-outline');

UPDATE d SET d.Nombre = s.Nombre, d.Orden = s.Orden, d.Activo = s.Activo,
             d.Ruta = s.Ruta, d.Icono = s.Icono
  FROM sigcm.Modulo AS d JOIN @Modulo AS s ON s.CodigoModulo = d.CodigoModulo;

INSERT INTO sigcm.Modulo (CodigoModulo, Nombre, Orden, Activo, Ruta, Icono)
SELECT s.CodigoModulo, s.Nombre, s.Orden, s.Activo, s.Ruta, s.Icono
  FROM @Modulo AS s
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.Modulo AS d WHERE d.CodigoModulo = s.CodigoModulo);
GO

/* -------------------------------------------------------------------------- */
/* 2. Quien lo ve                                                             */
/* -------------------------------------------------------------------------- */

/*
  Solo ADMIN_SISTEMA. Y el control no vive solo aqui: sigcm.paObtenerPanelSso
  vuelve a comprobar el rol (51701). El menu decide que se MUESTRA; la rutina
  decide que se PUEDE. Un menu sin la opcion no impide llamar al endpoint.
*/
INSERT INTO sigcm.RolModulo (CodigoRol, CodigoModulo)
SELECT 'ADMIN_SISTEMA', 'ADMIN_SSO'
 WHERE NOT EXISTS (SELECT 1 FROM sigcm.RolModulo
                    WHERE CodigoRol = 'ADMIN_SISTEMA' AND CodigoModulo = 'ADMIN_SSO');
GO

/* -------------------------------------------------------------------------- */
/* 3. Como se entra                                                           */
/* -------------------------------------------------------------------------- */

/*
  PUERTA PRINCIPAL: el perfil P0001 del SSO.

  Con esta fila, cualquiera a quien el SSO le active el acceso P0001 al sistema
  73 entra como administrador del SIGCM, sin tocar nada mas aqui. Es la puerta
  correcta porque no crea una segunda autoridad: el padron sigue siendo uno.

  Se mapea aunque hoy no haya nadie con ese acceso activo. Una fila que espera
  no molesta a nadie -F008 solo traduce lo que llega- y evita tener que acordarse
  de esto el dia que activen el acceso.
*/
IF NOT EXISTS (SELECT 1 FROM sigcm.PerfilSso WHERE CodigoPerfilSso = 'P0001')
    INSERT INTO sigcm.PerfilSso (CodigoPerfilSso, NombreSso, CodigoRol, Observacion)
    VALUES ('P0001', 'ADMINISTRADOR', 'ADMIN_SISTEMA',
            N'Administrador del sistema. Al 2026-08-27 el SSO tiene el perfil ligado al sistema 73 pero sin ningun acceso activo.');
ELSE
    UPDATE sigcm.PerfilSso
       SET NombreSso = 'ADMINISTRADOR', CodigoRol = 'ADMIN_SISTEMA'
     WHERE CodigoPerfilSso = 'P0001';
GO

/*
  PUERTA DE RESPALDO: una cuenta administradora local.

  QUE ES Y QUE NO ES
  No es una puerta trasera abierta. El SIGCM no guarda contrasenias (V001), asi
  que esta cuenta no autentica a nadie por si sola: solo se puede usar por
  api/acceso, que responde 404 mientras appSettings:acceso_local sea "false" -que
  es como quedo configurado el backend-. Con la bandera apagada, esta fila es
  inerte.

  POR QUE EXISTE IGUAL
  Porque el panel del SSO es justamente la herramienta para diagnosticar por que
  nadie puede entrar, y dejarla accesible solo a traves del SSO significa que si
  el SSO falla, la herramienta para averiguar por que falla tampoco esta. La
  cuenta local es el destornillador guardado fuera de la caja que abre.

  IdUsuarioSso queda NULL, y eso la protege: la reconciliacion de F008 solo cierra
  asignaciones de usuarios que el SSO gobierna (salvaguarda 2). Ninguna
  sincronizacion la va a dar de baja.

  SE ANCLA EN LA UNIDAD DE ABASTECIMIENTO por su centro de costo, no por un
  codigo de unidad fijo: en una base recien instalada las unidades las crea la
  primera sincronizacion y sus codigos dependen de lo que traiga el SSO. Si esa
  unidad todavia no existe, el script no inventa ninguna y avisa: es preferible a
  crear una unidad fantasma que despues nadie sabe de donde salio.
*/
DECLARE @IdUnidadAdmin uniqueidentifier = (
    SELECT TOP (1) IdUnidad FROM sigcm.Unidad
     WHERE CentroCostoSiga = '01.07.03.01' AND Activo = 1
     ORDER BY IdDependenciaSso DESC, Codigo);

/* Si no hay Abastecimiento, cualquier unidad activa sirve: el rol de
   administrador no ejerce en un area, solo necesita una para completar la
   terna que exige paResolverActor. */
IF @IdUnidadAdmin IS NULL
    SELECT TOP (1) @IdUnidadAdmin = IdUnidad FROM sigcm.Unidad WHERE Activo = 1 ORDER BY Codigo;

IF @IdUnidadAdmin IS NULL
    PRINT 'S007 aviso: no hay ninguna unidad activa todavia. La cuenta administradora local NO se creo; vuelva a aplicar S007 despues de la primera sincronizacion con el SSO.';
ELSE
BEGIN
    DECLARE @IdAdmin uniqueidentifier =
        (SELECT IdUsuario FROM sigcm.Usuario WHERE Cuenta = 'admin.sigcm');

    IF @IdAdmin IS NULL
    BEGIN
        SET @IdAdmin = NEWID();
        INSERT INTO sigcm.Usuario
              (IdUsuario, Cuenta, Nombres, Apellidos, Cargo, Correo, IdUsuarioSso,
               UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES (@IdAdmin, 'admin.sigcm', 'Administrador', 'del sistema',
                'Administrador funcional del SIGCM', NULL, NULL,
                'seed', 'localhost', 'S007');
    END
    ELSE
        UPDATE sigcm.Usuario SET Activo = 1 WHERE IdUsuario = @IdAdmin;

    IF NOT EXISTS (SELECT 1 FROM sigcm.UsuarioRol
                    WHERE IdUsuario = @IdAdmin AND CodigoRol = 'ADMIN_SISTEMA'
                      AND IdUnidad = @IdUnidadAdmin
                      AND Activo = 1 AND VigenteHasta IS NULL)
        INSERT INTO sigcm.UsuarioRol
              (IdUsuario, CodigoRol, IdUnidad, EsTitular,
               UsuarioCreacionAuditoria, EquipoCreacionAuditoria, ProgramaCreacionAuditoria)
        VALUES (@IdAdmin, 'ADMIN_SISTEMA', @IdUnidadAdmin, 0, 'seed', 'localhost', 'S007');
END
GO

DECLARE @msg varchar(400) =
    'S007 aplicada: modulo ADMIN_SSO, permiso para ADMIN_SISTEMA, mapeo P0001 y '
  + CONVERT(varchar(10), (SELECT COUNT(*) FROM sigcm.UsuarioRol ur
                            JOIN sigcm.Usuario u ON u.IdUsuario = ur.IdUsuario
                           WHERE ur.CodigoRol = 'ADMIN_SISTEMA'
                             AND ur.Activo = 1 AND ur.VigenteHasta IS NULL))
  + ' administrador(es) vigente(s).';
PRINT @msg;
GO
