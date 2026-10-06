# keep_console.ps1  v3
#
# 目的: 让"微信所在的会话"始终处于能渲染的状态
#
# 判断依据（关键）:
#   本脚本可能以 SYSTEM 运行 —— 那种情况下跑在 session 0，没有桌面，
#   任何截屏测试都会失败（假阴性）。所以【不能靠截屏判断】。
#
#   唯一可靠的依据是: 目标会话在 qwinsta 里的【状态列】
#       运行中 / Active  -> 好（桌面在渲染）
#       断开   / Disc    -> 坏（桌面不渲染）-> tscon /dest:console

$LOG = "C:\VirtualDisplayDriver\keep_console.log"
$DEV = "ROOT\MTTVDD\0000"

function W($m) {
    $line = "{0}  {1}" -f (Get-Date).ToString("MM-dd HH:mm:ss"), $m
    Add-Content -Path $LOG -Value $line -Encoding UTF8
    try {
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
        if ($ln -match '\S') {
            if ($ln -match ("\s" + [regex]::Escape("$sid") + "\s")) {
                if ($ln -match "运行中|Active") { return "ACTIVE" }
                if ($ln -match "断开|Disc")     { return "DISC" }
                if ($ln -match "已连接|Conn")   { return "CONN" }
                if ($ln -match "侦听|Listen")   { return "LISTEN" }
                return "OTHER"
            }
        }
    }
    return "UNKNOWN"
}

try {
    W ("[启动] 身份=" + [Security.Principal.WindowsIdentity]::GetCurrent().Name + "  会话=" + (Get-Process -Id $PID).SessionId)

    $d = Get-PnpDevice -InstanceId $DEV -ErrorAction SilentlyContinue
    if ($d -and $d.Status -ne "OK") {
        W "设备状态异常($($d.Status)) -> 启用"
        Enable-PnpDevice -InstanceId $DEV -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $sid = Get-BotSession
    if (-not $sid) { W "[退出] 找不到微信/python 进程"; exit 0 }

    $state = Get-SessionState $sid
    if ($state -eq "ACTIVE") { W "[退出] 会话正常(ACTIVE)"; exit 0 }

    W "会话 $sid 状态=($state) -> tscon $sid /dest:console"
    & tscon $sid /dest:console 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    W "处理完成: 状态=($(Get-SessionState $sid))"
} catch {
    W "异常: $_"
}
