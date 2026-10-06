# 版权与许可

**相关**：[主 README](README.md)

---

## ⚠️ 这不是原创项目

本仓库是 **wxauto_repost** 的**适配补丁版**，绝大部分代码来自上游。

**上游**

- 项目：wxauto-repost-onebotv11
- 作者：汐灿（[@luosheng520qaq](https://github.com/luosheng520qaq)）
- 地址：<https://github.com/luosheng520qaq/wxauto-repost-onebotv11>
- 许可：**⚠️ 上游未见 LICENSE 文件，需自行确认**

**本版底层库**

- wechatauto-replica — Apache-2.0
- <https://pypi.org/project/wechatauto-replica/>

**虚拟显示器驱动**

- Virtual-Display-Driver — 见上游
- <https://github.com/itsmikethetech/Virtual-Display-Driver>

---

## 发布建议（三选一）

**1. 最稳妥**

先联系上游作者 [@luosheng520qaq](https://github.com/luosheng520qaq)，
说明来意并询问是否可作为分支/补丁发布。

**2. 次稳**

仓库**只放**以下内容，不放上游源码：

- `PATCHES.md`（改动说明）
- `API.md`
- `system/`（自写的系统脚本）

README 里指向上游仓库。

**3. 若上游已声明开源许可**

（MIT / Apache-2.0 等）
保留其 LICENSE 文件与版权声明，注明本仓库做了哪些修改即可。

---

## 本仓库新增部分的版权

**以下内容为本次适配新增，可自由使用：**

- `PATCHES.md` / `API.md` 全文
- `system/` 目录全部脚本
- `上传到GitHub.bat`

**以下源自原仓库，版权归原作者：**

- `main.py` / `src/` / `static/` / `config/` / `metadata.yaml`

---

## 免责

本工具通过 **GUI 自动化**操作微信客户端。

**请遵守微信用户协议，仅用于自己账号的个人自动化。**
**不要用于骚扰、群发、营销等用途。**

由此产生的一切后果由使用者承担。
