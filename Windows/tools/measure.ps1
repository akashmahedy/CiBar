param([Parameter(Mandatory=$true)][int]$ProcessId, [int]$DurationSeconds=300, [string]$Output='CiBar-Windows-performance.json')
$ErrorActionPreference='Stop'
if ($DurationSeconds -lt 10) { throw 'Use at least 10 seconds; use 300 for acceptance.' }
$proc=Get-Process -Id $ProcessId
$clock=[Diagnostics.Stopwatch]::StartNew()
$previous=$proc.TotalProcessorTime.TotalSeconds
$previousElapsed=0.0
$samples=@()
while ($clock.Elapsed.TotalSeconds -lt $DurationSeconds) {
    Start-Sleep -Seconds 5
    $proc=Get-Process -Id $ProcessId
    $elapsed=$clock.Elapsed.TotalSeconds
    $cpu=100*($proc.TotalProcessorTime.TotalSeconds-$previous)/($elapsed-$previousElapsed)
    $memory=Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "IDProcess=$ProcessId"
    if (-not $memory) { throw 'Private working-set counter unavailable; no memory result claimed.' }
    $samples+= [ordered]@{elapsedSeconds=[math]::Round($elapsed,3);cpuPercentOneCore=[math]::Round($cpu,3);privateWorkingSetMiB=[math]::Round($memory.WorkingSetPrivate/1MB,3)}
    $previous=$proc.TotalProcessorTime.TotalSeconds
    $previousElapsed=$elapsed
}
$os=Get-CimInstance Win32_OperatingSystem
$cpuInfo=Get-CimInstance Win32_Processor | Select-Object -First 1
$report=[ordered]@{date=(Get-Date -Format o);os=$os.Caption;build=$os.BuildNumber;cpu=$cpuInfo.Name;processId=$ProcessId;elapsedSeconds=$clock.Elapsed.TotalSeconds;cpuPercentIsOneCore=$true;memoryMetric='private working set';meanCPU=($samples.cpuPercentOneCore|Measure-Object -Average).Average;peakCPU=($samples.cpuPercentOneCore|Measure-Object -Maximum).Maximum;meanPrivateWorkingSetMiB=($samples.privateWorkingSetMiB|Measure-Object -Average).Average;peakPrivateWorkingSetMiB=($samples.privateWorkingSetMiB|Measure-Object -Maximum).Maximum;samples=$samples}
$report | ConvertTo-Json -Depth 8 | Set-Content $Output -Encoding utf8
Write-Host "Saved $Output. This measures app CPU/private working set, not GPU power."
