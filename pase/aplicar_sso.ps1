<#
===============================================================================
  SIGCM - Perfiles SSO en calidad (PostgreSQL)
===============================================================================
  Aplica 03_SSO.sql (un solo archivo). Pide la contrasena por teclado.
===============================================================================
#>

$ErrorActionPreference = "Stop"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path

function Buscar-Archivo([string]$nombre) {
    foreach ($dir in @($aqui, (Join-Path $aqui ".."), (Join-Path $aqui "pase"))) {
        $p = Join-Path $dir $nombre
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    return $null
}

$sqlSso = Buscar-Archivo "03_SSO.sql"
if (-not $sqlSso) {
    throw "Falta 03_SSO.sql. Ejecute antes: .\pase\generar_sql.ps1"
}

$archivoParam = Buscar-Archivo "parametros.ps1"
if (-not $archivoParam) {
    throw "Falta parametros.ps1 (bloque `$ParametrosSso)."
}
. $archivoParam

$psql = Get-Command psql -ErrorAction SilentlyContinue
if (-not $psql) {
    Write-Host "psql no esta en el PATH." -ForegroundColor Red
    exit 1
}

$HostSso = $ParametrosSso.Host
$Puerto  = $ParametrosSso.Puerto
$Base    = $ParametrosSso.Base
$Usuario = $ParametrosSso.Usuario
$Dni     = $ParametrosSso.DniAdmin
$Dep     = $ParametrosSso.CodDependencia
if ([string]::IsNullOrWhiteSpace($Dep)) { $Dep = "D0001" }

Write-Host "SSO  $HostSso`:$Puerto  base=$Base  usuario=$Usuario  dni=$Dni"
$r = Read-Host "Aplicar 03_SSO.sql sobre el SSO de calidad? (S/N)"
if ($r -notmatch '^[SsYy]') { exit 0 }

$env:PGPASSWORD = Read-Host "Contrasena de $Usuario (SSO)"

try {
    Write-Host "  -> 03_SSO.sql"
    & psql -h $HostSso -p $Puerto -U $Usuario -d $Base -v dni=$Dni -v "cod_dependencia=$Dep" -f $sqlSso
    if ($LASTEXITCODE -ne 0) { throw "Fallo 03_SSO.sql" }
    Write-Host "SSO aplicado." -ForegroundColor Green
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
