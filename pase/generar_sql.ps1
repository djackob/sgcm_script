<#
===============================================================================
  Junta la serie versionada en UN .sql por base (pase a calidad).
  No sustituye V/F/W/S del repo: solo arma lo que se envia al ejecutor.
===============================================================================
#>

$ErrorActionPreference = "Stop"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = (Resolve-Path (Join-Path $aqui "..")).Path
$salida = $aqui
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm"

function Leer([string]$rel) {
    $ruta = Join-Path $raiz $rel
    if (-not (Test-Path $ruta)) { throw "No existe: $rel" }
    return [IO.File]::ReadAllText($ruta)
}

function Quitar-Setvar([string]$texto) {
    return [regex]::Replace($texto, '(?m)^\s*:setvar\s+\S+\s+".*"\s*\r?$', '')
}

function Quitar-UseSiga([string]$texto) {
    $texto = Quitar-Setvar $texto
    $texto = [regex]::Replace(
        $texto,
        '(?m)^\s*USE\s+\[\$\(bdSiga\)\];\s*\r?\n(?:GO\s*\r?\n)?',
        '')
    return $texto
}

function Bloque([string]$rel, [string]$texto) {
    $nl = "`r`n"
    $cuerpo = $texto.TrimEnd()
    return ($nl +
        "/******************************************************************************" + $nl +
        "  INICIO  $rel" + $nl +
        "******************************************************************************/" + $nl +
        $cuerpo + $nl +
        "GO" + $nl +
        "/******************************************************************************" + $nl +
        "  FIN  $rel" + $nl +
        "******************************************************************************/" + $nl)
}

function Lista-Sql([string]$relDir, [string]$filtro) {
    $dir = Join-Path $raiz $relDir
    return @(Get-ChildItem $dir -Filter $filtro | Where-Object {
        $_.Name -notlike "_tmp*"
    } | Sort-Object Name | ForEach-Object {
        Join-Path $relDir $_.Name
    })
}

function Guardar([string]$nombre, [string]$contenido) {
    $ruta = Join-Path $salida $nombre
    $utf8 = New-Object System.Text.UTF8Encoding $true
    [IO.File]::WriteAllText($ruta, $contenido, $utf8)
    Write-Host ("  {0}  ({1:N0} caracteres)" -f $nombre, $contenido.Length)
    return $ruta
}

# ---------------------------------------------------------------------------
# 01_SIGA.sql  (no recrea SIGA)
# ---------------------------------------------------------------------------

$incSiga = @(Lista-Sql "SIGA\integracion" "usp_ext_*.sql")
$cuerpoSiga = New-Object System.Text.StringBuilder
[void]$cuerpoSiga.AppendLine(@"
/*
===============================================================================
  SIGCM - Pase a calidad - base SIGA
  Generado: $stamp
  Idempotente. NO crea ni borra la base SIGA (es del MEF).

  Instala dbo.usp_ext_* y concede EXECUTE al rol sigcm_lector_siga.

  sqlcmd -S "<servidor>" -d master -E -b -I ^
         -v bdSiga="<nombre real SIGA>" -v loginApp="w_sgcmenores" ^
         -i 01_SIGA.sql

  Fuentes:
"@)
foreach ($f in $incSiga) { [void]$cuerpoSiga.AppendLine("    $f") }
[void]$cuerpoSiga.AppendLine("    00_servidor\C002B__ejecutar_usp_ext_siga.sql")
[void]$cuerpoSiga.AppendLine(@"
===============================================================================
*/

:setvar bdSiga "SIGA_1750"
:setvar loginApp "-"

USE [`$(bdSiga)];
GO
"@)

foreach ($f in $incSiga) {
    [void]$cuerpoSiga.Append((Bloque $f (Quitar-UseSiga (Leer $f))))
}
[void]$cuerpoSiga.Append((Bloque "00_servidor\C002B__ejecutar_usp_ext_siga.sql" (Quitar-Setvar (Leer "00_servidor\C002B__ejecutar_usp_ext_siga.sql"))))

# ---------------------------------------------------------------------------
# 02_DBSIGCM.sql
# ---------------------------------------------------------------------------

$incDbs = New-Object System.Collections.Generic.List[string]
foreach ($x in @(
    "00_servidor\C000C__permisos_instalacion.sql",
    "00_servidor\C000__preflight.sql",
    "00_servidor\C001__crear_dbsigcm.sql"
)) { $incDbs.Add($x) }

$despues = New-Object System.Collections.Generic.List[string]
$despues.Add("00_servidor\C003__sinonimos_siga.sql")
foreach ($par in @(
    @{ dir = "db\00_ddl"; filtro = "V*.sql" },
    @{ dir = "db\10_api"; filtro = "F*.sql" },
    @{ dir = "db\15_siga"; filtro = "W*.sql" },
    @{ dir = "db\20_seed"; filtro = "S*.sql" }
)) {
    foreach ($f in (Lista-Sql $par.dir $par.filtro)) { $despues.Add($f) }
}
$despues.Add("00_servidor\C900__inventario.sql")
$despues.Add("00_servidor\C002__acceso_lectura_siga.sql")

$cuerpoDbs = New-Object System.Text.StringBuilder
[void]$cuerpoDbs.AppendLine(@"
/*
===============================================================================
  SIGCM - Pase a calidad - base DBSIGCM
  Generado: $stamp
  Idempotente. Si DBSIGCM ya existe, NO la borra; reaplica objetos.

  1. Verifica cuenta y entorno (master).
  2. Crea DBSIGCM si falta (misma intercalacion que SIGA).
  3. Sinonimos, DDL, API, escritores, semilla, inventario.
  4. C002: SELECT en SIGA + usuario de aplicacion (loginApp).

  Ejecutar DESPUES de 01_SIGA.sql.

  sqlcmd -S "<servidor>" -d master -E -b -I ^
         -v bdSiga="<nombre real SIGA>" -v bdSigcm="DBSIGCM" ^
         -v loginApp="w_sgcmenores" ^
         -i 02_DBSIGCM.sql
===============================================================================
*/

:setvar bdSiga "SIGA_1750"
:setvar bdSigcm "DBSIGCM"
:setvar loginApp "-"

USE master;
GO
"@)

foreach ($f in $incDbs) {
    [void]$cuerpoDbs.Append((Bloque $f (Quitar-Setvar (Leer $f))))
}

[void]$cuerpoDbs.AppendLine(@"
USE [`$(bdSigcm)];
GO
"@)

foreach ($f in $despues) {
    [void]$cuerpoDbs.Append((Bloque $f (Quitar-Setvar (Leer $f))))
}

# ---------------------------------------------------------------------------
# 03_SSO.sql  (PostgreSQL)
# ---------------------------------------------------------------------------

$incSso = @(
    "sso\S03__perfil_secretaria_area_usuaria.sql",
    "sso\S04__perfil_secretaria_abastecimiento.sql",
    "sso\S01__acceso_administrador.sql",
    "sso\S02__acceso_coordinador_oti.sql"
)

$cuerpoSso = New-Object System.Text.StringBuilder
[void]$cuerpoSso.AppendLine(@"
/*
  SIGCM - Pase a calidad - base SSO (PostgreSQL, esquema login)
  Generado: $stamp
  No se ejecuta en SQL Server.

  Crea PE100/PE101/PE102 y asigna P0001 (y PE099) al DNI indicado.
  S02 usa el mismo dni y requiere cod_dependencia (por defecto D0001).
  Si el coordinador de oficina es otra persona, cambie el dni al ejecutar
  o edite la seccion S02.

  psql -h <host> -p 5432 -U <usuario> -d saa_ ^
       -v dni=44687266 -v cod_dependencia=D0001 ^
       -f 03_SSO.sql
*/
"@)

foreach ($f in $incSso) {
    $nl = "`r`n"
    [void]$cuerpoSso.Append(
        $nl + "-- ========== INICIO  $f ==========" + $nl +
        (Leer $f).TrimEnd() + $nl +
        "-- ========== FIN  $f ==========" + $nl)
}

Write-Host "Generando SQL de pase (un archivo por base)..."
$r1 = Guardar "01_SIGA.sql" ($cuerpoSiga.ToString())
$r2 = Guardar "02_DBSIGCM.sql" ($cuerpoDbs.ToString())
$r3 = Guardar "03_SSO.sql" ($cuerpoSso.ToString())

Write-Host "Listo."
