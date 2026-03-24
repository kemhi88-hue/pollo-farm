#!/bin/bash

cat > /tmp/pollo_farm.sh << 'EOFMAIN'
#!/bin/bash

# ═══════════════════════════════════════
# POLLO FARM - GITHUB CODESPACES/CLOUD
# ═══════════════════════════════════════

PACKAGE="ai.pollo.ai"
PASS="YourPassword123"
INVITE="L54v43"
SERIAL="localhost:9163"

APK_URL="https://videocdn.pollo.ai/app/android/Pollo.ai_Android.apk"
APK_FILE="/tmp/Pollo.ai_Android.apk"
LOG_FILE="$HOME/success.txt"

SSH_USER="10.10.47.45_1774307563126"
SSH_HOST="162.128.224.130"
SSH_PORT="1824"
SSH_PASSWORD="o96YLn0cBmogbzk6VYxbmZAhuq29CTcurIrLwLH6X7Vv36J6h2mTN4+o3Rn253BhgNfJ21v9NiVpnWlUKWn5ZA=="
LOCAL_PORT="9163"
REMOTE_ADB="adb-proxy:17294"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO] $1${NC}"; }
log_ok() { echo -e "${GREEN}[✓] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[!] $1${NC}"; }
log_error() { echo -e "${RED}[✗] $1${NC}"; }
log_step() { echo -e "${WHITE}[$1] $2${NC}"; }

install_deps() {
    log_info "Cài đặt dependencies..."
    
    if [ -f /etc/debian_version ]; then
        sudo apt-get update -qq >/dev/null 2>&1
        sudo apt-get install -y android-tools-adb sshpass jq curl >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y android-tools sshpass jq curl >/dev/null 2>&1
    fi
    
    log_ok "Dependencies installed"
}

kill_tunnel() {
    pkill -f "ssh.*$SSH_HOST.*$SSH_PORT" 2>/dev/null
    adb kill-server 2>/dev/null
    sleep 1
}

setup_ssh() {
    log_info "Thiết lập SSH tunnel..."
    
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keyscan -p $SSH_PORT $SSH_HOST >> ~/.ssh/known_hosts 2>/dev/null
    
    sshpass -p "$SSH_PASSWORD" ssh \
        -oHostKeyAlgorithms=+ssh-rsa \
        -oStrictHostKeyChecking=no \
        -oServerAliveInterval=30 \
        -oServerAliveCountMax=3 \
        -L $LOCAL_PORT:$REMOTE_ADB \
        -Nf \
        $SSH_USER@$SSH_HOST \
        -p $SSH_PORT >/dev/null 2>&1
    
    [ $? -eq 0 ] && { log_ok "SSH tunnel OK"; sleep 1; return 0; } || { log_error "SSH FAILED"; return 1; }
}

check_ssh() { pgrep -f "ssh.*$SSH_HOST.*$SSH_PORT" >/dev/null; }

check_adb() {
    adb start-server >/dev/null 2>&1
    sleep 1
    adb connect $SERIAL >/dev/null 2>&1
    sleep 1
    adb -s $SERIAL shell echo "OK" >/dev/null 2>&1 && { log_ok "ADB OK"; return 0; } || { log_error "ADB FAILED"; return 1; }
}

hide_kb() { adb -s $SERIAL shell input keyevent 4 >/dev/null 2>&1; }

tap() {
    echo -e "  ${CYAN}→ $3${NC}"
    adb -s $SERIAL shell input tap $1 $2
}

type_text() {
    echo -e "  ${CYAN}✎ $2${NC}"
    adb -s $SERIAL shell input text "$1"
    hide_kb
}

focus_type() {
    echo -e "  ${CYAN}⌨ $4${NC}"
    adb -s $SERIAL shell input tap $1 $2
    sleep 0.2
    adb -s $SERIAL shell input text "$3"
    hide_kb
    sleep 0.2
}

enter_key() { adb -s $SERIAL shell input keyevent 66; }

install_apk() {
    adb -s $SERIAL shell pm list packages 2>/dev/null | grep -q "$PACKAGE" && { log_ok "APK installed"; return 0; }
    
    log_warn "Downloading APK..."
    [ ! -f "$APK_FILE" ] && curl -L -o "$APK_FILE" "$APK_URL" --progress-bar
    
    [ ! -f "$APK_FILE" ] && { log_error "Download failed"; return 1; }
    
    log_info "Installing APK..."
    adb -s $SERIAL install -r -g "$APK_FILE" >/dev/null 2>&1 && { log_ok "APK OK"; return 0; } || { log_error "Install failed"; return 1; }
}

create_mail() {
    DOMAIN=$(curl -s --connect-timeout 10 https://api.mail.tm/domains | jq -r '.["hydra:member"][0].domain' 2>/dev/null)
    [ "$DOMAIN" = "null" ] || [ -z "$DOMAIN" ] && return 1
    
    RAND=$(cat /dev/urandom | tr -dc a-z0-9 | head -c 8)
    EMAIL="pollo_${RAND}@${DOMAIN}"
    MPASS="Pass${RAND}123"
    
    RESULT=$(curl -s --connect-timeout 10 -X POST https://api.mail.tm/accounts \
        -H "Content-Type: application/json" \
        -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null)
    
    CHECK=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
    [ -z "$CHECK" ] && return 1
    
    log_ok "Email: $EMAIL"
    return 0
}

get_otp() {
    TOKEN=$(curl -s --connect-timeout 10 -X POST https://api.mail.tm/token \
        -H "Content-Type: application/json" \
        -d "{\"address\":\"$1\",\"password\":\"$2\"}" 2>/dev/null | jq -r '.token')
    
    [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ] && echo "FAILED" && return
    
    for i in {1..40}; do
        echo -e "  ${CYAN}⏳ Wait OTP ($i/40)${NC}"
        
        MSG_ID=$(curl -s --connect-timeout 10 https://api.mail.tm/messages \
            -H "Authorization: Bearer $TOKEN" 2>/dev/null \
            | jq -r '.["hydra:member"] | sort_by(.createdAt) | reverse | .[0].id' 2>/dev/null)
        
        [ "$MSG_ID" = "null" ] || [ -z "$MSG_ID" ] && sleep 3 && continue
        
        TEXT=$(curl -s --connect-timeout 10 "https://api.mail.tm/messages/$MSG_ID" \
            -H "Authorization: Bearer $TOKEN" 2>/dev/null | jq -r '.text' 2>/dev/null)
        
        OTP=$(echo "$TEXT" | grep -oP '\b\d{6}\b' | head -n 1 | tr -d '\r\n ')
        [[ "$OTP" =~ ^[0-9]{6}$ ]] && echo "$OTP" && return
        
        sleep 3
    done
    
    echo "FAILED"
}

run_one() {
    echo ""
    echo -e "${YELLOW}════════════ RUN #$1 ════════════${NC}"
    
    log_step "1" "Clear data"
    adb -s $SERIAL shell pm clear $PACKAGE >/dev/null 2>&1
    
    log_step "2" "Launch app"
    adb -s $SERIAL shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 12
    
    log_step "3" "Navigate"
    tap 110 457 "menu"; sleep 3
    tap 623 1232 "login"; sleep 2
    tap 360 725 "login"; sleep 1
    tap 94 1210 "register"; sleep 1
    tap 283 1100 "next"; sleep 1
    tap 489 452 "next"; sleep 1
    tap 258 556 "email"; sleep 1
    
    log_step "4" "Create email"
    create_mail || return 1
    
    log_step "5" "Input email"
    focus_type 258 556 "$EMAIL" "email"; sleep 1
    tap 350 670 "GetOTP"; sleep 5
    
    OTP=$(get_otp "$EMAIL" "$MPASS")
    [[ ! "$OTP" =~ ^[0-9]{6}$ ]] && { log_error "OTP failed"; return 1; }
    log_ok "OTP: $OTP"
    
    log_step "6" "Submit OTP"
    tap 258 556 "otp"; sleep 0.3
    type_text "$OTP" "otp"; sleep 1
    tap 340 650 "submit"; sleep 5
    
    log_step "7" "Fill info"
    focus_type 210 580 "Minh" "firstname"; sleep 1
    focus_type 505 567 "Nguyen" "lastname"; sleep 1
    focus_type 154 711 "$PASS" "password"; sleep 2
    tap 324 843 "CREATE"; sleep 5
    
    log_step "8" "Login"
    tap 352 457 "email"; sleep 2
    focus_type 209 677 "$PASS" "password"; sleep 1
    tap 361 783 "submit"; sleep 4
    
    log_step "9" "Skip intro"
    tap 444 85 "skip1"; sleep 2
    tap 580 1018 "skip2"; sleep 2
    
    log_step "10" "Scroll"
    adb -s $SERIAL shell input swipe 500 1000 500 200 1000
    sleep 2
    
    log_step "11" "Enter invite"
    focus_type 173 973 "$INVITE" "code"; sleep 1
    enter_key; sleep 1
    
    log_step "12" "Redeem"
    tap 548 686 "REDEEM"; sleep 3
    
    echo ""
    echo -e "${GREEN}✅ SUCCESS #$1 | $EMAIL${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | #$1 | $EMAIL | $PASS" >> "$LOG_FILE"
    return 0
}

monitor_tunnel() {
    while true; do
        sleep 60
        check_ssh || {
            log_warn "Reconnecting SSH..."
            kill_tunnel
            setup_ssh
            check_adb
        }
    done
}

# ═══════════════════════════════════════
# MAIN
# ═══════════════════════════════════════

clear
echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🐔 POLLO FARM - CLOUD 🐔        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo ""

install_deps
kill_tunnel
setup_ssh || exit 1
check_adb || exit 1
install_apk || exit 1

monitor_tunnel &

log_ok "Starting farm loop..."
echo ""

COUNT=1
SUCCESS=0
FAIL=0

while true; do
    if run_one $COUNT; then
        SUCCESS=$((SUCCESS + 1))
        COUNT=$((COUNT + 1))
        log_ok "Stats: ✓$SUCCESS ✗$FAIL"
    else
        FAIL=$((FAIL + 1))
        log_warn "Stats: ✓$SUCCESS ✗$FAIL"
        sleep 10
    fi
done
EOFMAIN

chmod +x /tmp/pollo_farm.sh

clear
echo "╔════════════════════════════════════╗"
echo "║  ✅ POLLO FARM - INSTALLED        ║"
echo "╚════════════════════════════════════╝"
echo ""
echo "Script location: /tmp/pollo_farm.sh"
echo ""
echo "Starting in 3 seconds..."
sleep 3

exec /tmp/pollo_farm.sh
