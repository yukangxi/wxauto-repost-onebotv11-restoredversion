# system/ — 让机器人"断开远程桌面也能收发"

## 问题

微信 PC 版的**发送**靠截屏定位输入框。而 Windows 里：

| 会话状态 | 桌面渲染 | 能发消息 |
|---|---|---|
| 远程桌面连着（运行中） | ✅ | ✅ |
| **远程桌面断开（断开）** | ❌ | ❌ 截屏失败 |
| 无头服务器（无显示器） | ❌ | ❌ |

**所以"断开 RDP 后机器人就哑了"。** 这个目录解决它。

---

## 三步搞定

**全部用管理员 PowerShell 运行。**

```powershell
cd <本目录>

# 第 1 步：装虚拟显示器驱动 + 创建设备
powershell -ExecutionPolicy Bypass -File 1-install-vdd.ps1 -Download

# 第 2 步：注册"会话保活"计划任务（每分钟自动检查）
powershell -ExecutionPolicy Bypass -File 2-register-task.ps1

# 第 3 步：自检
powershell -ExecutionPolicy Bypass -File 3-verify.ps1
```

**第 3 步输出全绿，就成了。**

---

## 文件说明

| 文件 | 作用 |
|---|---|
| **`1-install-vdd.ps1`** | 装虚拟显示器驱动 + 建根枚举设备。`-Download` 会自动从 GitHub 拉驱动 |
| **`2-register-task.ps1`** | 注册/卸载计划任务 `KeepConsoleSession`（每分钟检查会话状态） |
| **`3-verify.ps1`** | 一条命令自检 6 项：会话 / 显示设备 / **桌面渲染** / 计划任务 / 微信进程 / 发送实测 |
| `keep_console.ps1` | 计划任务实际执行的脚本：会话掉回「断开」就 `tscon` 推回控制台 |
| `safedisconnect.bat` | 主动断开远程桌面时用它（保持会话活跃）。**别点右上角 ×** |
| `vdd_settings.xml` | 虚拟显示器配置（分辨率 / 刷新率） |

---

## 三步分别在做什么

### 1-install-vdd.ps1 —— 让它"有屏幕"

装一个**不跟 RDP 会话绑定**的虚拟显示器。

- 驱动来自 [Virtual-Display-Driver](https://github.com/itsmikethetech/Virtual-Display-Driver)（**有正规签名，不需要开测试模式**）
- `pnputil /add-driver` 只能把驱动**加进仓库**，**不会建设备** —— 所以脚本用 SetupAPI 手动创建 `Root\MttVDD` 根枚举设备
- 配置文件写到 `C:\VirtualDisplayDriver\vdd_settings.xml`

### 2-register-task.ps1 —— 让它"一直醒着"

Windows 里**「断开」状态的会话不渲染桌面**。这个计划任务每分钟检查一次：

```
会话是"运行中"  → 什么都不做（零干扰）
会话变"断开"    → tscon <id> /dest:console 推回控制台
```

出问题时才写日志：`C:\VirtualDisplayDriver\keep_console.log`

### 3-verify.ps1 —— 告诉你到底哪一步没到位

```
[1] 会话状态
[2] 显示设备        ← 应该能看到 "Virtual Display Driver"
[3] 桌面渲染        ← ★ 最关键的一项
[4] 计划任务
[5] 微信进程
[6] 发送实测        ← 真的发一条到「文件传输助手」
```

---

## 为什么两个都要装

```
只装虚拟显示器（不保活）→ 显示器有了，但会话"断开" → 还是不渲染 ❌
只保活（不装显示器）    → 会话在控制台了，但没屏   → 还是黑     ❌
两个都装 ✅             → 会话在控制台 + 有独立屏   → 正常渲染 ✅
```

**缺一不可。**

---

## 手动操作（不想用脚本时）

```powershell
# 装驱动
pnputil /add-driver MttVDD.inf /install

# 注册计划任务
schtasks /create /tn "KeepConsoleSession" /f ^
  /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\VirtualDisplayDriver\keep_console.ps1" ^
  /sc minute /mo 1 /ru SYSTEM /rl HIGHEST

# 手动推会话到控制台
tscon <会话ID> /dest:console
```

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File 2-register-task.ps1 -Remove
pnputil /remove-device "ROOT\MTTVDD\0000"
```

---

## 注意

- 驱动本体来自第三方，**本仓库不再分发**，请从[上游](https://github.com/itsmikethetech/Virtual-Display-Driver)获取
- `tscon` 会**断开你当前的远程桌面**（这是正常的，会话会留在控制台继续跑）
- 改分辨率：编辑 `vdd_settings.xml` 的 `<resolutions>`，然后 `pnputil /restart-device "ROOT\MTTVDD\0000"`
