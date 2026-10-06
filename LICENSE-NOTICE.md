# 版权与许可说明

## 重要：这不是原创项目

本仓库是 **wxauto_repost** 的**适配补丁版**，绝大部分代码来自上游。

| 项目 | 来源 | 许可 |
|---|---|---|
| **wxauto_repost** | https://github.com/luosheng520qaq/wxauto-repost-onebotv11 | **⚠️ 上游未见 LICENSE 文件，需自行确认** |
| **wechatauto-replica** | https://pypi.org/project/wechatauto-replica/ | Apache-2.0 |
| **Virtual-Display-Driver** | https://github.com/itsmikethetech/Virtual-Display-Driver | 见上游 |

## 发布建议（三选一）

1. **最稳妥**：先联系上游作者 [@luosheng520qaq](https://github.com/luosheng520qaq)，
   说明来意并询问是否可以作为分支/补丁发布。
2. **次稳**：仓库只放 **PATCHES.md**（改动说明）+ `system/`（自己写的系统脚本），
   不放上游源码；README 里指向上游仓库。
3. **若上游已声明开源许可**（MIT / Apache-2.0 等）：
   保留其 LICENSE 文件与版权声明，并注明本仓库做了哪些修改即可。

## 本仓库新增部分的版权

以下内容为本次适配**新增**，可自由使用：

- `PATCHES.md` 的全部内容
- `system/keep_console.ps1`
- `system/safedisconnect.bat`
- `README.md` 中「显示环境」一节

## 免责

本工具通过 GUI 自动化操作微信客户端。请遵守微信用户协议，仅用于**自己账号的个人自动化**，
不要用于骚扰、群发、营销等用途。由此产生的一切后果由使用者承担。
