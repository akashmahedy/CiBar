param([string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $root 'outputs/windows-build'
$release = Join-Path $root 'outputs/windows-release'
if (Test-Path $release) { Remove-Item $release -Recurse -Force }
New-Item -ItemType Directory -Force $release | Out-Null
Copy-Item (Join-Path $build "$Configuration/CiBar.exe") (Join-Path $release 'CiBar.exe') -Force
New-Item -ItemType Directory -Force (Join-Path $release 'Resources') | Out-Null
foreach ($name in @('words.json','ATTRIBUTIONS.txt','DATA-REVIEW.json','HSK4-CORRECTIONS-REVIEW.json')) {
    Copy-Item (Join-Path $root "Resources/$name") (Join-Path $release "Resources/$name") -Force
}
Copy-Item (Join-Path $root 'LICENSE') $release -Force
Copy-Item (Join-Path $root 'Windows/VERIFICATION.md') $release -Force
Copy-Item (Join-Path $root 'Windows/README.md') (Join-Path $release 'START-HERE.md') -Force
Copy-Item (Join-Path $root 'Windows/vendor/nlohmann/LICENSE.MIT') (Join-Path $release 'JSON-LICENSE.MIT') -Force
$archive = Join-Path $root 'outputs/CiBar-Windows-x64.zip'
# Explicit allowlist. Never read or package LOCALAPPDATA or exported backups.
$items = @((Join-Path $release 'CiBar.exe'), (Join-Path $release 'Resources'), (Join-Path $release 'LICENSE'), (Join-Path $release 'START-HERE.md'), (Join-Path $release 'JSON-LICENSE.MIT'), (Join-Path $release 'VERIFICATION.md'))
Compress-Archive -Path $items -DestinationPath $archive -Force
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content (Join-Path $root 'outputs/CiBar-Windows-SHA256SUMS.txt') "$hash  CiBar-Windows-x64.zip" -Encoding utf8
Write-Host "Created $archive; personal state excluded."
