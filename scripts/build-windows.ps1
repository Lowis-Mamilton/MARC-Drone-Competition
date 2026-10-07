param(
    [string]$GodotPath = (Join-Path $PSScriptRoot '..\.runtime\engine\Godot.exe'),
    [string]$TemplatePath = (Join-Path $PSScriptRoot '..\.runtime\templates\windows_release_x86_64.exe')
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$engine = (Resolve-Path -LiteralPath $GodotPath).Path
$releaseTemplate = (Resolve-Path -LiteralPath $TemplatePath).Path
$expectedTemplate = Join-Path $projectRoot '.runtime\templates\windows_release_x86_64.exe'
New-Item -ItemType Directory -Force -Path (Split-Path $expectedTemplate -Parent) | Out-Null
if ($releaseTemplate -ne $expectedTemplate) { Copy-Item -LiteralPath $releaseTemplate -Destination $expectedTemplate -Force }
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'web\scratch\dependencies.js'))) { throw 'Run npm run build:scratch first.' }
$outputDirectory = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$outputExe = Join-Path $outputDirectory 'MARCDroneSimulator.exe'
$env:GODOT_PATH = $engine
& node (Join-Path $PSScriptRoot 'run-godot.mjs') --headless --editor --import --quit --log-file (Join-Path $projectRoot '.runtime\logs\export-import.log')
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
& node (Join-Path $PSScriptRoot 'run-godot.mjs') --headless --export-release 'Windows Desktop' $outputExe --log-file (Join-Path $projectRoot '.runtime\logs\export.log')
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed.' }
New-Item -ItemType Directory -Force -Path (Join-Path $outputDirectory 'web') | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'web\scratch') -Destination (Join-Path $outputDirectory 'web') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'examples') -Destination $outputDirectory -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $outputDirectory -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $outputDirectory -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $outputDirectory -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs') -Destination $outputDirectory -Recurse -Force
foreach ($artifact in @($outputExe, (Join-Path $outputDirectory 'MARCDroneSimulator.pck'))) {
    if (-not (Test-Path -LiteralPath $artifact)) { throw "Missing build output: $artifact" }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact).Hash.ToLowerInvariant()
    Set-Content -LiteralPath ($artifact + '.sha256') -Value "$hash  $([IO.Path]::GetFileName($artifact))" -Encoding ascii
}
Write-Output "Windows build created: $outputExe"
exit 0
