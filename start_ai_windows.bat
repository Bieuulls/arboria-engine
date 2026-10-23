@echo off
setlocal
set REPO=D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL
if not exist "%REPO%\tools\arboria_ai\cli.py" (
  echo ERRO: execute INSTALL_WINDOWS.ps1 primeiro.
  exit /b 1
)
cd /d "%REPO%"
python -m tools.arboria_ai.cli status
if errorlevel 1 exit /b %errorlevel%
echo.
echo Defina o modelo no tools\arboria_ai\config.json e execute 'propose' ou 'cycle'.
