#!/bin/sh
# =============================================================================
# xboard-node 一键批量安装脚本 (MoFi/OpenWrt, MIPS mipsel)
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
#   MACHINE_ID        必填  该路由器 machine id (可为空则不写 machine 段)
#   CF_API_TOKEN      可选  Cloudflare API token (启用 CF DNS 更新用)
#   CF_ZONE_ID        可选  Cloudflare zone id
#   CF_PARENT_DOMAIN  可选  父域名, 默认 imis.eu.cc
#   XB_DL_URL         可选  二进制下载地址, 默认 GitHub Release (旧核心, 能上网版)
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
BIN="/tmp/xboard-node"
PKG="/tmp/xboard-node.gz"
DL_URL="${XB_DL_URL:-https://github.com/WhyVPS/xboard-node-mips/releases/download/v1.0.0-mips/xboard-node-linux-mipsle.gz}"
CONFIG="/etc/xboard-node/config.yml"
CREDS="/etc/xboard-node/credentials.env"
INIT="/etc/init.d/xboard-node"

# 生成唯一 instance id (主机名-机器id-随机串)
SYSNAME=$(uci -q get system.@system[0].hostname 2>/dev/null || echo mofi)
SYSNAME=$(echo "$SYSNAME" | sed 's/[^A-Za-z0-9_-]/-/g' | tr 'A-Z' 'a-z')
RAND4=$(head -c4 /dev/urandom 2>/dev/null | md5sum | cut -c1-4)
[ -n "$RAND4" ] || RAND4=0000
INSTANCE_ID="${SYSNAME}-machine-${MACHINE_ID:-0}-$RAND4"
TOKEN_ENV="INSTANCE_$(echo "$INSTANCE_ID" | tr 'a-z' 'A-Z' | sed 's/[^A-Z0-9_]/_/g')_MACHINE_TOKEN"

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

# ---------- 2. 下载二进制 ----------
step "下载 xboard-node 二进制 -> $BIN"
mkdir -p /tmp
if [ ! -x "$BIN" ]; then
    # 流式解压: 压缩包不落盘, 只占用最终二进制 ~70MB, 对 128MB 的 /tmp 更稳
    curl -fsSL "$DL_URL" | gunzip -c > "$BIN" 2>/dev/null && chmod +x "$BIN" \
        || { echo "ERROR: 二进制下载/解压失败 $DL_URL" >&2; rm -f "$BIN"; exit 1; }
fi
[ -x "$BIN" ] && echo "  二进制就绪: $("$BIN" -v 2>/dev/null | head -1 || echo ok)"

# ---------- 3. 生成配置目录 ----------
step "生成配置 /etc/xboard-node"
mkdir -p /etc/xboard-node /etc/xboard-node/instances
umask 077

# config.yml
cat > "$CONFIG" <<EOF
instances:
    - id: $INSTANCE_ID
      panel:
        url: $PANEL_URL
      kernel:
        type: singbox
        config_dir: /etc/xboard-node/instances/$INSTANCE_ID
        log_level: warn
      log:
        level: info
        output: stdout
      machine:
        machine_id: ${MACHINE_ID:-0}
        token_env: $TOKEN_ENV
EOF
echo "  config.yml 已生成 (instance=$INSTANCE_ID)"

# credentials.env
: > "$CREDS"
echo "$TOKEN_ENV=$MACHINE_TOKEN" >> "$CREDS"
if [ -n "${CF_API_TOKEN:-}" ]; then echo "CF_API_TOKEN=$CF_API_TOKEN" >> "$CREDS"; fi
if [ -n "${CF_ZONE_ID:-}" ]; then echo "CF_ZONE_ID=$CF_ZONE_ID" >> "$CREDS"; fi
chmod 600 "$CREDS"
echo "  credentials.env 已生成 (machine token 写入 $TOKEN_ENV)"

# install-meta.json
cat > /etc/xboard-node/install-meta.json <<EOF
{
  "config_mode": "instances",
  "version": "unknown",
  "latest_instance_id": "$INSTANCE_ID",
  "instance_count": 1,
  "instances": [
    {
      "id": "$INSTANCE_ID",
      "panel_url": "$PANEL_URL",
      "mode": "machine",
      "node_id": null,
      "machine_id": ${MACHINE_ID:-0},
      "health_port": 0
    }
  ],
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# ---------- 4. 安装 init 脚本 (procd 开机自启 + 等网 + CF DNS) ----------
step "安装 init 脚本 $INIT"
umask 022
cat > "$INIT" <<'INITEOF'
#!/bin/sh /etc/rc.common
# xboard-node MIPS deployment for MoFi/OpenWrt (MediaTek MT7621)
# 开机: 等网络 -> 更新 CF DNS -> 下载二进制(如缺失) -> procd 守护运行
# CF 凭据与机器 token 从 credentials.env 读取

START=98
STOP=20
USE_PROCD=1

BIN="/tmp/xboard-node"
PKG="/tmp/xboard-node.gz"
CONFIG="/etc/xboard-node/config.yml"
CREDS="/etc/xboard-node/credentials.env"

DL_URL="${XB_DL_URL:-https://github.com/WhyVPS/xboard-node-mips/releases/download/v1.0.0-mips/xboard-node-linux-mipsle.gz}"
NET_PROBE_URL="${XB_NET_PROBE_URL:-https://api.ipify.org}"
CF_PARENT_DOMAIN="${XB_CF_PARENT_DOMAIN:-imis.eu.cc}"
NET_WAIT_MAX="${XB_NET_WAIT_MAX:-600}"
NET_WAIT_STEP="${XB_NET_WAIT_STEP:-5}"

boot() {
    wait_for_network || true
    update_cf_dns >&2 || true
    start_service
}

wait_for_network() {
    local _t=0
    echo "xboard-node: waiting for network..."
    while [ "$_t" -lt "$NET_WAIT_MAX" ]; do
        if curl -s --max-time 8 -o /dev/null "$NET_PROBE_URL" 2>/dev/null; then
            echo "xboard-node: network OK after ${_t}s"
            return 0
        fi
        sleep "$NET_WAIT_STEP"
        _t=$((_t + NET_WAIT_STEP))
    done
    echo "xboard-node: no network after ${NET_WAIT_MAX}s"
    return 1
}

get_routerid() {
    local _id
    _id=$(uci -q get system.mofi.routerid 2>/dev/null)
    [ -n "$_id" ] && { echo "$_id"; return 0; }
    _id=$(uci -q get easycwmp.@device[0].serial_number 2>/dev/null)
    [ -n "$_id" ] && { echo "$_id"; return 0; }
    for _i in module1 wan eth0 br-lan; do
        _id=$(cat "/sys/class/net/$_i/address" 2>/dev/null | tr -d ':' | tr 'a-z' 'A-Z')
        [ -n "$_id" ] && [ "$_id" != "000000000000" ] && { echo "$_id"; return 0; }
    done
    return 1
}

get_public_ip() {
    curl -s --max-time 10 "https://api.ipify.org" 2>/dev/null
}

update_cf_dns() {
    local _rid _domain _ip _tkn _zone
    [ -f "$CREDS" ] && . "$CREDS"
    _tkn="$CF_API_TOKEN"
    _zone="$CF_ZONE_ID"
    if [ -z "$_tkn" ] || [ -z "$_zone" ]; then
        echo "xboard-node: CF_API_TOKEN/CF_ZONE_ID 未设置, 跳过 DNS 更新"
        return 0
    fi
    _rid=$(get_routerid) || { echo "xboard-node: 无法获取 Router ID"; return 0; }
    _domain="${_rid}.${CF_PARENT_DOMAIN}"
    _ip=$(get_public_ip) || { echo "xboard-node: 无法获取公网IP"; return 0; }
    echo "xboard-node: CF DNS ${_domain} -> ${_ip}"
    local _curl_base="curl -sS --max-time 15 -H \"Authorization: Bearer ${_tkn}\" -H \"Content-Type: application/json\""
    local _rec_list
    _rec_list=$(eval "$_curl_base \"https://api.cloudflare.com/client/v4/zones/${_zone}/dns_records?type=A&name=${_domain}\"" 2>/dev/null)
    if echo "$_rec_list" | grep -q '"id"' 2>/dev/null; then
        _rec_id=$(echo "$_rec_list" | sed -n 's/.*"id":"\([0-9a-f]\{32\}\)".*/\1/p' | head -1)
        _rec_content=$(echo "$_rec_list" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | head -1)
        if [ "$_rec_content" = "$_ip" ]; then
            echo "xboard-node: record already correct (${_domain}=${_ip})"
            return 0
        fi
        eval "$_curl_base -X PUT \"https://api.cloudflare.com/client/v4/zones/${_zone}/dns_records/${_rec_id}\" --data '{\"type\":\"A\",\"name\":\"${_domain}\",\"content\":\"${_ip}\",\"ttl\":1,\"proxied\":false}'" >/dev/null 2>&1
    else
        echo "xboard-node: creating A record ${_domain} -> ${_ip}"
        eval "$_curl_base -X POST \"https://api.cloudflare.com/client/v4/zones/${_zone}/dns_records\" --data '{\"type\":\"A\",\"name\":\"${_domain}\",\"content\":\"${_ip}\",\"ttl\":1,\"proxied\":false}'" >/dev/null 2>&1
    fi
    return 0
}

ensure_binary() {
    [ -x "$BIN" ] && return 0
    echo "xboard-node: 下载二进制..."
    mkdir -p /tmp
    # 流式解压, 压缩包不落盘, 控制 /tmp 占用
    curl -fsSL "$DL_URL" | gunzip -c > "$BIN" 2>/dev/null && chmod +x "$BIN"
    return 0
}

start_service() {
    [ -f "$CONFIG" ] || { echo "xboard-node: config 缺失: $CONFIG" >&2; return 1; }
    ensure_binary || { echo "xboard-node: 无法获取二进制" >&2; return 1; }

    procd_open_instance
    procd_set_param command "$BIN" -c "$CONFIG"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1

    if [ -f "$CREDS" ]; then
        set -a
        . "$CREDS"
        set +a
        for _e in $(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$CREDS"); do
            case "$_e" in
                INSTANCE_*_MACHINE_TOKEN)
                    procd_set_param env "$_e=$(eval echo \"\$$_e\")"
                    ;;
            esac
        done
    fi

    procd_close_instance
    echo "xboard-node: started (machine config $CONFIG)"
}

stop_service() { procd_kill "$BIN"; }

reload_service() {
    ( flock -n 9 || exit 1
      procd_send_signal SIGHUP "$BIN"
    ) 9> /var/lock/xboard-node-reload 2>/dev/null || \
    procd_send_signal SIGHUP "$BIN"
}
INITEOF
chmod 755 "$INIT"

# ---------- 5. 启用并启动 ----------
step "启用开机自启 + 启动服务"
/etc/init.d/xboard-node enable 2>&1
/etc/init.d/xboard-node start 2>&1

step "完成!"
echo "  实例: $INSTANCE_ID"
echo "  面板: $PANEL_URL (machine_id=${MACHINE_ID:-0})"
if [ -n "${CF_API_TOKEN:-}" ]; then
    echo "  CF DNS: <RouterID>.${CF_PARENT_DOMAIN} A 记录 (DNS-only)"
fi
echo "  日志: logread | grep xboard"