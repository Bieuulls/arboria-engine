# ARBORIA ENGINE - GATE: BUILD NATIVE (tools/gates/build_native.ps1)
param (
    [string]$Config = "Release"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path "$ScriptDir\..\.."
$NativeDir = "$RepoRoot\native\renderer"
$BuildDir = "$NativeDir\build"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "   ARBORIA GATES - BUILD NATIVO C++ & TESTES UNITARIOS  " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
}

Write-Host "[1/3] Configurando CMake com Ninja e Clang++..." -ForegroundColor Yellow
& cmake -B "$BuildDir" -S "$NativeDir" -G "Ninja" -DCMAKE_CXX_COMPILER=clang++
if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha na configuracao do CMake [Codigo: $LASTEXITCODE]"
    exit $LASTEXITCODE
}

Write-Host "[2/3] Compilando bibliotecas e executaveis nativos..." -ForegroundColor Yellow
& cmake --build "$BuildDir"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha na compilacao [Codigo: $LASTEXITCODE]"
    exit $LASTEXITCODE
}

Write-Host "[3/3] Executando testes unitarios do nucleo nativo..." -ForegroundColor Yellow
$TestExe = "$BuildDir\test_native_core.exe"
$TestMesh = "$RepoRoot\tests\dense_rock_verified.vgmesh"
if (Test-Path $TestExe) {
    & "$TestExe" "$TestMesh"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Falha nos testes unitarios do nucleo nativo [Codigo: $LASTEXITCODE]"
        exit $LASTEXITCODE
    }
} else {
    Write-Error "Executavel de teste nao encontrado: $TestExe"
    exit 1
}

Write-Host "[SUCESSO] Build nativo e testes concluidos com exito!" -ForegroundColor Green
exit 0
