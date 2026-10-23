@echo off
setlocal enabledelayedexpansion

echo ====================================================================
echo   ARBORIA VIRTUAL GEOMETRY - INSTALADOR DE ADDON PARA GODOT 4
echo ====================================================================

set "TARGET_DIR=%~1"

if "%TARGET_DIR%"=="" (
    echo.
    echo [ERRO] Nenhum diretorio de destino informado.
    echo Uso:
    echo   install_addon.bat ^<caminho_do_seu_projeto_godot^>
    echo.
    echo Exemplo:
    echo   install_addon.bat "C:\Projetos\MeuJogoGodot"
    echo.
    pause
    exit /b 1
)

if not exist "%TARGET_DIR%\project.godot" (
    echo.
    echo [AVISO] Nao foi encontrado 'project.godot' em "%TARGET_DIR%".
    echo Certifique-se de apontar para a pasta raiz do seu projeto Godot 4.
    set /p CONFIRM="Deseja continuar mesmo assim? (S/N): "
    if /i not "!CONFIRM!"=="S" (
        echo Instalacao cancelada.
        exit /b 1
    )
)

set "SOURCE_ADDON=%~dp0addons\arboria"
set "DEST_ADDON=%TARGET_DIR%\addons\arboria"

echo.
echo [1/3] Copiando arquivos do plugin para "%DEST_ADDON%"...
xcopy /E /I /Y /Q "%SOURCE_ADDON%" "%DEST_ADDON%" >nul
if errorlevel 1 (
    echo [ERRO] Falha ao copiar a pasta do addon.
    exit /b 1
)

echo [2/3] Verificando binario nativo GDExtension...
if exist "%~dp0project\bin\libarboria_native.dll" (
    copy /Y "%~dp0project\bin\libarboria_native.dll" "%DEST_ADDON%\bin\" >nul
    echo   - DLL nativa Windows copiada com sucesso para addons/arboria/bin/.
) else if exist "%~dp0bin\libarboria_native.dll" (
    copy /Y "%~dp0bin\libarboria_native.dll" "%DEST_ADDON%\bin\" >nul
    echo   - DLL nativa Windows copiada com sucesso para addons/arboria/bin/.
) else (
    echo   - AVISO: Binario libarboria_native.dll nao encontrado localmente.
    echo     Execute build.bat primeiro ou baixe a release compilada.
)

echo [3/3] Concluindo instalacao...
echo.
echo ====================================================================
echo [SUCESSO] ARBORIA instalado com sucesso no seu projeto!
echo.
echo Para ativar no editor:
echo   1. Abra o projeto no Godot 4.
echo   2. Acesse: Project Settings -^> Plugins
echo   3. Marque a opcao 'Enable' no plugin 'Arboria Virtual Geometry'.
echo ====================================================================
