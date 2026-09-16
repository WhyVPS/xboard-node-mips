# 更新日志 · xboard-node-mips

## v1.0.0-mips (2026-09-04) — 初始发行

OpenWrt/MoFi (MediaTek MT7621, mipsel) 路由器上的 xboard-node 节点客户端。

### 安装包说明

- 二进制与 ipk 均为 **自包含**：ipk 只装启动框架（LuCI 控制器/视图、`/etc/config/xboard-node`、`/etc/init.d/xboard-node`），
  agent 本体在 **开机时按架构自动从 Release 下载** 到 `/tmp/xboard-node`（tmpfs，重启后自动重取，无需手动升级）。
- 架构自动识别：`uname -m` → amd64/386/arm64/armv7/armv5/mipsle/riscv64。
- 已内置 singbox + xray 双内核（vless/anytls/hysteria2/tuic 均可下发）。

### 功能特性

- OpenWrt procd 守护运行，异常自动重生（respawn）。
- 开机流程：读 uci 配置 → 生成 `config.yml`/`credentials.env` → 等待网络 → 更新 Cloudflare DNS → 下载最新二进制 → 启动。
- **内置 Cloudflare 动态 DNS**：读取 Router ID（`uci get system.mofi.routerid` → easycwmp serial → WAN MAC 回退），
  将 `<ROUTERID>.<CF_PARENT_DOMAIN>` 的 A 记录幂等更新为该路由器当前公网 IP（IP 不变则跳过）。无需外部 DDNS 服务。

### 配置项（uci: `xboard-node.config.*`）

| 选项 | 必填 | 说明 |
|------|:---:|------|
| `panel_url` | ✓ | Xboard 面板地址，如 `https://tvoo.eu.cc` |
| `machine_token` | ✓ | 该路由器的机器 token |
| `machine_id` | ✓ | 该路由器的机器 id |
| `cf_api_token` | ⬜ | Cloudflare API token（启用 CF DNS 自更新） |
| `cf_zone_id` | ⬜ | Cloudflare zone id |
| `cf_parent_domain` | ⬜ | 父域名，默认 `imis.eu.cc` |
| `dl_url` | ⬜ | 二进制下载地址，默认 Release（`v1.0.0-mips` 全架构资产） |
| `machine_name` | ⬜ | 机器显示名 |

### 升级方式

- **二进制**：无需手动升级。机器重启或 `/tmp/xboard-node` 缺失时，自动重新下载 Release 最新二进制。
- **ipk/脚本**：重装最新 ipk 或重跑 `install.sh`（`opkg install --force-reinstall xboard-node_*.ipk`）。
