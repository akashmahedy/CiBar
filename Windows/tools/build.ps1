param([string]$Configuration = 'Release', [switch]$Smoke)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $root 'outputs/windows-build'
cmake -S (Join-Path $root 'Windows') -B $build -A x64
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed' }
cmake --build $build --config $Configuration --parallel
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
ctest --test-dir $build -C $Configuration --output-on-failure
if ($LASTEXITCODE -ne 0) { throw 'Core tests failed' }
if ($Smoke) {
    $data = Join-Path $build 'smoke-data'
    $app = Join-Path $build "$Configuration/CiBar.exe"
    $proc = Start-Process $app -ArgumentList @('--smoke-test', '--data-dir', "`"$data`"") -PassThru
    if (-not $proc.WaitForExit(30000)) { $proc.Kill(); throw 'GUI smoke did not exit within 30 seconds' }
    if ($proc.ExitCode -ne 0) { throw "GUI smoke failed with exit code $($proc.ExitCode)" }
    Get-Content (Join-Path $data 'smoke-result.json')
}
