/*
===============================================================================
  SIGCM - C002B : EXECUTE sobre usp_ext_* en la base SIGA
  Motor  : SQL Server 2016 (13.x) o superior
  Ambito : se ejecuta contra la base SIGA (sqlcmd -d $(bdSiga))

  C002 concede SELECT (lectura). Los escritores W001-W004 llaman a usp_ext_*
  DENTRO de SIGA; sin EXECUTE esas llamadas fallan en calidad/produccion
  (en desarrollo suele pasar inadvertido porque la cuenta es sysadmin).

  No concede INSERT/UPDATE/DELETE sobre tablas de SIGA. Los usp_ext_* deben
  poder escribir por ser dbo. Si en el ambiente el procedimiento corre como
  CALLER y falla al insertar, el DBA debe alterarlos a EXECUTE AS OWNER.

  Corre DESPUES de instalar los usp_ext_*.sql.

  Uso:
    sqlcmd -S "<servidor>" -d master -b -I ^
           -v bdSiga="SIGA_1750" -v loginApp="w_sgcmenores" ^
           -i C002B__ejecutar_usp_ext_siga.sql
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

:setvar bdSiga "SIGA_1750"
:setvar loginApp "-"

DECLARE @bdSiga sysname = N'$(bdSiga)';
DECLARE @login  sysname = N'$(loginApp)';
DECLARE @rol    sysname = N'sigcm_lector_siga';

IF @login IN (N'', N'-') SET @login = N'';

IF DB_ID(@bdSiga) IS NULL
BEGIN
    RAISERROR(N'No existe la base SIGA indicada. Pase -v bdSiga="<nombre real>".', 16, 1);
    SET NOEXEC ON;
END

DECLARE @sql nvarchar(max);
DECLARE @procs TABLE (nombre sysname NOT NULL PRIMARY KEY);
INSERT INTO @procs (nombre) VALUES
    (N'usp_ext_incluir_item_cmn'),
    (N'usp_ext_excluir_item_cmn'),
    (N'usp_ext_aprobar_solicitud_cmn'),
    (N'usp_ext_registrar_item_cmn'),
    (N'usp_ext_registrar_requerimiento'),
    (N'usp_ext_crear_cuadro_adquisicion_desde_pedido'),
    (N'usp_ext_crear_orden_servicio_desde_cuadro'),
    (N'usp_ext_registrar_recepcion_orden');

SET @sql = N'
USE ' + QUOTENAME(@bdSiga) + N';
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @rol AND type = ''R'')
    CREATE ROLE ' + QUOTENAME(@rol) + N';
';
EXEC sys.sp_executesql @sql, N'@rol sysname', @rol = @rol;

DECLARE @nombre sysname;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT nombre FROM @procs ORDER BY nombre;
OPEN cur;
FETCH NEXT FROM cur INTO @nombre;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@bdSiga) + N';
    IF OBJECT_ID(N''dbo.' + REPLACE(@nombre, '''', '''''') + N''', N''P'') IS NOT NULL
        GRANT EXECUTE ON dbo.' + QUOTENAME(@nombre) + N' TO ' + QUOTENAME(@rol) + N';
    ELSE
        PRINT N''  [AVISO] no existe dbo.' + REPLACE(@nombre, '''', '''''') + N'; instale usp_ext antes.'';
    ';
    EXEC sys.sp_executesql @sql;
    PRINT '  GRANT EXECUTE ON dbo.' + @nombre + ' TO ' + @rol;
    FETCH NEXT FROM cur INTO @nombre;
END
CLOSE cur;
DEALLOCATE cur;

IF @login <> N''
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @login)
    BEGIN
        DECLARE @err nvarchar(400) =
            N'El login ' + @login + N' no existe. Creelo el DBA y reejecute C002B.';
        RAISERROR(@err, 16, 1);
        SET NOEXEC ON;
    END

    SET @sql = N'
    USE ' + QUOTENAME(@bdSiga) + N';
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @login)
        CREATE USER ' + QUOTENAME(@login) + N' FOR LOGIN ' + QUOTENAME(@login) + N';
    ALTER ROLE ' + QUOTENAME(@rol) + N' ADD MEMBER ' + QUOTENAME(@login) + N';
    ';
    EXEC sys.sp_executesql @sql, N'@login sysname', @login = @login;
    PRINT '  ' + @login + ' miembro de ' + @rol + ' en ' + @bdSiga;
END

PRINT 'C002B listo: EXECUTE sobre usp_ext_* concedido al rol ' + @rol + '.';
GO
