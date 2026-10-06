<#
    2-register-task.ps1
    注册"会话保活"计划任务

    ★ 必须用 S4U 登录类型 ★
      为什么不用别的：
        SYSTEM        -> 实测在这类机器上任务根本不执行（连写文件都做不到）
        <你> + /it    -> "只使用交互方式"，断开远程桌面后就不跑了
        <你> + S4U    -> 不需要密码、不管有没有连着都跑  ✅

    用法:
        powershell -ExecutionPolicy Bypass -File 2-register-task.ps1
        卸载:  -Remove
#>
param([switch]$Remove)

$name = "KeepConsoleSession"
$script = "C:\VirtualDisplayDriver\keep_console.ps1"

if ($Remove) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    schtasks /delete /tn $name /f 2>$null | Out-Null
    Write-Host "已卸载计划任务 $name"
    exit 0
}

# 部署脚本本体
New-Item -ItemType Directory -Force -Path "C:\VirtualDisplayDriver" | Out-Null
$src = Join-Path $PSScriptRoot "keep_console.ps1"
if (Test-Path $src) {
    Copy-Item $src "C:\VirtualDisplayDriver\keep_console.ps1" -Force
    Write-Host "已部署: C:\VirtualDisplayDriver\keep_console.ps1"
} else {
    Write-Host "  [警告] 同目录下没找到 keep_console.ps1"
}

# 先清掉旧任务
Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
schtasks /delete /tn $name /f 2>$null | Out-Null

try {
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\VirtualDisplayDriver\keep_console.ps1"'
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
        -MultipleInstances IgnoreNew

    # ★ S4U: 不需要密码，也不要求交互登录
    $who = "$env:COMPUTERNAME\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId $who -LogonType S4U -RunLevel Highest

    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal -Force | Out-Null

    Write-Host ""
    Write-Host "✅ 已注册（S4U / 每 1 分钟）"
    $i1 = Get-ScheduledTask -TaskName $name | Select-Object TaskName,State,
        @{n='RunAs';e={$_.Principal.UserId}},@{n='LogonType';e={$_.Principal.LogonType}} |
        Format-List | Out-String
    Write-Host $i1

    Write-Host "立即试跑..."
    Start-ScheduledTask -TaskName $name
    Start-Sleep -Seconds 6
    $i2 = Get-ScheduledTaskInfo -TaskName $name | Select-Object LastRunTime,LastTaskResult | Format-List | Out-String
    Write-Host $i2
    Write-Host "日志: C:\VirtualDisplayDriver\keep_console.log （只有出问题时才写）"
} catch {
    Write-Host ""
    Write-Host "❌ S4U 注册失败: $_"
    Write-Host "回退方案：手动以'最高权限'注册，或用任务计划程序图形界面"
    Write-Host "      （启动方式选 '不管用户是否登录都要运行'，勾掉 '不存储密码'）"
}
