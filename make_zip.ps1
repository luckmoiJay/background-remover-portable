$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$zipName = "background-remover-portable.zip"
$zipPath = Join-Path $PSScriptRoot $zipName
$staging = Join-Path $env:TEMP ("background-remover-portable-" + [guid]::NewGuid().ToString("N"))

if (Test-Path $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

New-Item -ItemType Directory -Path $staging | Out-Null

$items = @(
    "app.py",
    "requirements.txt",
    "run.ps1",
    "啟動去背工具.bat",
    "static",
    "templates",
    ".gitignore",
    "README.md"
)

foreach ($item in $items) {
    $source = Join-Path $PSScriptRoot $item
    if (Test-Path $source) {
        Copy-Item -LiteralPath $source -Destination $staging -Recurse
    }
}

Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $staging -Recurse -Force

Write-Host "Created: $zipPath" -ForegroundColor Green
Write-Host "Move this zip to the new computer, unzip it, then run run.ps1." -ForegroundColor Cyan
