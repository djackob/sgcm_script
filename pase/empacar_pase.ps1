<#
===============================================================================
  Arma el zip que se envia al operador de calidad.
  Contenido: 3 SQL (uno por base) + instrucciones. Sin claves ni pruebas.
===============================================================================
#>

$ErrorActionPreference = "Stop"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = (Resolve-Path (Join-Path $aqui "..")).Path
$stamp = Get-Date -Format "yyyyMMdd"
$nombre = "sigcm_pase_calidad_$stamp"
$destino = Join-Path ([IO.Path]::GetTempPath()) $nombre

Write-Host "Generando 01_SIGA.sql / 02_DBSIGCM.sql / 03_SSO.sql ..."
& (Join-Path $aqui "generar_sql.ps1") | Out-Null

foreach ($f in @("01_SIGA.sql", "02_DBSIGCM.sql", "03_SSO.sql")) {
    if (-not (Test-Path (Join-Path $aqui $f))) {
        throw "No se genero $f"
    }
}

if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
New-Item -ItemType Directory -Path $destino | Out-Null

$copiar = @(
    "LEEME.md",
    "CHECKLIST.md",
    "parametros.ejemplo.ps1",
    "instalar_calidad.ps1",
    "aplicar_sso.ps1",
    "01_SIGA.sql",
    "02_DBSIGCM.sql",
    "03_SSO.sql"
)
foreach ($f in $copiar) {
    Copy-Item (Join-Path $aqui $f) (Join-Path $destino $f)
}

$lineas = @(
    "SIGCM - manifiesto del pase a calidad",
    ("Generado: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm")),
    "Un archivo .sql por base. Sin contrasenas, S900, Recrear ni API/front.",
    "",
    "Orden de ejecucion:",
    "  1. 01_SIGA.sql      (base SIGA, no la recrea)",
    "  2. 02_DBSIGCM.sql   (crea DBSIGCM si falta; no la borra)",
    "  3. 03_SSO.sql       (PostgreSQL, opcional)",
    "",
    "Contenido:"
)
Get-ChildItem $destino -File | Sort-Object Name | ForEach-Object {
    $lineas += ("  {0,10}  {1}" -f $_.Length, $_.Name)
}
$lineas += ""
$lineas += ("Total archivos: {0}" -f @(Get-ChildItem $destino -File).Count)
$lineas | Set-Content -Path (Join-Path $destino "MANIFIESTO.txt") -Encoding utf8

$dirBit = Join-Path $raiz "_bitacora"
if (-not (Test-Path $dirBit)) { New-Item -ItemType Directory -Path $dirBit | Out-Null }
$zip = Join-Path $dirBit ($nombre + ".zip")
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $destino "*") -DestinationPath $zip -Force
Remove-Item $destino -Recurse -Force

Write-Host "Paquete listo:" -ForegroundColor Green
Write-Host "  $zip"
