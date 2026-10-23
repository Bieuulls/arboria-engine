param([string]$Repo = 'D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL')
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path $Repo)) { throw "Repositorio nao encontrado: $Repo" }
$Target = Join-Path $Repo 'tools\arboria_ai'
if (Test-Path $Target) { throw "Destino ja existe, sem sobrescrita automatica: $Target" }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
Copy-Item -Recurse -Path (Join-Path $Here 'tools\arboria_ai') -Destination $Target
Write-Host "[INSTALADO] $Target" -ForegroundColor Green
Write-Host 'Agora execute no repositorio: python -m tools.arboria_ai.cli status'
Write-Host 'Preencha checks e benchmark no config.json ANTES de usar evaluate/cycle.'
