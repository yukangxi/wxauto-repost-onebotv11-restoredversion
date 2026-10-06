<#
    keep_console_loop.ps1
    常驻守护：每 60 秒检查一次"微信所在会话"能不能渲染，不能就推回控制台

    为什么不用计划任务:
      实测这台机器上【任务计划程序完全无法执行任何任务】
      （SYSTEM / S4U / 交互式 三种方式都试过，任务状态 Queued，标记文件从不生成）

    所以改成常驻进程:
      - 在用户会话里跑 -> tscon 有效
      - 断开远程桌面后继续跑
      - 随系统启动（放在"启动"文件夹）

    停止方式: 删掉启动文件夹里的快捷方式，并结束进程
              或跑 4-install-autostart.ps1 -Uninstall
#>
param([int]$IntervalSec = 20, [switch]$Quiet)

$LOG   = "C:\VirtualDisplayDriver\keep_console.log"
$DEV   = "ROOT\MTTVDD\0000"
$LOCK  = "C:\VirtualDisplayDriver\keep_console.lock"

# 单实例保护
if (Test-Path $LOCK) {
    $oldPid = (Get-Content $LOCK -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        exit 0     # 已经有一个在跑了
    }
}
$PID | Out-File $LOCK -Encoding ASCII

function W($m) {
    try {
        $line = "{0}  {1}" -f (Get-Date).ToString("MM-dd HH:mm:ss"), $m
        Add-Content -Path $LOG -Value $line -Encoding UTF8
        $all = Get-Content $LOG -ErrorAction SilentlyContinue
        if ($all.Count -gt 300) { $all | Select-Object -Last 150 | Set-Content $LOG -Encoding UTF8 }
    } catch { }
}

function Get-BotSession {
    $p = Get-Process Weixin -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 0 } | Select-Object -First 1
    if (-not $p) { $p = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 0 } | Select-Object -First 1 }
    if ($p) { return [int]$p.SessionId }
    return $null
}

function Get-SessionState($sid) {
    $raw = (qwinsta 2>$null | Out-String)
    foreach ($ln in ($raw -split "`n")) {
        if ($ln -match '\S' -and $ln -match ("\s" + [regex]::Escape("$sid") + "\s")) {
            if ($ln -match "运行中|Active") { return "ACTIVE" }
            if ($ln -match "断开|Disc")     { return "DISC" }
            if ($ln -match "已连接|Conn")   { return "CONN" }
            return "OTHER"
        }
    }
    return "UNKNOWN"
}

W "[守护启动] PID=$PID 间隔=${IntervalSec}s"
$lastSid = $null

while ($true) {
    try {
        # 设备被禁用？
        $d = Get-PnpDevice -InstanceId $DEV -ErrorAction SilentlyContinue
        if ($d -and $d.Status -ne "OK") {
            W "设备异常($($d.Status)) -> 启用"
            Enable-PnpDevice -InstanceId $DEV -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }

        $sid = Get-BotSession
        if ($sid) {
            $state = Get-SessionState $sid
            $dev  = Get-PnpDevice -InstanceId $DEV -ErrorAction SilentlyContinue
            $devS = if ($dev) { $dev.Status } else { "缺失" }

            if ($state -ne "ACTIVE") {
                W "检查: 会话=$sid 状态=$state 设备=$devS  -> 修复中(tscon)"
                & tscon $sid /dest:console 2>&1 | Out-Null
                Start-Sleep -Seconds 3
                W "修复完成: 状态=$(Get-SessionState $sid)"
            } else {
                # 正常也记一笔（可调 -Quiet 关掉）
                if (-not $Quiet) { W "检查: 会话=$sid 状态=$state 设备=$devS  -> 正常" }
            }
            $lastSid = $sid
        } else {
            if (-not $Quiet) { W "检查: 找不到微信/python 进程" }
        }
    } catch {
        W "循环异常: $_"
    }
    Start-Sleep -Seconds $IntervalSec
}
