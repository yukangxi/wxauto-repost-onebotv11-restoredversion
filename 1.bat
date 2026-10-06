@echo off
chcp 65001 >nul 2>&1
title 一键上传到 GitHub
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo ==================================================
echo            一键上传到 GitHub
echo.
echo   本文件必须和要上传的文件放在同一个文件夹里
echo   当前文件夹: %CD%
echo ==================================================
echo.

rem ---- 安全闸：文件太多说明放错地方了 ----
set "CNT=0"
for /f %%a in ('dir /a-d /b /s 2^>nul ^| find /c /v ""') do set "CNT=%%a"
echo   本文件夹共 !CNT! 个文件
if !CNT! GTR 800 (
    echo.
    echo   [已阻止] 文件太多了，你可能把本文件放错地方了。
    echo            请把它放进"要上传的那个仓库文件夹"里，再双击。
    echo.
    pause
    exit /b 1
)

where git >nul 2>&1
if errorlevel 1 ( echo [错误] 没找到 git，请先安装 Git for Windows & pause & exit /b 1 )

if not exist ".git" (
    echo   [1/5] 初始化仓库...
    git init -b main >nul 2>&1
    if errorlevel 1 git init >nul 2>&1
) else (
    echo   [1/5] 已是 git 仓库
)

set "GN="
for /f "delims=" %%a in ('git config user.name 2^>nul') do set "GN=%%a"
if "!GN!"=="" (
    echo.
    set /p "GN=  [2/5] 你的名字（只需填一次）: "
    if "!GN!"=="" set "GN=user"
)
git config user.name "!GN!"
echo   [2/5] 提交者: !GN!

set "GE="
for /f "delims=" %%a in ('git config user.email 2^>nul') do set "GE=%%a"
if "!GE!"=="" (
    set /p "GE=  邮箱（只需填一次）: "
    if "!GE!"=="" set "GE=user@example.com"
)
git config user.email "!GE!"
echo        邮箱: !GE!

set "RU="
for /f "delims=" %%a in ('git remote get-url origin 2^>nul') do set "RU=%%a"
if "!RU!"=="" (
    echo.
    echo   [3/5] 还没绑定远程仓库
    echo         去 GitHub 新建一个空仓库，复制地址粘进来
    echo         例: https://github.com/yourname/wxauto-repost-fixed.git
    set /p "RU=  仓库地址: "
    if "!RU!"=="" ( echo   [取消] 没有仓库地址 & pause & exit /b 1 )
    git remote add origin "!RU!"
)
echo   [3/5] 远程: !RU!

if "!RU!"=="https://github.com/你的用户名/wxauto-repost-fixed.git" (
    echo   [警告] 地址还是示例，请改成你自己的
    pause
    exit /b 1
)

echo.
echo   [4/5] 暂存 + 提交...
git add -A
git status --short
echo.
set "MSG="
set /p "MSG=  提交说明（回车=auto update）: "
if "!MSG!"=="" set "MSG=auto update"
git commit -m "!MSG!"
if errorlevel 1 echo   （没有新改动，跳过提交）

echo.
echo   [5/5] 推送中...
git branch -M main 2>nul
git push -u origin main
if errorlevel 1 (
    echo.
    echo   推送失败，常见原因:
    echo     1) 未登录 GitHub - 会弹窗口，登录后重新双击本文件
    echo     2) 远程已有内容   - 先执行: git pull --rebase origin main
    echo     3) 网络波动       - 再试一次
)

echo.
echo ==================================================
echo   完成，去 !RU! 看看
echo ==================================================
pause
