# keep_console.ps1 v2
# 每分钟检查，确保"微信所在的会话"处于能渲染的状态
#
# 检查顺序:
#   1) 会话是不是 Active（不是 -> 推回控制台）
#   2) 会话 Active 但截屏失败（-> 也推回控制台）
#   3) 虚拟显示设备被禁用（-> 启用）
#
# 只有"做了什么"才写日志，正常时静默

$LOG = "C:\VirtualDisplayDriver\keep_console.log"
$DEV = "ROOT\MTTVDD\0000"

function W($m) {
    $line = "{0}  {1}" -f (Get-Date).ToString("MM-dd HH:mm:ss"), $m
    Add-Content -Path $LOG -Value $line -Encoding UTF8
    # 日志超过 200 行就截断
    try {
        $all = Get-Content $LOG -ErrorAction SilentlyContinue
        if ($all.Count -gt 200) { $all | Select-Object -Last 100 | Set-Content $LOG -Encoding UTF8 }
    } catch { }
}

function Get-BotSession {
    $p = Get-Process Weixin -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 1 } | Select-Object -First 1
    if (-not $p) { $p = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 1 } | Select-Object -First 1 }
    if ($p) { return $p.SessionId }
    return $null
}

function Test-Active {
    $raw = (qwinsta 2>$null | Out-String)
    return ($raw -match "运行中|活动|Active")
}

# 截屏自检（判断桌面到底有没有在渲染）
function Test-Render {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { return $true }   # 找不到 python 就不判，别乱动
    $code = "from PIL import ImageGrab`nimport sys`ntry:`n    i=ImageGrab.grab(); e=i.convert('L').getextrema()`n    sys.exit(0 if e[0]!=e[1] else 2)`nexcept Exception:`n    sys.exit(3)"
    & python -c $code 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

try {
    $action = $false

    # 1) 虚拟显示设备被禁用了？
    $d = Get-PnpDevice -InstanceId $DEV -ErrorAction SilentlyContinue
    if ($d -and $d.Status -ne "OK") {
        W "虚拟显示设备状态异常 ($($d.Status)) -> 启用"
        Enable-PnpDevice -InstanceId $DEV -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $action = $true
    }

    # 2) 会话状态
    $sid = Get-BotSession
    if (-not $sid) {
        W "找不到微信/机器人进程，跳过"
        exit 0
    }

    $active = Test-Active
    $render = $true
    if ($active) { $render = Test-Render }

    if (-not $active -or -not $render) {
        $why = if (-not $active) { "会话非活动" } else { "截屏失败(桌面没渲染)" }
        W "检测到问题($why) 会话=$sid -> tscon /dest:console"
        & tscon $sid /dest:console 2>&1 | Out-Null
        Start-Sleep -Seconds 3
        $ok2 = Test-Render
        W ("处理完成: 会话活动=" + (Test-Active) + "  截屏=" + $ok2)
        $action = $true
    }

    if (-not $action) { exit 0 }   # 一切正常，静默退出
} catch {
    W "异常: $_"
}
