@echo off
title ARBORIA ENGINE - Official Project
echo =======================================================
echo          ARBORIA ENGINE - VIRTUAL GEOMETRY
echo =======================================================
echo.

if exist "..\bin\godot.exe" (
    start "" "..\bin\godot.exe" --path "%~dp0project"
) else (
    echo [AVISO] Executavel godot.exe nao encontrado em ..\bin\
    echo Por favor, abra a pasta "project" diretamente pelo Godot 4.
    pause
)
