param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$app = Join-Path $projectRoot '.runtime\studio\MARCDroneStudio.exe'
if (Test-Path -LiteralPath $app) {
    Start-Process -FilePath $app -WorkingDirectory (Split-Path $app -Parent) -WindowStyle Normal
} else {
    if ($GodotPath) { $env:GODOT_PATH = $GodotPath }
    & node (Join-Path $projectRoot 'scripts\run-godot.mjs')
}
