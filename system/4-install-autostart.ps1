<#
    4-install-autostart.ps1
    安装"会话保活守护进程"的自启动

    为什么不用计划任务:
      实测某些机器上【任务计划程序无法执行任何任务】
      （SYSTEM / S4U / 交互式 三种都试过，任务状态 Queued，但不产生任何效果）
      所以改用一个常驻进程 + "启动"文件夹自启。

    用法:
        powershell -ExecutionPolicy Bypass -File 4-install-autostart.ps1
        powershell -ExecutionPolicy Bypass -File 4-install-autostart.ps1 -Uninstall
#>
param([switch]$Uninstall)

$cfg    = "C:\VirtualDisplayDriver"
$loop   = "$cfg\keep_console_loop.ps1"
$lnk    = Join-Path ([Environment]::GetFolderPath("Startup")) "KeepConsoleSession.lnk"
$taskName = "KeepConsoleSession"

if ($Uninstall) {
    Write-Host "卸载中..."
    # 1) 干掉常驻进程
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*keep_console_loop*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host ("  已结束进程 " + $_.ProcessId) }
    # 2) 删快捷方式
    if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host "  已删启动项" }
    # 3) 顺带清掉可能存在的计划任务
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    schtasks /delete /tn $taskName /f 2>$null | Out-Null
    # 4) 清锁
    Remove-Item "$cfg\keep_console.lock" -Force -ErrorAction SilentlyContinue
    Write-Host "完成"
    exit 0
}

# ---- 安装 ----
New-Item -ItemType Directory -Force -Path $cfg | Out-Null

# 1) 部署守护脚本
$src = Join-Path $PSScriptRoot "keep_console_loop.ps1"
if (-not (Test-Path $src)) { Write-Host "[错误] 同目录下找不到 keep_console_loop.ps1"; exit 1 }
Copy-Item $src $loop -Force
Write-Host "已部署: $loop"

# 2) 清掉可能冲突的计划任务
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
schtasks /delete /tn $taskName /f 2>$null | Out-Null

# 3) 结束已有实例，重新起
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*keep_console_loop*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item "$cfg\keep_console.lock" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 4) 现在启动一个（隐藏窗口）
$args = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $loop + '"'
Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden
Start-Sleep -Seconds 4
$running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandLine -like "*keep_console_loop*" })
if ($running.Count -gt 0) { Write-Host ("✅ 守护进程已启动 (PID " + $running[0].ProcessId + ")") }
else { Write-Host "⚠️ 守护进程没起来，请检查" }

# 5) 放"启动"文件夹快捷方式（开机/登录自动起）
try {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sc.Arguments        = $args
    $sc.WorkingDirectory = $cfg
    $sc.WindowStyle      = 7          # 最小化
    $sc.Description      = "微信机器人会话保活"
    $sc.Save()
    Write-Host "✅ 已加入启动项: $lnk"
} catch {
    Write-Host ("⚠️ 创建启动项失败: " + $_)
    Write-Host "      可以手动:  Win+R -> shell:startup  把快捷方式放进去"
}

Write-Host ""
Write-Host "=================================================="
Write-Host "  安装完成"
Write-Host "=================================================="
Write-Host "  守护进程 : keep_console_loop.ps1 （每 60 秒检查一次）"
Write-Host "  日志     : C:\VirtualDisplayDriver\keep_console.log"
Write-Host "  自启动   : $lnk"
Write-Host ""
Write-Host "  验证: 断开远程桌面，等 1 分钟，回来看会话是否变回 运行中"
Write-Host "        或看日志里有没有 '会话 N 状态=(DISC) -> tscon'"
Write-Host ""
