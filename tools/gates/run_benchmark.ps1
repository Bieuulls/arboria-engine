# ARBORIA ENGINE — GATE: RUN BENCHMARK (tools/gates/run_benchmark.ps1)
param (
    [string]$ConfigPath = "bench/config.json",
    [string]$Stage = "00",
    [int]$Warmup = 300,
    [int]$Frames = 1000
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path "$ScriptDir\..\.."
$BenchRunner = "$RepoRoot\bench\runner.py"

$ArtifactDir = "$RepoRoot\artifacts\gates\stage_$Stage"
if (-not (Test-Path $ArtifactDir)) {
    New-Item -ItemType Directory -Path $ArtifactDir -Force | Out-Null
}

$LogFile = "$ArtifactDir\benchmark_run.log"
Write-Host "[RUN BENCHMARK] Executando benchmark (Warmup: $Warmup, Frames: $Frames)..." -ForegroundColor Cyan

& python "$BenchRunner" --config "$RepoRoot\$ConfigPath" --warmup $Warmup --frames $Frames *>&1 | Tee-Object -FilePath $LogFile
$ExitCode = $LASTEXITCODE

$Color = if ($ExitCode -eq 0) { "Green" } else { "Red" }
Write-Host "[RUN BENCHMARK] Finalizado com codigo: $ExitCode" -ForegroundColor $Color
exit $ExitCode
