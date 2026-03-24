cat > ~/pollo_farm.sh << 'EOFMAIN'
#!/bin/bash

# ═══════════════════════════════════════
# POLLO FARM - AUTO SSH + FIX OTP
# ═══════════════════════════════════════

PACKAGE="ai.pollo.ai"
PASS="YourPassword123"
INVITE="L54v43"
SERIAL="localhost:9163"

SSH_USER="10.10.47.45_1774307563126"
SSH_HOST="162.128.224.130"
SSH_PORT="1824"
SSH_PASS="o96YLn0cBmogbzk6VYxbmZAhuq29CTcurIrLwLH6X7Vv36J6h2mTN4+o3Rn253BhgNfJ21v9NiVpnWlUKWn5ZA=="
LOCAL_PORT="9163"
REMOTE_ADB="adb-proxy:17294"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

install_deps() {
    echo -e "${CYAN}[*] Kiểm tra dependencies...${NC}"
    local NEED=""
    command -v ssh      >/dev/null 2>&1 || NEED="$NEED openssh-client"
    command -v sshpass  >/dev/null 2>&1 || NEED="$NEED sshpass"
    command -v adb      >/dev/null 2>&1 || NEED="$NEED adb"
    command -v jq       >/dev/null 2>&1 || NEED="$NEED jq"
    command -v curl     >/dev/null 2>&1 || NEED="$NEED curl"

    if [ -n "$NEED" ]; then
        echo -e "${YELLOW}[!] Cài:$NEED${NC}"
        if command -v apt >/dev/null 2>&1; then
            sudo apt update -y >/dev/null 2>&1
            sudo apt install -y $NEED >/dev/null 2>&1
        elif command -v pkg >/dev/null 2>&1; then
            pkg install -y $NEED >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y $NEED >/dev/null 2>&1
        fi
    fi
    echo -e "${GREEN}[✓] Dependencies OK${NC}"
}

kill_tunnel() {
    pkill -f "ssh.*${SSH_HOST}.*${SSH_PORT}" 2>/dev/null
    adb kill-server 2>/dev/null
    sleep 1
}

start_tunnel() {
    echo -e "${CYAN}[*] Kết nối SSH tunnel...${NC}"
    echo -e "${CYAN}    ${SSH_USER}@${SSH_HOST}:${SSH_PORT}${NC}"
    echo -e "${CYAN}    Local :${LOCAL_PORT} → ${REMOTE_ADB}${NC}"

    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keyscan -p $SSH_PORT $SSH_HOST >> ~/.ssh/known_hosts 2>/dev/null

    sshpass -p "$SSH_PASS" ssh \
        -oHostKeyAlgorithms=+ssh-rsa \
        -oStrictHostKeyChecking=no \
        -oServerAliveInterval=30 \
        -oServerAliveCountMax=3 \
        -L ${LOCAL_PORT}:${REMOTE_ADB} \
        -Nf \
        ${SSH_USER}@${SSH_HOST} \
        -p ${SSH_PORT} 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] SSH tunnel OK${NC}"
        sleep 2
        return 0
    else
        echo -e "${RED}[✗] SSH tunnel FAILED${NC}"
        return 1
    fi
}

check_tunnel() {
    pgrep -f "ssh.*${SSH_HOST}.*${SSH_PORT}" >/dev/null 2>&1
}

ensure_tunnel() {
    if ! check_tunnel; then
        echo -e "${YELLOW}[!] Tunnel mất, reconnect...${NC}"
        kill_tunnel
        start_tunnel || return 1
        connect_adb || return 1
    fi
    return 0
}

connect_adb() {
    echo -e "${CYAN}[*] Kết nối ADB...${NC}"
    adb kill-server 2>/dev/null
    sleep 1
    adb start-server 2>/dev/null
    sleep 1
    adb connect $SERIAL 2>/dev/null
    sleep 2

    if adb -s $SERIAL shell echo "OK" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] ADB OK: $SERIAL${NC}"
        return 0
    else
        echo -e "${RED}[✗] ADB FAILED${NC}"
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
    adb -s $SERIAL shell input tap $1 $2
    sleep 0.2
}

type_text() {
    echo -e "  ${CYAN}[TYPE] $2${NC}"
    adb -s $SERIAL shell input text "$1"
    sleep 0.1
    hide_kb
    sleep 0.3
}

focus_and_type() {
    local x=$1 y=$2 text=$3 desc=$4
    echo -e "  ${CYAN}[FOCUS+TYPE] $desc ($x,$y)${NC}"
    adb -s $SERIAL shell input tap $x $y
    sleep 0.3
    adb -s $SERIAL shell input text "$text"
    sleep 0.1
    hide_kb
    sleep 0.3
}

create_mail() {
    echo -e "${CYAN}[*] Tạo email...${NC}"

    local retry=0
    DOMAIN=""
    while [ $retry -lt 5 ]; do
        DOMAIN=$(curl -s --max-time 10 https://api.mail.tm/domains \
            | jq -r '.["hydra:member"][0].domain // empty' 2>/dev/null)
        [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ] && break
        retry=$((retry + 1))
        echo -e "  ${YELLOW}Retry domain $retry/5...${NC}"
        sleep 2
    done

    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        echo -e "${RED}[✗] Không lấy được domain${NC}"
        return 1
    fi

    RAND=$(tr -dc a-z0-9 </dev/urandom | head -c 10)
    EMAIL="pf${RAND}@${DOMAIN}"
    MPASS="Xk${RAND}99"

    retry=0
    while [ $retry -lt 3 ]; do
        RESULT=$(curl -s --max-time 10 -X POST https://api.mail.tm/accounts \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null)

        CHECK=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
        [ -n "$CHECK" ] && [ "$CHECK" != "null" ] && break

        retry=$((retry + 1))
        RAND=$(tr -dc a-z0-9 </dev/urandom | head -c 10)
        EMAIL="pf${RAND}@${DOMAIN}"
        MPASS="Xk${RAND}99"
        sleep 2
    done

    if [ -z "$CHECK" ] || [ "$CHECK" = "null" ]; then
        echo -e "${RED}[✗] Tạo email thất bại${NC}"
        return 1
    fi

    echo -e "${GREEN}[✓] Email: $EMAIL${NC}"

    sleep 1
    retry=0
    MAIL_TOKEN=""
    while [ $retry -lt 3 ]; do
        MAIL_TOKEN=$(curl -s --max-time 10 -X POST https://api.mail.tm/token \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null \
            | jq -r '.token // empty' 2>/dev/null)

        if [ -n "$MAIL_TOKEN" ] && [ "$MAIL_TOKEN" != "null" ] && [ ${#MAIL_TOKEN} -gt 20 ]; then
            echo -e "${GREEN}[✓] Token OK${NC}"
            return 0
        fi

        retry=$((retry + 1))
        echo -e "  ${YELLOW}Retry token $retry/3...${NC}"
        sleep 2
    done

    echo -e "${RED}[✗] Lấy token thất bại${NC}"
    return 1
}

get_otp() {
    local TOKEN="$MAIL_TOKEN"

    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "${RED}[✗] Không có token${NC}" >&2
        echo "FAILED"
        return 1
    fi

    echo -e "${CYAN}[*] Chờ email OTP...${NC}" >&2

    local attempt=0
    local max=50

    while [ $attempt -lt $max ]; do
        attempt=$((attempt + 1))

        if [ $((attempt % 5)) -eq 0 ]; then
            echo -e "  ${CYAN}⏳ Đợi OTP ($attempt/$max)...${NC}" >&2
        fi

        local MSGS=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $TOKEN" \
            https://api.mail.tm/messages 2>/dev/null)

        [ -z "$MSGS" ] && sleep 3 && continue

        local TOTAL=$(echo "$MSGS" | jq -r '.["hydra:totalItems"] // 0' 2>/dev/null)
        [ "$TOTAL" = "0" ] || [ -z "$TOTAL" ] || [ "$TOTAL" = "null" ] && sleep 3 && continue

        echo -e "  ${GREEN}📨 Có $TOTAL email${NC}" >&2

        local MSG_ID=$(echo "$MSGS" | jq -r '
            .["hydra:member"]
            | sort_by(.createdAt)
            | reverse
            | .[0].id // empty
        ' 2>/dev/null)

        [ -z "$MSG_ID" ] || [ "$MSG_ID" = "null" ] && sleep 3 && continue

        local FULL=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $TOKEN" \
            "https://api.mail.tm/messages/$MSG_ID" 2>/dev/null)

        [ -z "$FULL" ] && sleep 3 && continue

        local F_SUBJECT=$(echo "$FULL" | jq -r '.subject // ""' 2>/dev/null)
        local F_TEXT=$(echo "$FULL" | jq -r '.text // ""' 2>/dev/null)
        local F_INTRO=$(echo "$FULL" | jq -r '.intro // ""' 2>/dev/null)
        local F_HTML=$(echo "$FULL" | jq -r '.html // ""' 2>/dev/null)

        local F_HTML_CLEAN=""
        if [ -n "$F_HTML" ] && [ "$F_HTML" != "null" ]; then
            F_HTML_CLEAN=$(echo "$F_HTML" | sed 's/<[^>]*>//g; s/&nbsp;/ /g; s/&#[0-9]*;//g')
        fi

        echo -e "  ${CYAN}Subject: $F_SUBJECT${NC}" >&2

        local ALL="$F_SUBJECT $F_INTRO $F_TEXT $F_HTML_CLEAN"

        local OTP=""
        OTP=$(echo "$ALL" | grep -oiE '(code|otp|verification|verify|is)[^0-9]{0,20}[0-9]{4,6}' \
            | grep -oE '[0-9]{4,6}' | head -1)

        if [ -z "$OTP" ]; then
            OTP=$(echo "$ALL" | grep -oE '\b[0-9]{6}\b' | head -1)
        fi

        if [ -z "$OTP" ]; then
            OTP=$(echo "$ALL" | grep -oE '\b[0-9]{4}\b' | head -1)
        fi

        OTP=$(echo "$OTP" | tr -d '\r\n\t ')

        if [[ "$OTP" =~ ^[0-9]{4,6}$ ]]; then
            echo -e "  ${GREEN}✅ OTP: $OTP${NC}" >&2
            echo "$OTP"
            return 0
        fi

        echo -e "  ${YELLOW}Có email nhưng chưa tìm được OTP${NC}" >&2
        echo -e "  ${YELLOW}Text: ${F_TEXT:0:150}${NC}" >&2

        sleep 3
    done

    echo -e "${RED}[✗] Timeout OTP${NC}" >&2
    echo "FAILED"
    return 1
}

run_one() {
    echo -e 
