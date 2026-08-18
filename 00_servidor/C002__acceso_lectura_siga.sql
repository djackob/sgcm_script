/*
===============================================================================
  SIGCM - C002 : Acceso de solo lectura a la base SIGA
  Motor  : SQL Server 2016 (13.x) o superior
  Ambito : se ejecuta en [master] y en la base SIGA

  POR QUE HACE FALTA
  ------------------
  El encadenamiento de propiedad entre bases (cross database ownership chaining)
  esta desactivado por defecto y NO se propone activarlo: es un ajuste de
  instancia con implicaciones de seguridad para todas las bases del servidor.
  En consecuencia, las vistas de V004 no bastan por si solas: la cuenta con la
  que el SIGCM se conecta necesita SELECT explicito sobre las tablas de origen.

  ESTE ES UN CAMBIO DENTRO DE SIGA Y REQUIERE AUTORIZACION DEL PROPIETARIO.
  Es el minimo posible: un rol de base, SELECT sobre catorce tablas nominadas,
  cero permisos de escritura, cero db_datareader, cero cambios de esquema.
  Aun asi, no se ejecuta sin permiso.

  ESTE SCRIPT NO CREA LOGINS NI MANEJA CONTRASENIAS.
  El login de aplicacion lo crea el DBA por su cuenta, con la contrasenia
  gestionada en el almacen de secretos de la institucion. Aqui solo se le
  concede acceso. Si el despliegue usa autenticacion integrada de Windows, el
  parametro es la cuenta de dominio del pool de la aplicacion.

  En el entorno local no hace falta ejecutarlo: la exploracion corre con
  autenticacion integrada bajo una cuenta sysadmin, que no pasa por
  comprobacion de permisos.

  Uso:
    sqlcmd -S "<servidor>" -d master -E ^
           -v bdSiga="SIGA_1750" login="ANIN\svc_sigcm" ^
           -i C002__acceso_lectura_siga.sql
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @bdSiga  sysname = N'SIGA_1750';
DECLARE @bdSigcm sysname = N'DBSIGCM';

/* Login ya existente al que se le concede el acceso. Debe crearlo el DBA. */
DECLARE @login sysname = N'';   /* p.ej. N'ANIN\svc_sigcm' */

DECLARE @rol sysname = N'sigcm_lector_siga';

IF @login = N''
BEGIN
    PRINT '';
    PRINT '  Sin parametro "login": no se concede acceso a nadie.';
    PRINT '  Se creara unicamente el rol ' + @rol + ' con sus permisos, listo para usarse.';
    PRINT '';
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @login)
BEGIN
    DECLARE @errLogin nvarchar(400) =
        N'El login ' + @login + N' no existe. Este script no crea logins ni maneja '
      + N'contrasenias: pidele al DBA que lo cree y vuelve a ejecutar.';
    RAISERROR(@errLogin, 16, 1);
    SET NOEXEC ON;
END

DECLARE @sql nvarchar(max);

/* -------------------------------------------------------------------------- */
/* 1. Rol de lectura dentro de la base SIGA                                   */
/* -------------------------------------------------------------------------- */

SET @sql = N'
USE ' + QUOTENAME(@bdSiga) + N';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @rol AND type = ''R'')
    CREATE ROLE ' + QUOTENAME(@rol) + N';
';
EXEC sys.sp_executesql @sql, N'@rol sysname', @rol = @rol;

/* -------------------------------------------------------------------------- */
/* 2. SELECT sobre las catorce tablas de origen, una por una                  */
/* -------------------------------------------------------------------------- */

/* Se enumeran a proposito en vez de conceder db_datareader: el SIGCM solo debe
   poder leer lo que las vistas de V004 necesitan, y nada mas. Si maniana una
   vista nueva necesita otra tabla, tiene que pasar por aqui y por la
   autorizacion correspondiente. */

DECLARE @tablas TABLE (tabla sysname NOT NULL PRIMARY KEY);
INSERT INTO @tablas (tabla) VALUES
    (N'SIG_CENTRO_COSTO'),
    (N'META'),
    (N'FUENTE_FINANC_EJEC'),
    (N'FUENTE_FINANC'),
    (N'SIG_CENTRO_COSTO_TAREA'),
    (N'UNIDAD_MEDIDA'),
    (N'CATALOGO_BIEN_SERV'),
    (N'SIG_TECHO_PRESUPUESTO'),
    (N'SIG_CUADRO_MODIFICADO'),
    (N'SIG_CUADRO_MODIFICADO_DET'),
    (N'SIG_CUADRO_MODIFICADO_SALDO'),
    (N'SIG_CUADRO_MODIFICADO_CMN'),
    (N'SIG_CUADRO_X_CENTRO'),
    (N'SIG_PARAMETRO_EJECUTORA_ANIO');

DECLARE @tabla sysname;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT tabla FROM @tablas ORDER BY tabla;
OPEN cur;
FETCH NEXT FROM cur INTO @tabla;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@bdSiga) + N';
                 GRANT SELECT ON dbo.' + QUOTENAME(@tabla) + N' TO ' + QUOTENAME(@rol) + N';';
    EXEC sys.sp_executesql @sql;
    PRINT '  GRANT SELECT ON dbo.' + @tabla;
    FETCH NEXT FROM cur INTO @tabla;
END
CLOSE cur;
DEALLOCATE cur;

/* Denegacion explicita de escritura. Redundante con no haberla concedido, pero
   deja la intencion escrita en el catalogo: si alguien anide este rol dentro de
   otro con mas permisos, DENY gana. */
SET @sql = N'
USE ' + QUOTENAME(@bdSiga) + N';
DENY INSERT, UPDATE, DELETE, ALTER, EXECUTE TO ' + QUOTENAME(@rol) + N';
';
EXEC sys.sp_executesql @sql;

/* -------------------------------------------------------------------------- */
/* 3. Alta del usuario, si se indico login                                    */
/* -------------------------------------------------------------------------- */

IF @login <> N''
BEGIN
    /* En SIGA: usuario sin permisos propios, solo miembro del rol de lectura. */
    SET @sql = N'
    USE ' + QUOTENAME(@bdSiga) + N';
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @login)
        CREATE USER ' + QUOTENAME(@login) + N' FOR LOGIN ' + QUOTENAME(@login) + N';
    ALTER ROLE ' + QUOTENAME(@rol) + N' ADD MEMBER ' + QUOTENAME(@login) + N';
    ';
    EXEC sys.sp_executesql @sql, N'@login sysname', @login = @login;
    PRINT '  ' + @login + ' agregado a ' + @rol + ' en ' + @bdSiga;

    /* En DBSIGCM: la aplicacion no necesita DDL, solo ejecutar las rutinas y
       leer las vistas. Los permisos finos por esquema quedan pendientes; por
       ahora, lectura y ejecucion. */
    SET @sql = N'
    USE ' + QUOTENAME(@bdSigcm) + N';
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @login)
        CREATE USER ' + QUOTENAME(@login) + N' FOR LOGIN ' + QUOTENAME(@login) + N';
    ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@login) + N';
    GRANT EXECUTE TO ' + QUOTENAME(@login) + N';
    ';
    EXEC sys.sp_executesql @sql, N'@login sysname', @login = @login;
    PRINT '  ' + @login + ' habilitado en ' + @bdSigcm;
END

PRINT '';
PRINT 'Listo. Continuar con C003__sinonimos_siga.sql.';

SET NOEXEC OFF;
GO
