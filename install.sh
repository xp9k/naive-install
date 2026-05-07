#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NaiveProxy Auto-Installer (Interactive)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

CADDY_DIR="/opt/naiveproxy"
CADDYFILE="/etc/caddy/Caddyfile"
SERVICE_FILE="/etc/systemd/system/caddy.service"
OUTPUT_FILE="/root/.naive.txt"
CADDY_METHOD=""
GO_INSTALLED_BY_SCRIPT=false

gen_random_user() {
    head /dev/urandom | tr -dc 'a-z0-9' | head -c 8
}

gen_random_pass() {
    head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16
}

prompt_input() {
    local varname="$1" prompt_text="$2" default="${3:-}" is_password="${4:-false}"
    local display_default=""
    if [[ -n "${default}" ]]; then
        if [[ "${is_password}" == "true" ]]; then
            display_default=" [${DIM}${default}${NC}]"
        else
            display_default=" [${DIM}${default}${NC}]"
        fi
    fi
    while true; do
        echo -ne "${BOLD}${prompt_text}${NC}${display_default}: "
        if [[ "${is_password}" == "true" ]]; then
            read -rs value
            echo
        else
            read -r value
        fi
        value="${value:-${default}}"
        if [[ -n "${value}" ]]; then
            eval "${varname}=\"${value}\""
            return
        fi
        echo -e "${RED}This field is required.${NC}"
    done
}

prompt_confirm() {
    local prompt_text="$1" default="${2:-y}"
    local suffix=""
    if [[ "${default}" == "y" ]]; then
        suffix="[Y/n]"
    else
        suffix="[y/N]"
    fi
    while true; do
        echo -ne "${BOLD}${prompt_text}${NC} ${suffix}: "
        read -r answer
        answer="${answer:-${default}}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

# ----------------------------------------------------------
# Interactive configuration
# ----------------------------------------------------------
interactive_setup() {
    echo -e "${CYAN}"
    echo "============================================"
    echo "    NaiveProxy Auto-Installer"
    echo "============================================"
    echo -e "${NC}"

    [[ "$(id -u)" -ne 0 ]] && error "This script must be run as root."

    echo -e "${BOLD}Please provide the following settings:${NC}"
    echo ""

    DOMAIN_DEFAULT=""
    EMAIL_DEFAULT=""
    WEBROOT_DEFAULT="/var/www/html"
    PORT_DEFAULT="443"

    prompt_input DOMAIN     "Domain name for TLS certificate"    "${DOMAIN_DEFAULT}"
    prompt_input EMAIL      "Email for ACME (Let's Encrypt)"     "${EMAIL_DEFAULT}"

    NAIVE_USER="$(gen_random_user)"
    NAIVE_PASS="$(gen_random_pass)"

    if prompt_confirm "Do you want to set your own username and password?" "n"; then
        echo -e "${DIM}  (leave empty to keep generated default)${NC}"
        local custom_user custom_pass
        prompt_input custom_user "Username" "${NAIVE_USER}"
        prompt_input custom_pass "Password" "${NAIVE_PASS}" "true"
        NAIVE_USER="${custom_user}"
        NAIVE_PASS="${custom_pass}"
    else
        info "Username and password auto-generated."
    fi

    prompt_input WEB_ROOT   "Web root for camouflage site"      "${WEBROOT_DEFAULT}"
    prompt_input NAIVE_PORT "Listen port"                        "${PORT_DEFAULT}"

    echo ""
    echo -e "${BOLD}How to get Caddy with naive forwardproxy?${NC}"
    echo -e "  ${CYAN}1)${NC} Download prebuilt binary (fast, recommended)"
    echo -e "  ${CYAN}2)${NC} Build from source (slower, requires Go)"
    echo ""
    while true; do
        echo -ne "${BOLD}Choose [1/2]${NC} (default: 1): "
        read -r method_choice
        method_choice="${method_choice:-1}"
        case "${method_choice}" in
            1) CADDY_METHOD="download"; break ;;
            2) CADDY_METHOD="build"; break ;;
            *) echo "Please enter 1 or 2." ;;
        esac
    done

    echo ""
    echo -e "${BOLD}--- Configuration Summary ---${NC}"
    echo -e "  Domain:    ${CYAN}${DOMAIN}${NC}"
    echo -e "  Email:     ${CYAN}${EMAIL}${NC}"
    echo -e "  Username:  ${CYAN}${NAIVE_USER}${NC}"
    echo -e "  Password:  ${CYAN}${NAIVE_PASS}${NC}"
    echo -e "  Web root:  ${CYAN}${WEB_ROOT}${NC}"
    echo -e "  Port:      ${CYAN}${NAIVE_PORT}${NC}"
    echo ""

    if ! prompt_confirm "Proceed with installation?"; then
        echo "Aborted."
        exit 0
    fi
    echo ""
}

# ----------------------------------------------------------
# Install dependencies
# ----------------------------------------------------------
install_deps() {
    info "Installing dependencies..."

    if command -v apt-get &>/dev/null; then
        apt-get update -y
        apt-get install -y curl wget xz-utils
    elif command -v yum &>/dev/null; then
        yum install -y curl wget xz
    elif command -v dnf &>/dev/null; then
        dnf install -y curl wget xz
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm curl wget xz
    else
        warn "Unsupported package manager. Trying to continue..."
    fi
}

install_build_deps() {
    info "Installing build dependencies..."

    if command -v apt-get &>/dev/null; then
        apt-get update -y
        apt-get install -y git curl wget xz-utils gcc make
    elif command -v yum &>/dev/null; then
        yum install -y git curl wget gcc make xz
    elif command -v dnf &>/dev/null; then
        dnf install -y git curl wget gcc make xz
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm git curl wget gcc make xz
    else
        warn "Unsupported package manager. Trying to continue..."
    fi

    if ! command -v go &>/dev/null; then
        info "Installing Go from official source..."
        GO_VERSION="1.22.5"
        GO_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
        GO_ARCH="$(uname -m)"
        [[ "${GO_ARCH}" == "x86_64" ]] && GO_ARCH="amd64"
        [[ "${GO_ARCH}" == "aarch64" ]] && GO_ARCH="arm64"

        wget -q "https://go.dev/dl/go${GO_VERSION}.${GO_OS}-${GO_ARCH}.tar.gz" -O /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm -f /tmp/go.tar.gz
        export PATH="/usr/local/go/bin:${PATH}"
        echo 'export PATH=/usr/local/go/bin:$PATH' > /etc/profile.d/go.sh
        GO_INSTALLED_BY_SCRIPT=true
    fi

    info "Go version: $(go version)"
}

# ----------------------------------------------------------
# Download prebuilt Caddy with naive forwardproxy
# ----------------------------------------------------------
download_caddy() {
    info "Downloading prebuilt Caddy with naive forwardproxy..."

    mkdir -p "${CADDY_DIR}"

    RELEASE_URL="https://github.com/klzgrad/forwardproxy/releases/latest/download/caddy-forwardproxy-naive.tar.xz"

    if ! wget -q "${RELEASE_URL}" -O /tmp/caddy-forwardproxy-naive.tar.xz; then
        rm -f /tmp/caddy-forwardproxy-naive.tar.xz
        return 1
    fi

    if ! tar -xJf /tmp/caddy-forwardproxy-naive.tar.xz -C "${CADDY_DIR}"; then
        rm -f /tmp/caddy-forwardproxy-naive.tar.xz
        return 1
    fi
    rm -f /tmp/caddy-forwardproxy-naive.tar.xz

    if [[ ! -f "${CADDY_DIR}/caddy" ]]; then
        return 1
    fi

    chmod +x "${CADDY_DIR}/caddy"
    cp "${CADDY_DIR}/caddy" /usr/bin/caddy

    info "Caddy installed: $(/usr/bin/caddy version)"
    return 0
}

# ----------------------------------------------------------
# Build Caddy with naive forwardproxy from source
# ----------------------------------------------------------
build_caddy() {
    info "Building Caddy with naive forwardproxy (this may take a few minutes)..."

    mkdir -p "${CADDY_DIR}"
    export PATH="/usr/local/go/bin:${PATH}"

    if ! command -v go &>/dev/null; then
        return 1
    fi

    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest || return 1

    cd "${CADDY_DIR}"
    ~/go/bin/xcaddy build \
        --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive \
        --output "${CADDY_DIR}/caddy" || return 1

    chmod +x "${CADDY_DIR}/caddy"
    cp "${CADDY_DIR}/caddy" /usr/bin/caddy

    info "Caddy built: $(/usr/bin/caddy version)"
    return 0
}

# ----------------------------------------------------------
# Get Caddy (try chosen method, fallback to the other)
# ----------------------------------------------------------
get_caddy() {
    if [[ "${CADDY_METHOD}" == "download" ]]; then
        if download_caddy; then
            return 0
        fi
        warn "Download failed. Trying to build from source..."
        install_build_deps
        if build_caddy; then
            return 0
        fi
        error "Both download and build failed. Cannot install Caddy."
    else
        install_build_deps
        if build_caddy; then
            return 0
        fi
        warn "Build failed. Trying to download prebuilt binary..."
        if download_caddy; then
            return 0
        fi
        error "Both build and download failed. Cannot install Caddy."
    fi
}

# ----------------------------------------------------------
# Clean up Go and build artifacts
# ----------------------------------------------------------
cleanup_go() {
    info "Cleaning up Go and build artifacts..."
    rm -rf /usr/local/go
    rm -f /etc/profile.d/go.sh
    rm -rf /root/go /root/.cache/go-build
    info "Go removed."
}

# ----------------------------------------------------------
# Create camouflage web root
# ----------------------------------------------------------
setup_webroot() {
    info "Setting up camouflage web site..."
    mkdir -p "${WEB_ROOT}"
    if [[ ! -f "${WEB_ROOT}/index.html" ]]; then
        cat > "${WEB_ROOT}/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
</head>
<body>
    <h1>Welcome</h1>
    <p>This site is running.</p>
</body>
</html>
HTMLEOF
    fi
}

# ----------------------------------------------------------
# Generate Caddyfile
# ----------------------------------------------------------
generate_caddyfile() {
    info "Generating Caddyfile..."

    mkdir -p /etc/caddy

    local port_block=":443"
    if [[ "${NAIVE_PORT}" != "443" ]]; then
        port_block=":${NAIVE_PORT}"
    fi

    cat > "${CADDYFILE}" <<CADDYEOF
{
  order forward_proxy before file_server
  log {
    exclude http.log.error
  }
}

${port_block}, ${DOMAIN} {
  tls ${EMAIL}
  encode

  forward_proxy {
    basic_auth ${NAIVE_USER} ${NAIVE_PASS}
    hide_ip
    hide_via
    probe_resistance
  }

  file_server {
    root ${WEB_ROOT}
  }
}
CADDYEOF

    chown -R caddy:caddy /etc/caddy 2>/dev/null || true
    info "Caddyfile written to ${CADDYFILE}"
}

# ----------------------------------------------------------
# Create caddy user and systemd service
# ----------------------------------------------------------
setup_systemd() {
    info "Setting up caddy user and systemd service..."

    if ! id -u caddy &>/dev/null; then
        groupadd --system caddy
        useradd --system \
            --gid caddy \
            --create-home \
            --home-dir /var/lib/caddy \
            --shell /usr/sbin/nologin \
            --comment "Caddy web server" \
            caddy
    fi

    chown -R caddy:caddy /etc/caddy
    chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true
    chown -R caddy:caddy "${WEB_ROOT}" 2>/dev/null || true

    cat > "${SERVICE_FILE}" <<SVCEOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
SVCEOF

    setcap cap_net_bind_service=+ep /usr/bin/caddy

    systemctl daemon-reload
    systemctl enable caddy
    systemctl start caddy

    info "Caddy service started."
    sleep 2
    systemctl status caddy --no-pager || true
}

# ----------------------------------------------------------
# Open firewall
# ----------------------------------------------------------
open_firewall() {
    info "Configuring firewall..."

    if command -v ufw &>/dev/null; then
        ufw allow 80/tcp 2>/dev/null || true
        ufw allow "${NAIVE_PORT}"/tcp 2>/dev/null || true
        ufw allow "${NAIVE_PORT}"/udp 2>/dev/null || true
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-service=http 2>/dev/null || true
        firewall-cmd --permanent --add-port="${NAIVE_PORT}"/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port="${NAIVE_PORT}"/udp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    elif command -v iptables &>/dev/null; then
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -p tcp --dport "${NAIVE_PORT}" -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -p udp --dport "${NAIVE_PORT}" -j ACCEPT 2>/dev/null || true
    fi
}

# ----------------------------------------------------------
# Output connection info
# ----------------------------------------------------------
output_info() {
    SERVER_IP="$(curl -s4 --connect-timeout 5 ifconfig.me || curl -s4 --connect-timeout 5 icanhazip.com || echo 'YOUR_SERVER_IP')"

    local scheme="https"
    [[ "${NAIVE_PORT}" != "443" ]] && scheme="https"
    
    local proxy_url="${scheme}://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}"
    [[ "${NAIVE_PORT}" != "443" ]] && proxy_url="${scheme}://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}:${NAIVE_PORT}"

    local quic_url="quic://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}"
    [[ "${NAIVE_PORT}" != "443" ]] && quic_url="quic://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}:${NAIVE_PORT}"

    CONNECTION_INFO="
============================================================
  NaiveProxy Installation Complete
============================================================

  Server IP:     ${SERVER_IP}
  Domain:        ${DOMAIN}
  Port:          ${NAIVE_PORT}
  Username:      ${NAIVE_USER}
  Password:      ${NAIVE_PASS}

  --- Connection strings ---

  HTTPS:  ${proxy_url}
  QUIC:   ${quic_url}

  --- Client config.json ---

  {
    \"listen\": \"socks://127.0.0.1:1080\",
    \"proxy\": \"${proxy_url}\"
  }

============================================================
"

    echo -e "${CYAN}${CONNECTION_INFO}${NC}"

    echo "${CONNECTION_INFO}" > "${OUTPUT_FILE}"
    chmod 600 "${OUTPUT_FILE}"
    info "Connection info saved to ${OUTPUT_FILE}"
}

# ----------------------------------------------------------
# Uninstall
# ----------------------------------------------------------
uninstall() {
    echo -e "${YELLOW}This will completely remove NaiveProxy (Caddy + config + service).${NC}"
    if ! prompt_confirm "Are you sure?" "n"; then
        echo "Aborted."
        exit 0
    fi

    info "Uninstalling NaiveProxy..."

    systemctl stop caddy 2>/dev/null || true
    systemctl disable caddy 2>/dev/null || true
    rm -f "${SERVICE_FILE}"
    rm -f /usr/bin/caddy
    rm -rf "${CADDY_DIR}"
    rm -rf /etc/caddy
    userdel caddy 2>/dev/null || true
    groupdel caddy 2>/dev/null || true
    rm -f "${OUTPUT_FILE}"
    cleanup_go

    systemctl daemon-reload
    info "Uninstall complete."
}

# ----------------------------------------------------------
# Main
# ----------------------------------------------------------
if [[ "${1:-}" == "uninstall" ]]; then
    uninstall
    exit 0
fi

interactive_setup
install_deps
get_caddy

if [[ "${CADDY_METHOD}" == "build" || -d /usr/local/go ]]; then
    if [[ "${GO_INSTALLED_BY_SCRIPT}" == "true" ]]; then
        if prompt_confirm "Remove Go and build artifacts to save space?" "y"; then
            cleanup_go
        else
            info "Go kept. You can remove it later with: rm -rf /usr/local/go /etc/profile.d/go.sh /root/go /root/.cache/go-build"
        fi
    fi
fi

setup_webroot
generate_caddyfile
setup_systemd

if prompt_confirm "Open firewall ports (80, ${NAIVE_PORT}/tcp, ${NAIVE_PORT}/udp)?"; then
    open_firewall
else
    info "Skipping firewall configuration. Make sure ports are open manually."
fi

output_info

info "Done! Manage caddy: systemctl {start|stop|reload|status} caddy"
info "To uninstall: $0 uninstall"