<#
    1-install-vdd.ps1
    安装虚拟显示器驱动并创建根枚举设备

    用法（管理员 PowerShell）:
        powershell -ExecutionPolicy Bypass -File 1-install-vdd.ps1

    参数:
        -DriverDir  MttVDD.inf 所在目录（默认自动查找）
        -Download   没有驱动时自动从 GitHub 下载
#>
param(
    [string]$DriverDir = "",
    [switch]$Download
)

$ErrorActionPreference = "Continue"
$log = "C:\VirtualDisplayDriver\install-vdd.log"
New-Item -ItemType Directory -Force -Path "C:\VirtualDisplayDriver" | Out-Null

function W($m) {
    $line = "{0}  {1}" -f (Get-Date).ToString("HH:mm:ss"), $m
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

W "=== 安装虚拟显示器驱动 ==="

# 管理员检查
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { W "错误: 需要管理员权限"; exit 1 }

# 找 INF
if (-not $DriverDir) {
    foreach ($p in @("$PSScriptRoot\MttVDD", "$PSScriptRoot", "C:\Users\$env:USERNAME\Desktop\vdd\drv\VirtualDisplayDriver")) {
        if (Test-Path (Join-Path $p "MttVDD.inf")) { $DriverDir = $p; break }
    }
}
if (-not $DriverDir -or -not (Test-Path (Join-Path $DriverDir "MttVDD.inf"))) {
    W "找不到 MttVDD.inf。"
    if ($Download) {
        W "尝试下载 Virtual-Display-Driver ..."
        $zip = "$env:TEMP\vdd.zip"
        $url = "https://github.com/itsmikethetech/Virtual-Display-Driver/releases/download/25.7.23/VirtualDisplayDriver-x86.Driver.Only.zip"
        try {
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath "$PSScriptRoot\MttVDD" -Force
            $DriverDir = Get-ChildItem "$PSScriptRoot\MttVDD" -Recurse -Filter "MttVDD.inf" | Select-Object -First 1 | ForEach-Object { $_.DirectoryName }
            W "下载完成: $DriverDir"
        } catch { W "下载失败: $_"; exit 1 }
    } else {
        W "请手动下载: https://github.com/itsmikethetech/Virtual-Display-Driver"
        W "把解压后的 MttVDD.inf 所在目录传给 -DriverDir，或放到本脚本同目录的 MttVDD\ 下"
        W "或加 -Download 参数让脚本自动下载"
        exit 1
    }
}
$inf = Join-Path $DriverDir "MttVDD.inf"
W "驱动目录: $DriverDir"

# 检查签名
$cat = Join-Path $DriverDir "mttvdd.cat"
if (Test-Path $cat) {
    $sig = Get-AuthenticodeSignature $cat
    W "签名状态: $($sig.Status)  ($($sig.SignerCertificate.Subject))"
    if ($sig.Status -ne "Valid") { W "警告: 签名无效，可能装不上" }
}

# ① 加进驱动仓库
W "[1/3] 添加驱动包到系统驱动仓库..."
$out = & pnputil /add-driver $inf /install 2>&1 | Out-String
W $out.Trim()

# ② 创建根枚举设备（pnputil 只加包，不建设备，必须用 SetupAPI）
W "[2/3] 创建根枚举设备 Root\MttVDD ..."
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DevSetup {
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr SetupDiCreateDeviceInfoList(IntPtr ClassGuid, IntPtr hwndParent);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SetupDiCreateDeviceInfoW(IntPtr hDevInfo, string DeviceName, IntPtr ClassGuid,
        string DeviceDescription, IntPtr hwndParent, uint CreationFlags, IntPtr DeviceInfoData);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SetupDiSetDeviceRegistryPropertyW(IntPtr hDevInfo, IntPtr DeviceInfoData,
        uint Property, byte[] PropertyBuffer, uint PropertyBufferSize);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SetupDiCallClassInstaller(uint InstallFunction, IntPtr hDevInfo, IntPtr DeviceInfoData);
    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr hDevInfo);
    [DllImport("newdev.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool UpdateDriverForPlugAndPlayDevicesW(IntPtr hwndParent, string HardwareId,
        string FullInfPath, uint InstallFlags, out bool bRebootRequired);
}
"@ -ErrorAction SilentlyContinue

try {
    $guid = [Guid]::Parse("4D36E968-E325-11CE-BFC1-08002BE10318")   # Display
    $g = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
    [Runtime.InteropServices.Marshal]::StructureToPtr($guid, $g, $false)
    $h = [DevSetup]::SetupDiCreateDeviceInfoList($g, [IntPtr]::Zero)
    if ($h -eq [IntPtr]::Zero) { throw "SetupDiCreateDeviceInfoList 失败" }

    $did = [Runtime.InteropServices.Marshal]::AllocHGlobal(32)
    $sz = [Runtime.InteropServices.Marshal]::SizeOf([type][Guid]) + 12 + [IntPtr]::Size
    [Runtime.InteropServices.Marshal]::WriteInt32($did, $sz)
    if (-not [DevSetup]::SetupDiCreateDeviceInfoW($h, "MttVDD", $g, $null, [IntPtr]::Zero, 1, $did)) { throw "创建设备节点失败" }

    $hwid = [Text.Encoding]::Unicode.GetBytes("Root\MttVDD`0")
    if (-not [DevSetup]::SetupDiSetDeviceRegistryPropertyW($h, $did, 1, $hwid, $hwid.Length)) { throw "设置 HardwareID 失败" }

    if (-not [DevSetup]::SetupDiCallClassInstaller(0x19, $h, $did)) { throw "注册设备失败" }   # DIF_REGISTERDEVICE
    W "设备节点创建成功"

    $reboot = $false
    $ok = [DevSetup]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, "Root\MttVDD", $inf, 1, [ref]$reboot)
    W "安装驱动: $ok   需要重启: $reboot"

    [DevSetup]::SetupDiDestroyDeviceInfoList($h) | Out-Null
} catch {
    W "SetupAPI 方式失败: $_"
    W "回退: 试试 pnputil /add-driver ... /install （部分系统会自动建设备）"
    & pnputil /add-driver $inf /install 2>&1 | Out-String | ForEach-Object { W $_.Trim() }
}

# ③ 放配置文件
W "[3/3] 放置 vdd_settings.xml ..."
$cfgSrc = Join-Path $PSScriptRoot "vdd_settings.xml"
if (Test-Path $cfgSrc) {
    Copy-Item $cfgSrc "C:\VirtualDisplayDriver\vdd_settings.xml" -Force
    W "已复制到 C:\VirtualDisplayDriver\vdd_settings.xml"
}

W ""
W "=== 完成，检查结果 ==="
W (Get-PnpDevice -Class Display | Format-Table Status, FriendlyName -AutoSize | Out-String).Trim()
W "屏幕数量:"
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
W ([System.Windows.Forms.Screen]::AllScreens | Format-Table DeviceName, Bounds, Primary -AutoSize | Out-String).Trim()
W ""
W "若设备显示 'Virtual Display Driver' 即成功。"
W "重启设备使配置生效:  pnputil /restart-device 'ROOT\MTTVDD\0000'"
