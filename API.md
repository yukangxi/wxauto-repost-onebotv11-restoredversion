# 接口文档

OneBot v11 子集 —— 本插件实际支持的接口。

**相关**：[README](README.md) · [改动清单](PATCHES.md)

---

## 目录

- [通信方式](#通信方式)
- [支持的 action](#支持的-action)
- [上报的 event](#上报的-event)
- [错误码](#错误码)
- [不支持的接口](#不支持的接口)
- [快速自测](#快速自测)

---

## 通信方式

本插件在 AstrBot 里以**反向 WebSocket（aiocqhttp）**运行：

```
AstrBot  ──action──▶  插件  ──▶  微信
AstrBot  ◀──event───  插件  ◀──  微信
```

- 连接地址：`ws://<本机>:7799/ws`
- 握手头：`X-Self-ID`（= `config/config.json` 的 `self_id`）、`X-Client-Role: Universal`
- Token：与 AstrBot 平台配置一致

---

## 支持的 action

**共 7 个：**

- `send_private_msg` — 发私聊
- `send_group_msg` — 发群聊
- `send_msg` — 通用发送（private / group 都支持）
- `send_private_forward_msg` — 合并转发（**摊平为纯文本**）
- `send_group_forward_msg` — 同上
- `get_login_info` — 返回 self_id
- `get_status` — 返回在线状态

**其他 action → 返回 `1404`**

---

### send_private_msg

**请求**

```json
{
  "action": "send_private_msg",
  "params": { "user_id": 258258, "message": "你好" },
  "echo": "1"
}
```

**参数**

- `user_id` — 目标会话 ID（插件内部会映射成微信昵称）
- `message` — 文本，或 OneBot 消息段数组

**成功**

```json
{ "status": "ok", "retcode": 0, "data": { "message_id": 0 }, "echo": "1" }
```

**失败**

```json
{ "status": "failed", "retcode": 1404, "data": null, "echo": "1" }
```

> **注意**
> `user_id` 必须能在 `wechat.monitor_users` 里找到对应 `nickname`，
> 否则会拿数字当昵称去微信里找，必然失败。
> （本版已修正字符串/整数类型不一致的问题）

---

### send_group_msg

```json
{
  "action": "send_group_msg",
  "params": { "group_id": "义和团", "message": "你好" },
  "echo": "2"
}
```

`group_id` 在本插件里等价于**会话标识**（微信昵称或映射后的 id）。

> 上游把群消息当独立类型处理，容易发不出。
> 本版**统一走同一条发送链路**。

---

### send_msg（通用）

```json
{
  "action": "send_msg",
  "params": {
    "message_type": "private",
    "user_id": 258258,
    "message": "你好"
  },
  "echo": "3"
}
```

**`message_type` 取值**

- `private` → 等价 `send_private_msg`
- `group` → 等价 `send_group_msg`（本版已对齐）
- 其他 → 返回 `1400 invalid message_type`

---

### 合并转发

```json
{
  "action": "send_private_forward_msg",
  "params": {
    "user_id": 258258,
    "messages": [
      { "type": "node", "data": { "content": "…" } }
    ]
  },
  "echo": "4"
}
```

**本插件没有实现原生合并转发**，收到后会把节点内容**摊平成纯文本**再发。

> 微信侧看到的是一条普通文字消息，**不是"聊天记录"卡片**。
>
> AstrBot 的 `forward_threshold`（转发字数阈值）会触发这个接口。
> 想少走这条路，把阈值调大即可。

---

### get_login_info / get_status

```json
{ "action": "get_login_info", "echo": "5" }
```

```json
{
  "status": "ok",
  "retcode": 0,
  "data": { "user_id": "10001000", "nickname": "WxAuto Bot" },
  "echo": "5"
}
```

```json
{ "action": "get_status", "echo": "6" }
```

```json
{
  "status": "ok",
  "retcode": 0,
  "data": { "online": true, "good": true },
  "echo": "6"
}
```

---

## 上报的 event

### 消息事件

```json
{
  "post_type": "message",
  "message_type": "private",
  "sub_type": "friend",
  "message_id": 1234567890,
  "user_id": "258258",
  "message": "流萤你好",
  "raw_message": "流萤你好",
  "font": 0,
  "self_id": "10001000",
  "time": 1791278957,
  "sender": { "user_id": "258258", "nickname": "义和团" }
}
```

**字段说明**

- `message_type` — **恒为 `private`**（上游设计如此，群消息也发成私聊）
- `user_id` — 由 `nickname` 反查 `monitor_users` 得到
- `message` — **已清洗**掉 `发送者wxid:` 前缀（本版修复）
- `self_id` — 与握手头 `X-Self-ID` 一致

> ⚠️ **群聊在 AstrBot 侧被当成私聊**，因此：
> - 白名单要按 `微信:FriendMessage:<user_id>` 格式加
> - 「私聊消息需要唤醒词」这一项**也会管到群聊**

### 心跳

```json
{
  "post_type": "meta_event",
  "meta_event_type": "heartbeat",
  "time": 1791278957,
  "self_id": "10001000",
  "status": { "online": true, "good": true }
}
```

---

## 错误码

- **0** — 成功
- **1400** — 参数错误（如 `message_type` 非法）
- **1404** — 未找到目标 / 接口未实现
- **1500** — 插件内部异常

---

## 不支持的接口

以下 OneBot v11 接口**没有实现**，调用会返回 `1404`：

**群管理类**

- `set_group_kick` / `set_group_ban` / `set_group_card`

**信息查询类**

- `get_friend_list` / `get_group_list`
- `get_group_member_info` / `get_stranger_info`

**媒体类**

- `get_image` / `get_record`
- （图片、文件通过消息段发送时是支持的）

**好友 / 群操作类**

- `set_friend_add_request` / `set_group_add_request`

**其他**

- `get_version_info` / `set_restart`

> 需要哪些可以提 issue，底层 wechatauto 部分能力是具备的。

---

## 快速自测

**1. 连接是否建立**

```bash
curl http://127.0.0.1:10001/api/status
```

看 `onebot.connected` 是否为 `true`。

**2. 直接测发送（不经过 AstrBot）**

```bash
python -c "from wechatauto import WeChat; print(WeChat().SendMsg('测试','文件传输助手'))"
```

- 返回 `{'status': '成功', ...}` → 微信侧发送链路正常
- 抛 `screen grab failed` → **桌面没有渲染**，见 [system/README.md](system/README.md)
