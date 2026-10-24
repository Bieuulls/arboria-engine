# ARBORIA Validation Lab Setup Script
param (
    [string]$LabPath = "D:\ARBORIA_VALIDATION_LAB"
)

$ErrorActionPreference = "Stop"

Write-Host "===================================================================="
Write-Host "  ARBORIA VALIDATION LAB - CRIANDO AMBIENTE DE ENGENHARIA GRAFICA  "
Write-Host "===================================================================="

$dirs = @(
    $LabPath,
    "$LabPath\scripts",
    "$LabPath\configs",
    "$LabPath\scenes",
    "$LabPath\assets",
    "$LabPath\captures",
    "$LabPath\logs",
    "$LabPath\results",
    "$LabPath\results\baseline",
    "$LabPath\results\debug",
    "$LabPath\results\stress"
)

foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Host " [+] Criado: $d"
    }
}

Write-Host "Diretorios do Laboratorio criados com sucesso em: $LabPath"
