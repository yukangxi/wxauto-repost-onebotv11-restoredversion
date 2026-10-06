@echo off
title 微信机器人守护工具
setlocal EnableExtensions EnableDelayedExpansion
set "STATE=%TEMP%\bot_guard.state"

rem ===== 自动提权 =====
net session >nul 2>&1
if errorlevel 1 (
    echo 正在申请管理员权限...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

rem ===== 记录"我在哪个会话"（只认 ID，最可靠）=====
call :getsid
set "MYSID=!SID!"

:menu
cls
echo ==================================================
echo            微信机器人守护工具
echo ==================================================
echo.
echo   [当前会话]
query session
echo.
echo   ------------------------------------------------
echo    本脚本所在会话 ID : !MYSID!
echo   ------------------------------------------------
echo.
echo    [1] 一键修复 + 守护
echo        把会话推到控制台（桌面才会渲染），
echo        然后每 60 秒自检；被顶掉第 1 次不关，第 2 次关
echo    [2] 只看状态（不做任何操作）
echo    [3] 退出
echo.
set "CH="
set /p "CH=请选择 1 / 2 / 3 然后回车: "
if "!CH!"=="1" goto fix
if "!CH!"=="2" goto only
if "!CH!"=="3" goto quit
goto menu

:only
cls
echo.
echo   [显示设备]
powershell -NoProfile -Command "Get-PnpDevice -Class Display | Format-Table Status,FriendlyName -AutoSize" 2>nul
echo   [屏幕]
powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::AllScreens | Format-Table DeviceName,Bounds,Primary -AutoSize" 2>nul
echo.
pause
goto menu

:fix
if not defined MYSID (
    echo.
    echo  [错误] 读不到本脚本所在会话，无法继续。
    pause
    goto menu
)

echo.
echo  第一步：把会话 !MYSID! 推到控制台...
tscon !MYSID! /dest=console

echo  第二步：等 5 秒，让桌面开始渲染...
powershell -NoProfile -Command "Start-Sleep -Seconds 5" 2>nul

echo  第三步：自检...
call :check

set "BASE=!ACT!"
set "CNT=0"
if exist "%STATE%" (set /p CNT=<"%STATE%")
echo.
echo  守护已启动：基准活动会话数 = !BASE!
echo  每 60 秒自检一次；被顶掉第 1 次不关，第 2 次关。
echo  （本窗口可以最小化，不要关）
echo.

:guard
powershell -NoProfile -Command "Start-Sleep -Seconds 60" 2>nul
call :check
if !ACT! GTR !BASE! (
    set /a CNT+=1
    echo !CNT!>"%STATE%"
    echo.
    echo  [!time:~0,8!] 检测到新的活动连接（!BASE! -^> !ACT!）—— 第 !CNT! 次
    if !CNT! GEQ 2 (
        echo  [规则] 第 2 次被顶掉，守护退出。
        powershell -NoProfile -Command "Start-Sleep -Seconds 8" 2>nul
        goto quit
    )
    echo  [规则] 第 1 次不关，继续守护。
    set "BASE=!ACT!"
) else (
    if !ACT! LSS !BASE! set "BASE=!ACT!"
)
goto guard

rem ==========================================
rem 取一次快照
rem ==========================================
:getsid
set "SID="
for /f "tokens=1,3" %%a in ('query session 2^>nul') do (
    set "N=%%a"
    if "!N:~0,1!"==">" set "SID=%%b"
)
exit /b 0

:check
call :getsid
set "ACT=0"
for /f %%a in ('query session 2^>nul ^| findstr /c:"运行中"') do set /a ACT+=1
exit /b 0

:quit
endlocal
exit /b 0
