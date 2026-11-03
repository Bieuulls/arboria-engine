@echo off
setlocal
title ARBORIA ENGINE - MASSIVE WORLD DEMO
cd /d "%~dp0project"

set "GODOT_EXEC="
if defined GODOT_BIN if exist "%GODOT_BIN%" set "GODOT_EXEC=%GODOT_BIN%"
if not defined GODOT_EXEC if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" set "GODOT_EXEC=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
if not defined GODOT_EXEC set "GODOT_EXEC=godot"

echo ================================================================
echo       ARBORIA ENGINE - MASSIVE WORLD DEMO
echo       Geometria Virtualizada para Godot 4 (Forward+ / Vulkan 1.4)
echo ================================================================

start "ARBORIA ENGINE" "%GODOT_EXEC%" --path "%~dp0project" res://scenes/arboria_massive_world_demo.tscn
exit /b 0
