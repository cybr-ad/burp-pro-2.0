#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════╗
# ║      BurpSuite Pro ─ Universal Setup Script v6                       ║
# ║      Supports: Kali Linux · Debian · Ubuntu · Fedora · Arch         ║
# ║      Features: JDK 17-26 Support · Automated Setup · Clean Networking║
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
    echo "  ║       JDK 17-26 · Automated Setup · Clean Networking       ║"
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
#  Execution Wrapper for Downloads
# ════════════════════════════════════════════════════════════════════════
net_run() {
    "$@"
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

get_oracle_jdk_url() {
    local v="$1"
    case "$v" in
        17) echo "https://download.oracle.com/java/17/archive/jdk-17_linux-x64_bin.deb" ;;
        18) echo "https://download.oracle.com/java/18/archive/jdk-18_linux-x64_bin.deb" ;;
        19) echo "https://download.oracle.com/java/19/archive/jdk-19_linux-x64_bin.deb" ;;
        20) echo "https://download.oracle.com/java/20/archive/jdk-20_linux-x64_bin.deb" ;;
        21) echo "https://download.oracle.com/java/21/archive/jdk-21_linux-x64_bin.deb" ;;
        22) echo "https://download.oracle.com/java/22/archive/jdk-22_linux-x64_bin.deb" ;;
        23) echo "https://download.oracle.com/java/23/archive/jdk-23_linux-x64_bin.deb" ;;
        24) echo "https://download.oracle.com/java/24/archive/jdk-24_linux-x64_bin.deb" ;;
        25) echo "https://download.oracle.com/java/25/archive/jdk-25_linux-x64_bin.deb" ;;
        26) echo "https://download.oracle.com/java/26/archive/jdk-26_linux-x64_bin.deb" ;;
        *)  echo "https://download.oracle.com/java/${v}/archive/jdk-${v}_linux-x64_bin.deb" ;;
    esac
}

configure_java_runtime() {
    # Check currently active Java version
    CURRENT_JAVA_VER=$(java -version 2>&1 | grep -oP 'version "(?:1\.)?\K[0-9]+' | head -1 || echo "0")
    if [ -z "$CURRENT_JAVA_VER" ] || [ "$CURRENT_JAVA_VER" -eq 0 ]; then
        CURRENT_JAVA_VER=$(java -version 2>&1 | grep -oP 'openjdk (?:1\.)?\K[0-9]+' | head -1 || echo "0")
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

        CANDIDATE_URLS=("$PRIMARY_URL")
        if [ -n "$FALLBACK_URL" ] && [ "$FALLBACK_URL" != "$PRIMARY_URL" ]; then
            CANDIDATE_URLS+=("$FALLBACK_URL")
        fi

        for dl_url in "${CANDIDATE_URLS[@]}"; do
            [ -z "$dl_url" ] && continue
            info "Connecting to: $dl_url"
            echo -e "${CYAN}★ Downloading JDK ${CHOSEN_JAVA_VER} package (live progress below):${NC}\n"
            if command -v wget &>/dev/null; then
                net_run wget --no-check-certificate --tries=3 --timeout=120 "${WGET_PROGRESS_OPTS[@]}" -c "$dl_url" -O "$JDK_DEB"
            else
                net_run curl -# -f -L -C - --max-time 300 "$dl_url" -o "$JDK_DEB"
            fi
            echo ""
            fsize=0
            if [ -f "$JDK_DEB" ]; then
                fsize=$(wc -c < "$JDK_DEB" 2>/dev/null || echo 0)
            fi
            if [ "$fsize" -gt 10000000 ]; then
                DOWNLOAD_OK=1
                break
            fi
            rm -f "$JDK_DEB"
        done

        # Fallback to distribution package manager if direct Oracle download is unavailable
        if [ "$DOWNLOAD_OK" -eq 0 ] && command -v apt-get &>/dev/null; then
            warn "Direct Oracle deb download failed. Attempting system package manager (openjdk-${CHOSEN_JAVA_VER}-jdk)..."
            if sudo apt-get update -qq && sudo apt-get install -y "openjdk-${CHOSEN_JAVA_VER}-jdk" 2>/dev/null; then
                DOWNLOAD_OK=1
                ok "Installed openjdk-${CHOSEN_JAVA_VER}-jdk via package manager."
            fi
        fi

        [ "$DOWNLOAD_OK" -eq 1 ] || die "JDK $CHOSEN_JAVA_VER download failed. Check network or proxy settings."

        if [ -f "$JDK_DEB" ]; then
            info "Installing JDK $CHOSEN_JAVA_VER package via dpkg..."
            sudo dpkg -i "$JDK_DEB"
            sudo apt-get install -f -y 2>/dev/null || true
        fi

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
}

configure_java_runtime
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

# ── Helper: Query PortSwigger for Latest BurpSuite Pro Releases ──────
fetch_portswigger_latest() {
    python3 - 'latest' << 'PYEOF' 2>/dev/null
import sys, urllib.request, json

headers = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'}
url = 'https://portswigger.net/burp/releases/data?pageSize=20'
try:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read().decode('utf-8'))
    results = data.get('ResultSet', {}).get('Results', [])
    stable = None
    early = None
    for r in results:
        v = r.get('version')
        channels = r.get('releaseChannels', [])
        dt = r.get('releaseDate', '')
        if not v:
            continue
        is_early = 'Early Adopter' in channels or 'Beta' in channels
        if is_early and not early:
            early = (v, 'Early Access', dt)
        elif not is_early and not stable:
            stable = (v, 'Stable', dt)
        if stable and early:
            break
    if stable:
        print(f"LATEST_STABLE={stable[0]}|{stable[1]}|{stable[2]}")
    if early:
        print(f"LATEST_EARLY={early[0]}|{early[1]}|{early[2]}")
except Exception:
    pass
PYEOF
}

# ── Helper: Query PortSwigger Archive for Releases with Channel Badges ─
fetch_portswigger_pro_releases() {
    local target_year="$1"
    python3 - "$target_year" << 'PYEOF' 2>/dev/null
import sys, urllib.request, json, re

year = sys.argv[1] if len(sys.argv) > 1 else '2026'
headers = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'}

FALLBACKS = {
    "2026": [
        ("2026.11.1", "Stable", "Nov 2026"),
        ("2026.11", "Early Access", "Nov 2026"),
        ("2026.10.4", "Stable", "Nov 2026"),
        ("2026.10.3", "Stable", "Oct 2026"),
        ("2026.10.2", "Stable", "Oct 2026"),
        ("2026.10.1", "Stable", "Oct 2026"),
        ("2026.10", "Early Access", "Oct 2026"),
        ("2026.9.3", "Stable", "Oct 2026"),
        ("2026.9.2", "Stable", "Oct 2026"),
        ("2026.9.1", "Stable", "Oct 2026"),
        ("2026.9", "Early Access", "Sep 2026"),
        ("2026.8.2", "Stable", "Sep 2026"),
        ("2026.7.3", "Stable", "Jul 2026"),
        ("2026.6.2", "Stable", "Jun 2026"),
        ("2026.5.1", "Stable", "May 2026"),
        ("2026.4", "Stable", "Apr 2026"),
        ("2026.3", "Stable", "Mar 2026"),
        ("2026.2", "Stable", "Feb 2026"),
        ("2026.1", "Stable", "Jan 2026"),
    ],
    "2025": [
        ("2025.12.3", "Stable", "Dec 2025"),
        ("2025.12.2", "Stable", "Dec 2025"),
        ("2025.12.1", "Stable", "Dec 2025"),
        ("2025.12", "Early Access", "Dec 2025"),
        ("2025.11.6", "Stable", "Dec 2025"),
        ("2025.10.7", "Stable", "Nov 2025"),
        ("2025.9.1", "Stable", "Sep 2025"),
        ("2025.8.3", "Stable", "Aug 2025"),
        ("2025.7.1", "Stable", "Jul 2025"),
        ("2025.6.2", "Stable", "Jun 2025"),
        ("2025.5.1", "Stable", "May 2025"),
        ("2025.4.1", "Stable", "Apr 2025"),
        ("2025.3.2", "Stable", "Mar 2025"),
        ("2025.2.1", "Stable", "Feb 2025"),
        ("2025.1.1", "Stable", "Jan 2025"),
    ],
    "2024": [
        ("2024.12", "Early Access", "Dec 2024"),
        ("2024.11.2", "Stable", "Dec 2024"),
        ("2024.11.1", "Stable", "Nov 2024"),
        ("2024.11", "Early Access", "Nov 2024"),
        ("2024.10.3", "Stable", "Nov 2024"),
        ("2024.10.2", "Stable", "Nov 2024"),
        ("2024.10.1", "Stable", "Nov 2024"),
        ("2024.9.5", "Stable", "Nov 2024"),
        ("2024.9.4", "Stable", "Oct 2024"),
        ("2024.8.5", "Stable", "Aug 2024"),
        ("2024.7.6", "Stable", "Jul 2024"),
        ("2024.6.4", "Stable", "Jun 2024"),
        ("2024.5.5", "Stable", "May 2024"),
        ("2024.4.1", "Stable", "Apr 2024"),
        ("2024.3.1", "Stable", "Mar 2024"),
        ("2024.2.2", "Stable", "Feb 2024"),
        ("2024.1.3", "Stable", "Jan 2024"),
    ],
    "2023": [
        ("2023.12.1", "Stable", "Dec 2023"),
        ("2023.11.1.3", "Stable", "Dec 2023"),
        ("2023.10.3.7", "Stable", "Nov 2023"),
        ("2023.9.4", "Stable", "Sep 2023"),
        ("2023.8.2", "Stable", "Aug 2023"),
        ("2023.7.3", "Stable", "Jul 2023"),
        ("2023.6.2", "Stable", "Jun 2023"),
        ("2023.5.3", "Stable", "May 2023"),
        ("2023.4.4", "Stable", "Apr 2023"),
        ("2023.3.5", "Stable", "Mar 2023"),
        ("2023.3.3", "Stable", "Mar 2023"),
        ("2023.2.1", "Stable", "Feb 2023"),
        ("2023.1.2", "Stable", "Jan 2023"),
    ],
    "2022": [
        ("2022.12.5", "Stable", "Dec 2022"),
        ("2022.11.3", "Stable", "Nov 2022"),
        ("2022.9.6", "Stable", "Oct 2022"),
        ("2022.8.5", "Stable", "Sep 2022"),
        ("2022.7.1", "Stable", "Jul 2022"),
        ("2022.3.9", "Stable", "Apr 2022"),
        ("2022.2.5", "Stable", "Mar 2022"),
        ("2022.1.1", "Stable", "Feb 2022"),
    ],
    "2021": [
        ("2021.12", "Stable", "Dec 2021"),
        ("2021.10.3", "Stable", "Nov 2021"),
        ("2021.8.4", "Stable", "Aug 2021"),
        ("2021.6.2", "Stable", "Jun 2021"),
        ("2021.5.1", "Stable", "May 2021"),
        ("2021.4.1", "Stable", "Apr 2021"),
        ("2021.2.1", "Stable", "Feb 2021"),
    ],
    "2020": [
        ("2020.12.1", "Stable", "Dec 2020"),
        ("2020.11.3", "Stable", "Nov 2020"),
        ("2020.9.2", "Stable", "Sep 2020"),
        ("2020.8.1", "Stable", "Aug 2020"),
        ("2020.5.1", "Stable", "May 2020"),
        ("2020.4.1", "Stable", "Apr 2020"),
        ("2020.2.1", "Stable", "Feb 2020"),
        ("2020.1", "Stable", "Jan 2020"),
    ],
    "2019": [
        ("2.1.07", "Stable", "Nov 2019"),
        ("2.1.06", "Stable", "Oct 2019"),
        ("2.1.05", "Stable", "Sep 2019"),
        ("2.1.04", "Stable", "Jul 2019"),
        ("2.1.02", "Stable", "May 2019"),
        ("2.1.01", "Stable", "Apr 2019"),
        ("2.0.20", "Stable", "Feb 2019"),
    ],
    "2018": [
        ("2.0.13beta", "Beta", "Nov 2018"),
        ("2.0.12beta", "Beta", "Nov 2018"),
        ("2.0.11beta", "Beta", "Oct 2018"),
        ("1.7.37", "Stable", "Oct 2018"),
        ("1.7.36", "Stable", "Sep 2018"),
        ("1.7.35", "Stable", "Aug 2018"),
        ("1.7.34", "Stable", "Jul 2018"),
        ("1.7.33", "Stable", "Jun 2018"),
        ("1.7.32", "Stable", "May 2018"),
        ("1.7.31", "Stable", "Apr 2018"),
    ],
    "2017": [
        ("1.7.30", "Stable", "Dec 2017"),
        ("1.7.29", "Stable", "Nov 2017"),
        ("1.7.28", "Stable", "Oct 2017"),
        ("1.7.27", "Stable", "Sep 2017"),
        ("1.7.26", "Stable", "Aug 2017"),
        ("1.7.25", "Stable", "Jul 2017"),
        ("1.7.24", "Stable", "Jun 2017"),
        ("1.7.23", "Stable", "May 2017"),
        ("1.7.22", "Stable", "Apr 2017"),
        ("1.7.21", "Stable", "Mar 2017"),
        ("1.7.20", "Stable", "Feb 2017"),
    ],
    "2016": [
        ("1.7.15", "Stable", "Dec 2016"),
        ("1.7.14", "Stable", "Nov 2016"),
        ("1.7.13", "Stable", "Oct 2016"),
        ("1.7.12", "Stable", "Sep 2016"),
        ("1.7.11", "Stable", "Aug 2016"),
        ("1.7.10", "Stable", "Jul 2016"),
        ("1.7.09", "Stable", "Jun 2016"),
        ("1.7.08", "Stable", "May 2016"),
        ("1.7.07", "Stable", "Apr 2016"),
        ("1.7.06", "Stable", "Mar 2016"),
        ("1.7.05", "Stable", "Feb 2016"),
    ]
}

results = []
seen = set()

# 1. Check API first for recent matching releases
try:
    url = 'https://portswigger.net/burp/releases/data?pageSize=30'
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read().decode('utf-8'))
    for r in data.get('ResultSet', {}).get('Results', []):
        v = r.get('version', '')
        if v and v.startswith(str(year)) and v not in seen:
            channels = r.get('releaseChannels', [])
            ch = 'Early Access' if ('Early Adopter' in channels or 'Beta' in channels) else 'Stable'
            dt = r.get('releaseDate', '')
            seen.add(v)
            results.append((v, ch, dt))
except Exception:
    pass

# 2. Query PortSwigger archive page
try:
    url = f"https://portswigger.net/burp/releases/archive?y={year}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=6) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    matches = re.findall(r'<a[^>]*href=["\']/burp/releases/([^"\'>]+)["\'][^>]*>(.*?)</a>', html, re.DOTALL)
    for href, text in matches:
        if 'enterprise' in href.lower() or 'dast' in href.lower():
            continue
        m = re.match(r'^(?:professional(?:-community)?)-([0-9a-zA-Z\.\-]+)$', href)
        if not m:
            continue
        raw_v = m.group(1)
        if not raw_v or not raw_v[0].isdigit():
            continue
        v = raw_v.replace('-', '.')
        if int(year) >= 2020 and not v.startswith(str(year)):
            continue
        if v in seen:
            continue
        clean_text = ' '.join(re.sub(r'<[^>]+>', ' ', text).split())
        if 'beta' in v.lower() or 'beta' in clean_text.lower():
            ch = 'Beta'
        elif 'early' in clean_text.lower():
            ch = 'Early Access'
        else:
            ch = 'Stable'
        seen.add(v)
        dt_match = re.search(r'\d{1,2}\s+[A-Za-z]+\s+\d{4}', clean_text)
        dt = dt_match.group(0) if dt_match else ''
        results.append((v, ch, dt))
except Exception:
    pass

# 3. Merge fallbacks
for item in FALLBACKS.get(str(year), []):
    v, ch, dt = item
    if v not in seen:
        seen.add(v)
        results.append((v, ch, dt))

for v, ch, dt in results:
    print(f"{v}|{ch}|{dt}")
PYEOF
}

# ── Select BurpSuite Pro Version (PortSwigger Releases — Last 10 Years)
info "Checking PortSwigger for latest Burp Suite Pro releases..."
LATEST_STABLE_VER="2026.11.1"
LATEST_STABLE_DATE="Nov 2026"
LATEST_EARLY_VER="2026.11"
LATEST_EARLY_DATE="Nov 2026"

while IFS='=' read -r key val; do
    if [ "$key" = "LATEST_STABLE" ]; then
        IFS='|' read -r LATEST_STABLE_VER _ LATEST_STABLE_DATE <<< "$val"
    elif [ "$key" = "LATEST_EARLY" ]; then
        IFS='|' read -r LATEST_EARLY_VER _ LATEST_EARLY_DATE <<< "$val"
    fi
done < <(fetch_portswigger_latest)

BURP_VER=""
while true; do
    echo ""
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}  STEP 02b ── SELECT BURPSUITE PRO VERSION (PORTSWIGGER)     ${NC}"
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "JAR files are downloaded directly from ${CYAN}https://portswigger.net/burp/releases${NC}."
    echo -e "You can select popular versions or browse all Pro JAR releases from the ${BOLD}last 10 years (2016–2026)${NC}.\n"

    echo -e "  ${CYAN}1)${NC}  v${LATEST_STABLE_VER}  ${GREEN}[Stable]${NC}        ${GREEN}★ Latest Stable Release (Auto-detected)${NC}"
    if [ -n "$LATEST_EARLY_VER" ] && [ "$LATEST_EARLY_VER" != "$LATEST_STABLE_VER" ]; then
        echo -e "  ${CYAN}2)${NC}  v${LATEST_EARLY_VER}  ${YELLOW}[Early Access]${NC}  ${YELLOW}★ Latest Early Access / Preview${NC}"
        echo -e "  ${CYAN}3)${NC}  v2023.3.3   ${GREEN}[Stable]${NC}        ${GREEN}★ Recommended (Proven loader compatibility)${NC}"
        echo -e "  ${CYAN}4)${NC}  v2025.12.3  ${GREEN}[Stable]${NC}        (Stable 2025 release)"
        echo -e "  ${CYAN}5)${NC}  v2024.11.2  ${GREEN}[Stable]${NC}        (Stable 2024 release)"
        echo -e "  ${CYAN}6)${NC}  ${BOLD}Browse by Year${NC}  ${CYAN}(Explore 2026 down to 2016 with Stable/Beta/Early Access)${NC}"
        echo -e "  ${CYAN}7)${NC}  ${BOLD}Custom Version${NC}  ${CYAN}(Enter any version manually)${NC}"
        echo -e "  ${CYAN}0)${NC}  ${BOLD}↩ Back to Java Selection${NC}  ${CYAN}(Re-configure JDK runtime)${NC}"
    else
        echo -e "  ${CYAN}2)${NC}  v2023.3.3   ${GREEN}[Stable]${NC}        ${GREEN}★ Recommended (Proven loader compatibility)${NC}"
        echo -e "  ${CYAN}3)${NC}  v2025.12.3  ${GREEN}[Stable]${NC}        (Stable 2025 release)"
        echo -e "  ${CYAN}4)${NC}  v2024.11.2  ${GREEN}[Stable]${NC}        (Stable 2024 release)"
        echo -e "  ${CYAN}5)${NC}  ${BOLD}Browse by Year${NC}  ${CYAN}(Explore 2026 down to 2016 with Stable/Beta/Early Access)${NC}"
        echo -e "  ${CYAN}6)${NC}  ${BOLD}Custom Version${NC}  ${CYAN}(Enter any version manually)${NC}"
        echo -e "  ${CYAN}0)${NC}  ${BOLD}↩ Back to Java Selection${NC}  ${CYAN}(Re-configure JDK runtime)${NC}"
    fi

    echo ""
    read -rp "Enter choice [default=1, 0=Back to Java]: " VER_MENU_CHOICE
    VER_MENU_CHOICE="${VER_MENU_CHOICE:-1}"

    if [ "$VER_MENU_CHOICE" = "0" ] || [ "$VER_MENU_CHOICE" = "b" ] || [ "$VER_MENU_CHOICE" = "back" ] || [ "$VER_MENU_CHOICE" = "j" ]; then
        info "Returning to Java runtime selection..."
        configure_java_runtime
        continue
    fi

    GOTO_BROWSE_YEAR=0
    GOTO_CUSTOM=0

    if [ -n "$LATEST_EARLY_VER" ] && [ "$LATEST_EARLY_VER" != "$LATEST_STABLE_VER" ]; then
        case "$VER_MENU_CHOICE" in
            1) BURP_VER="$LATEST_STABLE_VER"; break ;;
            2) BURP_VER="$LATEST_EARLY_VER"; break ;;
            3) BURP_VER="2023.3.3"; break ;;
            4) BURP_VER="2025.12.3"; break ;;
            5) BURP_VER="2024.11.2"; break ;;
            6) GOTO_BROWSE_YEAR=1 ;;
            7) GOTO_CUSTOM=1 ;;
            *) BURP_VER="$LATEST_STABLE_VER"; break ;;
        esac
    else
        case "$VER_MENU_CHOICE" in
            1) BURP_VER="$LATEST_STABLE_VER"; break ;;
            2) BURP_VER="2023.3.3"; break ;;
            3) BURP_VER="2025.12.3"; break ;;
            4) BURP_VER="2024.11.2"; break ;;
            5) GOTO_BROWSE_YEAR=1 ;;
            6) GOTO_CUSTOM=1 ;;
            *) BURP_VER="$LATEST_STABLE_VER"; break ;;
        esac
    fi

    if [ "$GOTO_CUSTOM" -eq 1 ]; then
        echo ""
        echo -e "${YELLOW}Enter Burp Suite Pro version (e.g. 2026.11.1, 2024.11.2, 2023.3.3, 1.7.30).${NC}"
        echo -e "${CYAN}Or enter '0' or 'b' to go back to the Main Version Menu.${NC}"
        read -rp "Version: " CUSTOM_VER_INPUT
        if [ "$CUSTOM_VER_INPUT" = "0" ] || [ "$CUSTOM_VER_INPUT" = "b" ] || [ "$CUSTOM_VER_INPUT" = "back" ] || [ -z "$CUSTOM_VER_INPUT" ]; then
            continue
        fi
        BURP_VER="$CUSTOM_VER_INPUT"
        break
    fi

    if [ "$GOTO_BROWSE_YEAR" -eq 1 ]; then
        YEARS=("2026" "2025" "2024" "2023" "2022" "2021" "2020" "2019" "2018" "2017" "2016")

        BACK_TO_MAIN=0
        while true; do
            echo ""
            echo -e "${BOLD}${YELLOW}Select Release Year (Last 10 Years):${NC}"
            for i in "${!YEARS[@]}"; do
                printf "  ${CYAN}%2d)${NC} %s\n" "$((i+1))" "${YEARS[$i]}"
            done
            echo ""
            echo -e "   ${CYAN}0)${NC} ${BOLD}↩ Back to Main Version Menu${NC}"
            echo ""
            read -rp "Enter year number [1-11, 0 to go back, default=1]: " YR_NUM
            YR_NUM="${YR_NUM:-1}"

            if [ "$YR_NUM" = "0" ] || [ "$YR_NUM" = "b" ] || [ "$YR_NUM" = "back" ]; then
                BACK_TO_MAIN=1
                break
            fi

            if [[ "$YR_NUM" =~ ^[0-9]+$ ]] && [ "$YR_NUM" -ge 1 ] && [ "$YR_NUM" -le "${#YEARS[@]}" ]; then
                SELECTED_YEAR="${YEARS[$((YR_NUM-1))]}"
            else
                SELECTED_YEAR="2026"
            fi

            info "Fetching Professional JAR releases for $SELECTED_YEAR from PortSwigger..."
            mapfile -t RAW_YEAR_RELEASES < <(fetch_portswigger_pro_releases "$SELECTED_YEAR")

            if [ "${#RAW_YEAR_RELEASES[@]}" -eq 0 ]; then
                warn "No releases retrieved automatically for $SELECTED_YEAR. Falling back to default."
                BURP_VER="$LATEST_STABLE_VER"
                break 2
            fi

            BACK_TO_YEARS=0
            while true; do
                echo ""
                echo -e "${BOLD}${YELLOW}Available Burp Suite Pro releases for $SELECTED_YEAR:${NC}"
                MAX_SHOW=25
                [ "${#RAW_YEAR_RELEASES[@]}" -lt "$MAX_SHOW" ] && MAX_SHOW="${#RAW_YEAR_RELEASES[@]}"

                for i in $(seq 0 $((MAX_SHOW-1))); do
                    IFS='|' read -r v_ver v_chan v_date <<< "${RAW_YEAR_RELEASES[$i]}"
                    case "$v_chan" in
                        "Stable")       CHAN_LABEL="${GREEN}[Stable]${NC}      " ;;
                        "Early Access") CHAN_LABEL="${YELLOW}[Early Access]${NC}" ;;
                        "Beta")         CHAN_LABEL="${MAGENTA}[Beta]${NC}        " ;;
                        *)              CHAN_LABEL="${CYAN}[$v_chan]${NC}      " ;;
                    esac
                    if [ -n "$v_date" ]; then
                        printf "  ${CYAN}%2d)${NC} v%-12s %b ${YELLOW}(%s)${NC}\n" "$((i+1))" "$v_ver" "$CHAN_LABEL" "$v_date"
                    else
                        printf "  ${CYAN}%2d)${NC} v%-12s %b\n" "$((i+1))" "$v_ver" "$CHAN_LABEL"
                    fi
                done

                echo ""
                echo -e "   ${CYAN}0)${NC} ${BOLD}↩ Back to Year Selection${NC}"
                echo -e "  ${CYAN}00)${NC} ${BOLD}↩ Back to Main Version Menu${NC}"
                echo ""
                read -rp "Enter release number [1-$MAX_SHOW, 0=Back to Years, 00=Main Menu, default=1]: " VER_PICK
                VER_PICK="${VER_PICK:-1}"

                if [ "$VER_PICK" = "00" ] || [ "$VER_PICK" = "m" ] || [ "$VER_PICK" = "main" ]; then
                    BACK_TO_MAIN=1
                    break
                elif [ "$VER_PICK" = "0" ] || [ "$VER_PICK" = "b" ] || [ "$VER_PICK" = "back" ]; then
                    BACK_TO_YEARS=1
                    break
                elif [[ "$VER_PICK" =~ ^[0-9]+$ ]] && [ "$VER_PICK" -ge 1 ] && [ "$VER_PICK" -le "$MAX_SHOW" ]; then
                    IFS='|' read -r chosen_ver _ <<< "${RAW_YEAR_RELEASES[$((VER_PICK-1))]}"
                    BURP_VER="$chosen_ver"
                    break 3
                else
                    IFS='|' read -r chosen_ver _ <<< "${RAW_YEAR_RELEASES[0]}"
                    BURP_VER="$chosen_ver"
                    break 3
                fi
            done

            if [ "$BACK_TO_MAIN" -eq 1 ]; then
                break
            fi
        done

        if [ "$BACK_TO_MAIN" -eq 1 ]; then
            continue
        fi
    fi
done

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
printf "  ║  %-58s║\n" "  Network Mode  : Direct (Automated)"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${GREEN}All set! You can launch BurpSuite Pro by:${NC}"
echo -e "  1. Double-clicking ${BOLD}Burp-pro${NC} on your Desktop"
echo -e "  2. Typing ${BOLD}burp-pro${NC} in any terminal\n"
