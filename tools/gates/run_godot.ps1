# ARBORIA ENGINE - GATE: RUN GODOT (tools/gates/run_godot.ps1)
param (
    [Parameter(Mandatory=$true)]
    [string]$ScenePath,
    [string]$Stage = "00",
    [int]$TimeoutSeconds = 45,
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path "$ScriptDir\..\.."
$ProjectDir = "$RepoRoot\project"
$GodotBin = "D:\ARBORIA_ENGINE\bin\godot_console.exe"

if (-not (Test-Path $GodotBin)) {
    Write-Error "Godot executavel nao encontrado em: $GodotBin"
    exit 1
}

$ArtifactDir = "$RepoRoot\artifacts\gates\stage_$Stage"
if (-not (Test-Path $ArtifactDir)) {
    New-Item -ItemType Directory -Path $ArtifactDir -Force | Out-Null
}

$LogFile = "$ArtifactDir\godot_run.log"
Write-Host "[RUN GODOT] Executando cena '$ScenePath' (Vulkan Forward+)..." -ForegroundColor Cyan

$CmdArgs = @("--rendering-driver", "vulkan", "--path", "$ProjectDir", "$ScenePath") + $ExtraArgs

$Output = & $GodotBin @CmdArgs 2>&1
$ExitCode = $LASTEXITCODE

if ($Output) {
    [System.IO.File]::WriteAllLines($LogFile, [string[]]$Output)
    foreach ($line in $Output) {
        Write-Host $line
    }
} else {
    [System.IO.File]::WriteAllText($LogFile, "[LOG VAZIO]")
}

$Color = if ($ExitCode -eq 0) { "Green" } else { "Red" }
Write-Host "[RUN GODOT] Finalizado com codigo de saida: $ExitCode (Log: $LogFile)" -ForegroundColor $Color
exit $ExitCode
