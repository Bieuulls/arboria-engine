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

where cl >nul 2>nul
if %ERRORLEVEL% neq 0 (
    where clang++ >nul 2>nul
    if %ERRORLEVEL% neq 0 (
        set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Packages\MartinStorsjo.LLVM-MinGW.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\llvm-mingw-20260616-ucrt-x86_64\bin;%LOCALAPPDATA%\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe;%PATH%"
    )
)

echo [1/4] Compilando ARBORIA Baker (tools/baker)...
where ninja >nul 2>nul
if %ERRORLEVEL% equ 0 (
    cmake -G Ninja -B tools/baker/build -S tools/baker -DCMAKE_BUILD_TYPE=Release
) else (
    cmake -B tools/baker/build -S tools/baker -DCMAKE_BUILD_TYPE=Release
)
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Falha ao configurar CMake para o Baker!
    exit /b 1
)
cmake --build tools/baker/build --config Release
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Falha ao compilar o Baker!
    exit /b 1
)

echo [1.5/4] Gerando malhas virtuais de referencia (.vgmesh) via Baker...
if not exist "assets" mkdir "assets"
if not exist "project\assets" mkdir "project\assets"

set "BAKER_EXE=bin\arboria_baker_cli.exe"
if not exist "%BAKER_EXE%" set "BAKER_EXE=bin\vg_baker_cli.exe"

if exist "%BAKER_EXE%" (
    if exist "assets\dense_rock_test.obj" (
        "%BAKER_EXE%" assets\dense_rock_test.obj assets\dense_rock.vgmesh
        copy /Y assets\dense_rock.vgmesh assets\dense_rock_verified.vgmesh >nul
        copy /Y assets\dense_rock.vgmesh project\assets\dense_rock.vgmesh >nul
        copy /Y assets\dense_rock.vgmesh project\assets\dense_rock_test.vgmesh >nul
        copy /Y assets\dense_rock.vgmesh project\assets\dense_rock_verified.vgmesh >nul
    )
    if exist "assets\boulder_granite.obj" (
        "%BAKER_EXE%" assets\boulder_granite.obj assets\boulder_granite.vgmesh
        copy /Y assets\boulder_granite.vgmesh project\assets\boulder_granite.vgmesh >nul
    )
    if exist "assets\pine_trunk_complex.obj" (
        "%BAKER_EXE%" assets\pine_trunk_complex.obj assets\pine_trunk_complex.vgmesh
        copy /Y assets\pine_trunk_complex.vgmesh project\assets\pine_trunk_complex.vgmesh >nul
    )
    if exist "assets\small_mesh_test.obj" (
        "%BAKER_EXE%" assets\small_mesh_test.obj assets\small_mesh.vgmesh
        copy /Y assets\small_mesh.vgmesh project\assets\small_mesh.vgmesh >nul
    )
    if exist "assets\rock_cluster.obj" (
        "%BAKER_EXE%" assets\rock_cluster.obj project\assets\rock_cluster_baked.vgmesh
    )
) else (
    echo [AVISO] Executavel do Baker nao encontrado para pre-bake de malhas.
)

echo [2/4] Compilando ARBORIA Native Core e GDExtension (native/renderer)...
where ninja >nul 2>nul
if %ERRORLEVEL% equ 0 (
    cmake -G Ninja -B native/renderer/build -S native/renderer -DCMAKE_BUILD_TYPE=Release
) else (
    cmake -B native/renderer/build -S native/renderer -DCMAKE_BUILD_TYPE=Release
)
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
if not exist "bin\arboria_baker_cli.exe" if not exist "bin\vg_baker_cli.exe" (
    echo [ERRO] bin\arboria_baker_cli.exe nao foi gerado!
    exit /b 1
)
if not exist "project\bin\libarboria_native.dll" (
    echo [ERRO] project\bin\libarboria_native.dll nao foi gerado!
    exit /b 1
)

if not exist "addons\arboria\bin" mkdir "addons\arboria\bin"
copy /Y "project\bin\libarboria_native.dll" "addons\arboria\bin\" >nul

echo [Extra] Sincronizando assets/ com project/assets/ para o Godot...
if not exist "project\assets" mkdir "project\assets"
for %%f in (assets\*.vgmesh) do (
    copy /Y "%%f" "project\assets\" >nul
)
for %%f in (assets\*.obj) do (
    copy /Y "%%f" "project\assets\" >nul
)

echo [Extra 2] Indexando projeto e classes do Godot (.godot cache)...
set "GODOT_EXE="
if defined GODOT_BIN if exist "%GODOT_BIN%" set "GODOT_EXE=%GODOT_BIN%"
if not defined GODOT_EXE if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" set "GODOT_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
if not defined GODOT_EXE if exist "bin\godot_console.exe" set "GODOT_EXE=bin\godot_console.exe"
if not defined GODOT_EXE (
    where godot_console.exe >nul 2>nul && set "GODOT_EXE=godot_console.exe"
)
if not defined GODOT_EXE (
    where godot.exe >nul 2>nul && set "GODOT_EXE=godot.exe"
)

if defined GODOT_EXE (
    "%GODOT_EXE%" --headless --editor --quit --path project >nul 2>nul
) else (
    echo [AVISO] Executavel do Godot nao encontrado para pre-indexacao.
)

echo ================================================================
echo   BUILD CONCLUIDO COM SUCESSO E REPRODUZIVEL!
echo ================================================================
exit /b 0
