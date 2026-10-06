@echo off
chcp 65001 >nul 2>&1
title 启用虚拟屏幕
cd /d "%~dp0"

net session >nul 2>&1
if errorlevel 1 (
    echo 正在申请管理员权限...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp00-start-display.ps1"
pause
