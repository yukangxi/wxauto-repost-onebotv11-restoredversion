# 系统层脚本

这三个文件解决的是**同一件事**：让"没有远程桌面连接"的时候，桌面依然在渲染。

## 为什么需要

微信 PC 版的**发送**要靠截屏定位输入框。而 Windows 里：

| 会话状态 | 桌面渲染 | 能发消息 |
|---|---|---|
| 远程桌面连着（运行中） | ✅ | ✅ |
| **远程桌面断开（断开）** | ❌ | ❌ |

所以断开 RDP 后，机器人就"瞎"了。

## 三个文件

| 文件 | 用途 |
|---|---|
| `vdd_settings.xml` | 虚拟显示器配置。放到 `C:\VirtualDisplayDriver\`。让系统有一块**不跟 RDP 绑定**的显示器 |
| `keep_console.ps1` | 每分钟检查会话；掉回"断开"就 `tscon <id> /dest:console` 推回控制台 |
| `safedisconnect.bat` | 主动断开远程桌面时用它（保持会话活跃）。**别点右上角的 ×** |

## 安装步骤

### 1) 装虚拟显示器驱动

推荐 [Virtual-Display-Driver](https://github.com/itsmikethetech/Virtual-Display-Driver)
（**有正规签名，不需要开测试模式**）。

```powershell
pnputil /add-driver MttVDD.inf /install
```

然后把 `vdd_settings.xml` 放到 `C:\VirtualDisplayDriver\`。

### 2) 注册保活计划任务

```cmd
schtasks /create /tn "KeepConsoleSession" /f ^
  /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\VirtualDisplayDriver\keep_console.ps1" ^
  /sc minute /mo 1 /ru SYSTEM /rl HIGHEST
```

> 把 `keep_console.ps1` 也放到 `C:\VirtualDisplayDriver\`。

### 3) 验证

```powershell
# 会话应该显示 运行中，且挂在 console 上
query session

# 截屏应该能拿到内容（不是纯色）
python -c "from PIL import ImageGrab; i=ImageGrab.grab(); print(i.size, i.convert('L').getextrema())"
```

## 调分辨率

改 `vdd_settings.xml` 里的 `<resolutions>` 段，然后重启驱动设备：

```powershell
pnputil /restart-device "ROOT\MTTVDD\0000"
```

## 说明

- 计划任务**每分钟**跑一次，正常时**什么都不做**（不写日志、零干扰）
- 只有发现会话掉回"断开"时才会动作，并写入 `C:\VirtualDisplayDriver\keep_console.log`
