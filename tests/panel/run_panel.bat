@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\.."
cd /d "%REPO_ROOT%"

python tests\panel\panel.py %*
if %ERRORLEVEL% neq 0 (
    echo [ERRO] O painel de testes encerrou com codigo de erro %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

exit /b 0
