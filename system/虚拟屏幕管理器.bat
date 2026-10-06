@echo off
chcp 65001 >nul 2>&1
title 虚拟屏幕管理器
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
    echo 正在申请管理员权限...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0manage-vdd.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0manage-vdd.ps1" %*
    pause
)
