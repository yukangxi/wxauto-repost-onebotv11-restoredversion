<#
    0-start-display.ps1
    一键启用虚拟屏幕 —— 把"不跟远程桌面走"的那块屏点亮，
    并把微信所在的会话推回控制台（桌面才会真正渲染）

    什么时候用:
      - 睡眠/唤醒之后，机器人突然发不出消息
      - 手动改过分辨率
      - 设备被禁用过
      - 换远程桌面连接后状态不对

    用法（管理员 PowerShell）:
        powershell -ExecutionPolicy Bypass -File 0-start-display.ps1
        或直接双击 启动虚拟屏幕.bat
#>
$ErrorActionPreference = "Continue"
$DEVICE_ID = "ROOT\MTTVDD\0000"

function Say($m) { Write-Host $m }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Say ""; Say "  [错误] 需要管理员权限。请右键 → 以管理员身份运行"; Say ""; exit 1 }

Say ""
Say "=================================================="
Say "         启用虚拟屏幕"
Say "=================================================="
Say ""

# ---- 1) 设备在不在 ----
Say "  [1/4] 检查虚拟显示设备..."
$devInfo = Get-PnpDevice -InstanceId $DEVICE_ID -ErrorAction SilentlyContinue
if (-not $devInfo) {
    Say "        设备不存在 —— 需要先运行 1-install-vdd.ps1"
    Say ""
    exit 1
}
Say "        找到: $($devInfo.FriendlyName)   状态: $($devInfo.Status)"

# ---- 2) 被禁用就启用 ----
Say ""
Say "  [2/4] 确保设备已启用..."
if ($devInfo.Status -ne "OK") {
    Say "        状态是 $($devInfo.Status)，正在启用..."
    Enable-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $devInfo = Get-PnpDevice -InstanceId $DEVICE_ID -ErrorAction SilentlyContinue
    Say "        现在: $($devInfo.Status)"
} else {
    Say "        已是 OK，跳过"
}

# ---- 3) 重启设备，让配置生效 ----
Say ""
Say "  [3/4] 重启设备使配置生效..."
# 用禁用/启用代替 pnputil（pnputil 在某些版本上会报"实例名无效"）
try {
    Disable-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction Stop
    Start-Sleep -Seconds 2
    Enable-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction Stop
    Start-Sleep -Seconds 2
    Say "        重启完成"
} catch {
    Say "        自动重启失败: $_"
    Say "        改用 pnputil 重试..."
    $r = & pnputil /restart-device "$DEVICE_ID" 2>&1 | Out-String
    if ($r -match "成功|Success" -or $LASTEXITCODE -eq 0) { Say "        pnputil 重启完成" }
    else { Say "        pnputil 也失败。若设备状态是 OK，可忽略（配置已加载）" }
}

# ---- 4) 把会话推回控制台 ----
Say ""
Say "  [4/4] 把微信所在会话推回控制台..."
$p = Get-Process Weixin -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 1 } | Select-Object -First 1
if (-not $p) { $p = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 1 } | Select-Object -First 1 }
if (-not $p) {
    Say "        找不到微信/机器人进程，跳过"
} else {
    $sid = $p.SessionId
    # 直接看 qwinsta 的原始输出里有没有"活动/运行中/Active"，比拆列稳
    $raw = (qwinsta 2>$null | Out-String)
    $isActive = $raw -match "运行中|活动|Active"
    Say "        会话 ID = $sid"
    if ($isActive) {
        Say "        检测到活动会话，无需处理"
    } else {
        Say "        未检测到活动会话，正在推送会话 $sid 到控制台..."
        & tscon $sid /dest:console | Out-Null
        Start-Sleep -Seconds 3
        Say "        已执行 tscon $sid /dest:console"
    }
}

# ---- 结果 ----
Say ""
Say "=================================================="
Say "  结果"
Say "=================================================="
Get-PnpDevice -Class Display | Format-Table Status, FriendlyName -AutoSize | Out-String | ForEach-Object { Say $_ }
Say "  屏幕:"
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
[System.Windows.Forms.Screen]::AllScreens | Format-Table DeviceName, Bounds, Primary -AutoSize | Out-String | ForEach-Object { Say $_ }
Say "  会话:"
(qwinsta 2>$null | Out-String) -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { Say "    $_" }
Say ""
Say "  如果上面能看到 'Virtual Display Driver' 且会话是「运行中」，就绪了。"
Say "  进一步验证: 跑 3-verify.ps1"
Say ""
