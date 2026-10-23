@echo off
setlocal
title ARBORIA ENGINE — ANALYTICAL VIEWER
cd /d "%~dp0project"

set "GODOT_EXEC="
if defined GODOT_BIN if exist "%GODOT_BIN%" set "GODOT_EXEC=%GODOT_BIN%"
if not defined GODOT_EXEC if exist "%~dp0bin\godot.exe" set "GODOT_EXEC=%~dp0bin\godot.exe"
if not defined GODOT_EXEC if exist "%~dp0bin\godot_console.exe" set "GODOT_EXEC=%~dp0bin\godot_console.exe"
if not defined GODOT_EXEC if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" set "GODOT_EXEC=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
if not defined GODOT_EXEC set "GODOT_EXEC=godot"

start "" "%GODOT_EXEC%" --rendering-driver vulkan scenes/main_viewer.tscn
exit /b 0
