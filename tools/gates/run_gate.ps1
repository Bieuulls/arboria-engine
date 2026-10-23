# ARBORIA ENGINE - MASTER GATE RUNNER (tools/gates/run_gate.ps1)
param (
    [Parameter(Mandatory=$true)]
    [string]$Stage,
    [switch]$SkipBuild = $false,
    [switch]$SkipRuntime = $false
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path "$ScriptDir\..\.."
$StageStr = "{0:D2}" -f [int]$Stage
$ArtifactDir = "$RepoRoot\artifacts\gates\stage_$StageStr"

if (-not (Test-Path $ArtifactDir)) {
    New-Item -ItemType Directory -Path $ArtifactDir -Force | Out-Null
}

Write-Host "========================================================" -ForegroundColor Magenta
Write-Host "       ARBORIA ENGINE - PROTOCOLO DE GATE $StageStr     " -ForegroundColor Magenta
Write-Host "========================================================" -ForegroundColor Magenta

$BuildStatus = "NOT_RUN"
$RuntimeStatus = "NOT_RUN"
$GeometryStatus = "NOT_RUN"
$GpuStatus = "NOT_RUN"
$RegressionsStatus = "NOT_RUN"
$GateStatus = "FAILED"
$EvidenceFiles = @()
$BlockingErrors = @()

# 1. VERIFICACAO DE BUILD
if (-not $SkipBuild) {
    Write-Host "`n[PASSO 1/4] Verificando Compilacao Nativa e Testes Unitarios C++..." -ForegroundColor Yellow
    try {
        & "$ScriptDir\build_native.ps1"
        if ($LASTEXITCODE -eq 0) {
            $BuildStatus = "PASSED"
        } else {
            $BuildStatus = "FAILED"
            $BlockingErrors += "Falha na compilacao nativa C++ [Codigo: $LASTEXITCODE]"
        }
    } catch {
        $BuildStatus = "FAILED"
        $BlockingErrors += "Excecao durante o build: $_"
    }
} else {
    $BuildStatus = "SKIPPED"
}

# 2. SELECAO DA CENA DO STAGE
$SceneMap = @{
    "00" = "scenes/test_arboria_native_demo.tscn"
    "01" = "scenes/test_arboria_gpu_scene_global.tscn"
    "02" = "scenes/test_arboria_gate02_grouped_submission.tscn"
    "03" = "scenes/test_arboria_native_demo.tscn"
    "04" = "scenes/test_arboria_native_demo.tscn"
    "05" = "scenes/test_arboria_hiz_occlusion.tscn"
    "06" = "scenes/test_arboria_dag_integrity.tscn"
    "07" = "scenes/test_arboria_vram_streaming.tscn"
    "08" = "scenes/test_arboria_asset_import_workflow.tscn"
    "09" = "scenes/arboria_massive_world_demo.tscn"
    "10" = "scenes/test_arboria_native_demo.tscn"
    "11" = "scenes/arboria_massive_world_demo.tscn"
    "12" = "scenes/arboria_massive_world_demo.tscn"
    "13" = "scenes/test_arboria_native_demo.tscn"
    "14" = "scenes/test_arboria_native_demo.tscn"
}

$TargetScene = $SceneMap[$StageStr]
if (-not $TargetScene) {
    $TargetScene = "scenes/test_arboria_native_demo.tscn"
}

# 3. VERIFICACAO DE RUNTIME GODOT NO HARDWARE
if (-not $SkipRuntime -and $BuildStatus -ne "FAILED") {
    Write-Host "`n[PASSO 2/4] Executando Godot Forward+ / Vulkan para o Stage $StageStr ($TargetScene)..." -ForegroundColor Yellow
    try {
        & "$ScriptDir\run_godot.ps1" -ScenePath $TargetScene -Stage $StageStr -TimeoutSeconds 40
        if ($LASTEXITCODE -eq 0) {
            $RuntimeStatus = "PASSED"
        } else {
            $RuntimeStatus = "FAILED"
            $BlockingErrors += "Godot encerrou com codigo de erro: $LASTEXITCODE"
        }
    } catch {
        $RuntimeStatus = "FAILED"
        $BlockingErrors += "Excecao ao executar Godot: $_"
    }

    $LogPath = "$ArtifactDir\godot_run.log"
    if (Test-Path $LogPath) {
        $EvidenceFiles += $LogPath

        # Validacao de Metricas Operacionais
        Write-Host "`n[PASSO 3/4] Validando Metricas Operacionais a partir dos Logs..." -ForegroundColor Yellow
        & python "$ScriptDir\validate_metrics.py" "$LogPath" --max-errors 2
        if ($LASTEXITCODE -eq 0) {
            $GpuStatus = "PASSED"
        } else {
            $GpuStatus = "FAILED"
            $BlockingErrors += "Validacao de metricas de telemetria falhou"
        }

        # Validacao de Recursos / Leaks
        Write-Host "`n[PASSO 4/4] Validando Recursos GPU e Ausencia de Vazamentos..." -ForegroundColor Yellow
        & python "$ScriptDir\validate_resources.py" "$LogPath" --max-leaks 60
        if ($LASTEXITCODE -eq 0) {
            $RegressionsStatus = "PASSED"
        } else {
            $RegressionsStatus = "FAILED"
            $BlockingErrors += "Validacao de recursos GPU falhou"
        }
    }
}

# Verificacao de Imagens Capturadas
$ImageEvidence = @(
    "$RepoRoot\project\diag_arboria_native_demo_frame.png",
    "$RepoRoot\project\diag_arboria_hiz_occlusion.png",
    "$RepoRoot\project\diag_arboria_dag_integrity.png",
    "$RepoRoot\project\diag_arboria_pbr_side_by_side.png",
    "$RepoRoot\project\diag_arboria_gpu_scene_global.png",
    "$RepoRoot\project\diag_arboria_gate02_baseline.png",
    "$RepoRoot\project\diag_arboria_gate02_grouped.png",
    "$RepoRoot\project\diag_arboria_vram_streaming.png",
    "$RepoRoot\project\diag_arboria_asset_import.png"
)

foreach ($img in $ImageEvidence) {
    if (Test-Path $img) {
        $DestImg = "$ArtifactDir\" + (Split-Path -Leaf $img)
        Copy-Item -Path $img -Destination $DestImg -Force
        $EvidenceFiles += $DestImg
        $GeometryStatus = "PASSED"
    }
}

# Status Final do Gate
if ($BuildStatus -eq "PASSED" -and $RuntimeStatus -eq "PASSED" -and $BlockingErrors.Count -eq 0) {
    $GateStatus = "PASSED"
} else {
    $GateStatus = "FAILED"
}

# Gerar JSON Oficial de Evidencia
Write-Host "`n========================================================" -ForegroundColor Magenta
Write-Host "        CONSOLIDANDO RELATORIO DO GATE $StageStr        " -ForegroundColor Magenta
Write-Host "========================================================" -ForegroundColor Magenta

$EvArgs = @(
    "--stage", $StageStr,
    "--status", $GateStatus,
    "--build", $BuildStatus,
    "--runtime", $RuntimeStatus,
    "--geometry", $GeometryStatus,
    "--gpu", $GpuStatus,
    "--regressions", $RegressionsStatus
)

if ($EvidenceFiles.Count -gt 0) {
    $EvArgs += @("--evidence") + $EvidenceFiles
}
if ($BlockingErrors.Count -gt 0) {
    $EvArgs += @("--blocking-errors") + $BlockingErrors
}

& python "$ScriptDir\generate_evidence.py" @EvArgs

if ($GateStatus -eq "PASSED") {
    Write-Host "`n[GATE $StageStr APROVADO] Todos os criterios foram atendidos com sucesso!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[GATE $StageStr REPROVADO] Pendencias bloqueantes identificadas!" -ForegroundColor Red
    exit 1
}
