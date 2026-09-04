# xboard-node-mips

xboard-node 的 MIPS (mipsel) 交叉编译版 + **一键批量安装脚本**，用于 MoFi / OpenWrt (MediaTek MT7621) 路由器。

本仓库包含：

- **Release 资产**：`xboard-node-linux-mipsle.gz`（旧核心，带 singbox+xray 双内核，面板 tuic 节点可用）、以及 `.xz` 备选。
- **`install.sh`**：一键安装脚本（`curl | sh`），自动完成：下载二进制 → 生成配置 → 安装 procd 开机自启 → （可选）配置 Cloudflare DNS 自动更新。

---

## 一键安装

每台路由器执行以下命令，把 `PANEL_URL` / `MACHINE_TOKEN` / `MACHINE_ID` 换成对应值。

**（1）+ CF DNS 自动更新（完整推荐，含 Cloudflare DNS）**：

```sh
curl -sL https://raw.githubusercontent.com/WhyVPS/xboard-node-mips/main/install.sh \
  | PANEL_URL=https://tvoo.eu.cc MACHINE_TOKEN=<机器token> MACHINE_ID=<机器id> \
    CF_API_TOKEN=<cf_token> CF_ZONE_ID=<zone_id> CF_PARENT_DOMAIN=imis.eu.cc sh
```

**（2）仅 xboard-node（不配 CF DNS）**：

```sh
curl -sL https://raw.githubusercontent.com/WhyVPS/xboard-node-mips/main/install.sh \
  | PANEL_URL=https://tvoo.eu.cc MACHINE_TOKEN=<机器token> MACHINE_ID=<机器id> sh
```

> 命令是两行，中间的 `\` 是换行连接符；实际执行时把整段（含 `| ... sh`）一起复制运行。

### 环境变量

| 变量 | 必填 | 说明 |
|------|:---:|------|
| `PANEL_URL` | ✅ | Xboard 面板地址，如 `https://tvoo.eu.cc` |
| `MACHINE_TOKEN` | ✅ | 该路由器的机器 token（面板添加服务器后获取） |
| `MACHINE_ID` | ✅ | 该路由器的机器 id |
| `CF_API_TOKEN` | ⬜ | Cloudflare API token（启用 CF DNS 更新） |
| `CF_ZONE_ID` | ⬜ | Cloudflare zone id |
| `CF_PARENT_DOMAIN` | ⬜ | 父域名，默认 `imis.eu.cc` |
| `XB_DL_URL` | ⬜ | 二进制下载地址，默认本仓库 Release |

> ⚠️ **安全**：token 通过环境变量在运行时传入，**不会写入本仓库**。本仓库公开。

---

## 含 Cloudflare DNS 自动更新

传入 `CF_API_TOKEN` / `CF_ZONE_ID` 后，开机脚本会：

1. 等待网络可用；
2. 读取 Router ID（`uci get system.mofi.routerid`，回退 easycwmp serial / WAN MAC）；
3. 将 `<ROUTERID>.<CF_PARENT_DOMAIN>` 的 **A 记录（DNS-only）** 创建/更新为该路由器当前公网 IP。

例：Router ID `E43A65269A34` → `E43A65269A34.imis.eu.cc → <公网IP>`（幂等，IP 不变则跳过）。

### 部署后

- 开机自启：`/etc/init.d/xboard-node enable`（已自动 enable）
- 日志：`logread | grep xboard` 或 `xbctl logs`
- CF 凭据保存在 `/etc/xboard-node/credentials.env`（权限 600）

---

## 手动构建 / 交叉编译

```sh
CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat \
go build -ldflags "-s -w" \
  -tags "with_quic with_utls with_wireguard with_clash_api" \
  -o xboard-node-linux-mipsle ./cmd/xboard-node
```

> 注：设备端需 `mbedTLS`；本版已内置 singbox（tuic 需 singbox 内核）。

---

## 说明

- `/tmp` 为 tmpfs，设备重启后二进制清空，开机自动重新下载（见 init 脚本 `ensure_binary`）。
- 本仓库公开：**请勿提交任何真实 token / 密钥**。
