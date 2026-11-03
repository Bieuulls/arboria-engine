@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo   ARBORIA ENGINE - COMPILADOR DO NUCLEO NATIVO C++
echo ========================================================

set ROOT_DIR=%~dp0
if "%ROOT_DIR:~-1%"=="\" set ROOT_DIR=%ROOT_DIR:~0,-1%
set BUILD_DIR=%ROOT_DIR%\build

if not exist "%BUILD_DIR%" (
    mkdir "%BUILD_DIR%"
)

echo [1/3] Configurando CMake com compilador Clang++ e Ninja...
cmake -B "%BUILD_DIR%" -S "%ROOT_DIR%" -G "Ninja" -DCMAKE_CXX_COMPILER=clang++
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Falha na configuracao do CMake.
    exit /b %ERRORLEVEL%
)

echo [2/3] Compilando bibliotecas e binarios nativos...
cmake --build "%BUILD_DIR%"
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Falha na compilacao.
    exit /b %ERRORLEVEL%
)

echo [3/3] Executando testes unitarios do nucleo nativo...
"%BUILD_DIR%\test_native_core.exe" "%ROOT_DIR%\..\..\tests\dense_rock_verified.vgmesh"
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Falha nos testes unitarios.
    exit /b %ERRORLEVEL%
)

echo ========================================================
echo   COMPILACAO E TESTES CONCLUIDOS COM SUCESSO!
echo   Artefatos gerados em: %BUILD_DIR%
echo ========================================================
