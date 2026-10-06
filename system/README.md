# system/ — 让它"断开远程桌面也能收发"

**相关**：[主 README](../README.md) · [接口文档](../API.md)

---

## 为什么需要这个目录

微信 PC 版的**发送**靠截屏定位输入框。
而 Windows 里，**「断开」状态的会话不渲染桌面**：

- 远程桌面连着 → ✅ 能收发
- **断开远程桌面 → ❌ 截屏失败，发不出去**
- 无头服务器（没显示器）→ ❌

**这就是"断开 RDP 后机器人就哑了"的根本原因。**

---

## 日常使用：出了问题就跑这一个

**双击 `启动虚拟屏幕.bat`**（或管理员 PowerShell 跑 `0-start-display.ps1`）。

**它做四件事：**

```
[1/4] 检查虚拟显示设备在不在
[2/4] 被禁用了就启用
[3/4] 重启设备，让配置生效
[4/4] 把微信所在会话推回控制台
```

**什么时候用：**

- 睡眠 / 唤醒之后，机器人突然发不出消息
- 手动改过分辨率
- 设备被禁用过
- 换远程桌面连接后状态不对

**就绪的样子**：能看到 `Virtual Display Driver`，且会话是「运行中」。

---

## 三步解决

**全部用管理员 PowerShell 运行。**

```powershell
cd system

# 1. 装虚拟显示器（让它"有屏幕"）
powershell -ExecutionPolicy Bypass -File 1-install-vdd.ps1 -Download

# 2. 注册会话保活（让它"一直醒着"）
powershell -ExecutionPolicy Bypass -File 2-register-task.ps1

# 3. 自检
powershell -ExecutionPolicy Bypass -File 3-verify.ps1
```

**第 3 步全绿，就成了。**

---

## 缺一不可

- 只装虚拟显示器 → 会话还是「断开」→ **照样黑** ❌
- 只做保活 → 会话在控制台了，**但没屏** → 还是黑 ❌
- **两个都装** → ✅

---

## 文件说明

**自动化脚本**

- `0-start-display.ps1` / `启动虚拟屏幕.bat` — **日常用这个**，一键启用虚拟屏幕
- `1-install-vdd.ps1` — 首次安装：装驱动 + 创建根枚举设备
- `2-register-task.ps1` — 注册/卸载保活计划任务
- `3-verify.ps1` — 6 项自检

**配置与运行时**

- `keep_console.ps1` — 计划任务实际执行的脚本
- `safedisconnect.bat` — 主动断开远程桌面时用它
- `vdd_settings.xml` — 虚拟显示器配置

---

## 1-install-vdd.ps1

装一个**不跟 RDP 会话绑定**的虚拟显示器。

**做了什么**

1. 检查驱动签名（应为 Valid，**不需要开测试模式**）
2. `pnputil /add-driver` 把驱动包加进系统仓库
3. **用 SetupAPI 手动创建 `Root\MttVDD` 根枚举设备**
4. 写配置到 `C:\VirtualDisplayDriver\vdd_settings.xml`

> ⚠️ **第 3 步是必须的**：
> `pnputil` 只会把驱动**加进仓库**，**不会创建设备**。
> 必须用 SetupAPI（脚本已内置）。

**参数**

- `-Download` — 没有驱动时自动从 GitHub 下载
- `-DriverDir <路径>` — 手动指定 MttVDD.inf 所在目录

**驱动来源**

[Virtual-Display-Driver](https://github.com/itsmikethetech/Virtual-Display-Driver)
（**本仓库不重新分发驱动**，请从上游获取）

---

## 2-register-task.ps1

注册计划任务 `KeepConsoleSession`，**每分钟**检查一次：

```
会话是「运行中」 → 什么都不做（零干扰）
会话变「断开」   → tscon <id> /dest:console 推回控制台
```

**参数**

- 无 — 注册
- `-Remove` — 卸载

**日志**（只有出问题时才写）

```
C:\VirtualDisplayDriver\keep_console.log
```

---

## 3-verify.ps1

一条命令告诉你**到底缺哪一步**：

```
[1] 会话状态
[2] 显示设备        ← 应看到 "Virtual Display Driver"
[3] 桌面渲染        ← ★ 最关键
[4] 计划任务
[5] 微信进程
[6] 发送实测        ← 真发一条到「文件传输助手」
```

**失败对应关系**

- `[3]` 失败 → 断开 RDP 了，或没装虚拟显示器 → 跑 `1-install-vdd.ps1`
- `[4]` 失败 → 没注册保活任务 → 跑 `2-register-task.ps1`
- `[6]` 失败 → 看 `keep_console.log`

---

## 手动操作（不想用脚本）

```powershell
# 装驱动
pnputil /add-driver MttVDD.inf /install

# 注册计划任务
schtasks /create /tn "KeepConsoleSession" /f /tr ^
  "powershell -NoProfile -ExecutionPolicy Bypass -File C:\VirtualDisplayDriver\keep_console.ps1" ^
  /sc minute /mo 1 /ru SYSTEM /rl HIGHEST

# 手动推会话到控制台
tscon <会话ID> /dest:console
```

---

## 改分辨率

编辑 `vdd_settings.xml` 里的 `<resolutions>` 段，然后：

```powershell
pnputil /restart-device "ROOT\MTTVDD\0000"
```

---

## 卸载

```powershell
# 卸计划任务
powershell -ExecutionPolicy Bypass -File 2-register-task.ps1 -Remove

# 卸设备
pnputil /remove-device "ROOT\MTTVDD\0000"
```

---

## 注意

- **`tscon` 会断开你当前的远程桌面** —— 这是正常的，会话会留在控制台继续跑
- 驱动本体来自第三方，**本仓库不再分发**
- 如果你从不使用远程桌面（本地一直开着），**可能不需要这套**

---

## ⚠️ 计划任务必须用 Administrator 跑，不能用 SYSTEM

**原因**：**SYSTEM 账户无法操作交互式会话** —— `tscon` 会**静默失败**。

**表现**：任务显示"上次结果 0"（成功），但断开远程桌面后机器人**照样发不出消息**。

**正确写法**（`2-register-task.ps1` 已内置）：

```cmd
schtasks /create /tn "KeepConsoleSession" /f ^
  /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\VirtualDisplayDriver\keep_console.ps1" ^
  /sc minute /mo 1 /ru %COMPUTERNAME%\%USERNAME% /rl HIGHEST /it
```

关键在 `/ru <你> /rl HIGHEST /it` —— **`/it` 表示"仅交互式"**，这样它才能操作桌面会话。


---

## ⚠️ 重要更正：不要用计划任务，用常驻守护

**实测发现**：某些 Windows 机器上**任务计划程序完全无法执行任务** ——
`SYSTEM` / `S4U` / `交互式` 三种登录类型全试过，任务状态显示 `Queued`、`上次结果 0`，
**但脚本一行都没跑**（用"写标记文件"的方式验证过，标记文件从不生成）。

**所以保活改用常驻进程 + 启动文件夹：**

```powershell
cd system
powershell -ExecutionPolicy Bypass -File 4-install-autostart.ps1
```

**它做三件事：**

1. 部署 `keep_console_loop.ps1` 到 `C:\VirtualDisplayDriver\`
2. **立刻启动**一个隐藏窗口的守护进程（每 60 秒检查一次）
3. 在"启动"文件夹放一个快捷方式 → **开机/登录自动起**

**卸载：**

```powershell
powershell -ExecutionPolicy Bypass -File 4-install-autostart.ps1 -Uninstall
```

**优点：**

- 不依赖任务计划程序 ✅
- 跑在你的会话里 → `tscon` 有效 ✅
- 断开远程桌面后继续跑 ✅
- 重启后自动恢复 ✅

**代价**：一个常驻 powershell 进程（约 30 MB 内存）

### 为什么计划任务会失败

系统层面的原因不明（可能是策略或环境差异）。
**对使用者来说不重要 —— 用守护进程就绕过去了。**

（`2-register-task.ps1` 保留着，在任务计划程序正常的机器上仍然可用，
  但它不是推荐方式。）
