<#
    3-verify.ps1
    一条命令自检："现在能不能收发微信消息"

    用法:
        powershell -ExecutionPolicy Bypass -File 3-verify.ps1
#>
$ErrorActionPreference = "Continue"
# ---- 自举：如果执行策略禁止运行脚本，自动用 Bypass 重跑 ----
if (-not $env:WXREPOST_BYPASSED) {
    $blocked = $false
    try { $null = Get-ExecutionPolicy -Scope CurrentUser } catch {}
    if ((Get-ExecutionPolicy) -in @("Restricted","AllSigned")) {
        $blocked = $true
    }
    if ($blocked) {
        $env:WXREPOST_BYPASSED = "1"
        Start-Process powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"")
        exit
    }
    $env:WXREPOST_BYPASSED = "1"
}



# ============================================================
#  渲染检测：纯 PowerShell，不依赖 python
#  原理：抓屏幕一小块，看有没有"多种颜色"
#        纯色 = 没渲染；有杂色 = 在渲染
# ============================================================
function Test-ScreenRendered {
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

        $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
        if ($vs.Width -le 0 -or $vs.Height -le 0) { return $false }

        # 抓中间 200x200 的一小块
        $w = [Math]::Min(200, $vs.Width)
        $h = [Math]::Min(200, $vs.Height)
        $x = [int](($vs.Width - $w) / 2)
        $y = [int](($vs.Height - $h) / 2)

        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($vs.X + $x, $vs.Y + $y, 0, 0, $bmp.Size)
        $g.Dispose()

        $colors = @{}
        for ($i = 0; $i -lt $w; $i += 10) {
            for ($j = 0; $j -lt $h; $j += 10) {
                $c = $bmp.GetPixel($i, $j)
                $key = "$($c.R),$($c.G),$($c.B)"
                $colors[$key] = 1
                if ($colors.Count -gt 5) { $bmp.Dispose(); return $true }
            }
        }
        $bmp.Dispose()
        return ($colors.Count -gt 1)
    } catch {
        return $false
    }
}

# 找 python（兜底用，某些脚本需要）
function Find-PythonExe {
    $c = Get-Command python -ErrorAction SilentlyContinue
    if ($c -and $c.Source -and $c.Source -notlike "*WindowsApps*") { return $c.Source }
    $pats = @(
        "$env:USERPROFILE\.astrbot_launcher\instances\*\venv\Scripts\python.exe",
        "$env:USERPROFILE\.astrbot_launcher\components\python\*\python.exe",
        "C:\Users\*\.astrbot_launcher\instances\*\venv\Scripts\python.exe",
        "C:\Users\*\.astrbot_launcher\components\python\*\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe",
        "C:\Python*\python.exe",
        "C:\Program Files\Python*\python.exe"
    )
    foreach ($p in $pats) {
        $hit = Get-ChildItem $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

$pass = 0; $fail = 0
function Chk($name, $ok, $detail) {
    if ($ok) { Write-Host "  [OK]   $name  $detail" -ForegroundColor Green; $script:pass++ }
    else     { Write-Host "  [FAIL] $name  $detail" -ForegroundColor Red;   $script:fail++ }
}

Write-Host "=== 微信消息收发自检 ===" -ForegroundColor Cyan
Write-Host ""

# 1 会话状态
Write-Host "[1] 会话状态"
$out = (qwinsta 2>$null | Out-String)
$out -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host "     $_" }
$active = ($out -split "`n" | Where-Object { $_ -match "运行中|Active" }).Count
Chk "有活动会话" ($active -gt 0) "(活动会话数: $active)"

# 2 显示设备
Write-Host ""
Write-Host "[2] 显示设备"
$disps = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue
$disps | ForEach-Object { Write-Host "     $($_.Status)  $($_.FriendlyName)" }
$hasVdd = $false
foreach ($x in $disps) {
    if ($x.FriendlyName -match "Virtual Display|MttVDD" -or $x.InstanceId -match "MTTVDD") { $hasVdd = $true; break }
}
Chk "虚拟显示器已安装" $hasVdd "(不装的话断开远程桌面就会瞎)"

# 3 屏幕渲染
Write-Host ""
Write-Host "[3] 桌面渲染（最关键）"
$rendered = Test-ScreenRendered
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
Chk "能截到屏（桌面在渲染）" $rendered ("屏幕 " + $vs.Width + "x" + $vs.Height)

Write-Host "[4] 会话保活"
$daemon = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match "keep_console_loop" })
$lnk = Join-Path ([Environment]::GetFolderPath("Startup")) "KeepConsoleSession.lnk"
if ($daemon.Count -gt 0) {
    Chk "守护进程在运行" $true ("PID " + ($daemon.ProcessId -join ","))
} else {
    Chk "守护进程在运行" $false "未运行 -> 跑 4-install-autostart.ps1"
}
Chk "已设置自启动" (Test-Path $lnk) $(if (Test-Path $lnk) {""} else {"-> 4-install-autostart.ps1"})

# 5 微信进程
Write-Host ""
Write-Host "[5] 微信进程"
$wx = Get-Process Weixin -ErrorAction SilentlyContinue
Chk "微信 PC 版在运行" ($wx.Count -gt 0) "(进程数: $($wx.Count))"
if ($wx) { Write-Host "     会话 ID: $(($wx | Select-Object -First 1).SessionId)" }

# 6 发送实测
Write-Host ""
Write-Host "[6] 发送实测（发到「文件传输助手」）"
$py = Find-PythonExe
if ($py) {
    Write-Host "     python: $py"
    $code2 = "from wechatauto import WeChat`nprint(WeChat().SendMsg('自检消息', who='文件传输助手'))"
    # 用 UTF-8 拿输出，避免中文乱码误判
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
    $r2 = (& $py -c $code2 2>&1 | Out-String)

    # 判定只看两件 ASCII 事实：
    #   1) 有没有 'status'  —— 有说明真的拿到了 WxResponse
    #   2) 有没有 grab failed / Traceback —— 有说明没发出去
    $gotStatus = $r2 -match "status"
    $hasError  = $r2 -match "grab failed|Traceback"
    $ok = $gotStatus -and (-not $hasError)

    if ($ok) { $brief = "发送成功" }
    elseif ($r2 -match "grab failed") { $brief = "屏幕截图失败 —— 桌面没渲染（会话被断开了？跑 manage-vdd.ps1 start）" }
    elseif ($hasError) { $brief = "运行异常" }
    else { $brief = "没拿到返回" }

    Chk "微信发送链路" $ok $brief
} else { Write-Host "     (跳过)" }

Write-Host ""
Write-Host "=================================================="
if ($fail -eq 0) { Write-Host " 全部通过 ($pass) —— 可以正常收发" -ForegroundColor Green }
else { Write-Host " 通过 $pass 项，失败 $fail 项 —— 请看上面标 [FAIL] 的" -ForegroundColor Yellow }
Write-Host "=================================================="
Write-Host ""
Write-Host "常见对应关系:"
Write-Host "  [3] 失败 -> 断开远程桌面了，或没装虚拟显示器  -> 跑 1-install-vdd.ps1"
Write-Host "  [4] 失败 -> 守护没装/没跑                     -> 跑 4-install-autostart.ps1"
Write-Host "  [6] 失败 -> 看 C:\VirtualDisplayDriver\keep_console.log"
