<#
===============================================================================
  SIGCM - Instalacion en el servidor de DESARROLLO del ANIN
===============================================================================

  Un solo paso: diagnostica, y si todo esta en orden, instala.

      .\desa.ps1

  Esta pensado para ejecutarse en una maquina de la red del ANIN (por escritorio
  remoto), donde no se sabe de antemano que version de sqlcmd hay ni si la
  cuenta tiene permiso de escritura. Todo eso lo averigua antes de tocar nada.

  ORDEN DE LO QUE HACE
  --------------------
   1. Comprueba que sqlcmd exista y detecta su version (para saber si hace
      falta -C).
   2. Comprueba que el servidor responda en el puerto 1433.
   3. Pide la contrasena UNA sola vez y la deja en SQLCMDPASSWORD, que es la
      forma que sqlcmd documenta para no ponerla en la linea de comandos. Sin
      esto la serie la pediria 31 veces, una por script.
   4. Corre C000C, que dice si la cuenta puede instalar. Es solo lectura.
   5. Muestra que se va a hacer y pide confirmacion.
   6. Llama a instalar.ps1 en modo actualizacion.

  Nunca pasa -Recrear. Recrear contra desarrollo borra la base compartida y el
  trabajo de los dos; si algun dia hace falta, se hace a mano y de acuerdo con
  el otro.
===============================================================================
#>

param(
    [string]$Servidor = "192.168.40.75",
    [string]$Usuario  = "",
    [switch]$Integrada,
    [switch]$SoloDiagnostico
)

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path

function Titulo([string]$t) {
    Write-Host ""
    Write-Host ("=" * 75) -ForegroundColor DarkGray
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 75) -ForegroundColor DarkGray
}

function Bien([string]$t) { Write-Host "  [OK] $t"    -ForegroundColor Green }
function Mal ([string]$t) { Write-Host "  [ERROR] $t" -ForegroundColor Red }
function Nota([string]$t) { Write-Host "  $t"         -ForegroundColor Gray }

Titulo "SIGCM - Instalacion en desarrollo"
Nota "Servidor : $Servidor"
Nota "Carpeta  : $raiz"

# ---------------------------------------------------------------------------
# 1. sqlcmd
# ---------------------------------------------------------------------------

Titulo "1. Herramientas"

$cmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $cmd) {
    Mal "sqlcmd no esta instalado o no esta en el PATH."
    Nota "Viene con SQL Server Command Line Utilities o con SSMS."
    exit 1
}
Bien "sqlcmd : $($cmd.Source)"

# La version se saca del encabezado de -?, que sqlcmd imprime siempre.
$encabezado = & sqlcmd -? 2>&1 | Select-Object -First 5 | Out-String
$mayor = 0
if ($encabezado -match 'Version\s+(\d+)\.') { $mayor = [int]$Matches[1] }

$confiar = $false
if ($mayor -ge 18) {
    $confiar = $true
    Nota "Version $mayor : cifra por defecto, se usara -C para aceptar el certificado."
} elseif ($mayor -gt 0) {
    Nota "Version $mayor : no cifra por defecto, -C no aplica."
} else {
    Nota "No se pudo leer la version; se asume que -C no hace falta."
}

# ---------------------------------------------------------------------------
# 2. Red
# ---------------------------------------------------------------------------

Titulo "2. Red"

$soloHost = ($Servidor -split '[\\,]')[0]

# Una instancia nombrada (SERVIDOR\INSTANCIA) casi nunca escucha en 1433: usa un
# puerto dinamico que negocia por el SQL Browser. Probar 1433 ahi daria un falso
# error. Desarrollo es instancia por defecto, asi que la prueba si aplica.
if ($Servidor -match '[\\,]') {
    Nota "$Servidor es instancia nombrada o trae puerto: se omite la prueba de 1433."
    $tcp = $null
} else {
    Nota "Probando $soloHost : 1433 ..."
    $tcp = Test-NetConnection $soloHost -Port 1433 -WarningAction SilentlyContinue
}

if ($null -ne $tcp -and -not $tcp.TcpTestSucceeded) {
    Mal "No hay ruta al puerto 1433 de $soloHost desde esta maquina."
    Nota ""
    Nota "Si estas por VPN, es la politica del gateway: la red 192.168.40.0/24"
    Nota "esta cerrada para los perfiles externos. Hay que pedir la regla por"
    Nota "User-ID, no por IP de tunel (la IP cambia entre reconexiones)."
    Nota ""
    Nota "Si estas en una maquina de la red del ANIN y aun asi falla, prueba"
    Nota "desde el otro salto (192.168.40.71)."
    exit 1
}
if ($null -ne $tcp) {
    Bien "El servidor responde en 1433 (origen: $($tcp.SourceAddress))"
}

# ---------------------------------------------------------------------------
# 3. Credenciales
# ---------------------------------------------------------------------------

Titulo "3. Credenciales"

if ($Usuario -eq "" -and $Integrada) {
    Nota "Autenticacion integrada de Windows (-Integrada)."
}
elseif ($Usuario -eq "") {
    Nota "Sin -Usuario se usa autenticacion integrada de Windows."
    Nota "Solo funciona si esta maquina esta en el dominio ANIN."
    $r = Read-Host "Usar autenticacion integrada? (S/N)"
    if ($r -notmatch '^[SsYy]') {
        $Usuario = Read-Host "Usuario SQL"
    }
}

$limpiar = $false
if ($Usuario -ne "") {
    Nota "Usuario : $Usuario"
    $seg = Read-Host "Contrasena de $Usuario" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seg)
    try {
        # SQLCMDPASSWORD es la via documentada por Microsoft: no queda en el
        # historial de PowerShell ni en la bitacora, y vive solo en este proceso.
        $env:SQLCMDPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $limpiar = $true
    Bien "Contrasena cargada en el entorno; no se pedira de nuevo."
}

try {

    # -----------------------------------------------------------------------
    # 4. Permisos
    # -----------------------------------------------------------------------

    Titulo "4. Permisos de la cuenta (solo lectura, no toca nada)"

    $argsPerm = @("-S", $Servidor, "-d", "master", "-b", "-I", "-W",
                  "-i", (Join-Path $raiz "00_servidor\C000C__permisos_instalacion.sql"))
    if ($Usuario -ne "") { $argsPerm += @("-U", $Usuario) } else { $argsPerm += "-E" }
    if ($confiar)        { $argsPerm += "-C" }

    & sqlcmd $argsPerm
    $codigo = $LASTEXITCODE

    if ($codigo -ne 0) {
        Write-Host ""
        Mal "La cuenta no puede instalar la serie, o la conexion fallo."
        Nota "Si el mensaje de arriba habla de permisos, hay que pedirle al DBA"
        Nota "dbcreator, o que cree DBSIGCM vacia y nos de db_owner sobre ella."
        exit 1
    }

    if ($SoloDiagnostico) {
        Write-Host ""
        Write-Host "  Solo diagnostico: no se instalo nada." -ForegroundColor Yellow
        exit 0
    }

    # -----------------------------------------------------------------------
    # 5. Confirmacion
    # -----------------------------------------------------------------------

    Titulo "5. Confirmacion"
    Nota "Se va a aplicar la serie completa sobre DBSIGCM en $Servidor."
    Nota "Modo actualizacion: respeta los datos existentes, NO borra la base."
    Write-Host ""
    $r = Read-Host "Continuar? (S/N)"
    if ($r -notmatch '^[SsYy]') {
        Write-Host "  Cancelado por el usuario." -ForegroundColor Yellow
        exit 0
    }

    # -----------------------------------------------------------------------
    # 6. Instalacion
    # -----------------------------------------------------------------------

    $argsInst = @{ Servidor = $Servidor }
    if ($Usuario -ne "") { $argsInst.Usuario = $Usuario }
    if ($confiar)        { $argsInst.Confiar = $true }

    & (Join-Path $raiz "instalar.ps1") @argsInst
    $codigo = $LASTEXITCODE

    Titulo "Fin"
    if ($codigo -eq 0) {
        Bien "Instalacion terminada."
        Nota "La bitacora quedo en _bitacora\. Si trabajas por escritorio remoto,"
        Nota "copiala a \\tsclient\D\... para poder revisarla desde tu equipo."
    } else {
        Mal "La instalacion fallo. La bitacora de _bitacora\ tiene el detalle."
    }
    exit $codigo

} finally {
    if ($limpiar) { Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue }
}
