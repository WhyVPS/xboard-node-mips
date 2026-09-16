#!/bin/sh
# =============================================================================
# xboard-node 一键安装脚本 (MoFi/OpenWrt, MIPS mipsel)
#
# 基于 ipk 安装: xboard-node_1.0.0-1_all.ipk (含 LuCI 界面, 架构无关)
#   - opkg install <ipk>
#   - 写入 uci (panel_url / machine_token / machine_id / cf_*)
#   - 由 ipk 自带的 /etc/init.d/xboard-node 生成配置并启动
#
# 用法 (一行式, 每台路由器执行):
#   curl -sL https://raw.githubusercontent.com/WhyVPS/xboard-node-mips/main/install.sh \
#     | PANEL_URL=https://tvoo.eu.cc \
#       MACHINE_TOKEN=你的机器token \
#       MACHINE_ID=3 \
#       CF_API_TOKEN=你的cf_token \
#       CF_ZONE_ID=你的zone_id \
#       CF_PARENT_DOMAIN=imis.eu.cc \
#       sh
#
# 环境变量 (运行时传入, 不入库, 不落盘明文到仓库):
#   PANEL_URL         必填  面板地址, 如 https://tvoo.eu.cc
#   MACHINE_TOKEN     必填  该路由器 machine token (面板添加服务器后获取)
#   MACHINE_ID        必填  该路由器 machine id
#   CF_API_TOKEN      可选  Cloudflare API token (启用 CF DNS 更新用)
#   CF_ZONE_ID        可选  Cloudflare zone id
#   CF_PARENT_DOMAIN  可选  父域名, 默认 imis.eu.cc
#   XB_IPK_URL        可选  ipk 下载地址, 默认 GitHub Release _all.ipk
#   XB_DL_URL         可选  二进制下载地址覆盖 (默认按架构由 init.d 自动组装)
# =============================================================================

set -u

# ---------- 必填校验 ----------
[ -n "${PANEL_URL:-}" ] && [ -n "${MACHINE_TOKEN:-}" ] || {
    echo "ERROR: 缺少必填变量. 用法:" >&2
    echo "  curl -sL <install.sh> | PANEL_URL=<面板> MACHINE_TOKEN=<机器token> MACHINE_ID=<id> sh" >&2
    exit 1
}

# ---------- 默认值 ----------
CF_PARENT_DOMAIN="${CF_PARENT_DOMAIN:-imis.eu.cc}"
RELEASE_TAG="${XB_RELEASE_TAG:-v1.0.0-mips}"
IPK_URL="${XB_IPK_URL:-https://github.com/WhyVPS/xboard-node-mips/releases/download/${RELEASE_TAG}/xboard-node_1.0.0-1_all.ipk}"
IPK="/tmp/xboard-node.ipk"

step() { echo; echo "==> $*"; }

# ---------- 1. 等网络 ----------
step "等待网络..."
_t=0
while [ "$_t" -lt 300 ]; do
    if curl -s --max-time 8 -o /dev/null https://api.ipify.org 2>/dev/null; then
        echo "  网络 OK"
        break
    fi
    sleep 5; _t=$((_t+5))
done

# ---------- 2. 下载并安装 ipk ----------
step "下载 ipk -> $IPK"
mkdir -p /tmp
curl -fsSL "$IPK_URL" -o "$IPK" || { echo "ERROR: ipk 下载失败 $IPK_URL" >&2; exit 1; }
[ -s "$IPK" ] || { echo "ERROR: ipk 为空/下载失败" >&2; exit 1; }
echo "  ipk 就绪: $(ls -l "$IPK" | awk '{print $5}') bytes"

step "opkg install (强制重装, 幂等)"
opkg install --force-reinstall "$IPK" 2>&1 || { echo "ERROR: opkg 安装失败" >&2; exit 1; }
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null

# ---------- 3. 写入 uci 配置 ----------
step "写入 uci 配置 (xboard-node.config)"
uci set xboard-node.config.panel_url="$PANEL_URL"
uci set xboard-node.config.machine_token="$MACHINE_TOKEN"
uci set xboard-node.config.machine_id="${MACHINE_ID:-}"
[ -n "${MACHINE_ID:-}" ] || uci delete xboard-node.config.machine_id 2>/dev/null || true
if [ -n "${CF_API_TOKEN:-}" ]; then
    uci set xboard-node.config.cf_api_token="$CF_API_TOKEN"
fi
if [ -n "${CF_ZONE_ID:-}" ]; then
    uci set xboard-node.config.cf_zone_id="$CF_ZONE_ID"
fi
uci set xboard-node.config.cf_parent_domain="$CF_PARENT_DOMAIN"
if [ -n "${XB_DL_URL:-}" ]; then
    uci set xboard-node.config.dl_url="$XB_DL_URL"
    uci delete xboard-node.config.dl_base 2>/dev/null || true
else
    uci delete xboard-node.config.dl_url 2>/dev/null || true
    uci set xboard-node.config.dl_base="https://github.com/WhyVPS/xboard-node-mips/releases/download/${RELEASE_TAG}/xboard-node-linux"
fi
uci commit xboard-node
echo "  panel_url=$PANEL_URL"
echo "  machine_id=${MACHINE_ID:-<空>} cf_parent_domain=$CF_PARENT_DOMAIN"

# ---------- 4. 启用并启动 ----------
step "启用开机自启 + 启动服务"
/etc/init.d/xboard-node enable 2>&1
/etc/init.d/xboard-node start 2>&1

step "完成!"
echo "  ipk 版本: $(opkg list-installed 2>/dev/null | grep '^xboard-node ')"
echo "  面板: $PANEL_URL (machine_id=${MACHINE_ID:-0})"
echo "  LuCI: 系统 -> 服务 -> xboard-node (或 /cgi-bin/luci/admin/services/xboard-node)"
if [ -n "${CF_API_TOKEN:-}" ]; then
    echo "  CF DNS: <RouterID>.${CF_PARENT_DOMAIN} A 记录 (DNS-only)"
fi
