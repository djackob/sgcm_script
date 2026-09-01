<#
===============================================================================
  SIGCM - Instalador de la base de datos
===============================================================================

  Aplica la serie completa de scripts en el orden del README, aborta al primer
  error y deja bitacora de todo en _bitacora\.

  Antes de tocar la base verifica el codigo fuente: ningun script puede usar
  construcciones de SQL Server 2025, porque el servidor de desarrollo del ANIN
  es 2022 (16.0.4262.2, medido con C000B el 2026-08-18) y ahi fallarian. El
  equipo local corre 2025, que es mas permisivo; esa diferencia es la que este
  paso impide que se cuele.

  USO
  ---
  Instalacion o actualizacion normal (respeta la base existente):

      .\instalar.ps1

  Rearmar DBSIGCM desde cero y reaplicar las extensiones usp_ext_* en SIGA
  (NO borra la base SIGA; esa es del MEF y se restaura por backup):

      .\instalar.ps1 -Recrear

  Con los usuarios ficticios para probar sin SSO (solo en desarrollo local):

      .\instalar.ps1 -Recrear -ConDatosPrueba

  Solo revisar el codigo fuente, sin conectarse a ninguna base:

      .\instalar.ps1 -SoloVerificar

  Contra otro servidor:

      .\instalar.ps1 -Servidor "192.168.40.75" -Usuario developer_anin

  Si no pasas -Servidor, el instalador prueba 127.0.0.1, localhost y
  localhost\SQLSERVER25 y se queda con la instancia que tenga SIGA_1750.

  Si el sqlcmd de la maquina es version 18 o superior, hace falta -Confiar para
  aceptar el certificado autofirmado del servidor. Para no tener que averiguarlo
  a mano, usa desa.ps1, que lo detecta solo:

      .\desa.ps1

  NOTA SOBRE C002
  ---------------
  C002__acceso_lectura_siga.sql NO forma parte de esta serie. Concede permisos
  DENTRO de la base SIGA y requiere autorizacion del propietario; ademas en
  local no hace falta, porque se trabaja con una cuenta sysadmin. Se ejecuta a
  mano en los entornos donde corresponda.

  NOTA SOBRE SIGA
  ---------------
  Este instalador NO crea ni borra SIGA_1750. Aplica los usp_ext_*.sql de
  SIGA/integracion/ sobre la base SIGA que ya existe (copia restaurada del MEF).
  Si restauras SIGA desde un backup limpio, corre el mismo comando: las
  extensiones vuelven a crearse en el mismo golpe que DBSIGCM.

  Los scripts de usuarios, menus y claves de SIGA (GLUNA, IRIVERA, HBOJORQUEZ)
  viven en SIGA/integracion/solo_desarrollo/ y NUNCA se aplican aqui: son
  solo de la copia local y no pasan a produccion.
===============================================================================
#>

param(
    [string]$Servidor       = "localhost\SQLSERVER25",
    [string]$Base           = "DBSIGCM",
    [string]$BaseSiga       = "SIGA_1750",
    [string]$Usuario        = "",
    [switch]$Recrear,
    [switch]$ConDatosPrueba,
    [switch]$SoloVerificar,
    [switch]$OmitirSigaExt,
    [switch]$Confiar
)

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path

$carpetaBitacora = Join-Path $raiz "_bitacora"
if (-not (Test-Path $carpetaBitacora)) {
    New-Item -ItemType Directory -Path $carpetaBitacora | Out-Null
}
$bitacora = Join-Path $carpetaBitacora ("instalacion_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

$script:pasos   = 0
$script:fallidos = 0

function Escribir([string]$texto, [string]$color = "Gray") {
    Write-Host $texto -ForegroundColor $color
    Add-Content -Path $bitacora -Value $texto -Encoding utf8
}

function Titulo([string]$texto) {
    Escribir ""
    Escribir ("=" * 75) "DarkGray"
    Escribir "  $texto" "Cyan"
    Escribir ("=" * 75) "DarkGray"
}

# ---------------------------------------------------------------------------
# 1. Verificacion del codigo fuente contra la linea base 2022
# ---------------------------------------------------------------------------

# Construcciones que existen en SQL Server 2025 y NO en 2022. Si aparecen en un
# script, la instalacion pasa en el equipo local y falla en desarrollo.
$prohibidas = @(
    @{ patron = 'DECLARE\s+@\w+\s+json\b';              nombre = 'tipo json nativo (variable)' },
    @{ patron = 'RETURNS\s+json\b';                     nombre = 'tipo json nativo (retorno)' },
    @{ patron = '^\s*\[?\w+\]?\s+json\s*(,|\)|NULL|NOT)'; nombre = 'tipo json nativo (columna)' },
    @{ patron = '\bREGEXP_(LIKE|REPLACE|SUBSTR|COUNT|INSTR|MATCHES|SPLIT_TO_TABLE)\s*\('; nombre = 'funciones REGEXP' },
    @{ patron = '\bJSON_(ARRAYAGG|OBJECTAGG)\s*\(';     nombre = 'agregados JSON de 2025' },
    @{ patron = '\bVECTOR_(DISTANCE|NORM|NORMALIZE)\s*\('; nombre = 'funciones de vector' },
    @{ patron = '\bAI_GENERATE_(EMBEDDINGS|CHUNKS)\s*\('; nombre = 'funciones de IA' },
    @{ patron = '\bCREATE\s+EXTERNAL\s+MODEL\b';        nombre = 'modelo externo' }
)

# C000B contiene esas construcciones a proposito: son sus pruebas de capacidad.
$exentos = @("C000B__diagnostico_motor.sql")

# Carpetas con SQL de OTRO motor. La premisa de la regla es "esto corre en SQL
# Server 2022"; un script de PostgreSQL no corre ahi, y ademas usa legitimamente
# construcciones que aqui estan prohibidas -el tipo json, sin ir mas lejos, que
# es lo que devuelve la propia funcion del SSO-. Revisarlos seria comparar contra
# una linea base que no es la suya.
$carpetasExentas = @("sso")

function Verificar-Fuentes {
    Titulo "1. Verificacion del codigo fuente (linea base SQL Server 2022)"

    $archivos = Get-ChildItem -Path $raiz -Filter "*.sql" -Recurse |
                Where-Object { $exentos -notcontains $_.Name } |
                Where-Object {
                    $relativa = $_.FullName.Substring($raiz.Length + 1)
                    $primera  = ($relativa -split '[\\/]')[0]
                    $carpetasExentas -notcontains $primera
                }

    $hallazgos = 0
    foreach ($archivo in $archivos) {
        $contenido = Get-Content -Path $archivo.FullName -Raw
        foreach ($regla in $prohibidas) {
            $coincidencias = [regex]::Matches($contenido, $regla.patron,
                'IgnoreCase, Multiline')
            foreach ($c in $coincidencias) {
                $linea = ($contenido.Substring(0, $c.Index) -split "`n").Count
                $relativa = $archivo.FullName.Substring($raiz.Length + 1)
                Escribir ("  [PROHIBIDO] {0}:{1} -> {2}" -f $relativa, $linea, $regla.nombre) "Red"
                Escribir ("              {0}" -f $c.Value.Trim()) "DarkRed"
                $hallazgos++
            }
        }
    }

    Escribir ("  Archivos revisados : {0}" -f $archivos.Count)
    if ($hallazgos -eq 0) {
        Escribir "  [OK] Ningun script usa construcciones de SQL Server 2025." "Green"
        return $true
    }

    Escribir ("  [ERROR] {0} uso(s) de construcciones que desarrollo (2022) no acepta." -f $hallazgos) "Red"
    return $false
}

# ---------------------------------------------------------------------------
# 2. Ejecucion de un script
# ---------------------------------------------------------------------------

function Ejecutar([string]$ruta, [string]$baseDestino, [string[]]$variables) {
    $script:pasos++
    $relativa = $ruta.Substring($raiz.Length + 1)
    Escribir ("[{0,2}] {1}  ->  [{2}]" -f $script:pasos, $relativa, $baseDestino) "White"

    # -b devuelve codigo de salida distinto de cero al primer error.
    # -I fija QUOTED_IDENTIFIER ON, que los indices filtrados exigen.
    # -W recorta el relleno: sin el, una columna sysname ocupa 128 caracteres y
    #    la bitacora se vuelve ilegible.
    $argumentos = @("-S", $Servidor, "-d", $baseDestino, "-b", "-I", "-W", "-s", "|", "-i", $ruta)
    if ($Usuario -ne "") { $argumentos += @("-U", $Usuario) } else { $argumentos += "-E" }
    # -C acepta el certificado del servidor sin validar la cadena. Hace falta con
    # sqlcmd 18 o superior, que cifra por defecto: contra un servidor con
    # certificado autofirmado -como el de desarrollo- si no se pasa, la conexion
    # ni siquiera se abre. En sqlcmd 11 la opcion no existe.
    if ($Confiar) { $argumentos += "-C" }
    foreach ($v in $variables) { $argumentos += @("-v", $v) }

    $salida = & sqlcmd $argumentos 2>&1 | Out-String
    $codigo = $LASTEXITCODE

    if ($salida.Trim() -ne "") {
        Add-Content -Path $bitacora -Value $salida -Encoding utf8
    }

    if ($codigo -ne 0) {
        $script:fallidos++
        Escribir "     FALLO:" "Red"
        foreach ($linea in ($salida -split "`r?`n")) {
            if ($linea.Trim() -ne "") { Escribir ("     | " + $linea) "Red" }
        }
        return $false
    }

    Escribir "     ok" "DarkGreen"
    return $true
}

# ---------------------------------------------------------------------------
# Arranque
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Arranque
# ---------------------------------------------------------------------------

Titulo "SIGCM - Instalacion de la base de datos"
Escribir ("  Base      : {0}" -f $Base)
Escribir ("  Base SIGA : {0}" -f $BaseSiga)
Escribir ("  Modo      : {0}" -f $(if ($Recrear) { "RECREAR (borra DBSIGCM, no SIGA)" } else { "actualizar" }))
Escribir ("  Bitacora  : {0}" -f $bitacora)

if (-not (Verificar-Fuentes)) {
    Escribir ""
    Escribir "Instalacion cancelada: corrige los usos marcados antes de continuar." "Red"
    exit 1
}

if ($SoloVerificar) {
    Escribir ""
    Escribir "Solo verificacion: no se toco ninguna base." "Yellow"
    exit 0
}

$varSiga = @("bdSiga=$BaseSiga")

function Probar-Instancia([string]$instancia) {
    $argumentos = @("-S", $instancia, "-d", "master", "-b", "-h", "-1", "-W",
                    "-Q", "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name = N'$BaseSiga';")
    if ($Usuario -ne "") { $argumentos += @("-U", $Usuario) } else { $argumentos += "-E" }
    $salida = & sqlcmd $argumentos 2>&1 | Out-String
    return ($LASTEXITCODE -eq 0 -and $salida -match [regex]::Escape($BaseSiga))
}

if (-not $PSBoundParameters.ContainsKey("Servidor")) {
    $candidatos = @("127.0.0.1", "localhost", "localhost\SQLSERVER25", ".")
    $encontrado = $null
    foreach ($candidato in $candidatos) {
        if (Probar-Instancia $candidato) {
            $encontrado = $candidato
            break
        }
    }
    if ($encontrado) {
        $Servidor = $encontrado
    }
    else {
        Escribir ("  [AVISO] No se encontro {0} en 127.0.0.1 / localhost / SQLSERVER25. Se usara {1}." -f $BaseSiga, $Servidor) "Yellow"
    }
}

Escribir ("  Servidor  : {0}" -f $Servidor)

# ---------------------------------------------------------------------------
# 2. Servidor
# ---------------------------------------------------------------------------

Titulo "2. Servidor"

if (-not (Ejecutar (Join-Path $raiz "00_servidor\C000__preflight.sql") "master" $varSiga)) { exit 1 }

if ($Recrear) {
    $c001 = Join-Path $raiz "00_servidor\C001R__recrear_dbsigcm.sql"
    if (-not (Ejecutar $c001 "master" ($varSiga + @("recrear=SI")))) { exit 1 }
} else {
    $c001 = Join-Path $raiz "00_servidor\C001__crear_dbsigcm.sql"
    if (-not (Ejecutar $c001 "master" $varSiga)) { exit 1 }
}

# ---------------------------------------------------------------------------
# 2b. Extensiones dentro de SIGA (usp_ext_*). No se borra SIGA_1750.
# ---------------------------------------------------------------------------

if (-not $OmitirSigaExt) {
    Titulo "2b. Extensiones SIGA (usp_ext_*)"
    $carpetaSigaExt = Join-Path $raiz "SIGA\integracion"
    $sigaExt = @(Get-ChildItem -Path $carpetaSigaExt -Filter "usp_ext_*.sql" -ErrorAction SilentlyContinue |
                 Sort-Object Name)
    if ($sigaExt.Count -eq 0) {
        Escribir "     [ERROR] No hay SIGA/integracion/usp_ext_*.sql." "Red"
        exit 1
    }
    foreach ($archivo in $sigaExt) {
        if (-not (Ejecutar $archivo.FullName $BaseSiga $varSiga)) { exit 1 }
    }
}
else {
    Escribir "  OmitirSigaExt: no se reaplican usp_ext_* sobre $BaseSiga." "Yellow"
}

if (-not (Ejecutar (Join-Path $raiz "00_servidor\C003__sinonimos_siga.sql") $Base $varSiga)) { exit 1 }

# ---------------------------------------------------------------------------
# 3. Migraciones
# ---------------------------------------------------------------------------

Titulo "3. Migraciones (DDL, API, semilla)"

# El orden es el del README: DDL, luego API, luego el escritor SIGA si existe,
# luego la semilla. Dentro de cada bloque manda el numero del archivo.
$patrones = @(
    "db\00_ddl\V*.sql",
    "db\10_api\F*.sql",
    "db\15_siga\W*.sql",
    "db\20_seed\S*.sql"
)

foreach ($patron in $patrones) {
    $ruta = Join-Path $raiz $patron
    $archivos = @(Get-ChildItem -Path $ruta -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($archivos.Count -eq 0) {
        Escribir ("     (sin archivos en {0})" -f $patron) "DarkGray"
        continue
    }
    foreach ($archivo in $archivos) {
        if (-not (Ejecutar $archivo.FullName $Base $varSiga)) { exit 1 }
    }
}

if ($ConDatosPrueba) {
    Titulo "4. Datos de prueba (solo desarrollo local)"
    $prueba = Join-Path $raiz "db\90_pruebas\S900__datos_prueba.sql"
    if (-not (Ejecutar $prueba $Base $varSiga)) { exit 1 }
}

# ---------------------------------------------------------------------------
# 5. Verificacion final
# ---------------------------------------------------------------------------

Titulo "5. Inventario y verificacion"

if (-not (Ejecutar (Join-Path $raiz "00_servidor\C900__inventario.sql") $Base $varSiga)) { exit 1 }

Titulo "Resultado"
Escribir ("  {0} script(s) aplicados, {1} fallido(s)." -f $script:pasos, $script:fallidos) "Green"
Escribir ("  Bitacora completa en {0}" -f $bitacora)
exit 0
