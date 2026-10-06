<#
    3-verify.ps1
    一条命令自检："现在能不能收发微信消息"

    用法:
        powershell -ExecutionPolicy Bypass -File 3-verify.ps1
#>
$ErrorActionPreference = "Continue"
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
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    $code = "from PIL import ImageGrab`nimport sys`ntry:`n    i=ImageGrab.grab();e=i.convert('L').getextrema()`n    print(i.size, e)`n    sys.exit(0 if e[0]!=e[1] else 2)`nexcept Exception as ex:`n    print(ex); sys.exit(3)"
    $r = python -c $code 2>&1
    $rc = $LASTEXITCODE
    if ($rc -eq 0)      { Chk "能截到屏（桌面在渲染）" $true  "$r" }
    elseif ($rc -eq 2)  { Chk "能截到屏（桌面在渲染）" $false "纯色画面，可能桌面没在渲染" }
    else                { Chk "能截到屏（桌面在渲染）" $false "$r   <-- 这就是发不出消息的原因" }
} else {
    Write-Host "     (跳过: 找不到 python)"
}

# 4 计划任务
Write-Host ""
Write-Host "[4] 会话保活计划任务"
$t = schtasks /query /tn "KeepConsoleSession" 2>$null
Chk "KeepConsoleSession 已注册" ($LASTEXITCODE -eq 0) ""

# 5 微信进程
Write-Host ""
Write-Host "[5] 微信进程"
$wx = Get-Process Weixin -ErrorAction SilentlyContinue
Chk "微信 PC 版在运行" ($wx.Count -gt 0) "(进程数: $($wx.Count))"
if ($wx) { Write-Host "     会话 ID: $(($wx | Select-Object -First 1).SessionId)" }

# 6 发送实测
Write-Host ""
Write-Host "[6] 发送实测（发到「文件传输助手」）"
if ($py) {
    $code2 = "from wechatauto import WeChat`nprint(WeChat().SendMsg('自检消息', who='文件传输助手'))"
    $r2 = python -c $code2 2>&1
    $ok = ($LASTEXITCODE -eq 0) -and ($r2 -match "成功|success")
    Chk "微信发送链路" $ok "$(($r2 | Select-Object -Last 1))"
} else { Write-Host "     (跳过)" }

Write-Host ""
Write-Host "=================================================="
if ($fail -eq 0) { Write-Host " 全部通过 ($pass) —— 可以正常收发" -ForegroundColor Green }
else { Write-Host " 通过 $pass 项，失败 $fail 项 —— 请看上面标 [FAIL] 的" -ForegroundColor Yellow }
Write-Host "=================================================="
Write-Host ""
Write-Host "常见对应关系:"
Write-Host "  [3] 失败 -> 断开远程桌面了，或没装虚拟显示器  -> 跑 1-install-vdd.ps1"
Write-Host "  [4] 失败 -> 没注册保活任务                     -> 跑 2-register-task.ps1"
Write-Host "  [6] 失败 -> 看 C:\VirtualDisplayDriver\keep_console.log"
