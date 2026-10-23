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
$GodotBin = $env:GODOT_BIN
if (-not $GodotBin -or -not (Test-Path $GodotBin)) {
    $Candidates = @(
        "$RepoRoot\bin\godot_console.exe",
        "$RepoRoot\bin\godot.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe",
        (Get-Command godot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
    )
    foreach ($c in $Candidates) {
        if ($c -and (Test-Path $c)) {
            $GodotBin = $c
            break
        }
    }
}

if (-not $GodotBin -or -not (Test-Path $GodotBin)) {
    Write-Error "Godot executavel nao encontrado. Defina a variavel GODOT_BIN ou coloque o executavel no PATH."
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
