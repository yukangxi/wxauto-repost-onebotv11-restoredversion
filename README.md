> # ⚠️ 这是修改版（Fork / Modified Version）
>
> 本仓库是 **[wxauto-repost-onebotv11](https://github.com/luosheng520qaq/wxauto-repost-onebotv11)** 的**修改版**，
> **不是原创项目**。原作者 **汐灿**（[@luosheng520qaq](https://github.com/luosheng520qaq)）。
>
> **本版做了什么**：把底层 `wxauto`（只支持微信 3.9，且 3.9 已被官方强制升级拦截）
> 换成 **[wechatauto-replica](https://pypi.org/project/wechatauto-replica/)**（支持微信 4.1.12+），
> 并修复了由此暴露的 **12 个问题**。逐条见 [PATCHES.md](PATCHES.md)。
>
> | | |
> |---|---|
> | **原插件仓库** | https://github.com/luosheng520qaq/wxauto-repost-onebotv11 |
> | **本修改版仓库** | https://github.com/yukangxi/wxauto-repost-onebotv11-restoredversion |
> | **许可** | 请以原仓库为准（原仓库暂未见 LICENSE，发布前请先确认） |

# wxauto_repost · wechatauto-replica 适配版

> 让 **AstrBot** 通过 **微信 PC 版（4.1.12+）** 收发消息的补丁包。
>
> 基于 [wxauto_repost](https://github.com/luosheng520qaq/wxauto-repost-onebotv11) v1.2.0 改造。

---

## 这是什么

上游插件 `wxauto_repost` 依赖 **wxauto**，而 wxauto 只支持微信 3.9 及更早版本。
微信 3.9 已被官方强制升级拦截，**老方案全线失效**。

本补丁把底层换成 **[wechatauto-replica](https://pypi.org/project/wechatauto-replica/)**
（支持微信 4.1.12+，Apache-2.0），并修复了换库后暴露出的 **11 个问题**。

**效果**：AstrBot 与微信 PC 端双向收发（私聊 / 群聊）。

---

---

## 支持的系统与环境

### 硬性要求

| 项目 | 要求 | 说明 |
|---|---|---|
| **操作系统** | **Windows 10 / 11（x64）** | ❌ **不支持 Linux / macOS / Android** |
| **微信** | **PC 版 4.1.12 及以上** | 实测 4.1.15.13 ✅；**3.9 已不可用**（官方强制升级拦截） |
| **CPU** | **x64（AMD64）** | ARM64 未测试 |
| **AstrBot** | **≥ 3.0.0** | |
| **Python** | **3.10+** | 实测 3.12.14 |
| **网络** | 能访问互联网（插件本体） | 国内访问 GitHub 可能不稳定 |

### 为什么只支持 Windows

底层 `wechatauto` 依赖 **Windows UI 自动化**：

```
src/window_controller.py   win32gui / win32con        ← 纯 Windows API
src/wechat_monitor.py      pythoncom / ctypes.windll / user32
requirements.txt           pywin32                    ← Windows 专用包
```

微信 PC 版本身也只有 Windows / macOS 版本，而本项目走的是 **Windows 客户端自动化**。

### ⚠️ 最容易被忽略的门槛：桌面

**微信 PC 版的「发送」要靠屏幕截图定位输入框。所以必须有一个"正在渲染"的桌面。**

| 场景 | 能否收发 |
|---|---|
| 连着远程桌面（会话"运行中"） | ✅ 可以 |
| 断开远程桌面（会话"断开"） | ❌ **发不出去**（截屏失败） |
| 无头服务器 / 没有显示器 | ❌ **必须有虚拟显示器** |

**解决方案见 [`system/README.md`](system/README.md)**：

1. **虚拟显示器驱动**（`vdd_settings.xml`）—— 让系统有一块不跟 RDP 走的屏
2. **会话保活计划任务**（`keep_console.ps1`）—— 每分钟把掉回「断开」的会话推回控制台
3. **安全断开工具**（`safedisconnect.bat`）—— 主动断开时用它，别点右上角 ×

### 依赖

```
wechatauto-replica>=1.2.4     底层（微信 4.1.12+ 自动化）
flask>=2.3.0
flask-cors>=4.0.0
websocket-client>=1.6.0
requests>=2.31.0
pywin32>=306                  Windows API 绑定
```

`astrbot` 框架、`psutil`、`pillow` 等由 AstrBot 自带，无需声明。

---

## 快速开始

```bash
# 1. 安装依赖
pip install wechatauto-replica websocket-client flask requests flask-cors

# 2. 放进 AstrBot 插件目录
#    <AstrBot>/core/data/plugins/wxauto_repost/

# 3. 配置 OneBot 平台（AstrBot 侧）
#    类型 aiocqhttp / 反向 WS 端口 7799 / token 自定

# 4. 打开插件面板
#    http://127.0.0.1:10001
#    → 填 monitor_users（要监听的微信昵称）
#    → 点「启动服务」
```

详细步骤见 **[INSTALL.md](INSTALL.md)**；接口清单见 **[API.md](API.md)**。

---

## ⚠️ 重要：需要一套"不会被断开搞瞎"的显示环境

微信 PC 版的**发送**依赖屏幕截图定位输入框。而 Windows 有一个坑：

| 会话状态 | 桌面是否渲染 | 能发消息吗 |
|---|---|---|
| 连着远程桌面（运行中） | ✅ | ✅ |
| **断开远程桌面（断开）** | ❌ 不渲染 | ❌ 截屏失败 |

**所以"断开 RDP 后机器人就瞎了"**。本仓库的 `system/` 目录给了一套解决方案：

| 文件 | 作用 |
|---|---|
| `system/vdd_settings.xml` | 虚拟显示器配置（让系统有一块**不跟 RDP 走**的屏） |
| `system/keep_console.ps1` | 每分钟检查会话，掉回"断开"就自动推回控制台 |
| `system/safedisconnect.bat` | 主动断开时用（保持会话活跃，别点右上角 ×） |

配套步骤：

1. 安装虚拟显示器驱动（推荐 [Virtual-Display-Driver](https://github.com/itsmikethetech/Virtual-Display-Driver)，**有正规签名，无需测试模式**）
2. 把 `vdd_settings.xml` 放到 `C:\VirtualDisplayDriver\`
3. 注册计划任务，每分钟跑 `keep_console.ps1`：
   ```cmd
   schtasks /create /tn "KeepConsoleSession" /f ^
     /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\VirtualDisplayDriver\keep_console.ps1" ^
     /sc minute /mo 1 /ru SYSTEM /rl HIGHEST
   ```

**做完这三步，你就可以随便连、随便断 RDP，机器人始终能收发。**

---

## 原版 → 本版 改了什么

**11 处改动**，详见 **[PATCHES.md](PATCHES.md)**。摘要：

| # | 改动 | 解决的问题 |
|---|---|---|
| 1 | 依赖 `wxauto` → `wechatauto-replica` | 原库不支持微信 4.x |
| 2 | `from wxauto` → `from wechatauto` | 同上 |
| 3 | 窗口类名加 `Qt51514QWindowIcon` | 微信 4.x 窗口类名变了，找不到窗口 |
| 4 | 补 `send_private_forward_msg` / `send_group_forward_msg` | AstrBot 调用这些接口时报错 |
| 5 | 群消息改走发送链路 | 原版群消息发不出去 |
| 6 | `X-Self-ID` 改为读配置 | 写死的 ID 与 AstrBot 侧不一致 → `ApiNotAvailable` |
| 7 | `user_id` 比较加 `str()` | 配置是字符串、传参是整数 → 永远匹配不上 |
| 8 | 监听改 `AddListenAll` + 逐会话双路 | 按名字挂监听不稳，群聊经常挂不上 |
| 9 | 收消息去重 | 底层读库不稳会导致同一条消息重复处理 |
| 10 | 清洗内容中的 `发送者wxid:` 前缀 | 唤醒词检查看开头，前缀把内容挡住了 |
| 11 | 微信窗口自动归位 | 窗口漂出屏幕 → 发送按钮点不到 → 发不出 |

---

## 已知限制

- **群聊/私聊在 AstrBot 侧都表现为私聊**（上游 `onebot_converter.py` 把 `message_type` 写死为 `private`）
- 依赖 GUI 自动化，**必须有可渲染的桌面**（见上文）
- 微信窗口**不要最小化**（可被 `_ensure_window_visible` 拉回，但最小化状态下无效）

---

## 版权与许可

本仓库是**对上游项目的适配补丁**，**不是原创项目**。

| 项目 | 作者 / 来源 | 许可 |
|---|---|---|
| wxauto_repost | [@luosheng520qaq](https://github.com/luosheng520qaq/wxauto-repost-onebotv11)（汐灿） | **需自行确认**（上游未见 LICENSE） |
| wechatauto-replica | PyPI | Apache-2.0 |
| Virtual-Display-Driver | [@itsmikethetech](https://github.com/itsmikethetech/Virtual-Display-Driver) | 见上游仓库 |

**⚠️ 发布前请先向上游作者确认许可，或改为仅发布 `PATCHES.md` 中的补丁说明**。
详见 [LICENSE-NOTICE.md](LICENSE-NOTICE.md)。

---

## 致谢

- 上游插件作者 **汐灿** — 提供了完整的框架与 WebUI
- `wechatauto-replica` 的作者 — 让微信 4.x 自动化成为可能
- `Virtual-Display-Driver` 的作者 — 解决了无头环境渲染问题


---

## 相关项目与出处

本插件站在这些项目的肩膀上。**感谢每一位作者。**

| 项目 | 作用 | 地址 |
|---|---|---|
| **wxauto-repost-onebotv11** | **本仓库的原型**（原作者：汐灿） | https://github.com/luosheng520qaq/wxauto-repost-onebotv11 |
| **AstrBot** | 机器人框架（本插件运行其中） | https://github.com/AstrBotDevs/AstrBot |
| **AstrBot 插件文档** | 插件开发规范 | https://astrbot.app/dev/star/plugin.html |
| **wxauto** | 原版底层库（仅支持微信 3.9） | https://github.com/cluic/wxauto |
| **wechatauto-replica** | **本版底层库**（支持微信 4.1.12+） | https://pypi.org/project/wechatauto-replica/ |
| **OneBot v11** | 通信协议标准 | https://github.com/botuniverse/onebot-11 |
| **aiocqhttp** | AstrBot 侧的 OneBot 适配 | https://github.com/nonebot/aiocqhttp |
| **Virtual-Display-Driver** | 虚拟显示器（无头环境渲染） | https://github.com/itsmikethetech/Virtual-Display-Driver |
| **Git for Windows** | 本仓库附带脚本依赖 | https://gitforwindows.org |

### 本版新增的部分（可自由使用）

- `PATCHES.md` 的全部内容
- `API.md`
- `system/` 目录（`keep_console.ps1` / `safedisconnect.bat` / `vdd_settings.xml`）
- `上传到GitHub.bat`

### 原版部分

`main.py` / `src/` / `static/` / `config/` / `metadata.yaml` 等**源自原仓库**，
版权归原作者所有。**发布或二次分发前，请先确认原仓库的许可。**

---

*本仓库由使用者自行修改与维护，与原作者无关。使用本插件产生的任何后果由使用者承担。*
