# 接口文档（OneBot v11 子集）

本插件在 AstrBot 里以 **反向 WebSocket（aiocqhttp）** 方式运行：

```
AstrBot  --(action / 调用)-->  插件  --(wechatauto)-->  微信
AstrBot  <--(event  / 上报)--  插件  <--(读数据库)---  微信
```

- 连接地址：`ws://<插件所在机>:7799/ws`
- 握手头：`X-Self-ID`（= `config/config.json` 里的 `self_id`）、`X-Client-Role: Universal`
- Token：与 AstrBot 平台配置一致

---

## 一、插件支持的 action（AstrBot → 插件）

| action | 状态 | 说明 |
|---|---|---|
| `send_private_msg` | ✅ 支持 | 发私聊 |
| `send_group_msg` | ✅ 支持 | 发群聊（走同一条链路） |
| `send_msg` | ✅ 支持 | 通用发送，`private`/`group` 都支持 |
| `send_private_forward_msg` | ✅ 支持 | 合并转发 → **摊平成纯文本**发送 |
| `send_group_forward_msg` | ✅ 支持 | 同上 |
| `get_login_info` | ✅ 支持 | 返回 self_id |
| `get_status` | ✅ 支持 | 返回在线状态 |
| 其他 | ❌ 返回 1404 | 未实现 |

### 1.1 send_private_msg

```json
{
  "action": "send_private_msg",
  "params": { "user_id": 258258, "message": "你好" },
  "echo": "1"
}
```

| 参数 | 类型 | 说明 |
|---|---|---|
| `user_id` | str \| int | 目标会话的 user_id（**插件内部会映射成微信昵称**） |
| `message` | str \| array | 文本，或 OneBot 消息段数组 |

**成功**
```json
{ "status": "ok", "retcode": 0, "data": { "message_id": 0 }, "echo": "1" }
```
**失败**
```json
{ "status": "failed", "retcode": 1404, "data": null, "echo": "1" }
```

> **注意**：`user_id` 必须能在插件配置 `wechat.monitor_users` 里找到对应的 `nickname`，
> 否则会拿数字当昵称去微信里找，必然失败。
> （本版已修正**字符串/整数**类型不一致的问题）

---

### 1.2 send_group_msg

```json
{
  "action": "send_group_msg",
  "params": { "group_id": "义和团", "message": "你好" },
  "echo": "2"
}
```

**参数**：`group_id` 在本插件里等价于**会话标识**（微信昵称或映射后的 id）。

> 上游把群消息当作独立类型处理，容易发不出。本版**统一走同一条发送链路**。

---

### 1.3 send_msg（通用）

```json
{
  "action": "send_msg",
  "params": { "message_type": "private", "user_id": 258258, "message": "你好" },
  "echo": "3"
}
```

| `message_type` | 行为 |
|---|---|
| `private` | 等价 `send_private_msg` |
| `group` | 等价 `send_group_msg`（本版已对齐） |
| 其他 | 返回 `1400 invalid message_type` |

---

### 1.4 合并转发（*_forward_msg）

```json
{
  "action": "send_private_forward_msg",
  "params": { "user_id": 258258, "messages": [ { "type": "node", "data": { "content": "…" } } ] },
  "echo": "4"
}
```

**本插件没有实现原生合并转发**，收到后会把节点内容**摊平成纯文本**再发。
（微信侧看到的就是一条普通文字消息，不是"聊天记录"卡片）

> AstrBot 的 `forward_threshold`（转发字数阈值）会触发这个接口。
> 若希望少走这条路，把阈值调大即可。

---

### 1.5 get_login_info / get_status

```json
{ "action": "get_login_info", "echo": "5" }
→ { "status": "ok", "retcode": 0, "data": { "user_id": "10001000", "nickname": "WxAuto Bot" }, "echo": "5" }

{ "action": "get_status", "echo": "6" }
→ { "status": "ok", "retcode": 0, "data": { "online": true, "good": true }, "echo": "6" }
```

---

## 二、插件上报的 event（插件 → AstrBot）

### 2.1 消息事件

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

| 字段 | 说明 |
|---|---|
| `message_type` | **恒为 `private`**（上游设计如此，群消息也发成私聊） |
| `user_id` | 由 `nickname` 反查 `monitor_users` 得到 |
| `message` | **已清洗**掉 `发送者wxid:` 前缀（本版修复） |
| `self_id` | 与握手头 `X-Self-ID` 一致 |

> ⚠️ **群聊在 AstrBot 侧被当成私聊**。因此：
> - 白名单要按 `微信:FriendMessage:<user_id>` 的格式加
> - 「私聊消息需要唤醒词」这项也会管到群聊

### 2.2 心跳

```json
{ "post_type": "meta_event", "meta_event_type": "heartbeat", "time": 1791278957, "self_id": "10001000", "status": { "online": true, "good": true } }
```

---

## 三、错误码

| retcode | 含义 |
|---|---|
| `0` | 成功 |
| `1400` | 参数错误（如 `message_type` 非法） |
| `1404` | 未找到目标 / 接口未实现 |
| `1500` | 插件内部异常 |

---

## 四、本版修复的接口相关问题

| 问题 | 现象 | 修复 |
|---|---|---|
| `X-Self-ID` 与 AstrBot 侧不一致 | `aiocqhttp.exceptions.ApiNotAvailable` | 改为读配置 |
| `send_*_forward_msg` 未实现 | 长消息报错 | 补上并摊平为文本 |
| `send_group_msg` 空实现 | 群消息发不出 | 走同一链路 |
| `send_msg(group)` 返回 1404 | 同一条路两种结果 | 与 `send_group_msg` 对齐 |
| `user_id` 类型不一致 | 拿数字当昵称，找不到人 | 比较时 `str()` |
| 消息内容带 `发送者wxid:` 前缀 | 唤醒词不生效，不回复 | 上报前清洗 |

---

## 五、不在支持范围内的能力

以下 OneBot v11 接口**没有实现**（会返回 1404）：

- 群管理类：`set_group_kick` / `set_group_ban` / `set_group_card` …
- 信息查询类：`get_friend_list` / `get_group_list` / `get_group_member_info` / `get_stranger_info` …
- 媒体类：`get_image` / `get_record`（图片/文件走消息段发送）
- 好友/群操作类：`set_friend_add_request` / `set_group_add_request` …
- 其他：`get_version_info` / `set_restart` …

> 需要哪些可以提 issue，底层的 wechatauto 部分能力是具备的。

---

## 六、快速自测

```bash
# 1. 连接是否建立（看插件面板 WebUI 的 onebot.connected）
curl http://127.0.0.1:10001/api/status

# 2. 直接测发送（不经过 AstrBot）
python -c "from wechatauto import WeChat; print(WeChat().SendMsg('测试','文件传输助手'))"
```

`SendMsg` 返回 `{'status': '成功', ...}` 表示微信侧发送链路 OK；
若抛 `screen grab failed`，说明**桌面没有渲染** —— 见 `system/README.md`。
