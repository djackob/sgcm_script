<#
===============================================================================
  SIGCM - Instalacion en CALIDAD (la ejecuta un usuario ANIN)
===============================================================================

  Aplica UN script por base:
    01_SIGA.sql      extensiones en la base SIGA (no la recrea)
    02_DBSIGCM.sql   crea DBSIGCM si falta y aplica el modelo
    03_SSO.sql       perfiles en PostgreSQL (aplicar_sso.ps1)

  No borra bases. No aplica datos de prueba. La contrasena no se escribe.
===============================================================================
#>

param(
    [switch]$SoloDiagnostico,
    [switch]$SoloSiga,
    [switch]$SoloDbsigcm
)

$ErrorActionPreference = "Stop"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path

function Buscar-Archivo([string]$nombre) {
    foreach ($dir in @($aqui, (Join-Path $aqui ".."), (Join-Path $aqui "pase"))) {
        $p = Join-Path $dir $nombre
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    return $null
}

$sqlSiga = Buscar-Archivo "01_SIGA.sql"
$sqlDbs  = Buscar-Archivo "02_DBSIGCM.sql"
if (-not $sqlSiga -or -not $sqlDbs) {
    Write-Host "Faltan 01_SIGA.sql / 02_DBSIGCM.sql. Ejecute antes: .\pase\generar_sql.ps1" -ForegroundColor Red
    exit 1
}
$raiz = Split-Path -Parent $sqlSiga

$archivoParam = Buscar-Archivo "parametros.ps1"
if (-not $archivoParam) {
    Write-Host "Falta parametros.ps1. Copie parametros.ejemplo.ps1 y complete servidor y bases." -ForegroundColor Red
    exit 1
}
. $archivoParam

$Servidor = $ParametrosCalidad.Servidor
$Usuario  = $ParametrosCalidad.Usuario
$Base     = $ParametrosCalidad.Base
$BaseSiga = $ParametrosCalidad.BaseSiga
$LoginApp = $ParametrosCalidad.LoginApp
$Confiar  = [bool]$ParametrosCalidad.Confiar

function Titulo([string]$t) {
    Write-Host ""
    Write-Host ("=" * 75) -ForegroundColor DarkGray
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 75) -ForegroundColor DarkGray
}
function Bien([string]$t) { Write-Host "  [OK] $t" -ForegroundColor Green }
function Mal ([string]$t) { Write-Host "  [ERROR] $t" -ForegroundColor Red }
function Nota([string]$t) { Write-Host "  $t" -ForegroundColor Gray }

Titulo "SIGCM - Pase a calidad"
Nota "Carpeta  : $raiz"
Nota "Servidor : $Servidor"
Nota "SIGCM    : $Base"
Nota "SIGA     : $BaseSiga"
Nota "Login app: $LoginApp"

$cmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $cmd) {
    Mal "sqlcmd no esta en el PATH."
    exit 1
}
Bien "sqlcmd : $($cmd.Source)"

$limpiar = $false
if ($Usuario -ne "") {
    Nota "Usuario SQL : $Usuario"
    $seg = Read-Host "Contrasena de $Usuario" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seg)
    try {
        $env:SQLCMDPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $limpiar = $true
    Bien "Contrasena cargada en el proceso; no queda en el archivo de parametros."
} else {
    Nota "Autenticacion integrada de Windows."
}

$vars = @("bdSiga=$BaseSiga", "bdSigcm=$Base")
if ([string]::IsNullOrWhiteSpace($LoginApp)) {
    $vars += "loginApp=-"
} else {
    $vars += "loginApp=$LoginApp"
}

function Invoke-SqlArchivo([string]$ruta, [string]$baseDestino) {
    $argumentos = @("-S", $Servidor, "-d", $baseDestino, "-b", "-I", "-W", "-s", "|", "-i", $ruta)
    if ($Usuario -ne "") { $argumentos += @("-U", $Usuario) } else { $argumentos += "-E" }
    if ($Confiar) { $argumentos += "-C" }
    foreach ($v in $vars) { $argumentos += @("-v", $v) }
    Write-Host ("  -> {0}  [{1}]" -f (Split-Path $ruta -Leaf), $baseDestino) -ForegroundColor White
    & sqlcmd $argumentos
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo $ruta (exit $LASTEXITCODE)"
    }
}

try {
    if ($SoloDiagnostico) {
        Titulo "Diagnostico (sin instalar)"
        $q = @"
SET NOCOUNT ON;
SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion')) AS motor,
       CONVERT(nvarchar(128), SERVERPROPERTY('Edition')) AS edicion;
SELECT name FROM sys.databases WHERE name IN (N'$BaseSiga', N'$Base') ORDER BY name;
"@
        $argumentos = @("-S", $Servidor, "-d", "master", "-b", "-I", "-W", "-s", "|", "-Q", $q)
        if ($Usuario -ne "") { $argumentos += @("-U", $Usuario) } else { $argumentos += "-E" }
        if ($Confiar) { $argumentos += "-C" }
        & sqlcmd $argumentos
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Nota "Debe aparecer la base SIGA. DBSIGCM puede no existir todavia."
        exit 0
    }

    Titulo "Confirmacion"
    Nota "Se aplicaran 01_SIGA.sql y 02_DBSIGCM.sql (no se borra ninguna base)."
    $r = Read-Host "Continuar? (S/N)"
    if ($r -notmatch '^[SsYy]') {
        Write-Host "  Cancelado." -ForegroundColor Yellow
        exit 0
    }

    if (-not $SoloDbsigcm) {
        Titulo "01_SIGA.sql  (base SIGA)"
        Invoke-SqlArchivo $sqlSiga "master"
        Bien "SIGA: usp_ext_* y GRANT EXECUTE."
    }

    if (-not $SoloSiga) {
        Titulo "02_DBSIGCM.sql  (base DBSIGCM)"
        Invoke-SqlArchivo $sqlDbs "master"
        Bien "DBSIGCM aplicada. C900 debe haber cerrado sin [ERROR]."
    }

    Titulo "Listo"
    Nota "SSO (PostgreSQL), si corresponde:"
    Nota "  .\aplicar_sso.ps1"
    exit 0
}
finally {
    if ($limpiar) { Remove-Item Env:SQLCMDPASSWORD -ErrorAction SilentlyContinue }
}
