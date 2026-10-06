# wxauto_repost · wechatauto-replica 适配版

让 **AstrBot** 通过**微信 PC 版（4.1.12+）**收发消息。

> ### ⚠️ 这是修改版（Fork）
>
> 本仓库基于 **[wxauto-repost-onebotv11](https://github.com/luosheng520qaq/wxauto-repost-onebotv11)** 修改，
> **不是原创项目**。
>
> - 原作者：**汐灿**（[@luosheng520qaq](https://github.com/luosheng520qaq)）
> - 本版做了什么：把底层 `wxauto` 换成 `wechatauto-replica`，并修复 **12 个问题**
> - 逐条改动见 [PATCHES.md](PATCHES.md)
> - **许可：请以原仓库为准**（原仓库暂无 LICENSE）

---

## 目录

- [这是什么](#这是什么)
- [支持的系统](#支持的系统)
- [安装](#安装)
- [依赖](#依赖)
- [⚠️ 最容易踩的坑：桌面](#-最容易踩的坑桌面)
- [接口文档](API.md)
- [改动清单](PATCHES.md)
- [相关项目](#相关项目)
- [许可](#许可)

---

## 这是什么

上游插件 `wxauto_repost` 依赖 **wxauto**，而 wxauto 只支持微信 3.9 及更早。

**微信 3.9 已被官方强制升级拦截，老方案全线失效。**

本补丁把底层换成 **[wechatauto-replica](https://pypi.org/project/wechatauto-replica/)**
（支持微信 4.1.12+，Apache-2.0），并修复换库后暴露的问题。

**效果**：AstrBot 与微信 PC 端双向收发（私聊 / 群聊）。

---

## 支持的系统

**只有 Windows。** 因为底层依赖 Windows UI 自动化：

```
window_controller.py   win32gui / win32con     ← Windows API
wechat_monitor.py      pythoncom / user32      ← Windows API
requirements.txt       pywin32                 ← Windows 专用
```

### ✅ 支持

- **操作系统**：Windows 10 / 11（x64）
- **微信**：PC 版 **4.1.12 及以上**（实测 4.1.15.13）
- **AstrBot**：≥ 3.0.0
- **Python**：3.10+（实测 3.12）
- **架构**：x64（AMD64）

### ❌ 不支持

- Linux / macOS / Android
- 微信 **3.9 及以下**（已被官方拦截）
- **没有桌面的服务器**（除非装虚拟显示器，见下文）

### 实测通过的环境

```
Windows 10.0.19045  ·  Python 3.12.14  ·  x64
微信 4.1.15.13
```

---

## 安装

### 方式一：从仓库装（需联网装依赖）

```bash
# 1. 放进 AstrBot 插件目录
<AstrBot>/core/data/plugins/wxauto_repost/

# 2. 装依赖
pip install -r requirements.txt

# 3. AstrBot 面板 → 平台 → 新增 aiocqhttp
#    反向 WS 端口 7799，token 自定

# 4. 打开插件面板
http://127.0.0.1:10001
#    填 monitor_users（要监听的微信昵称）
#    点「启动服务」
```

### 方式二：下载 Release 包（**依赖已打包**）

到右侧 **Releases** 下载 `wxauto-repost-*.zip`。

**该包已内置全部依赖的 wheel**，离线也能装：

```bash
# 解压后
pip install --no-index --find-links wheels -r requirements.txt
```

> 只打包了 **AstrBot 不自带**的依赖。
> `astrbot` / `psutil` / `pillow` 等由 AstrBot 提供，**不在包内**。

---

## 依赖

**只有这 6 个需要装**（其余 AstrBot 自带）：

- `wechatauto-replica>=1.2.4` — 底层库（微信 4.1.12+ 自动化）
- `flask>=2.3.0`
- `flask-cors>=4.0.0`
- `websocket-client>=1.6.0`
- `requests>=2.31.0`
- `pywin32>=306` — Windows API 绑定

> AstrBot 自带里虽然有 `fastapi` / `websockets` / `httpx`，
> 但**和上面这些不是同一个库**，不能省略。

---

## ⚠️ 最容易踩的坑：桌面

**微信 PC 版的「发送」要靠屏幕截图定位输入框，所以必须有一个"正在渲染"的桌面。**

| 场景 | 能否收发 |
|---|---|
| 连着远程桌面 | ✅ |
| **断开远程桌面** | ❌ 截屏失败，发不出去 |
| 无头服务器 | ❌ |

### 解决：装虚拟显示器 + 会话保活

**两个都要装，缺一不可：**

- 只装虚拟显示器 → 会话还是"断开"状态 → 照样不渲染 ❌
- 只做保活 → 会话在控制台了，但没屏 → 还是黑 ❌
- **两个都装** → ✅

**[`system/`](system/README.md) 目录里有全套脚本**：

```powershell
cd system

# 1. 装虚拟显示器（-Download 自动拉驱动）
powershell -ExecutionPolicy Bypass -File 1-install-vdd.ps1 -Download

# 2. 注册会话保活（每分钟检查，掉了就推回控制台）
powershell -ExecutionPolicy Bypass -File 2-register-task.ps1

# 3. 自检（6 项，告诉你缺哪一步）
powershell -ExecutionPolicy Bypass -File 3-verify.ps1
```

详见 **[system/README.md](system/README.md)**。

---

## 原版 → 本版改了什么

**12 处改动**，逐条含前后代码见 **[PATCHES.md](PATCHES.md)**。

速览：

- 依赖 `wxauto` → `wechatauto-replica`
- 窗口类名加 `Qt51514QWindowIcon`（微信 4.x 变了）
- 补 `send_private_forward_msg` / `send_group_forward_msg`
- 群消息改走发送链路
- `X-Self-ID` 改为读配置
- `user_id` 比较加 `str()`
- 监听改 `AddListenAll` + 双路
- 收消息去重
- 清洗内容里的 `发送者wxid:` 前缀
- 微信窗口自动归位
- `send_msg(group)` 与 `send_group_msg` 对齐

---

## 相关项目

**本插件站在这些项目的肩膀上，感谢每一位作者。**

**核心**

- **wxauto-repost-onebotv11** — 本仓库的原型
  <https://github.com/luosheng520qaq/wxauto-repost-onebotv11>
- **AstrBot** — 机器人框架
  <https://github.com/AstrBotDevs/AstrBot>
- **wechatauto-replica** — 本版底层库
  <https://pypi.org/project/wechatauto-replica/>

**参考**

- **wxauto** — 原版底层（仅微信 3.9）
  <https://github.com/cluic/wxauto>
- **AstrBot 插件文档**
  <https://astrbot.app/dev/star/plugin.html>
- **OneBot v11 协议**
  <https://github.com/botuniverse/onebot-11>
- **aiocqhttp** — OneBot 适配
  <https://github.com/nonebot/aiocqhttp>
- **Virtual-Display-Driver** — 虚拟显示器
  <https://github.com/itsmikethetech/Virtual-Display-Driver>

---

## 许可

**本仓库是对上游项目的适配补丁，不是原创项目。**

### 本版新增（可自由使用）

- `PATCHES.md` / `API.md` 全文
- `system/` 全部脚本
- `上传到GitHub.bat`

### 源自原仓库（版权归原作者）

- `main.py` / `src/` / `static/` / `config/` / `metadata.yaml`

**⚠️ 发布或二次分发前，请先确认原仓库的许可。**

详见 [LICENSE-NOTICE.md](LICENSE-NOTICE.md)。

---

*本仓库由使用者自行修改维护，与原作者无关。使用后果由使用者承担。*
