#!/bin/bash
# =========================================================
# GoogleToThisCountry (GTTC) - 纯 IPv6 专属 + GitHub 加速版
# 修复纯 IPv6 机器无法访问 1.1.1.1 的 DNS 死锁问题
# =========================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

GH_PROXY="https://ghproxy.net/"

PING_SCRIPT="/usr/local/bin/gttc_pingv6.sh"
SERVICE_FILE_SYSTEMD="/etc/systemd/system/gttc-pingv6.service"
SERVICE_FILE_OPENRC="/etc/init.d/gttc-pingv6"
CONFIG_TAG_FILE="/etc/gttc_countryv6.conf"

check_warp() {
    local ip
    ip=$(curl -s6 --connect-timeout 5 https://api64.ipify.org 2>/dev/null || curl -s6 --connect-timeout 5 https://ifconfig.co 2>/dev/null || echo "")
    if [[ "$ip" =~ ^2606:4700: ]]; then
        echo -e "${RED}[⚠ 错误] 检测到当前处于 Cloudflare WARP 环境 (IPv6: $ip)！${NC}"
        exit 1
    fi
}

show_banner() {
    clear
    echo -e "${CYAN}+-------------------------------------------------------+${NC}"
    echo -e "${CYAN}|    GoogleToThisCountry (GTTC) [纯IPv6 + 加速版]       |${NC}"
    echo -e "${CYAN}+-------------------------------------------------------+${NC}"
    echo ""
}

find_config() {
    XRAY_CONF=""
    for path in "/etc/xray/config.json" "/usr/local/etc/xray/config.json" "/etc/v2ray/config.json" "/usr/local/etc/v2ray/config.json"; do
        if [ -f "$path" ]; then
            XRAY_CONF="$path"
            break
        fi
    done
}

check_status() {
    find_config
    if [ -n "$XRAY_CONF" ] && [ -f "$CONFIG_TAG_FILE" ]; then
        COUNTRY=$(cat "$CONFIG_TAG_FILE")
        echo -e "${GREEN}[已开启 - ${COUNTRY} (IPv6)]${NC}"
    else
        echo -e "${RED}[已关闭]${NC}"
    fi
}

setup_shortcut() {
    mkdir -p /usr/local/bin
    LOCAL_SCRIPT="/usr/local/bin/gttc_manager.sh"

    SCRIPT_SOURCE="$0"
    if [ "$SCRIPT_SOURCE" = "bash" ] || [ "$SCRIPT_SOURCE" = "-bash" ] || [[ "$SCRIPT_SOURCE" == *"/dev/fd/"* ]] || [ "$SCRIPT_SOURCE" = "/dev/stdin" ]; then
        echo -e "${YELLOW}正在通过镜像下载并安装脚本至 $LOCAL_SCRIPT ...${NC}"
        curl -sSL "${GH_PROXY}https://raw.githubusercontent.com/yodit10124/GoogleToThisCountry-v6/main/gttc.sh" -o "$LOCAL_SCRIPT" || \
        wget -qO "$LOCAL_SCRIPT" "${GH_PROXY}https://raw.githubusercontent.com/yodit10124/GoogleToThisCountry-v6/main/gttc.sh"
    else
        if [ "$(readlink -f "$SCRIPT_SOURCE" 2>/dev/null)" != "$LOCAL_SCRIPT" ]; then
            cp -f "$(readlink -f "$SCRIPT_SOURCE")" "$LOCAL_SCRIPT" 2>/dev/null || true
        fi
    fi

    chmod +x "$LOCAL_SCRIPT" 2>/dev/null || true
    ln -sf "$LOCAL_SCRIPT" /usr/local/bin/gttc
    chmod +x /usr/local/bin/gttc
}

check_swap() {
    MEM_FREE=$(free -m | awk '/Mem:/ {print $4+$6}')
    SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
    if [ -n "$MEM_FREE" ] && [ "$MEM_FREE" -lt 300 ] && [ "$SWAP_TOTAL" -eq 0 ]; then
        echo -e "${YELLOW}检测到内存不足，正在建立 1GB 临时 Swap...${NC}"
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none 2>/dev/null || true
        chmod 600 /swapfile 2>/dev/null || true
        mkswap /swapfile >/dev/null 2>&1 || true
        swapon /swapfile >/dev/null 2>&1 || true
    fi
}

create_ping_service() {
    local lang_header="$1"
    cat << EOF > "$PING_SCRIPT"
#!/bin/bash
UA_MOBILE="Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UD1A.230803.041) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.119 Mobile Safari/537.36"
endpoints=(
    "https://www.google.com/generate_204"
    "https://connectivitycheck.gstatic.com/generate_204"
    "https://clients3.google.com/generate_204"
)
while true; do
    ip=\$(curl -s6 --connect-timeout 5 https://api64.ipify.org 2>/dev/null || echo "")
    if [[ "\$ip" =~ ^2606:4700: ]]; then exit 1; fi
    for url in "\${endpoints[@]}"; do
        curl -s6 -A "\$UA_MOBILE" -H "Accept-Language: ${lang_header}" -H "Cache-Control: no-cache" --connect-timeout 5 "\$url" >/dev/null 2>&1 || true
    done
    sleep 600
done
EOF
    chmod +x "$PING_SCRIPT"

    if command -v rc-service >/dev/null 2>&1 || [ -f /etc/alpine-release ]; then
        cat << 'EOF' > "$SERVICE_FILE_OPENRC"
#!/sbin/openrc-run
name="gttc-ping"
command="/usr/local/bin/gttc_ping.sh"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
depend() { need net; }
EOF
        chmod +x "$SERVICE_FILE_OPENRC"
        rc-update add gttc-ping default >/dev/null 2>&1 || true
    else
        cat << EOF > "$SERVICE_FILE_SYSTEMD"
[Unit]
Description=Google Country Location Keep-Alive Service (IPv6)
After=network.target
[Service]
Type=simple
ExecStart=$PING_SCRIPT
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

install_core_alpine_binary() {
    echo -e "${YELLOW}正在通过镜像加速下载核心服务...${NC}"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) XARCH="64" ;;
        aarch64|arm64) XARCH="arm64-v8a" ;;
        *) XARCH="64" ;;
    esac

    TMP_DIR=$(mktemp -d)
    curl -sSL -o "$TMP_DIR/xray.zip" "${GH_PROXY}https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XARCH}.zip"
    unzip -q -o "$TMP_DIR/xray.zip" -d "$TMP_DIR"
    
    mkdir -p /usr/local/bin /usr/local/share/xray /etc/xray
    cp -f "$TMP_DIR/xray" /usr/local/bin/xray
    chmod +x /usr/local/bin/xray
    [ -f "$TMP_DIR/geoip.dat" ] && cp -f "$TMP_DIR/geoip.dat" /usr/local/share/xray/
    [ -f "$TMP_DIR/geosite.dat" ] && cp -f "$TMP_DIR/geosite.dat" /usr/local/share/xray/
    rm -rf "$TMP_DIR"

    cat << 'EOF' > /etc/init.d/xray
#!/sbin/openrc-run
name="xray"
command="/usr/local/bin/xray"
command_args="run -c /etc/xray/config.json"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
depend() { need net; }
EOF
    chmod +x /etc/init.d/xray
    rc-update add xray default >/dev/null 2>&1 || true
}

install_core() {
    setup_shortcut
    for pkg in curl jq python3 bash unzip; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            check_swap
            if command -v apk >/dev/null 2>&1; then
                apk update -q && apk add -q curl jq python3 bash unzip
            elif command -v apt-get >/dev/null 2>&1; then
                apt-get update -qq && apt-get install -y -qq curl jq python3 bash unzip
            elif command -v yum >/dev/null 2>&1; then
                yum install -y -q curl jq python3 bash unzip
            fi
            break
        fi
    done

    if command -v apk >/dev/null 2>&1 || [ -f /etc/alpine-release ]; then
        if ! command -v xray >/dev/null 2>&1; then
            ALPINE_VER=$(cat /etc/alpine-release | cut -d'.' -f1,2)
            echo "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/community" >> /etc/apk/repositories
            apk update -q
            if ! apk add -q xray 2>/dev/null; then
                install_core_alpine_binary
            else
                rc-update add xray default >/dev/null 2>&1 || true
            fi
        fi
    else
        find_config
        if [ -z "$XRAY_CONF" ]; then
            echo -e "${YELLOW}未检测到核心服务，开始通过镜像加速执行一键安装...${NC}"
            bash <(curl -L "${GH_PROXY}https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh")
        fi
    fi

    find_config
    if [ -z "$XRAY_CONF" ]; then XRAY_CONF="/etc/xray/config.json"; fi
    if [ ! -s "$XRAY_CONF" ]; then
        mkdir -p "$(dirname "$XRAY_CONF")"
        cat << 'CONF_EOF' > "$XRAY_CONF"
{ "log": { "loglevel": "warning" }, "inbounds": [], "outbounds": [{ "protocol": "freedom", "tag": "direct" }] }
CONF_EOF
    fi
}

restart_service() {
    local action="$1"
    echo -e "${YELLOW}正在重启相关服务...${NC}"
    if command -v rc-service >/dev/null 2>&1 || [ -f /etc/alpine-release ]; then
        rc-service xray $action 2>/dev/null || true
        rc-service gttc-ping $action 2>/dev/null || true
    else
        systemctl $action xray 2>/dev/null || systemctl $action v2ray 2>/dev/null || true
        if [ "$action" = "restart" ] || [ "$action" = "start" ]; then
            systemctl enable gttc-ping.service >/dev/null 2>&1 || true
            systemctl restart gttc-ping.service >/dev/null 2>&1 || true
        else
            systemctl stop gttc-ping.service >/dev/null 2>&1 || true
            systemctl disable gttc-ping.service >/dev/null 2>&1 || true
        fi
    fi
}

enable_target_country() {
    echo ""
    echo "================================================="
    echo "         请选择目标国家 / 地区 (纯IPv6模式)"
    echo "================================================="
    echo " 1. 🇹🇼 台湾 (Taiwan) - 宣告 HiNet IPv6"
    echo " 2. 🇨🇳 中国大陆 (China) - 宣告 ChinaTelecom IPv6"
    echo " 3. 🇯🇵 日本 (Japan) - 宣告 NTT IPv6"
    echo " 4. 🇲🇴 澳门 (Macao) - 宣告 CTM IPv6"
    echo " 5. 🇺🇸 美国 (United States) - 宣告 美国家宽 IPv6"
    echo "================================================="
    read -p "请选择 [1-5]: " c_choice

    # 替换所有的 DoH 服务器为原生的 IPv6 Literal (需用方括号包裹)
    # Google DoH: https://[2001:4860:4860::8888]/dns-query
    # 阿里 DoH: https://[2400:3200::1]/dns-query
    case "$c_choice" in
        1) COUNTRY_NAME="🇹🇼 台湾"; DOH_SERVER="https://[2001:4860:4860::8888]/dns-query"; ECS_IP="2001:b000::/32"; LANG_HEADER="zh-TW,zh;q=0.9,en;q=0.8";;
        2) COUNTRY_NAME="🇨🇳 中国大陆"; DOH_SERVER="https://[2400:3200::1]/dns-query"; ECS_IP="240e:fc::/32"; LANG_HEADER="zh-CN,zh;q=0.9,en;q=0.8";;
        3) COUNTRY_NAME="🇯🇵 日本"; DOH_SERVER="https://[2001:4860:4860::8888]/dns-query"; ECS_IP="2001:240::/32"; LANG_HEADER="ja-JP,ja;q=0.9,en;q=0.8";;
        4) COUNTRY_NAME="🇲🇴 澳门"; DOH_SERVER="https://[2001:4860:4860::8888]/dns-query"; ECS_IP="2400:8700::/32"; LANG_HEADER="zh-MO,zh-TW;q=0.9,zh;q=0.8,en;q=0.7";;
        5) COUNTRY_NAME="🇺🇸 美国"; DOH_SERVER="https://[2001:4860:4860::8888]/dns-query"; ECS_IP="2600::/16"; LANG_HEADER="en-US,en;q=0.9";;
        *) echo -e "${RED}无效选择！${NC}"; return;;
    esac

    find_config
    [ -z "$XRAY_CONF" ] && XRAY_CONF="/etc/xray/config.json"

    if [ ! -f "$XRAY_CONF" ]; then echo -e "${RED}错误：未找到配置！${NC}"; return; fi
    cp "$XRAY_CONF" "${XRAY_CONF}.bak"

    # 注意：移除了 fallback 里面的 1.1.1.1，替换为 Cloudflare 和 Google 的纯 IPv6
    python3 -c "
import json
with open('$XRAY_CONF', 'r') as f: data = json.load(f)
data['dns'] = {
    'servers': [
        {
            'address': '$DOH_SERVER', 'clientSubnet': '$ECS_IP',
            'domains': ['geosite:google','domain:google.com','domain:googleapis.com','domain:gstatic.com','domain:gvt1.com','domain:1e100.net','domain:location.services']
        },
        'https://[2606:4700:4700::1111]/dns-query', 
        '2001:4860:4860::8888'
    ]
}
if 'routing' not in data: data['routing'] = {}
data['routing']['domainStrategy'] = 'IPIfNonMatch'
with open('$XRAY_CONF', 'w') as f: json.dump(data, f, indent=2)
"
    create_ping_service "$LANG_HEADER"
    echo "$COUNTRY_NAME" > "$CONFIG_TAG_FILE"
    restart_service "restart"
    echo -e "${GREEN}✅ 已开启纯 IPv6 模式 -> [${COUNTRY_NAME}]！${NC}"
}

disable_target_country() {
    find_config
    [ -z "$XRAY_CONF" ] && XRAY_CONF="/etc/xray/config.json"
    cp "$XRAY_CONF" "${XRAY_CONF}.bak"
    # 彻底清理 IPv4，使用纯 IPv6 的 DoH 及传统 DNS
    python3 -c "
import json
with open('$XRAY_CONF', 'r') as f: data = json.load(f)
data['dns'] = {
    'servers': [
        'https://[2606:4700:4700::1111]/dns-query', 
        '2001:4860:4860::8888', 
        '2606:4700:4700::1111'
    ]
}
with open('$XRAY_CONF', 'w') as f: json.dump(data, f, indent=2)
"
    rm -f "$CONFIG_TAG_FILE"
    restart_service "stop"
    echo -e "${GREEN}✅ 已关闭重定向，恢复国际 IPv6 解析！${NC}"
}

show_menu() {
    check_warp
    show_banner
    echo -e "       当前状态: $(check_status)"
    echo "================================================="
    echo -e " 1. ${GREEN}开启/切换 目标国家 (解决1.1.1.1不可达)${NC}"
    echo -e " 2. ${RED}关闭重定向模式${NC}"
    echo -e " 3. ${YELLOW}一键安装/修复 环境 (使用 GitHub 加速)${NC}"
    echo " 0. 退出脚本"
    echo "================================================="
    read -p "请选择选项 [0-3]: " choice

    case "$choice" in
        1) enable_target_country ;;
        2) disable_target_country ;;
        3) install_core ;;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

check_warp
install_core
show_menu
