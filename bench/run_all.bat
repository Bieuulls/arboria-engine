@echo off
setlocal enabledelayedexpansion

echo ================================================================
echo   ARBORIA ENGINE — EXECUCAO DA BATERIA DE BENCHMARK REAL
echo ================================================================

set "ROOT_DIR=%~dp0.."
cd /d "%ROOT_DIR%"

python bench\runner.py
if %ERRORLEVEL% neq 0 (
    echo [ERRO] O benchmark retornou codigo de erro: %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

echo ================================================================
echo   BENCHMARK EXECUTADO COM SUCESSO!
echo ================================================================
exit /b 0
