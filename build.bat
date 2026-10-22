@echo off
setlocal enabledelayedexpansion

echo ================================================================
echo   ARBORIA ENGINE — SISTEMA DE BUILD REPRODUZIVEL (Windows)
echo ================================================================

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

where cmake >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERRO] CMake nao encontrado no PATH!
    exit /b 1
)

echo [1/4] Compilando ARBORIA Baker (tools/baker)...
cmake -B tools/baker/build -S tools/baker -DCMAKE_BUILD_TYPE=Release
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Falha ao configurar CMake para o Baker!
    exit /b 1
)
cmake --build tools/baker/build --config Release
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Falha ao compilar o Baker!
    exit /b 1
)

echo [2/4] Compilando ARBORIA Native Core e GDExtension (native/renderer)...
cmake -B native/renderer/build -S native/renderer -DCMAKE_BUILD_TYPE=Release
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Falha ao configurar CMake para o nucleo nativo!
    exit /b 1
)
cmake --build native/renderer/build --config Release
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Falha ao compilar o nucleo nativo!
    exit /b 1
)

echo [3/4] Executando Testes Unitarios C++ (CTest)...
ctest --test-dir native/renderer/build --output-on-failure
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Testes unitarios do nucleo nativo falharam!
    exit /b 1
)

echo [4/4] Verificando Artefatos Gerados...
if not exist "bin\vg_baker_cli.exe" (
    echo [ERRO] bin\vg_baker_cli.exe nao foi gerado!
    exit /b 1
)
if not exist "project\bin\libarboria_native.dll" (
    echo [ERRO] project\bin\libarboria_native.dll nao foi gerado!
    exit /b 1
)

echo ================================================================
echo   BUILD CONCLUIDO COM SUCESSO E REPRODUZIVEL!
echo ================================================================
exit /b 0
