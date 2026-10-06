<#
    虚拟屏幕管理器  manage-vdd.ps1
    统一管理虚拟显示器 + 会话保活

    用法:
        manage-vdd.ps1              交互菜单（推荐）
        manage-vdd.ps1 status       查看状态
        manage-vdd.ps1 start        启动（启用设备 + 推会话到控制台）
        manage-vdd.ps1 stop         关闭（禁用设备）
        manage-vdd.ps1 restart      重启设备
        manage-vdd.ps1 check        自检 6 项
        manage-vdd.ps1 task on      注册保活任务
        manage-vdd.ps1 task off     卸载保活任务
#>
param(
    [Parameter(Position=0)][string]$Cmd = "",
    [Parameter(Position=1)][string]$Arg = ""
)

$ErrorActionPreference = "Continue"
$DEVICE_ID  = "ROOT\MTTVDD\0000"
$TASK_NAME  = "KeepConsoleSession"
$CFG_DIR    = "C:\VirtualDisplayDriver"
# ---- 自身定位（不依赖当前目录）----
$SELF = $PSCommandPath
if (-not $SELF) { $SELF = $MyInvocation.MyCommand.Path }
if (-not $SELF) { $SELF = $MyInvocation.MyCommand.Definition }
$HERE = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $SELF }
if (-not $HERE) { $HERE = (Get-Location).Path }

# 在多个位置找兄弟脚本（复制到任意目录也能用）
function Find-Sibling($name) {
    $cands = @()
    if ($HERE) { $cands += (Join-Path $HERE $name) }
    $cands += (Join-Path $CFG_DIR $name)
    $cands += (Join-Path (Get-Location).Path $name)
    $desk = [Environment]::GetFolderPath("Desktop")
    if ($desk) {
        $cands += (Join-Path $desk $name)
        $cands += (Join-Path $desk ("wxauto-repost-onebotv11-restoredversion\system\" + $name))
    }
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path } }
    # 最后：在桌面下两层里搜
    if ($desk) {
        $hit = Get-ChildItem -Path $desk -Filter $name -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

# ============ 工具函数 ============
function Line($c = "-", $n = 50) { Write-Host ($c * $n) }
function Head($t) { Write-Host ""; Line "=" 50; Write-Host ("  " + $t); Line "=" 50; Write-Host "" }
function Ok($m)   { Write-Host ("  [OK]   " + $m) -ForegroundColor Green }
function Bad($m)  { Write-Host ("  [FAIL] " + $m) -ForegroundColor Red }
function Info($m) { Write-Host ("         " + $m) }
function Warn($m) { Write-Host ("  [警告] " + $m) -ForegroundColor Yellow }

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DeviceInfo {
    return Get-PnpDevice -InstanceId $DEVICE_ID -ErrorAction SilentlyContinue
}

function Get-WechatSession {
    $p = Get-Process Weixin -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 1 } | Select-Object -First 1
    if (-not $p) { $p = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 1 } | Select-Object -First 1 }
    if ($p) { return $p.SessionId }
    return $null
}

function Test-SessionActive {
    $raw = (qwinsta 2>$null | Out-String)
    return ($raw -match "运行中|活动|Active")
}

# ============ 各项功能 ============
function Do-Status {
    Head "虚拟屏幕状态"

    # 设备
    Write-Host "  [显示设备]"
    $d = Get-DeviceInfo
    if ($d) {
        if ($d.Status -eq "OK") { Ok  ("Virtual Display Driver   状态: " + $d.Status) }
        else                    { Warn ("Virtual Display Driver   状态: " + $d.Status) }
    } else { Bad "虚拟显示设备不存在（需要先安装）" }

    $all = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue
    foreach ($x in $all) { Info ("  " + $x.Status.PadRight(8) + $x.FriendlyName) }

    # 屏幕
    Write-Host ""
    Write-Host "  [屏幕]"
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $scr = [System.Windows.Forms.Screen]::AllScreens
    foreach ($s in $scr) { Info ($s.DeviceName + "  " + $s.Bounds.Width + "x" + $s.Bounds.Height + $(if($s.Primary){"  (主)"}else{""})) }
    if ($scr.Count -le 1) { Warn "只有 1 块屏 —— 断开远程桌面后可能无法收发" }

    # 会话
    Write-Host ""
    Write-Host "  [会话]"
    (qwinsta 2>$null | Out-String) -split "`n" | Where-Object { $_ -match "\S" } | ForEach-Object { Info $_ }
    $sid = Get-WechatSession
    if ($sid) { Info ("微信所在会话: " + $sid) }
    if (Test-SessionActive) { Ok "存在活动会话（桌面在渲染）" } else { Bad "没有活动会话 —— 桌面不会渲染，微信发不出消息" }

    # 计划任务
    Write-Host ""
    Write-Host "  [保活任务]"
    $t = schtasks /query /tn $TASK_NAME 2>$null
    if ($LASTEXITCODE -eq 0) { Ok ($TASK_NAME + " 已注册") } else { Bad ($TASK_NAME + " 未注册") }

    # 渲染实测
    Write-Host ""
    Write-Host "  [渲染实测]"
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        $code = "from PIL import ImageGrab`nimport sys`ntry:`n    i=ImageGrab.grab(); e=i.convert('L').getextrema()`n    print(i.size, e)`n    sys.exit(0 if e[0]!=e[1] else 2)`nexcept Exception as ex:`n    print(ex); sys.exit(3)"
        $r = python -c $code 2>&1
        if ($LASTEXITCODE -eq 0) { Ok ("能截到屏  " + $r) }
        elseif ($LASTEXITCODE -eq 2) { Bad "能截到，但画面是纯色（桌面没在渲染）" }
        else { Bad ("截屏失败: " + $r) }
    } else { Info "（跳过：找不到 python）" }
    Write-Host ""
}

function Do-Start {
    Head "启动虚拟屏幕"
    $d = Get-DeviceInfo
    if (-not $d) { Bad "设备不存在，请先执行「安装」"; return }

    Write-Host "  [1/3] 确保设备启用..."
    if ($d.Status -ne "OK") {
        Enable-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $d = Get-DeviceInfo
        Info ("现在: " + $d.Status)
    } else { Info "已是 OK" }

    Write-Host ""
    Write-Host "  [2/3] 重启设备使配置生效..."
    try {
        Disable-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2
        Enable-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2
        Info "重启完成"
    } catch {
        Info ("自动重启失败: " + $_)
    }

    Write-Host ""
    Write-Host "  [3/3] 把微信所在会话推回控制台..."
    $sid = Get-WechatSession
    if (-not $sid) { Info "找不到微信/机器人进程，跳过" }
    elseif (Test-SessionActive) { Info ("会话 " + $sid + " 已是活动状态，无需处理") }
    else {
        Info ("会话 " + $sid + " 非活动，正在推送...")
        & tscon $sid /dest:console | Out-Null
        Start-Sleep -Seconds 3
        Info ("已执行 tscon " + $sid + " /dest:console")
    }
    Write-Host ""
    Ok "启动完成。跑 status 或 check 验证"
    Write-Host ""
}

function Do-Stop {
    Head "关闭虚拟屏幕"
    $d = Get-DeviceInfo
    if (-not $d) { Bad "设备不存在"; return }
    if ($d.Status -ne "OK") { Info ("设备已经是 " + $d.Status + "，无需关闭"); return }
    Warn "关闭后，断开远程桌面将无法收发微信消息"
    Disable-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $d = Get-DeviceInfo
    if ($d.Status -eq "OK") { Bad "关闭失败" } else { Ok ("已关闭，当前状态: " + $d.Status) }
    Write-Host ""
}

function Do-Restart {
    Head "重启虚拟显示设备"
    $d = Get-DeviceInfo
    if (-not $d) { Bad "设备不存在"; return }
    try {
        Disable-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2
        Enable-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2
        Ok "重启完成"
    } catch { Bad ("重启失败: " + $_) }
    Write-Host ""
}

function Do-Install {
    Head "安装虚拟屏幕"
    $script = Find-Sibling "1-install-vdd.ps1"
    if (-not $script) { Bad "找不到 1-install-vdd.ps1（把它和本脚本放同一个文件夹）"; return }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Download
    Write-Host ""
}

function Do-Uninstall {
    Head "卸载虚拟屏幕"
    Warn "这会移除虚拟显示设备和保活任务"
    $yn = Read-Host "  确定吗? 输入 YES"
    if ($yn -ne "YES") { Info "已取消"; Write-Host ""; return }

    Write-Host ""
    Write-Host "  [1/2] 移除保活任务..."
    schtasks /delete /tn $TASK_NAME /f 2>$null | Out-Null
    Info "完成"

    Write-Host "  [2/2] 移除虚拟显示设备..."
    Remove-PnpDevice -InstanceId $DEVICE_ID -Confirm:$false -ErrorAction SilentlyContinue
    if (Get-DeviceInfo) { Bad "移除失败（可能需要重启）" } else { Ok "已移除" }
    Write-Host ""
}

function Do-Check {
    Head "自检"
    $script = Find-Sibling "3-verify.ps1"
    if ($script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script }
    else { Bad "找不到 3-verify.ps1（把它和本脚本放同一个文件夹）" }
}

function Do-Task($mode) {
    Head $(if ($mode -eq "on") { "注册保活任务" } else { "卸载保活任务" })
    $script = Find-Sibling "2-register-task.ps1"
    if (-not $script) { Bad "找不到 2-register-task.ps1（把它和本脚本放同一个文件夹）"; return }
    if ($mode -eq "on") { & powershell -NoProfile -ExecutionPolicy Bypass -File $script }
    else                { & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Remove }
    Write-Host ""
}

# ============ 菜单 ============
function Menu {
    while ($true) {
        Clear-Host
        Line "=" 50
        Write-Host "          虚拟屏幕管理器"
        Line "=" 50
        $d = Get-DeviceInfo
        $st = if ($d) { $d.Status } else { "不存在" }
        $act = if (Test-SessionActive) { "活动" } else { "非活动" }
        Write-Host ("   设备: " + $st.PadRight(10) + "  会话: " + $act)
        Line "-" 50
        Write-Host "   [1] 查看状态"
        Write-Host "   [2] 启动（启用 + 推会话到控制台）"
        Write-Host "   [3] 关闭"
        Write-Host "   [4] 重启设备"
        Write-Host "   [5] 安装（首次使用）"
        Write-Host "   [6] 卸载"
        Write-Host "   [7] 自检（6 项）"
        Write-Host "   [8] 保活：安装/卸载自启动守护"
        Write-Host "       (推荐 —— 不依赖任务计划程序)"
        Write-Host "   [9] 安全断开远程桌面"
        Write-Host "   [0] 退出"
        Line "-" 50
        $c = Read-Host "   请选择"
        switch ($c) {
            "1" { Do-Status;  Read-Host "  回车继续" | Out-Null }
            "2" { Do-Start;   Read-Host "  回车继续" | Out-Null }
            "3" { Do-Stop;    Read-Host "  回车继续" | Out-Null }
            "4" { Do-Restart; Read-Host "  回车继续" | Out-Null }
            "5" { Do-Install; Read-Host "  回车继续" | Out-Null }
            "6" { Do-Uninstall; Read-Host "  回车继续" | Out-Null }
            "7" { Do-Check;   Read-Host "  回车继续" | Out-Null }
            "8" {
                $m = Read-Host "  on=安装自启动守护  off=卸载"
                $script = Find-Sibling "4-install-autostart.ps1"
                if (-not $script) { Bad "找不到 4-install-autostart.ps1"; Read-Host "  回车继续" | Out-Null; continue }
                if ($m -eq "off") { & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Uninstall }
                else              { & powershell -NoProfile -ExecutionPolicy Bypass -File $script }
                Read-Host "  回车继续" | Out-Null
            }
            "9" {
                $b = Find-Sibling "safedisconnect.bat"
                if ($b) { & $b } else { Bad "找不到 safedisconnect.bat" }
            }
            "0" { return }
            default { }
        }
    }
}

# ============ 入口 ============
if (-not (Test-Admin)) {
    Write-Host ""
    Write-Host "  [错误] 需要管理员权限。请右键 → 以管理员身份运行" -ForegroundColor Red
    Write-Host ""
    if ($Cmd) { exit 1 }
    $yn = Read-Host "  是否以管理员身份重新启动? (Y/N)"
    if ($yn -eq "Y" -or $yn -eq "y") {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`""
    }
    exit 0
}

switch ($Cmd.ToLower()) {
    "status"  { Do-Status }
    "start"   { Do-Start }
    "stop"    { Do-Stop }
    "restart" { Do-Restart }
    "check"   { Do-Check }
    "install" { Do-Install }
    "task"    { if ($Arg) { Do-Task $Arg } else { Do-Task "on" } }
    ""        { Menu }
    default   { Menu }
}
