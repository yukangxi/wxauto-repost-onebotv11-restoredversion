# 改动清单（原版 v1.2.0 → 本版）

**共 12 处。** 每处给出：**文件 / 原因 / 改法**。

**相关**：[README](README.md) · [接口文档](API.md)

---

## 目录

1. [依赖换库：wxauto → wechatauto-replica](#1-2-依赖换库wxauto--wechatauto-replica)
2. （同 1，含 metadata 与 requirements）
3. [窗口类名适配微信 4.x](#3-窗口类名适配微信-4x)
4. [补齐合并转发接口](#4-补齐合并转发接口)
5. [群消息改走发送链路](#5-群消息改走发送链路)
6. [X-Self-ID 一致性](#6-x-self-id-一致性关键)
7. [user_id 类型比较](#7-user_id-类型比较关键)
8. [监听方式：AddListenAll + 双路](#8-监听方式addlistenchat--addlistenall--双路)
9. [收消息去重](#9-收消息去重)
10. [清洗「发送者wxid:」前缀](#10-清洗内容里的发送者wxid前缀关键)
11. [微信窗口自动归位](#11-微信窗口自动归位)
12. [send_msg(group) 对齐](#12-send_msggroup-与-send_group_msg-对齐)
13. [附：非代码层的两件事](#附非代码层的两件事)

---

## 1-2. 依赖换库：wxauto → wechatauto-replica

**原因**：`wxauto` 只支持微信 3.9 及更早；3.9 已被官方强制升级拦截，且 PyPI 上**没有** `wxauto` 包。

**文件**

`requirements.txt`
```diff
- wxauto
- pyqt5
+ wechatauto-replica>=1.2.4
+ flask-cors>=4.0.0
```

`metadata.yaml`
```diff
 dependencies:
-  - "wxauto"
+  - "wechatauto-replica>=1.2.4"
```

`src/wechat_monitor.py`
```diff
- from wxauto import WeChat
+ from wechatauto import WeChat
```

---

## 3. 窗口类名适配微信 4.x

**原因**：微信 3.9 的窗口类名是 `WeChatMainWndForPC`；**4.x 改成了 `Qt51514QWindowIcon`**（Qt 窗口），按老类名找不到窗口。

`src/window_controller.py`
```diff
- WECHAT_WINDOW_CLASSES = ["WeChatMainWndForPC"]
+ WECHAT_WINDOW_CLASSES = ["Qt51514QWindowIcon", "WeChatMainWndForPC"]
```

---

## 4. 补齐合并转发接口

**原因**：AstrBot 在消息较长时会调用 `send_private_forward_msg` / `send_group_forward_msg`，原版没有实现这些 action → 报错。

`src/message_handler.py`
```python
def _handle_send_private_forward_msg(self, params):
    # 把 Node 合并转发摊平成纯文本，再走普通发送
    ...
def _handle_send_group_forward_msg(self, params):
    ...
```

---

## 5. 群消息改走发送链路

**原因**：原版 `send_group_msg` 是空实现，群消息发不出去。

`src/message_handler.py`
```diff
- def _handle_send_group_msg(self, params):
-     pass
+ def _handle_send_group_msg(self, params):
+     return self._handle_send_private_msg(params)   # 底层同一套
```

---

## 6. X-Self-ID 一致性（关键）

**原因**：插件发给 AstrBot 的 `X-Self-ID` 是写死的 `wxauto_bot`，而 AstrBot 按配置的 `self_id` 查连接表 → **查不到 → `aiocqhttp.exceptions.ApiNotAvailable`**。

`src/websocket_client.py`
```diff
- headers = {"X-Self-ID": "wxauto_bot", ...}
+ headers = {"X-Self-ID": self.onebot_converter.self_id or "wxauto_bot", ...}
```

`config/config.json`
```diff
- "self_id": "wxauto_bot"
+ "self_id": "10001000"
```

> **两者必须一致**，否则消息能收不能发。

---

## 7. user_id 类型比较（关键）

**原因**：配置里 `user_id` 是**字符串** `"258258"`，而 AstrBot 传过来的是 `int(session_id)` = **整数** `258258`。
`"258258" == 258258` → `False` → 匹配失败 → 兜底把**数字当昵称**去微信里找 → 找不到。

**表现**：日志里能看到它拿着 `258258` 而不是微信昵称「义和团」去搜。

`src/message_handler.py`（**两处**）
```diff
- if user.get('user_id') == user_id:
+ if str(user.get('user_id')) == str(user_id):
```

---

## 8. 监听方式：AddListenChat → AddListenAll（+ 双路）

**原因**：`AddListenChat` 靠**昵称**查找会话，而 wechatauto 的会话列表读取（UIA/OCR）不稳 ——
实测列表里只有 6 个会话，目标群经常**不在列表内** → 监听挂不上 → **群聊完全没反应**。

`src/wechat_monitor.py`
```diff
- self.wechat.AddListenChat(nickname=nickname, callback=self._on_message_callback)
+ # 全局监听：一次覆盖全部会话（含群聊、含新群）
+ self.wechat.AddListenAll(callback=self._on_message_callback, discover=True)
+ # 同时保留逐个挂载做双保险（重复由第 9 条去重挡住）
+ self.wechat.AddListenChat(nickname=nickname, callback=self._on_message_callback)
```

---

## 9. 收消息去重

**原因**：底层读微信数据库时会出现 `WAL 合并失败，改用仅主库快照`，同一条消息可能被**重复上报** →
表现为「消息重复发、乱发」。加上双路监听后重复概率更高。

`src/wechat_monitor.py`
```python
self._seen_msg = {}          # message_id -> timestamp

# 回调开头
mid = str(self._get_message_id(msg))
if mid in self._seen_msg:  return      # 20 秒内同一条只处理一次
self._seen_msg[mid] = time.time()
```

---

## 10. 清洗内容里的「发送者wxid:」前缀（关键）

**原因**：wechatauto 给群消息的 `content` 自带前缀，例如：

```
wxid_6anve9h3aryq12:
流萤你好
```

而 AstrBot 的**唤醒词检查是看开头**的 → 开头是 `wxid_...` → **"流萤" 不在开头 → 不唤醒 → 不回复**。

**表现**：日志里消息收到了，但 `Prepare to send` 永远不出现。

`src/wechat_monitor.py`
```python
content = str(message.content)

# 去掉「发送者wxid:」前缀
_sw = getattr(message, 'sender_wxid', None)
if _sw and content.startswith(_sw):
    content = content[len(_sw):].lstrip('：: \t\r\n')
# 兜底：首行形如 "xxxx:"（无空格、较短）则去掉该行
if '\n' in content:
    _first, _rest = content.split('\n', 1)
    if _first.strip().endswith(':') and 0 < len(_first.strip()) <= 64 and ' ' not in _first.strip():
        content = _rest
content = content.strip()
```

---

## 11. 微信窗口自动归位

**原因**：微信窗口会因分辨率变化 / RDP 连断而**漂到屏幕外**。
而 wechatauto 的**发送按钮定位在窗口宽度的 88%~98%** —— 窗口一漂，按钮就在屏幕外，**点不到**。

**表现**：`SendMsg` 抛 `RuntimeError: 屏幕截图失败 / 点击失败`。

`src/wechat_monitor.py`
```python
def _ensure_window_visible(self):
    """启动时检查微信窗口是否完整在屏幕内，不在就拉回 (5,5)"""
    ...
    if x0 < 0 or y0 < 0 or x1 > 屏宽 or y1 > 屏高:
        ShowWindow(h, SW_RESTORE)
        SetWindowPos(h, 0, 5, 5, min(1000, 屏宽-10), min(740, 屏高-10), 0)
```

在 `start()` 里、`_setup_listeners()` 之前调用。

---

## 附：非代码层的两件事

这两件不在代码里，但**缺了它整套跑不起来**（详见 README）：

1. **虚拟显示器**（`system/vdd_settings.xml`）
   让系统有一块**不跟 RDP 会话绑定**的屏。
2. **会话保活计划任务**（`system/keep_console.ps1`）
   Windows 里**「断开」状态的会话不渲染桌面** → 截屏失败 → 发不出消息。
   该脚本每分钟检查一次，掉回「断开」就 `tscon <id> /dest:console` 推回控制台。

---

## 12. send_msg(group) 与 send_group_msg 对齐

**原因**：`send_group_msg` 已经能发（见第 5 条），但 `send_msg` 里 `message_type == 'group'`
的分支却直接返回 `1404 group message not supported` —— **同一条路，两种结果**。
AstrBot 有时会用 `send_msg`，于是又发不出去。

`src/message_handler.py`
```diff
- elif message_type == 'group':
-     logger.warning(f"群消息发送暂不支持: group_id={group_id}")
-     self.websocket_client.send_api_response(echo, None, 1404, "group message not supported")
+ elif message_type == 'group':
+     logger.info(f"send_msg(group) 按普通消息发送: group_id={group_id}")
+     self._handle_send_private_msg({'user_id': group_id, 'message': params.get('message','')}, echo)
```
