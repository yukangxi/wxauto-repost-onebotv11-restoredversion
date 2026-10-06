# 自动把"微信所在的会话"维持在一个"会渲染"的状态
# 原理：断开状态的会话不渲染桌面 -> 截屏失败 -> 微信发不出消息
# 做法：发现会话不是"运行中"就把它接到控制台（tscon /dest:console）

$log = "C:\VirtualDisplayDriver\keep_console.log"

function W($m) {
    $line = "{0}  {1}" -f (Get-Date).ToString('MM-dd HH:mm:ss'), $m
    Add-Content -Path $log -Value $line -Encoding UTF8
}

try {
    # 找微信进程所在的会话（那就是机器人所在的会话）
    $p = Get-Process Weixin -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 1 } | Select-Object -First 1
    if (-not $p) { $p = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 1 } | Select-Object -First 1 }
    if (-not $p) { W "找不到微信/机器人进程，跳过"; exit 0 }
    $sid = $p.SessionId

    # 查该会话的状态
    $out = & qwinsta $sid 2>$null | Out-String
    $state = ""
    foreach ($l in ($out -split "`n")) {
        if ($l -match '\S') {
            $parts = ($l.Trim() -split '\s{2,}')
            if ($parts.Count -ge 3 -and $parts[0] -match '^\d+$') { $state = $parts[2]; break }
        }
    }
    if (-not $state) { foreach ($l in ($out -split "`n")) { if ($l -match '运行中|Active|Disc|断开|已连接|Conn') { $state = $Matches[0]; break } } }

    if ($state -match '运行中|Active') {
        # 已经正常，什么都不做（不写日志，避免刷屏）
        exit 0
    }

    W "会话 $sid 状态=($state) -> 执行 tscon $sid /dest:console"
    & tscon $sid /dest:console | Out-Null
    Start-Sleep -Seconds 3
    $out2 = & qwinsta $sid 2>$null | Out-String
    W ("执行后: " + (($out2 -split "`n" | Where-Object { $_ -match '\S' }) -join ' | '))
} catch {
    W "异常: $_"
}
