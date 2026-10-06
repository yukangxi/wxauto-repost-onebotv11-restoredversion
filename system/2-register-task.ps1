<#
    2-register-task.ps1
    注册"会话保活"计划任务：每分钟检查一次，
    发现微信所在会话掉回「断开」就自动 tscon /dest:console 推回控制台

    用法（管理员 PowerShell）:
        powershell -ExecutionPolicy Bypass -File 2-register-task.ps1
        卸载:  -Remove
#>
param([switch]$Remove)

$taskName = "KeepConsoleSession"
$script = "C:\VirtualDisplayDriver\keep_console.ps1"

if ($Remove) {
    schtasks /delete /tn $taskName /f
    Write-Host "已卸载计划任务 $taskName"
    exit 0
}

# 部署脚本
New-Item -ItemType Directory -Force -Path "C:\VirtualDisplayDriver" | Out-Null
Copy-Item (Join-Path $PSScriptRoot "keep_console.ps1") $script -Force
Write-Host "已部署: $script"

# 注册任务
$tr = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""

# ★ 必须用 Administrator + /it，不能用 SYSTEM
#   原因: SYSTEM 账户无法操作交互式会话 -> tscon 会静默失败
#         （表现为: 断开远程桌面后机器人发不出消息）
$who = "$env:COMPUTERNAME\$env:USERNAME"
schtasks /create /tn $taskName /f /tr $tr /sc minute /mo 1 /ru $who /rl HIGHEST /it

if ($LASTEXITCODE -ne 0) {
    Write-Host "  [警告] 以 $who 注册失败，回退到 SYSTEM（tscon 可能失效）"
    schtasks /create /tn $taskName /f /tr $tr /sc minute /mo 1 /ru SYSTEM /rl HIGHEST
}

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ 已注册，每分钟运行一次（账户: SYSTEM）"
    Write-Host "   立即试跑一次..."
    schtasks /run /tn $taskName
    Start-Sleep -Seconds 3
    schtasks /query /tn $taskName /v /fo list | Select-String "上次结果|下次运行时间|状态"
    Write-Host ""
    Write-Host "日志: C:\VirtualDisplayDriver\keep_console.log （只有出问题时才写）"
} else {
    Write-Host "❌ 注册失败，请用管理员身份运行"
}
