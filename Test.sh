cat > ~/af.sh << 'BASH_SCRIPT'
#!/bin/bash

PACKAGE="ai.pollo.ai"
PASS="YourPassword123"
CONFIG_CACHE=~/.af_last.conf

load_last_config() {
    if [ -f "$CONFIG_CACHE" ]; then
        source "$CONFIG_CACHE"
        echo -e "${CYAN}[*] Loaded last config${NC}"
    fi
}

save_config() {
    cat > "$CONFIG_CACHE" << CONF
SSH_USER="$SSH_USER"
SSH_HOST="$SSH_HOST"
SSH_PORT="$SSH_PORT"
SSH_PASS="$SSH_PASS"
REMOTE_ADB="$REMOTE_ADB"
LOCAL_PORT="$LOCAL_PORT"
INVITE="$INVITE"
CONF
}

SSH_USER=""
SSH_HOST=""
SSH_PORT=""
REMOTE_ADB=""
SSH_PASS=""
LOCAL_PORT=""
INVITE="bnqOrS"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE=""
MULTI_FILE=""

load_last_config

while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-user)   SSH_USER="$2";    shift 2 ;;
        --ssh-host)   SSH_HOST="$2";    shift 2 ;;
        --ssh-port)   SSH_PORT="$2";    shift 2 ;;
        --ssh-pass)   SSH_PASS="$2";    shift 2 ;;
        --remote-adb) REMOTE_ADB="$2";  shift 2 ;;
        --local-port) LOCAL_PORT="$2";  shift 2 ;;
        --invite)     INVITE="$2";      shift 2 ;;
        --password)   PASS="$2";        shift 2 ;;
        -f|--config)  CONFIG_FILE="$2"; shift 2 ;;
        -m|--multi)   MULTI_FILE="$2";  shift 2 ;;
        --clear)      rm -f "$CONFIG_CACHE"; echo "Config cleared"; exit 0 ;;
        --show)       cat "$CONFIG_CACHE" 2>/dev/null || echo "No saved config"; exit 0 ;;
        -h|--help)
            echo "Usage: $0 --invite CODE"
            echo "       $0 --ssh-host ... --invite CODE"
            echo "       $0 --clear | --show"
            exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

find_free_port() {
    local START=${1:-9999}
    local END=${2:-10050}
    for port in $(seq $START $END); do
        if ! ss -tlnp 2>/dev/null | grep -q ":${port} " && ! netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            echo "$port"; return 0
        fi
    done
    echo $(( RANDOM % 1000 + 10000 ))
}

set_port() {
    if [ -z "$LOCAL_PORT" ]; then
        LOCAL_PORT=$(find_free_port 9999 10050)
        echo -e "${CYAN}[*] Auto port: ${LOCAL_PORT}${NC}"
    fi
    SERIAL="127.0.0.1:${LOCAL_PORT}"
}

load_config() {
    local file="$1"
    [ ! -f "$file" ] && echo -e "${RED}[FAIL] Not found: $file${NC}" && exit 1
    echo -e "${CYAN}[*] Loading: $file${NC}"
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [ -z "$key" ] && continue
        value=$(echo "$value" | sed 's/^["'"'"']//;s/["'"'"']$//;s/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$key" in
            SSH_USER) SSH_USER="$value" ;;
            SSH_HOST) SSH_HOST="$value" ;;
            SSH_PORT) SSH_PORT="$value" ;;
            SSH_PASS) SSH_PASS="$value" ;;
            REMOTE_ADB) REMOTE_ADB="$value" ;;
            LOCAL_PORT) LOCAL_PORT="$value" ;;
            INVITE) INVITE="$value" ;;
            PASS) PASS="$value" ;;
        esac
    done < "$file"
}

[ -n "$CONFIG_FILE" ] && load_config "$CONFIG_FILE"

install_deps() {
    echo -e "${CYAN}[*] Check deps...${NC}"
    local NEED=""
    command -v ssh >/dev/null 2>&1 || NEED="$NEED openssh-client"
    command -v sshpass >/dev/null 2>&1 || NEED="$NEED sshpass"
    command -v adb >/dev/null 2>&1 || NEED="$NEED adb"
    command -v jq >/dev/null 2>&1 || NEED="$NEED jq"
    command -v curl >/dev/null 2>&1 || NEED="$NEED curl"
    if [ -n "$NEED" ]; then
        sudo apt-get update -y >/dev/null 2>&1
        sudo apt-get install -y $NEED >/dev/null 2>&1
    fi
    echo -e "${GREEN}[OK] Deps ready${NC}"
}

kill_tunnel() { pkill -f "ssh.*-L ${LOCAL_PORT}:" 2>/dev/null; sleep 1; }

start_tunnel() {
    echo -e "${CYAN}[*] SSH ${SSH_HOST}:${SSH_PORT} → :${LOCAL_PORT}${NC}"
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    ssh-keyscan -p $SSH_PORT $SSH_HOST >> ~/.ssh/known_hosts 2>/dev/null
    sshpass -p "$SSH_PASS" ssh -oHostKeyAlgorithms=+ssh-rsa -oStrictHostKeyChecking=no \
        -oServerAliveInterval=30 -oServerAliveCountMax=3 \
        -L ${LOCAL_PORT}:${REMOTE_ADB} -Nf ${SSH_USER}@${SSH_HOST} -p ${SSH_PORT} 2>/dev/null
    [ $? -eq 0 ] && { echo -e "${GREEN}[OK] Tunnel${NC}"; sleep 2; return 0; } || { echo -e "${RED}[FAIL] Tunnel${NC}"; return 1; }
}

check_tunnel() { pgrep -f "ssh.*-L ${LOCAL_PORT}:" >/dev/null 2>&1; }

ensure_tunnel() {
    if ! check_tunnel; then
        echo -e "${YELLOW}[!] Tunnel lost, reconnecting...${NC}"
        kill_tunnel; start_tunnel || return 1; connect_adb || return 1
    fi
}

connect_adb() {
    echo -e "${CYAN}[*] ADB connect...${NC}"
    adb disconnect $SERIAL 2>/dev/null
    sleep 1
    adb connect $SERIAL 2>/dev/null
    sleep 2
    if adb -s $SERIAL shell echo OK >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] ADB: $SERIAL${NC}"; return 0
    else
        echo -e "${RED}[FAIL] ADB${NC}"; return 1
    fi
}

hide_kb() { adb -s $SERIAL shell input keyevent 4 >/dev/null 2>&1; sleep 0.1; }
tap() { echo -e "  ${CYAN}[TAP] $3 ($1,$2)${NC}"; adb -s $SERIAL shell input tap "$1" "$2"; sleep 0.25; }
focus_and_type() { echo -e "  ${CYAN}[F+T] $4 ($1,$2)${NC}"; adb -s $SERIAL shell input tap "$1" "$2"; sleep 0.4; adb -s $SERIAL shell input text "$3"; sleep 0.2; hide_kb; sleep 0.3; }

# ==================== PHẦN MỚI - KHỞI ĐỘNG APP TỐT HƠN ====================
launch_app() {
    echo -e "${CYAN}[2] Launching Pollo...${NC}"
    
    adb -s $SERIAL shell am force-stop $PACKAGE 2>/dev/null
    sleep 1.5
    
    adb -s $SERIAL shell am start -n ai.pollo.ai/.MainActivity \
        --activity-clear-top --activity-single-top 2>&1 | cat
    
    sleep 10
    echo -e "${GREEN}[✓] App launched${NC}"
}

# =====================================================================

create_mail() { ... }   # (giữ nguyên phần create_mail, get_otp, run_one cũ)

# ... (các hàm create_mail, get_otp giữ nguyên như version trước)

run_one() {
    echo -e "\n${YELLOW}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}  RUN #$1 │ ${SSH_HOST}:${SSH_PORT} → :${LOCAL_PORT} │ Invite: $INVITE${NC}"
    echo -e "${YELLOW}══════════════════════════════════════${NC}"

    ensure_tunnel || return 1

    echo -e "${CYAN}[1] Clear data${NC}"
    adb -s $SERIAL shell pm clear $PACKAGE >/dev/null 2>&1
    sleep 2

    launch_app

    echo -e "${CYAN}[3] Navigate UI${NC}"
    tap 110 457 "menu";       sleep 3
    tap 623 1232 "login/reg"; sleep 2
    tap 360 725 "login";      sleep 1
    tap 94 1210 "register";   sleep 1
    tap 283 1100 "next";      sleep 1
    tap 489 452 "next";       sleep 1
    tap 258 556 "email";      sleep 1

    create_mail || return 1
    focus_and_type 258 556 "$EMAIL" "email"; sleep 1
    tap 350 670 "GetOTP"; sleep 8

    OTP=$(get_otp)
    OTP=$(echo "$OTP" | tr -d '\r\n\t ')
    [[ ! "$OTP" =~ ^[0-9]{4,6}$ ]] && echo -e "${RED}[FAIL] Bad OTP${NC}" && return 1

    tap 258 556 "otp field"; sleep 0.5
    for (( i=0; i<${#OTP}; i++ )); do
        adb -s $SERIAL shell input text "${OTP:$i:1}"; sleep 0.15
    done
    sleep 1
    tap 340 650 "submit"; sleep 6

    focus_and_type 210 580 "Minh" "first"; sleep 1
    focus_and_type 505 567 "Nguyen" "last"; sleep 1
    focus_and_type 154 711 "$PASS" "pass"; sleep 2
    tap 324 843 "CREATE"; sleep 6

    tap 352 457 "email"; sleep 2
    focus_and_type 209 677 "$PASS" "pass"; sleep 1
    tap 361 783 "submit"; sleep 5

    tap 444 85 "skip1"; sleep 2
    tap 580 1018 "skip2"; sleep 2
    adb -s $SERIAL shell input swipe 500 1000 500 200 1000; sleep 2
    focus_and_type 173 973 "$INVITE" "invite"; sleep 1
    adb -s $SERIAL shell input keyevent 66; sleep 1
    tap 548 686 "REDEEM"; sleep 4

    echo -e "${GREEN}✅ SUCCESS #$1 | $EMAIL | Invite: $INVITE${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | #$1 | $EMAIL | $INVITE | ${SSH_HOST}:${SSH_PORT}" >> ~/success.log
    return 0
}

# MAIN
clear
install_deps
curl -s --max-time 10 https://api.mail.tm/domains >/dev/null 2>&1 || { echo -e "${RED}mail.tm failed${NC}"; exit 1; }

if [ -z "$SSH_HOST" ] || [ -z "$SSH_PASS" ]; then
    echo -e "${RED}[ERROR] Missing SSH config!${NC}"
    exit 1
fi

if [ -n "$MULTI_FILE" ]; then
    run_multi "$MULTI_FILE"
    exit 0
fi

set_port
save_config

echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          🐔 AF v4.3                ║${NC}"
echo -e "${GREEN}║  ${SSH_HOST}:${SSH_PORT} → :${LOCAL_PORT}     ║${NC}"
echo -e "${GREEN}║  Invite: ${INVITE}                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"

kill_tunnel
start_tunnel || exit 1
connect_adb || exit 1

COUNT=1 OK=0 FAIL=0
while true; do
    if run_one $COUNT; then
        OK=$((OK+1))
        COUNT=$((COUNT+1))
    else
        FAIL=$((FAIL+1))
        sleep 12
    fi
    echo -e "${GREEN}📊 OK: $OK | FAIL: $FAIL${NC}"
    sleep 5
done
BASH_SCRIPT

chmod +x ~/af.sh
