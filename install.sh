#!/bin/bash

# ═══════════════════════════════════════════════════════
#  🐔 POLLO FARM v4.1 - Dynamic ADB (IPv4 Fixed)
#  curl -sL https://raw.githubusercontent.com/kemhi88-hue/pollo-farm/refs/heads/main/install.sh | bash -s -- "SSH_STRING" "SSH_PASSWORD"
# ═══════════════════════════════════════════════════════

PACKAGE="ai.pollo.ai"
PASS="YourPassword123"
INVITE="${INVITE:-}"

SSH_USER="${SSH_USER:-}"
SSH_HOST="${SSH_HOST:-}"
SSH_PORT="${SSH_PORT:-1824}"
SSH_PASS="${SSH_PASS:-}"
LOCAL_PORT="${LOCAL_PORT:-}"
REMOTE_ADB="${REMOTE_ADB:-}"

parse_args() {
    if [ -n "$1" ] && [ -z "$SSH_USER" ]; then
        local CONN_STR="$1"
        local PASS_STR="$2"

        local USER_HOST=$(echo "$CONN_STR" | grep -oE '[^ ]+@[^ ]+' | head -1)
        if [ -n "$USER_HOST" ]; then
            SSH_USER=$(echo "$USER_HOST" | cut -d'@' -f1)
            SSH_HOST=$(echo "$USER_HOST" | cut -d'@' -f2)
        fi

        local P_PORT=$(echo "$CONN_STR" | grep -oE '\-p [0-9]+' | awk '{print $2}')
        [ -n "$P_PORT" ] && SSH_PORT="$P_PORT"

        local L_PART=$(echo "$CONN_STR" | grep -oE '\-L [^ ]+' | awk '{print $2}')
        if [ -n "$L_PART" ]; then
            LOCAL_PORT=$(echo "$L_PART" | cut -d':' -f1)
            local R_HOST=$(echo "$L_PART" | cut -d':' -f2)
            local R_PORT=$(echo "$L_PART" | cut -d':' -f3)
            REMOTE_ADB="${R_HOST}:${R_PORT}"
        fi

        [ -n "$PASS_STR" ] && SSH_PASS="$PASS_STR"
    fi
}

parse_args "$1" "$2"

SERIAL="localhost:${LOCAL_PORT}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

validate_config() {
    local MISSING=0
    echo -e "${CYAN}[*] Validating config...${NC}"

    [ -z "$SSH_USER" ] && echo -e "${RED}  ✗ SSH_USER missing${NC}" && MISSING=1 || echo -e "${GREEN}  ✓ SSH_USER: $SSH_USER${NC}"
    [ -z "$SSH_HOST" ] && echo -e "${RED}  ✗ SSH_HOST missing${NC}" && MISSING=1 || echo -e "${GREEN}  ✓ SSH_HOST: $SSH_HOST${NC}"
    [ -z "$SSH_PORT" ] && echo -e "${RED}  ✗ SSH_PORT missing${NC}" && MISSING=1 || echo -e "${GREEN}  ✓ SSH_PORT: $SSH_PORT${NC}"
    [ -z "$SSH_PASS" ] && echo -e "${RED}  ✗ SSH_PASS missing${NC}" && MISSING=1 || echo -e "${GREEN}  ✓ SSH_PASS: ${SSH_PASS:0:10}...${NC}"
    [ -z "$LOCAL_PORT" ] && echo -e "${RED}  ✗ LOCAL_PORT missing${NC}" && MISSING=1 || echo -e "${GREEN}  ✓ LOCAL_PORT: $LOCAL_PORT${NC}"
    [ -z "$REMOTE_ADB" ] && echo -e "${RED}  ✗ REMOTE_ADB missing${NC}" && MISSING=1 || echo -e "${GREEN}  ✓ REMOTE_ADB: $REMOTE_ADB${NC}"

    echo -e "${GREEN}  ✓ SERIAL: $SERIAL${NC}"

    if [ $MISSING -eq 1 ]; then
        echo -e "\n${RED}══════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  THIẾU THÔNG TIN KẾT NỐI!${NC}"
        echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
        echo -e "\n${YELLOW}Cách dùng:${NC}"
        echo -e "  curl -sL URL | bash -s -- \"user@host -p PORT -L LPORT:RHOST:RPORT\" \"password\""
        echo -e "\n${YELLOW}Ví dụ:${NC}"
        echo -e "  curl -sL https://raw.githubusercontent.com/kemhi88-hue/pollo-farm/main/install.sh | bash -s -- \\"
        echo -e "    \"10.12.11.115_xxx@98.98.37.2 -p 1824 -L 9999:adb-proxy:63494\" \\"
        echo -e "    \"your_password_here\""
        exit 1
    fi
    echo -e "${GREEN}[OK] Config valid${NC}"
}

install_deps() {
    echo -e "${CYAN}[*] Check deps...${NC}"
    local NEED=""
    command -v ssh     >/dev/null 2>&1 || NEED="$NEED openssh-client"
    command -v sshpass >/dev/null 2>&1 || NEED="$NEED sshpass"
    command -v adb     >/dev/null 2>&1 || NEED="$NEED adb"
    command -v jq      >/dev/null 2>&1 || NEED="$NEED jq"
    command -v curl    >/dev/null 2>&1 || NEED="$NEED curl"
    if [ -n "$NEED" ]; then
        echo -e "${YELLOW}[!] Installing:$NEED${NC}"
        sudo apt-get update -y >/dev/null 2>&1
        sudo apt-get install -y $NEED >/dev/null 2>&1
    fi
    echo -e "${GREEN}[OK] Deps ready${NC}"
}

kill_tunnel() {
    pkill -f "ssh.*${SSH_HOST}.*${SSH_PORT}" 2>/dev/null
    fuser -k ${LOCAL_PORT}/tcp 2>/dev/null
    adb kill-server 2>/dev/null
    sleep 2
}

start_tunnel() {
    echo -e "${CYAN}[*] SSH tunnel → ${SSH_USER}@${SSH_HOST}:${SSH_PORT}${NC}"
    echo -e "${CYAN}    Local :${LOCAL_PORT} → ${REMOTE_ADB}${NC}"
    
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    ssh-keyscan -p $SSH_PORT $SSH_HOST >> ~/.ssh/known_hosts 2>/dev/null
    
    # *** FIX: Thêm -4 để force IPv4, tránh lỗi bind [::1] ***
    sshpass -p "$SSH_PASS" ssh \
        -4 \
        -oHostKeyAlgorithms=+ssh-rsa \
        -oStrictHostKeyChecking=no \
        -oServerAliveInterval=30 \
        -oServerAliveCountMax=3 \
        -oExitOnForwardFailure=yes \
        -L 127.0.0.1:${LOCAL_PORT}:${REMOTE_ADB} \
        -Nf \
        ${SSH_USER}@${SSH_HOST} \
        -p ${SSH_PORT}
    
    local RET=$?
    sleep 2
    
    if [ $RET -eq 0 ] && ss -tlnp 2>/dev/null | grep -q ":${LOCAL_PORT}"; then
        echo -e "${GREEN}[OK] SSH tunnel (port ${LOCAL_PORT} listening)${NC}"
        return 0
    else
        echo -e "${RED}[FAIL] SSH tunnel${NC}"
        return 1
    fi
}

check_tunnel() {
    pgrep -f "ssh.*${SSH_HOST}.*${SSH_PORT}" >/dev/null 2>&1 && \
    ss -tlnp 2>/dev/null | grep -q ":${LOCAL_PORT}"
}

ensure_tunnel() {
    if ! check_tunnel; then
        echo -e "${YELLOW}[!] Tunnel lost, reconnecting...${NC}"
        kill_tunnel
        start_tunnel || return 1
        connect_adb || return 1
    fi
}

connect_adb() {
    echo -e "${CYAN}[*] ADB connect → $SERIAL${NC}"
    
    # Start ADB với biến môi trường cố định
    export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
    
    adb kill-server 2>/dev/null
    sleep 1
    adb -L tcp:127.0.0.1:5037 start-server 2>/dev/null
    sleep 2
    adb connect $SERIAL 2>/dev/null
    sleep 3
    
    if adb -s $SERIAL shell echo OK 2>/dev/null | grep -q OK; then
        echo -e "${GREEN}[OK] ADB: $SERIAL${NC}"
        return 0
    else
        echo -e "${RED}[FAIL] ADB${NC}"
        adb devices
        return 1
    fi
}

hide_kb() {
    adb -s $SERIAL shell input keyevent 4 >/dev/null 2>&1
    sleep 0.1
}

tap() {
    echo -e "  ${CYAN}[TAP] $3 ($1,$2)${NC}"
    adb -s $SERIAL shell input tap "$1" "$2"
    sleep 0.2
}

focus_and_type() {
    echo -e "  ${CYAN}[F+T] $4 ($1,$2)${NC}"
    adb -s $SERIAL shell input tap "$1" "$2"
    sleep 0.3
    adb -s $SERIAL shell input text "$3"
    sleep 0.1
    hide_kb
    sleep 0.3
}

create_mail() {
    echo -e "${CYAN}[*] Creating email...${NC}"
    local retry=0
    DOMAIN=""
    while [ $retry -lt 5 ]; do
        DOMAIN=$(curl -s --max-time 10 https://api.mail.tm/domains \
            | jq -r '.["hydra:member"][0].domain // empty' 2>/dev/null)
        [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ] && break
        retry=$((retry+1))
        sleep 2
    done
    [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ] && echo -e "${RED}[FAIL] No domain${NC}" && return 1

    RAND=$(tr -dc a-z0-9 </dev/urandom | head -c 10)
    EMAIL="pf${RAND}@${DOMAIN}"
    MPASS="Xk${RAND}99"

    retry=0
    local CHECK=""
    while [ $retry -lt 3 ]; do
        RESULT=$(curl -s --max-time 10 -X POST https://api.mail.tm/accounts \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null)
        CHECK=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
        [ -n "$CHECK" ] && [ "$CHECK" != "null" ] && break
        retry=$((retry+1))
        RAND=$(tr -dc a-z0-9 </dev/urandom | head -c 10)
        EMAIL="pf${RAND}@${DOMAIN}"
        MPASS="Xk${RAND}99"
        sleep 2
    done
    [ -z "$CHECK" ] || [ "$CHECK" = "null" ] && echo -e "${RED}[FAIL] Create email${NC}" && return 1

    echo -e "${GREEN}[OK] $EMAIL${NC}"
    sleep 1

    retry=0
    MAIL_TOKEN=""
    while [ $retry -lt 3 ]; do
        MAIL_TOKEN=$(curl -s --max-time 10 -X POST https://api.mail.tm/token \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null \
            | jq -r '.token // empty' 2>/dev/null)
        if [ -n "$MAIL_TOKEN" ] && [ "$MAIL_TOKEN" != "null" ] && [ ${#MAIL_TOKEN} -gt 20 ]; then
            echo -e "${GREEN}[OK] Token cached${NC}"
            return 0
        fi
        retry=$((retry+1))
        sleep 2
    done
    echo -e "${RED}[FAIL] Token${NC}"
    return 1
}

get_otp() {
    local TOKEN="$MAIL_TOKEN"
    [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ] && echo "FAILED" && return 1

    echo -e "${CYAN}[*] Waiting OTP...${NC}" >&2

    local attempt=0
    while [ $attempt -lt 50 ]; do
        attempt=$((attempt+1))
        [ $((attempt%5)) -eq 0 ] && echo -e "  ${CYAN}⏳ ($attempt/50)...${NC}" >&2

        local MSGS=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $TOKEN" \
            https://api.mail.tm/messages 2>/dev/null)
        [ -z "$MSGS" ] && sleep 3 && continue

        local TOTAL=$(echo "$MSGS" | jq -r '.["hydra:totalItems"] // 0' 2>/dev/null)
        [ "$TOTAL" = "0" ] || [ -z "$TOTAL" ] || [ "$TOTAL" = "null" ] && sleep 3 && continue

        echo -e "  ${GREEN}📨 $TOTAL email(s)${NC}" >&2

        local MSG_ID=$(echo "$MSGS" | jq -r '.["hydra:member"] | sort_by(.createdAt) | reverse | .[0].id // empty' 2>/dev/null)
        [ -z "$MSG_ID" ] || [ "$MSG_ID" = "null" ] && sleep 3 && continue

        local FULL=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $TOKEN" \
            "https://api.mail.tm/messages/$MSG_ID" 2>/dev/null)
        [ -z "$FULL" ] && sleep 3 && continue

        local F_SUB=$(echo "$FULL" | jq -r '.subject // ""' 2>/dev/null)
        local F_TXT=$(echo "$FULL" | jq -r '.text // ""' 2>/dev/null)
        local F_INT=$(echo "$FULL" | jq -r '.intro // ""' 2>/dev/null)
        local F_HTM=$(echo "$FULL" | jq -r '.html // ""' 2>/dev/null)
        local F_HC=""
        [ -n "$F_HTM" ] && [ "$F_HTM" != "null" ] && \
            F_HC=$(echo "$F_HTM" | sed 's/<[^>]*>//g; s/&nbsp;/ /g; s/&#[0-9]*;//g')

        echo -e "  ${CYAN}Subj: $F_SUB${NC}" >&2

        local ALL="$F_SUB $F_INT $F_TXT $F_HC"
        local OTP=""

        OTP=$(echo "$ALL" | grep -oiE '(code|otp|verification|verify|is)[^0-9]{0,20}[0-9]{4,6}' \
            | grep -oE '[0-9]{4,6}' | head -1)
        [ -z "$OTP" ] && OTP=$(echo "$ALL" | grep -oE '\b[0-9]{6}\b' | head -1)
        [ -z "$OTP" ] && OTP=$(echo "$ALL" | grep -oE '\b[0-9]{4}\b' | head -1)

        OTP=$(echo "$OTP" | tr -d '\r\n\t ')

        if [[ "$OTP" =~ ^[0-9]{4,6}$ ]]; then
            echo -e "  ${GREEN}✅ OTP: $OTP${NC}" >&2
            echo "$OTP"
            return 0
        fi

        echo -e "  ${YELLOW}No OTP yet, text: ${F_TXT:0:100}${NC}" >&2
        sleep 3
    done

    echo -e "${RED}[FAIL] OTP timeout${NC}" >&2
    echo "FAILED"
    return 1
}

run_one() {
    echo -e "\n${YELLOW}══════════════════════════════${NC}"
    echo -e "${YELLOW}  RUN #$1${NC}"
    echo -e "${YELLOW}══════════════════════════════${NC}"

    ensure_tunnel || return 1

    echo -e "${CYAN}[1] Clear${NC}"
    adb -s $SERIAL shell pm clear $PACKAGE >/dev/null 2>&1
    sleep 2

    echo -e "${CYAN}[2] Open${NC}"
    adb -s $SERIAL shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 12

    echo -e "${CYAN}[3] Navigate${NC}"
    tap 110 457 "menu";       sleep 3
    tap 623 1232 "login/reg"; sleep 2
    tap 360 725 "login";      sleep 1
    tap 94 1210 "register";   sleep 1
    tap 283 1100 "next";      sleep 1
    tap 489 452 "next";       sleep 1
    tap 258 556 "email";      sleep 1

    echo -e "${CYAN}[4] Mail${NC}"
    create_mail || return 1

    focus_and_type 258 556 "$EMAIL" "email"
    sleep 1
    tap 350 670 "GetOTP"
    echo -e "${CYAN}[*] Wait 8s...${NC}"
    sleep 8

    echo -e "${CYAN}[5] OTP${NC}"
    OTP=$(get_otp)
    OTP=$(echo "$OTP" | tr -d '\r\n\t ')
    echo -e "${CYAN}[*] Got: [$OTP]${NC}"

    if [[ ! "$OTP" =~ ^[0-9]{4,6}$ ]]; then
        echo -e "${RED}[FAIL] Bad OTP: [$OTP]${NC}"
        return 1
    fi

    tap 258 556 "OTP field"; sleep 0.5
    for (( i=0; i<${#OTP}; i++ )); do
        adb -s $SERIAL shell input text "${OTP:$i:1}"
        sleep 0.15
    done
    sleep 1
    tap 340 650 "submit"; sleep 5

    echo -e "${CYAN}[6] Info${NC}"
    focus_and_type 210 580 "Minh" "first"
    sleep 1
    focus_and_type 505 567 "Nguyen" "last"
    sleep 1
    focus_and_type 154 711 "$PASS" "pass"
    sleep 2
    tap 324 843 "CREATE"; sleep 5

    echo -e "${CYAN}[7] Login${NC}"
    tap 352 457 "email"; sleep 2
    focus_and_type 209 677 "$PASS" "pass"
    sleep 1
    tap 361 783 "submit"; sleep 4

    echo -e "${CYAN}[8] Skip${NC}"
    tap 444 85 "skip1"; sleep 2
    tap 580 1018 "skip2"; sleep 2

    echo -e "${CYAN}[9] Scroll${NC}"
    adb -s $SERIAL shell input swipe 500 1000 500 200 1000
    sleep 2

    echo -e "${CYAN}[10] Invite${NC}"
    focus_and_type 173 973 "$INVITE" "invite"
    sleep 1
    adb -s $SERIAL shell input keyevent 66
    sleep 1

    echo -e "${CYAN}[11] Redeem${NC}"
    tap 548 686 "REDEEM"; sleep 3

    echo -e "${GREEN}╔═══════════════════════════╗${NC}"
    echo -e "${GREEN}║ ✅ SUCCESS #$1${NC}"
    echo -e "${GREEN}║ $EMAIL${NC}"
    echo -e "${GREEN}╚═══════════════════════════╝${NC}"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | #$1 | $EMAIL" >> ~/success.txt
    return 0
}

# ═══════════════════════════════
# MAIN
# ═══════════════════════════════
clear
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🐔 POLLO FARM v4.1 (IPv4 Fixed) 🐔     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""

validate_config
install_deps

echo -e "${CYAN}[*] Test mail.tm...${NC}"
curl -s --max-time 10 https://api.mail.tm/domains >/dev/null 2>&1 || {
    echo -e "${RED}[FAIL] mail.tm${NC}"; exit 1
}
echo -e "${GREEN}[OK] mail.tm${NC}"

kill_tunnel
start_tunnel || exit 1
connect_adb || exit 1

echo -e "\n${GREEN}[🚀] Starting farm...${NC}\n"

COUNT=1 OK=0 FAIL=0

while true; do
    if run_one $COUNT; then
        OK=$((OK+1))
        COUNT=$((COUNT+1))
        echo -e "${GREEN}📊 OK:$OK FAIL:$FAIL${NC}"
    else
        FAIL=$((FAIL+1))
        echo -e "${YELLOW}📊 OK:$OK FAIL:$FAIL | Wait 15s...${NC}"
        sleep 15
    fi
    sleep 5
done
