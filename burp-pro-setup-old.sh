#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════╗
# ║      BurpSuite Pro ─ Universal Setup Script v6                       ║
# ║      Supports: Kali Linux · Debian · Ubuntu · Fedora · Arch         ║
# ║      Features: JDK 17-26 Support · Proxychains Awareness · Clean Net ║
# ╚══════════════════════════════════════════════════════════════════════╝

# ── Colors & Formatting ──────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';   BOLD='\033[1m';  NC='\033[0m'
MAGENTA='\033[0;35m'

# ── Helper Functions ─────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║       BurpSuite Pro ─ Universal Setup Script v6            ║"
    echo "  ║       JDK 17-26 · Proxychains Safe · Clean Networking      ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

step()  { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BOLD}${GREEN}  $*${NC}\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ ✔ ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[ ! ]${NC}  $*"; }
err()   { echo -e "${RED}[ ✘ ]${NC}  $*"; }
pause() { echo -e "\n${YELLOW}▶  Press ENTER to continue...${NC}"; read -r; }
die()   { err "$*"; exit 1; }

# ════════════════════════════════════════════════════════════════════════
#  CRITICAL: Identify the REAL user (not root even if run with sudo)
# ════════════════════════════════════════════════════════════════════════
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$USER"
fi

REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)
[ -z "$REAL_HOME" ] && REAL_HOME="$HOME"

REAL_DISPLAY="${DISPLAY:-:0}"
REAL_XAUTH="${XAUTHORITY:-${REAL_HOME}/.Xauthority}"

REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo "1000")
REAL_DBUS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/${REAL_UID}/bus}"

as_user() {
    if [ "$EUID" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" \
             DISPLAY="$REAL_DISPLAY" \
             XAUTHORITY="$REAL_XAUTH" \
             DBUS_SESSION_BUS_ADDRESS="$REAL_DBUS" \
             HOME="$REAL_HOME" \
             "$@"
    else
        DISPLAY="$REAL_DISPLAY" \
        XAUTHORITY="$REAL_XAUTH" \
        DBUS_SESSION_BUS_ADDRESS="$REAL_DBUS" \
        HOME="$REAL_HOME" \
        "$@"
    fi
}

banner
info "Executing user : $(whoami) (EUID=$EUID)"
info "Real desktop user : $REAL_USER"
info "Real user home : $REAL_HOME"
info "X11 Display    : $REAL_DISPLAY"
echo ""

# ════════════════════════════════════════════════════════════════════════
#  SAFEGUARD: System State & Network Cleanup
# ════════════════════════════════════════════════════════════════════════
step "INSPECTION ── Restoring Clean System & Network State"

# 1. Clean up any artificial PortSwigger entries in /etc/hosts
if grep -qiE "portswigger|burpsuite" /etc/hosts 2>/dev/null; then
    warn "Detected modified entries in /etc/hosts. Restoring clean hosts file..."
    sudo sed -i '/portswigger/d' /etc/hosts 2>/dev/null || true
    sudo sed -i '/burpsuite/d' /etc/hosts 2>/dev/null || true
    ok "/etc/hosts restored to clean state."
else
    ok "/etc/hosts is clean."
fi

# 2. Inspect and remove custom DROP rules targeting PortSwigger IPs
if command -v iptables &>/dev/null && [ "$EUID" -eq 0 ]; then
    BLOCKED_RULES=$(iptables -L OUTPUT -n --line-numbers 2>/dev/null | grep -E "DROP.*(portswigger|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)" || true)
    if [ -n "$BLOCKED_RULES" ]; then
        info "Checking firewall OUTPUT chain for custom DROP rules..."
        # Safely remove individual PortSwigger block rules if previously created
        for domain in "portswigger.net" "burpsuite.net" "license.portswigger.net"; do
            mapfile -t ips < <(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
            for ip in "${ips[@]}"; do
                iptables -D OUTPUT -d "$ip" -j DROP 2>/dev/null || true
            done
        done
        ok "Verified firewall OUTPUT rules."
    else
        ok "No conflicting firewall rules found."
    fi
fi

# ════════════════════════════════════════════════════════════════════════
#  PROXYCHAINS CONFIGURATION & NETWORK MODE
# ════════════════════════════════════════════════════════════════════════
step "NETWORK MODE ── Connection Routing Preference"

HAS_PROXYCHAINS=0
PROXYCHAINS_BIN=""

if command -v proxychains4 &>/dev/null; then
    HAS_PROXYCHAINS=1
    PROXYCHAINS_BIN="proxychains4"
elif command -v proxychains &>/dev/null; then
    HAS_PROXYCHAINS=1
    PROXYCHAINS_BIN="proxychains"
fi

echo -e "Choose how download operations should be routed:"
echo -e "  ${CYAN}1)${NC} ${BOLD}Direct Connection${NC} (Recommended — fast, reliable, bypasses proxy timeouts)"
if [ "$HAS_PROXYCHAINS" -eq 1 ]; then
    echo -e "  ${CYAN}2)${NC} ${BOLD}Proxychains Mode${NC} (Routes file downloads through $PROXYCHAINS_BIN)"
else
    echo -e "  ${CYAN}2)${NC} Proxychains Mode [Unavailable — proxychains not installed]"
fi
echo ""
read -rp "Enter choice [1 or 2, default=1]: " NET_CHOICE
NET_CHOICE="${NET_CHOICE:-1}"

USE_PROXY=0
if [ "$NET_CHOICE" -eq 2 ] && [ "$HAS_PROXYCHAINS" -eq 1 ]; then
    info "Testing $PROXYCHAINS_BIN connectivity..."

    # Check if Tor is installed and inactive
    if command -v systemctl &>/dev/null && systemctl list-unit-files 2>/dev/null | grep -q "^tor\.service"; then
        if ! systemctl is-active --quiet tor; then
            warn "Tor service is currently inactive. Proxychains default config (127.0.0.1:9050) requires Tor."
            read -rp "Would you like to start the Tor service now? [Y/n]: " START_TOR
            START_TOR="${START_TOR:-Y}"
            if [[ "$START_TOR" =~ ^[Yy] ]]; then
                sudo systemctl start tor
                sleep 2
                ok "Tor service started."
            fi
        fi
    fi

    # Perform a quick reachability test through proxychains
    if $PROXYCHAINS_BIN -q curl -sI --max-time 10 "https://portswigger.net" &>/dev/null; then
        USE_PROXY=1
        ok "Proxychains is working and online ✔"
    else
        err "Proxychains test failed (proxy is down, unresponsive, or blocking downloads)."
        echo -e "  ${YELLOW}Common reasons:${NC}"
        echo -e "   • Tor service not running: run ${CYAN}sudo systemctl start tor${NC}"
        echo -e "   • /etc/proxychains4.conf contains dead proxy IPs"
        echo -e "   • DNS timeout via SOCKS proxy"
        echo ""
        read -rp "Fall back to Direct Connection for downloads? [Y/n, default=Y]: " FALLBACK_DIRECT
        FALLBACK_DIRECT="${FALLBACK_DIRECT:-Y}"
        if [[ "$FALLBACK_DIRECT" =~ ^[Yy] ]]; then
            USE_PROXY=0
            ok "Switched to Direct Connection for smooth downloads."
        else
            USE_PROXY=1
            warn "Continuing with Proxychains (downloads may fail if proxy is not fixed)."
        fi
    fi
else
    ok "Direct connection mode enabled."
fi

# Wrapper for download commands
net_run() {
    if [ "$USE_PROXY" -eq 1 ]; then
        $PROXYCHAINS_BIN "$@"
    else
        "$@"
    fi
}

# ════════════════════════════════════════════════════════════════════════
#  JAR Validation Helper
# ════════════════════════════════════════════════════════════════════════
is_valid_jar() {
    local f="$1"
    local min="${2:-5000}"   # Default minimum size 5 KB

    [ ! -f "$f" ] && return 1

    local sz
    sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [ "$sz" -lt "$min" ] && return 1

    local magic
    magic=$(head -c 2 "$f" 2>/dev/null)
    [ "$magic" != "PK" ] && return 1

    unzip -t "$f" &>/dev/null && return 0
    return 1
}

# ════════════════════════════════════════════════════════════════════════
#  Google Drive Downloader with Multiple Fallback Methods
# ════════════════════════════════════════════════════════════════════════
gdrive_download() {
    local id="$1"
    local out="$2"

    # Method 1: Direct curl with browser User-Agent
    info "  [Method 1] Trying direct curl download..."
    net_run curl -sL \
         -A "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" \
         --max-time 60 --retry 3 \
         "https://drive.google.com/uc?export=download&id=${id}" \
         -o "$out" 2>/dev/null
    if is_valid_jar "$out" 5000; then ok "  curl: success"; return 0; fi
    rm -f "$out"

    # Method 2: Python 3 urllib (cookie & token aware)
    info "  [Method 2] Trying Python urllib..."
    python3 - <<PYEOF 2>/dev/null
import urllib.request, http.cookiejar, re, sys

file_id = "$id"
out_path = "$out"
cookie_jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))
headers = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
}

url = f'https://drive.google.com/uc?export=download&id={file_id}'
req = urllib.request.Request(url, headers=headers)
try:
    resp = opener.open(req, timeout=45)
    data = resp.read()
    if data.startswith(b'PK\x03\x04'):
        with open(out_path, 'wb') as f:
            f.write(data)
        sys.exit(0)
    html = data.decode('utf-8', errors='ignore')
    match = re.search(r'confirm=([0-9A-Za-z_]+)', html)
    token = match.group(1) if match else 't'
    confirm_url = f'https://drive.google.com/uc?export=download&confirm={token}&id={file_id}'
    req2 = urllib.request.Request(confirm_url, headers=headers)
    resp2 = opener.open(req2, timeout=45)
    data2 = resp2.read()
    if data2.startswith(b'PK\x03\x04'):
        with open(out_path, 'wb') as f:
            f.write(data2)
        sys.exit(0)
except Exception:
    sys.exit(1)
sys.exit(1)
PYEOF
    if is_valid_jar "$out" 5000; then ok "  Python urllib: success"; return 0; fi
    rm -f "$out"

    # Method 3: wget with session cookies
    info "  [Method 3] Trying wget with cookies..."
    net_run wget --quiet --no-check-certificate \
         --user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" \
         --save-cookies /tmp/gd_ck.txt \
         --keep-session-cookies \
         "https://drive.google.com/uc?export=download&id=${id}" \
         -O "$out" 2>/dev/null

    if is_valid_jar "$out" 5000; then
        rm -f /tmp/gd_ck.txt
        ok "  wget: success"
        return 0
    fi

    local token
    token=$(grep -oP 'confirm=\K[^&"]+' "$out" 2>/dev/null | head -1)
    if [ -n "$token" ]; then
        net_run wget --quiet --no-check-certificate \
             --user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" \
             --load-cookies /tmp/gd_ck.txt \
             "https://drive.google.com/uc?export=download&confirm=${token}&id=${id}" \
             -O "$out" 2>/dev/null
    fi
    rm -f /tmp/gd_ck.txt

    if is_valid_jar "$out" 5000; then ok "  wget (confirm token): success"; return 0; fi
    rm -f "$out"

    # Method 4: gdown fallback
    info "  [Method 4] Trying gdown..."
    if command -v gdown &>/dev/null || python3 -m gdown --version &>/dev/null 2>&1; then
        net_run python3 -m gdown "https://drive.google.com/uc?id=${id}" -O "$out" --fuzzy 2>/dev/null
        if is_valid_jar "$out" 5000; then ok "  gdown: success"; return 0; fi
    fi
    rm -f "$out"

    return 1
}

# ════════════════════════════════════════════════════════════════════════
#  PRE-FLIGHT ── System Detection & Core Dependencies
# ════════════════════════════════════════════════════════════════════════
step "PRE-FLIGHT ── System Detection & Dependencies"

ARCH=$(uname -m)
DISTRO=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
info "Detected OS   : $DISTRO"
info "Architecture  : $ARCH"

if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
    warn "Unsupported architecture ($ARCH). Oracle JDK x64 packages require x86_64."
fi

if command -v apt-get &>/dev/null; then
    info "Updating package lists and installing prerequisites..."
    sudo apt-get update -qq
    sudo apt-get install -y wget curl ca-certificates unzip python3-pip \
        imagemagick libxrender1 libxtst6 libxi6 2>/dev/null
    sudo update-ca-certificates -f 2>/dev/null || true
elif command -v dnf &>/dev/null; then
    sudo dnf install -y wget curl ca-certificates unzip python3-pip ImageMagick 2>/dev/null
elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm wget curl ca-certificates unzip python-pip imagemagick 2>/dev/null
fi

ok "Prerequisites verified."

# ════════════════════════════════════════════════════════════════════════
# ════════════════════════════════════════════════════════════════════════
#  STEP 01 ── Select, Install & Configure Java (JDK 17 – 26)
# ════════════════════════════════════════════════════════════════════════
step "STEP 01 ── Installing & Configuring Java Runtime (JDK 17–26)"

# Check currently active Java version
CURRENT_JAVA_VER=$(java -version 2>&1 | grep -oP 'version "\K[0-9]+' | head -1 || echo "0")
if [ "$CURRENT_JAVA_VER" -eq 0 ]; then
    CURRENT_JAVA_VER=$(java -version 2>&1 | grep -oP 'openjdk \K[0-9]+' | head -1 || echo "0")
fi
info "Current active system Java version: $CURRENT_JAVA_VER"

echo ""
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${YELLOW}  Select Java Runtime Version (JDK 17 – 26)                  ${NC}"
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Burp Suite Pro and loaders run on modern Java runtimes (Java 17+)."
echo -e "Choose which JDK version to configure or install:\n"
echo -e "  ${CYAN}17)${NC} JDK 17 (LTS)  ${YELLOW}(Stable LTS)${NC}"
echo -e "  ${CYAN}18)${NC} JDK 18"
echo -e "  ${CYAN}19)${NC} JDK 19"
echo -e "  ${CYAN}20)${NC} JDK 20"
echo -e "  ${CYAN}21)${NC} JDK 21 (LTS)  ${GREEN}★ Recommended LTS${NC}"
echo -e "  ${CYAN}22)${NC} JDK 22"
echo -e "  ${CYAN}23)${NC} JDK 23        ${GREEN}★ Recommended (Default — proven loader compatibility)${NC}"
echo -e "  ${CYAN}24)${NC} JDK 24"
echo -e "  ${CYAN}25)${NC} JDK 25"
echo -e "  ${CYAN}26)${NC} JDK 26        ${RED}✘ NOT RECOMMENDED (Experimental / potential incompatibilities)${NC}"
echo ""
read -rp "Enter Java version [17-26, default=23]: " CHOSEN_JAVA_VER
CHOSEN_JAVA_VER="${CHOSEN_JAVA_VER:-23}"

# Validate numeric input
if ! [[ "$CHOSEN_JAVA_VER" =~ ^[0-9]+$ ]] || [ "$CHOSEN_JAVA_VER" -lt 17 ] || [ "$CHOSEN_JAVA_VER" -gt 26 ]; then
    warn "Invalid choice ($CHOSEN_JAVA_VER). Defaulting to recommended JDK 23."
    CHOSEN_JAVA_VER=23
fi

# Strong warning advising against JDK 26
if [ "$CHOSEN_JAVA_VER" -eq 26 ]; then
    echo ""
    warn "⚠️  WARNING: Java 26 is NOT recommended!"
    echo -e "   ${YELLOW}Java 26 is experimental and may cause bytecode incompatibility, loader crashes, or agent errors with Burp Suite.${NC}"
    echo -e "   ${YELLOW}We strongly advise using Java 21 LTS or Java 23 instead.${NC}"
    echo ""
    read -rp "Are you sure you want to proceed with Java 26? [y/N, default=N]: " CONFIRM_26
    CONFIRM_26="${CONFIRM_26:-N}"
    if [[ ! "$CONFIRM_26" =~ ^[Yy] ]]; then
        info "Switched to recommended Java 23."
        CHOSEN_JAVA_VER=23
    else
        warn "Proceeding with Java 26 per user selection."
    fi
fi

ok "Selected target Java runtime: JDK $CHOSEN_JAVA_VER"

get_oracle_jdk_url() {
    local v="$1"
    case "$v" in
        17) echo "https://download.oracle.com/java/17/archive/jdk-17_linux-x64_bin.deb" ;;
        18) echo "https://download.oracle.com/java/18/archive/jdk-18_linux-x64_bin.deb" ;;
        19) echo "https://download.oracle.com/java/19/archive/jdk-19_linux-x64_bin.deb" ;;
        20) echo "https://download.oracle.com/java/20/archive/jdk-20_linux-x64_bin.deb" ;;
        21) echo "https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb" ;;
        22) echo "https://download.oracle.com/java/22/archive/jdk-22_linux-x64_bin.deb" ;;
        23) echo "https://download.oracle.com/java/23/archive/jdk-23_linux-x64_bin.deb" ;;
        24) echo "https://download.oracle.com/java/24/archive/jdk-24_linux-x64_bin.deb" ;;
        25) echo "https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb" ;;
        26) echo "https://download.oracle.com/java/26/latest/jdk-26_linux-x64_bin.deb" ;;
        *)  echo "" ;;
    esac
}

JDK_TARGET_INSTALLED=0
if [ "$CURRENT_JAVA_VER" -eq "$CHOSEN_JAVA_VER" ]; then
    ok "Java $CHOSEN_JAVA_VER is already the active runtime."
    JDK_TARGET_INSTALLED=1
elif update-alternatives --list java 2>/dev/null | grep -qE "jdk-${CHOSEN_JAVA_VER}|java-${CHOSEN_JAVA_VER}"; then
    info "Java $CHOSEN_JAVA_VER package found on system. Switching active runtime..."
    JAVA_TARGET_BIN=$(update-alternatives --list java 2>/dev/null | grep -E "jdk-${CHOSEN_JAVA_VER}|java-${CHOSEN_JAVA_VER}" | head -1)
    if [ -n "$JAVA_TARGET_BIN" ]; then
        sudo update-alternatives --set java "$JAVA_TARGET_BIN" 2>/dev/null || true
        JDK_TARGET_INSTALLED=1
    fi
fi

if [ "$JDK_TARGET_INSTALLED" -eq 0 ]; then
    info "Downloading JDK $CHOSEN_JAVA_VER (Debian x64) from Oracle Archive..."
    mkdir -p "$REAL_HOME/java"
    cd "$REAL_HOME/java" || die "Cannot access $REAL_HOME/java"

    JDK_DEB="jdk-${CHOSEN_JAVA_VER}_linux-x64_bin.deb"
    PRIMARY_URL=$(get_oracle_jdk_url "$CHOSEN_JAVA_VER")
    FALLBACK_URL="https://download.oracle.com/java/${CHOSEN_JAVA_VER}/latest/jdk-${CHOSEN_JAVA_VER}_linux-x64_bin.deb"

    DOWNLOAD_OK=0
    WGET_PROGRESS_OPTS=("-q" "--show-progress")
    if ! wget --help 2>&1 | grep -q -- '--show-progress'; then
        WGET_PROGRESS_OPTS=("--progress=bar:force")
    fi

    for dl_url in "$PRIMARY_URL" "$FALLBACK_URL"; do
        [ -z "$dl_url" ] && continue
        info "Connecting to: $dl_url"
        echo -e "${CYAN}★ Downloading JDK ${CHOSEN_JAVA_VER} package (live progress below):${NC}\n"
        if command -v wget &>/dev/null; then
            net_run wget --no-check-certificate --tries=3 --timeout=120 "${WGET_PROGRESS_OPTS[@]}" -c "$dl_url" -O "$JDK_DEB"
        else
            net_run curl -# -L -C - --max-time 300 "$dl_url" -o "$JDK_DEB"
        fi
        echo ""
        if [ -s "$JDK_DEB" ]; then
            DOWNLOAD_OK=1
            break
        fi
        rm -f "$JDK_DEB"
    done

    [ "$DOWNLOAD_OK" -eq 1 ] || die "JDK $CHOSEN_JAVA_VER download failed. Check network or proxy settings."

    info "Installing JDK $CHOSEN_JAVA_VER package via dpkg..."
    sudo dpkg -i "$JDK_DEB"
    sudo apt-get install -f -y 2>/dev/null || true

    cd "$REAL_HOME" || true
fi

# Configure Java alternatives
echo ""
echo -e "${YELLOW}${BOLD}Select the Java ${CHOSEN_JAVA_VER} / JDK-${CHOSEN_JAVA_VER} alternative if prompted below:${NC}"
if update-alternatives --list java 2>/dev/null | grep -qE "jdk-${CHOSEN_JAVA_VER}|java-${CHOSEN_JAVA_VER}"; then
    JAVA_TARGET_PATH=$(update-alternatives --list java 2>/dev/null | grep -E "jdk-${CHOSEN_JAVA_VER}|java-${CHOSEN_JAVA_VER}" | head -1)
    sudo update-alternatives --set java "$JAVA_TARGET_PATH" 2>/dev/null || sudo update-alternatives --config java
else
    sudo update-alternatives --config java
fi

echo ""
info "Active Java runtime:"
java --version 2>&1 | head -2 || java -version 2>&1 | head -2
ok "JDK $CHOSEN_JAVA_VER configured!"
pause

# ════════════════════════════════════════════════════════════════════════
#  STEP 02 ── Download BurpSuite Pro & Loader Files
# ════════════════════════════════════════════════════════════════════════
step "STEP 02 ── Downloading BurpSuite Pro & Helper Files"

BURP_DIR="${REAL_HOME}/Documents/burp"
as_user mkdir -p "$BURP_DIR"
cd "$BURP_DIR" || die "Cannot access $BURP_DIR"
info "Working directory: $BURP_DIR"

GDRIVE_ID="10JUah3Zoa1bi4qXTeQvx4phGtNxngMIZ"
KEYGEN="burploader.jar"

# ── Download burploader.jar ───────────────────────────────────────────
if is_valid_jar "${BURP_DIR}/${KEYGEN}" 5000; then
    ok "burploader.jar already exists and is valid — skipping download."
else
    rm -f "${BURP_DIR}/${KEYGEN}"
    info "Downloading burploader.jar..."
    gdrive_download "$GDRIVE_ID" "${BURP_DIR}/${KEYGEN}"

    if ! is_valid_jar "${BURP_DIR}/${KEYGEN}" 5000; then
        rm -f "${BURP_DIR}/${KEYGEN}"
        echo ""
        err "Automated download failed. Please download it manually:"
        echo -e "  ${YELLOW}1. Open this URL in your browser:${NC}"
        echo -e "     ${CYAN}https://drive.google.com/file/d/${GDRIVE_ID}/view?usp=sharing${NC}"
        echo -e "  ${YELLOW}2. Save file as:${NC}"
        echo -e "     ${CYAN}${BURP_DIR}/${KEYGEN}${NC}"
        echo -e "  ${YELLOW}3. Return here and press ENTER.${NC}"
        pause
        is_valid_jar "${BURP_DIR}/${KEYGEN}" 5000 \
            || die "burploader.jar is not present or invalid."
    fi
fi

ok "burploader.jar verified ✔"
sudo chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${KEYGEN}" 2>/dev/null || true

# ── Helper: Query PortSwigger Archive for Professional Releases ──────
fetch_portswigger_pro_releases() {
    local target_year="$1"
    python3 - "$target_year" << 'PYEOF' 2>/dev/null
import sys, urllib.request, re

year = sys.argv[1]
url = f"https://portswigger.net/burp/releases/archive?y={year}"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'})
try:
    with urllib.request.urlopen(req, timeout=12) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    raw = re.findall(r'href=["\']/burp/releases/(?:professional(?:-community)?)-([0-9a-zA-Z\.\-]+)["\']', html)
    versions = []
    seen = set()
    for item in raw:
        v = item.replace('-', '.')
        if v not in seen:
            seen.add(v)
            versions.append(v)
    if versions:
        for v in versions:
            print(v)
        sys.exit(0)
except Exception:
    pass

fallbacks = {
    "2026": ["2026.9.2", "2026.9.1", "2026.9", "2026.8", "2026.7.3", "2026.6.2", "2026.5.1", "2026.4", "2026.3", "2026.2", "2026.1"],
    "2025": ["2025.12.3", "2025.12.2", "2025.12.1", "2025.11.6", "2025.10.7", "2025.9.1", "2025.8.3", "2025.7.1", "2025.6.2", "2025.5.1", "2025.4.1", "2025.3.2", "2025.2.1", "2025.1.1"],
    "2024": ["2024.12", "2024.11.2", "2024.11.1", "2024.10.3", "2024.9.4", "2024.8.5", "2024.7.6", "2024.6.4", "2024.5.5", "2024.4.1", "2024.3.1", "2024.2.2", "2024.1.3"],
    "2023": ["2023.12.1", "2023.11.1.3", "2023.10.3.7", "2023.9.4", "2023.8.2", "2023.7.3", "2023.6.2", "2023.5.3", "2023.4.4", "2023.3.5", "2023.3.3", "2023.2.1", "2023.1.2"],
    "2022": ["2022.12.5", "2022.11.3", "2022.9.6", "2022.8.5", "2022.7.1", "2022.3.9", "2022.2.5", "2022.1.1"],
    "2021": ["2021.12", "2021.10.3", "2021.8.4", "2021.6.2", "2021.5.1", "2021.4.1", "2021.2.1"],
    "2020": ["2020.12.1", "2020.11.3", "2020.9.2", "2020.8.1", "2020.5.1", "2020.4.1", "2020.2.1", "2020.1"],
    "2019": ["2.1.07", "2.1.06", "2.1.05", "2.1.04", "2.1.02", "2.1.01", "2.0.20"],
    "2018": ["2.0.13beta", "2.0.12beta", "2.0.11beta", "1.7.37", "1.7.36", "1.7.35", "1.7.34", "1.7.33", "1.7.32", "1.7.31"],
    "2017": ["1.7.30", "1.7.29", "1.7.28", "1.7.27", "1.7.26", "1.7.25", "1.7.24", "1.7.23", "1.7.22", "1.7.21", "1.7.20"],
    "2016": ["1.7.15", "1.7.14", "1.7.13", "1.7.12", "1.7.11", "1.7.10", "1.7.09", "1.7.08", "1.7.07", "1.7.06", "1.7.05"]
}
for v in fallbacks.get(str(year), []):
    print(v)
PYEOF
}

# ── Select BurpSuite Pro Version (PortSwigger Releases — Last 10 Years) 
echo ""
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${YELLOW}  STEP 02b ── SELECT BURPSUITE PRO VERSION (PORTSWIGGER)     ${NC}"
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "JAR files are downloaded directly from ${CYAN}https://portswigger.net/burp/releases${NC}."
echo -e "You can select popular versions or browse all Pro JAR releases from the ${BOLD}last 10 years (2016–2026)${NC}.\n"

echo -e "  ${CYAN}1)${NC}  v2025.12.3  ${YELLOW}(Stable 2025 release)${NC}"
echo -e "  ${CYAN}2)${NC}  v2023.3.3   ${YELLOW}(Recommended — highest loader compatibility)${NC}"
echo -e "  ${CYAN}3)${NC}  v2026.9.2   ${YELLOW}(Latest 2026 release)${NC}"
echo -e "  ${CYAN}4)${NC}  v2024.11.2  ${YELLOW}(Stable 2024 release)${NC}"
echo -e "  ${CYAN}5)${NC}  ${BOLD}Browse by Year${NC}  ${CYAN}(Explore last 10 years: 2026 down to 2016)${NC}"
echo -e "  ${CYAN}6)${NC}  ${BOLD}Custom Version${NC}  ${CYAN}(Enter any version manually)${NC}"
echo ""
read -rp "Enter choice [1-6, default=1]: " VER_MENU_CHOICE
VER_MENU_CHOICE="${VER_MENU_CHOICE:-1}"

BURP_VER=""
case "$VER_MENU_CHOICE" in
    1)
        BURP_VER="2025.12.3"
        ;;
    2)
        BURP_VER="2023.3.3"
        ;;
    3)
        BURP_VER="2026.9.2"
        ;;
    4)
        BURP_VER="2024.11.2"
        ;;
    5)
        YEARS=("2026" "2025" "2024" "2023" "2022" "2021" "2020" "2019" "2018" "2017" "2016")
        echo ""
        echo -e "${BOLD}${YELLOW}Select Release Year (Last 10 Years):${NC}"
        for i in "${!YEARS[@]}"; do
            printf "  ${CYAN}%2d)${NC} %s\n" "$((i+1))" "${YEARS[$i]}"
        done
        echo ""
        read -rp "Enter year number [1-11, default=1]: " YR_NUM
        YR_NUM="${YR_NUM:-1}"
        if [[ "$YR_NUM" =~ ^[0-9]+$ ]] && [ "$YR_NUM" -ge 1 ] && [ "$YR_NUM" -le "${#YEARS[@]}" ]; then
            SELECTED_YEAR="${YEARS[$((YR_NUM-1))]}"
        else
            SELECTED_YEAR="2026"
        fi

        info "Fetching Professional JAR releases for $SELECTED_YEAR from PortSwigger..."
        mapfile -t YEAR_VERSIONS < <(fetch_portswigger_pro_releases "$SELECTED_YEAR")

        if [ "${#YEAR_VERSIONS[@]}" -eq 0 ]; then
            warn "No releases retrieved automatically for $SELECTED_YEAR. Falling back to default."
            BURP_VER="2025.12.3"
        else
            echo ""
            echo -e "${BOLD}${YELLOW}Available Burp Suite Pro releases for $SELECTED_YEAR:${NC}"
            MAX_SHOW=20
            [ "${#YEAR_VERSIONS[@]}" -lt "$MAX_SHOW" ] && MAX_SHOW="${#YEAR_VERSIONS[@]}"
            for i in $(seq 0 $((MAX_SHOW-1))); do
                printf "  ${CYAN}%2d)${NC} v%s\n" "$((i+1))" "${YEAR_VERSIONS[$i]}"
            done
            echo ""
            read -rp "Enter release number [1-$MAX_SHOW, default=1]: " VER_PICK
            VER_PICK="${VER_PICK:-1}"
            if [[ "$VER_PICK" =~ ^[0-9]+$ ]] && [ "$VER_PICK" -ge 1 ] && [ "$VER_PICK" -le "$MAX_SHOW" ]; then
                BURP_VER="${YEAR_VERSIONS[$((VER_PICK-1))]}"
            else
                BURP_VER="${YEAR_VERSIONS[0]}"
            fi
        fi
        ;;
    6)
        echo ""
        read -rp "Enter Burp Suite Pro version (e.g. 2024.11.2, 2023.3.3, 1.7.30): " CUSTOM_VER_INPUT
        BURP_VER="${CUSTOM_VER_INPUT:-2025.12.3}"
        ;;
    *)
        BURP_VER="2025.12.3"
        ;;
esac

BURP_JAR="burpsuite_pro_v${BURP_VER}.jar"
ok "Selected Burp Suite Pro: v${BURP_VER}"

# ── Download BurpSuite Pro JAR from PortSwigger ───────────────────────
if is_valid_jar "${BURP_DIR}/${BURP_JAR}" 50000000; then
    ok "$BURP_JAR already exists and is valid — skipping download."
else
    rm -f "${BURP_DIR}/${BURP_JAR}"
    info "Downloading BurpSuite Pro v${BURP_VER} from PortSwigger (~600–750 MB)..."

    # Prioritize endpoint schema by release year
    # 2026+ uses product=desktop, pre-2026 uses product=pro
    if [[ "$BURP_VER" =~ ^202[6-9] ]]; then
        DOWNLOAD_URLS=(
            "https://portswigger.net/burp/releases/download?product=desktop&version=${BURP_VER}&type=jar"
            "https://portswigger.net/burp/releases/startdownload?product=desktop&version=${BURP_VER}&type=jar"
            "https://portswigger.net/burp/releases/download?product=pro&version=${BURP_VER}&type=Jar"
            "https://portswigger.net/burp/releases/startdownload?product=pro&version=${BURP_VER}&type=Jar"
        )
    else
        DOWNLOAD_URLS=(
            "https://portswigger.net/burp/releases/download?product=pro&version=${BURP_VER}&type=Jar"
            "https://portswigger.net/burp/releases/startdownload?product=pro&version=${BURP_VER}&type=Jar"
            "https://portswigger.net/burp/releases/download?product=desktop&version=${BURP_VER}&type=jar"
            "https://portswigger.net/burp/releases/startdownload?product=desktop&version=${BURP_VER}&type=jar"
        )
    fi

    WGET_PROGRESS_OPTS=("-q" "--show-progress")
    if ! wget --help 2>&1 | grep -q -- '--show-progress'; then
        WGET_PROGRESS_OPTS=("--progress=bar:force")
    fi

    DOWNLOADED=0
    for dl_url in "${DOWNLOAD_URLS[@]}"; do
        info "Connecting to PortSwigger endpoint: $dl_url"
        echo -e "${CYAN}★ Downloading ${BURP_JAR} (live progress below):${NC}\n"

        if command -v wget &>/dev/null; then
            net_run wget --no-check-certificate --tries=3 --timeout=300 "${WGET_PROGRESS_OPTS[@]}" -c "$dl_url" -O "${BURP_DIR}/${BURP_JAR}"
        else
            net_run curl -# -L -C - --max-time 600 "$dl_url" -o "${BURP_DIR}/${BURP_JAR}"
        fi
        echo ""

        if is_valid_jar "${BURP_DIR}/${BURP_JAR}" 50000000; then
            DOWNLOADED=1
            break
        fi
        warn "Endpoint did not return a valid JAR (>50 MB). Trying next endpoint..."
        rm -f "${BURP_DIR}/${BURP_JAR}"
    done

    if [ "$DOWNLOADED" -eq 1 ]; then
        ok "BurpSuite Pro v${BURP_VER} downloaded successfully!"
    else
        echo ""
        err "Automated download failed. Please download it manually:"
        echo -e "  ${YELLOW}1. Open this URL in your browser:${NC}"
        echo -e "     ${CYAN}https://portswigger.net/burp/releases${NC}"
        echo -e "  ${YELLOW}2. Locate version ${BURP_VER} and download the JAR file.${NC}"
        echo -e "  ${YELLOW}3. Save file as:${NC}"
        echo -e "     ${CYAN}${BURP_DIR}/${BURP_JAR}${NC}"
        echo -e "  ${YELLOW}4. Return here and press ENTER.${NC}"
        pause
        is_valid_jar "${BURP_DIR}/${BURP_JAR}" 50000000 \
            || die "Downloaded BurpSuite JAR is invalid. Please check the file and re-run."
    fi
fi

sudo chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${BURP_JAR}" 2>/dev/null || true
sudo chown "$REAL_USER":"$REAL_USER" "$BURP_DIR" 2>/dev/null || true

echo ""
ok "Files ready in $BURP_DIR:"
ls -lh "$BURP_DIR"
pause

# ════════════════════════════════════════════════════════════════════════
#  STEP 03 ── Launch Keygen & BurpSuite
# ════════════════════════════════════════════════════════════════════════
step "STEP 03 ── Application Launch & Activation Workflow"

echo -e "${BOLD}${CYAN}━━━━━━ ACTIVATION PROCEDURE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Keygen GUI will open → ${BOLD}Copy the License Key${NC}."
echo -e "  ${CYAN}2.${NC} Click ${BOLD}[ Run ]${NC} in Keygen to start BurpSuite."
echo -e "  ${CYAN}3.${NC} In BurpSuite: Paste the License Key and click ${BOLD}[ Next ]${NC}."
echo -e "  ${CYAN}4.${NC} Select ${BOLD}[ Manual Activation ]${NC} when shown."
echo -e "  ${CYAN}5.${NC} Copy the ${BOLD}Activation Request${NC} from Burp into Keygen."
echo -e "  ${CYAN}6.${NC} Copy the generated ${BOLD}Activation Response${NC} from Keygen into Burp."
echo -e "  ${CYAN}7.${NC} Finish activation in BurpSuite."
echo ""
echo -e "${YELLOW}Press ENTER to launch ${KEYGEN}...${NC}"
pause

# ── Launch keygen in background so the window STAYS OPEN on screen ────
JAVA_MODULE_FLAGS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.desktop/javax.swing=ALL-UNNAMED"
info "Launching ${KEYGEN} GUI in background (window will stay open)..."
as_user java $JAVA_MODULE_FLAGS -jar "${BURP_DIR}/${KEYGEN}" &
KEYGEN_PID=$!

echo ""
ok "${KEYGEN} GUI is now running (PID: $KEYGEN_PID)."
echo -e "${GREEN}★ The Keygen window is now open on your screen — do NOT close it!${NC}"
echo ""

# ── Ask user if activation is finished or retry ───────────────────────
ACTIVATION_DONE=0
while [ "$ACTIVATION_DONE" -eq 0 ]; do
    echo -e "${BOLD}${YELLOW}Activation Status:${NC}"
    read -rp "Has Burp Suite activation finished successfully? [y/N]: " ACT_INPUT
    if [[ "$ACT_INPUT" =~ ^[Yy] ]]; then
        ACTIVATION_DONE=1
        ok "Activation completed successfully! ✔"
    else
        echo ""
        warn "Activation is not finished yet."
        read -rp "Would you like to re-launch the Keygen to try again? [Y/n, default=Y]: " RETRY_ACT
        RETRY_ACT="${RETRY_ACT:-Y}"
        if [[ "$RETRY_ACT" =~ ^[Yy] ]]; then
            info "Relaunching ${KEYGEN} GUI..."
            as_user java $JAVA_MODULE_FLAGS -jar "${BURP_DIR}/${KEYGEN}" &
            KEYGEN_PID=$!
            ok "${KEYGEN} relaunched (PID: $KEYGEN_PID)."
            echo -e "${CYAN}Complete the activation steps in the GUI, then return here.${NC}"
        else
            warn "Proceeding with launcher setup..."
            ACTIVATION_DONE=1
        fi
    fi
done

# ── Step 03b: Copy Loader Command ─────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${YELLOW}  STEP 03b ── GET THE LOADER COMMAND FROM KEYGEN${NC}"
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${YELLOW}★ Make sure to KEEP the Keygen loader window open!${NC}"
echo -e "  ${CYAN}1.${NC} Look at the ${BOLD}'Loader Command'${NC} field at the top of the Keygen window."
echo -e "  ${CYAN}2.${NC} Copy the text from that field and paste it below."
echo -e "  ${CYAN}3.${NC} (Or press ENTER to use the auto-detected Java command)."
echo ""
read -rp "Paste Loader Command here [or press ENTER]: " CUSTOM_LOADER_CMD

if [ -n "$CUSTOM_LOADER_CMD" ]; then
    LOADER_CMD="$CUSTOM_LOADER_CMD"
else
    JAVA_BIN=$(readlink -f "$(which java)" 2>/dev/null || echo "java")
    LOADER_CMD="\"$JAVA_BIN\" $JAVA_MODULE_FLAGS -javaagent:\"${BURP_DIR}/${KEYGEN}\" -jar \"${BURP_DIR}/${BURP_JAR}\""
fi

echo ""
ok "Loader command configured:"
echo -e "  ${CYAN}${LOADER_CMD}${NC}"
echo ""

# ── Create ~/Documents/burp/burp.sh with nohup ────────────────────────
BURP_SH="${BURP_DIR}/burp.sh"
info "Creating startup script at $BURP_SH..."

cat > "$BURP_SH" <<EOF
#!/bin/bash
cd "${BURP_DIR}"
nohup ${LOADER_CMD} >/dev/null 2>&1 &
EOF

chmod +x "$BURP_SH"
sudo chown "$REAL_USER":"$REAL_USER" "$BURP_SH" 2>/dev/null || true
ok "Startup script created: $BURP_SH ✔"

# ── Create /usr/local/bin/burp-pro symlink ─────────────────────────────
info "Creating system symlink: /usr/local/bin/burp-pro -> $BURP_SH..."
sudo rm -f /usr/local/bin/burp-pro
sudo ln -sf "$BURP_SH" /usr/local/bin/burp-pro
ok "CLI command created: type ${BOLD}burp-pro${NC} in any terminal to launch!"

# ════════════════════════════════════════════════════════════════════════
#  STEP 04 ── Create Desktop Launcher
# ════════════════════════════════════════════════════════════════════════
step "STEP 04 ── Creating Desktop Launcher"

ICON_DIR="${REAL_HOME}/.local/share/icons"
mkdir -p "$ICON_DIR"
ICON_PATH="${ICON_DIR}/burpsuite.png"
PIXMAP_ICON="/usr/share/pixmaps/burpsuite.png"
BURP_DIR_ICON="${BURP_DIR}/burpsuite.png"

# Extract official icon from BurpSuite JAR
info "Configuring Burp Suite Pro icon..."
if command -v unzip &>/dev/null && [ -f "${BURP_DIR}/${BURP_JAR}" ]; then
    # 1) Try known PortSwigger official icon paths inside JAR
    for candidate in "resources/Media/icon64pro.png" "resources/Media/icon64.png" "resources/Media/icon32pro.png" "resources/Media/icon32.png" "resources/Media/icon16pro.png"; do
        if unzip -p "${BURP_DIR}/${BURP_JAR}" "$candidate" > "$ICON_PATH" 2>/dev/null && [ -s "$ICON_PATH" ]; then
            ok "Official icon extracted: $candidate"
            break
        fi
    done

    # 2) Fallback search for any icon*pro*.png or icon64*.png inside JAR
    if [ ! -s "$ICON_PATH" ]; then
        ICON_ENTRY=$(unzip -l "${BURP_DIR}/${BURP_JAR}" 2>/dev/null \
            | grep -iE '(icon.*pro|icon64|burpsuite.*icon).*\.png$' \
            | awk '{print $NF}' | head -1)
        if [ -n "$ICON_ENTRY" ]; then
            unzip -p "${BURP_DIR}/${BURP_JAR}" "$ICON_ENTRY" > "$ICON_PATH" 2>/dev/null \
                && ok "Icon extracted: $ICON_ENTRY" \
                || rm -f "$ICON_PATH"
        fi
    fi
fi

# 3) Embedded official 64x64 BurpSuite Pro icon fallback (guarantees icon is never blank)
if [ ! -s "$ICON_PATH" ]; then
    info "Embedding official Burp Suite Pro 64x64 icon..."
    base64 -d > "$ICON_PATH" 2>/dev/null <<'EOF_ICON'
iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAAAnFBMVEVbT/9jV/9tYv+qo/////+6tf+Lgv/9/f90af/19f+Hfv9kWf/l5P+po/9cUP/Py//IxP+xrP/h3/9iVv+Si//y8f9vZf95cP/4+P/8/P+Ee/9nXP/r6f+hmv9dUf/W0//BvP/7+v+uqP+Ad/+ak/9/dv9sYf/v7v9gVP/c2v96cP+moP/Rzv/6+v+/uv+gmf9hVf/g3v/Hw//19P8g0/xMAAAA2klEQVR4Ae3WNXrFMBRE4XnRfczMzLbD+99bPJVTBebmS6W/n9MYJETRt0oPuRJ0wXLBFYiBsjNQqfoCtTr31QZEzZZRG6JO16gHVd9oMIRoZDSeQDSdcT9fQLRcGa0h2myNdr430PaHQEf82skKypt43vsCl6u5Are7+QJJWsjiL+2PAllaSJTAJ/ebL3C9wBXYn+ELnPBrx0CHR6MyVE9G2w1Ez0arJUSLOfezKUSTsdEIopdXoz5Ub0bdDkRto1YTokaV+/ea72usVuALlOMv7R8D+nU/ij4AkKERE6vBiJsAAAAASUVORK5CYII=
EOF_ICON
fi

# Install icon to system pixmaps and user directories for universal desktop support
if [ -s "$ICON_PATH" ]; then
    mkdir -p /usr/share/pixmaps 2>/dev/null || true
    cp -f "$ICON_PATH" "$PIXMAP_ICON" 2>/dev/null || true
    cp -f "$ICON_PATH" "$BURP_DIR_ICON" 2>/dev/null || true
    chmod 644 "$ICON_PATH" "$PIXMAP_ICON" "$BURP_DIR_ICON" 2>/dev/null || true
    chown "$REAL_USER":"$REAL_USER" "$ICON_PATH" "$BURP_DIR_ICON" 2>/dev/null || true
    ACTIVE_ICON="$PIXMAP_ICON"
else
    ACTIVE_ICON="application-x-java"
fi

# Create Desktop Entry directly without subshell wrapper
DESKTOP_DIR="${REAL_HOME}/Desktop"
mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="${DESKTOP_DIR}/Burp-pro.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Burp-pro
GenericName=BurpSuite Professional
Comment=BurpSuite Pro v${BURP_VER} - Web Security Testing
Exec=${LOADER_CMD}
Path=${BURP_DIR}
Icon=${ACTIVE_ICON}
Terminal=false
Categories=Security;Network;Development;
Keywords=burpsuite;security;web;proxy;pentest;
StartupNotify=true
StartupWMClass=burp-StartBurp
EOF

chmod +x "$DESKTOP_FILE"
chown "$REAL_USER":"$REAL_USER" "$DESKTOP_FILE" 2>/dev/null || true

# Mark launcher as trusted & secure across XFCE (4.18+ SHA-256 checksum) and GNOME/KDE
if command -v gio &>/dev/null; then
    DESK_CHECKSUM=$(sha256sum "$DESKTOP_FILE" 2>/dev/null | awk '{print $1}')
    if [ -n "$DESK_CHECKSUM" ]; then
        gio set -t string "$DESKTOP_FILE" metadata::xfce-exe-checksum "$DESK_CHECKSUM" 2>/dev/null || true
        as_user gio set -t string "$DESKTOP_FILE" metadata::xfce-exe-checksum "$DESK_CHECKSUM" 2>/dev/null || true
    fi
    gio set -t string "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
    as_user gio set -t string "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
fi

# If running on root desktop or root Desktop exists, duplicate for root session and mark secure
if [ -d "/root/Desktop" ] && [ "$DESKTOP_DIR" != "/root/Desktop" ]; then
    cp -f "$DESKTOP_FILE" "/root/Desktop/Burp-pro.desktop" 2>/dev/null || true
    chmod +x "/root/Desktop/Burp-pro.desktop" 2>/dev/null || true
    if command -v gio &>/dev/null; then
        ROOT_CHECKSUM=$(sha256sum "/root/Desktop/Burp-pro.desktop" 2>/dev/null | awk '{print $1}')
        [ -n "$ROOT_CHECKSUM" ] && gio set -t string "/root/Desktop/Burp-pro.desktop" metadata::xfce-exe-checksum "$ROOT_CHECKSUM" 2>/dev/null || true
        gio set -t string "/root/Desktop/Burp-pro.desktop" metadata::trusted true 2>/dev/null || true
    fi
fi

# Register in applications menu (user and global)
APPS_MENU_DIR="${REAL_HOME}/.local/share/applications"
mkdir -p "$APPS_MENU_DIR"
cp -f "$DESKTOP_FILE" "${APPS_MENU_DIR}/Burp-pro.desktop" 2>/dev/null || true
chown "$REAL_USER":"$REAL_USER" "${APPS_MENU_DIR}/Burp-pro.desktop" 2>/dev/null || true
mkdir -p /usr/share/applications 2>/dev/null || true
cp -f "$DESKTOP_FILE" /usr/share/applications/Burp-pro.desktop 2>/dev/null || true

ok "Desktop launcher created at: $DESKTOP_FILE"
ok "Launcher command set to: ${LOADER_CMD}"
ok "Launcher icon set to: ${ACTIVE_ICON}"

# ════════════════════════════════════════════════════════════════════════
#  STEP 05 ── System & Installation Diagnostics
# ════════════════════════════════════════════════════════════════════════
step "DIAGNOSTICS ── System Summary"

echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                   ✔   Installation Summary                   ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
printf "  ║  %-58s║\n" "  OS / Distro   : $DISTRO ($ARCH)"
printf "  ║  %-58s║\n" "  User          : $REAL_USER"
printf "  ║  %-58s║\n" "  Active Java   : $(java -version 2>&1 | head -1)"
printf "  ║  %-58s║\n" "  Burp Version  : v${BURP_VER}"
printf "  ║  %-58s║\n" "  Directory     : $BURP_DIR"
printf "  ║  %-58s║\n" "  Script        : $BURP_SH"
printf "  ║  %-58s║\n" "  CLI Command   : /usr/local/bin/burp-pro"
printf "  ║  %-58s║\n" "  Launcher      : $DESKTOP_FILE"
printf "  ║  %-58s║\n" "  Network Mode  : $([ "$USE_PROXY" -eq 1 ] && echo "Proxychains" || echo "Direct")"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${GREEN}All set! You can launch BurpSuite Pro by:${NC}"
echo -e "  1. Double-clicking ${BOLD}Burp-pro${NC} on your Desktop"
echo -e "  2. Typing ${BOLD}burp-pro${NC} in any terminal\n"
