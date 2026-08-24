# Enumera el menu del Modulo de Logistica. Solo lee: no ejecuta ninguna opcion.
$src = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class M1 {
  [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetMenuItemCount(IntPtr m);
  [DllImport("user32.dll")] public static extern IntPtr GetSubMenu(IntPtr m, int pos);
  [DllImport("user32.dll")] public static extern int GetMenuItemID(IntPtr m, int pos);
  [DllImport("user32.dll", CharSet=CharSet.Auto)]
  public static extern int GetMenuString(IntPtr m, int id, StringBuilder s, int n, int flags);
}
"@
if (-not ("M1" -as [type])) { Add-Type -TypeDefinition $src }

$p = Get-Process -Name logistica -ErrorAction SilentlyContinue
if (-not $p) { Write-Output "Logistica no esta abierto."; exit 1 }
$h = $p.MainWindowHandle
$menu = [M1]::GetMenu($h)
if ($menu -eq [IntPtr]::Zero) { Write-Output "La ventana no expone menu por API."; exit 1 }

function Recorrer([IntPtr]$m, [string]$ruta, [int]$nivel) {
  $n = [M1]::GetMenuItemCount($m)
  for ($i = 0; $i -lt $n; $i++) {
    $sb = New-Object System.Text.StringBuilder 256
    [void][M1]::GetMenuString($m, $i, $sb, 256, 0x400)   # MF_BYPOSITION
    $texto = $sb.ToString() -replace '&',''
    if ([string]::IsNullOrWhiteSpace($texto)) { continue }
    $sub = [M1]::GetSubMenu($m, $i)
    $id  = [M1]::GetMenuItemID($m, $i)
    $completo = if ($ruta) { "$ruta > $texto" } else { $texto }
    if ($sub -ne [IntPtr]::Zero) {
      if ($nivel -lt 3) { Recorrer $sub $completo ($nivel + 1) }
    } else {
      Write-Output ("id={0,-6} pos={1,-3} {2}" -f $id, $i, $completo)
    }
  }
}

Write-Output "--- opciones del menu ---"
Recorrer $menu "" 0
