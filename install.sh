#!/bin/bash

# ================== Variables ==================
CMD="${CMD:-}"
key="${key:-}"
INVITE="${INVITE:-abc123}"
PACKAGE="ai.pollo.ai"
PASS="111111"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ================== Decode CMD/Key ==================
echo -e "${CYAN}[*] Decoding variables...${NC}"

if [ -n "$CMD" ]; then
    CMD=$(echo "$CMD" | base64 --decode)
    echo -e "${GREEN}[OK] Decoded CMD${NC}"
else
    echo -e "${RED}[ERROR] CMD is empty!${NC}"
    exit 1
fi

if [ -n "$key" ]; then
    key=$(echo "$key" | base64 --decode)
    echo -e "${GREEN}[OK] Decoded key (${#key} chars)${NC}"
else
    echo -e "${RED}[ERROR] key is empty!${NC}"
    exit 1
fi

# ================== Parse SSH info ==================
if [ -n "$CMD" ]; then
    echo -e "${CYAN}[*] Parsing SSH config...${NC}"
    
    USER_HOST=$(echo "$CMD" | awk '{for(i=1;i<=NF;i++) if($i ~ /@/) print $i}')
    SSH_USER=$(echo "$USER_HOST" | cut -d@ -f1)
    SSH_HOST=$(echo "$USER_HOST" | cut -d@ -f2)
    SSH_PORT=$(echo "$CMD" | awk '{for(i=1;i<=NF;i++) if($i=="-p") print $(i+1)}')
    
    L_PARAM=$(echo "$CMD" | awk '{for(i=1;i<=NF;i++) if($i=="-L") print $(i+1)}')
    LOCAL_PORT=$(echo "$L_PARAM" | cut -d: -f1)
    REMOTE_ADB=$(echo "$L_PARAM" | cut -d: -f2-)
    
    SERIAL="localhost:${LOCAL_PORT}"
    
    # Set ADB port động
    ADB_PORT=$((LOCAL_PORT + 10000))
    export ADB_SERVER_PORT=$ADB_PORT
    export ADB_VENDOR_KEYS=~/.android
    
    if [ -z "$SSH_USER" ] || [ -z "$SSH_HOST" ] || [ -z "$SSH_PORT" ] || [ -z "$LOCAL_PORT" ]; then
        echo -e "${RED}[ERROR] Parse failed!${NC}"
        echo "USER_HOST: $USER_HOST"
        echo "L_PARAM: $L_PARAM"
        exit 1
    fi
    
    echo -e "${GREEN}[OK] Configuration:${NC}"
    echo -e "  ${CYAN}SSH:${NC} ${SSH_USER}@${SSH_HOST}:${SSH_PORT}"
    echo -e "  ${CYAN}Tunnel:${NC} localhost:${LOCAL_PORT} → ${REMOTE_ADB}"
    echo -e "  ${CYAN}ADB Server:${NC} 127.0.0.1:${ADB_PORT}"
    echo -e "  ${CYAN}ADB Device:${NC} ${SERIAL}"
fi

# ================== Dependencies ==================
install_deps() {
    echo -e "${CYAN}[*] Installing dependencies...${NC}"
    local NEED=""
    command -v ssh >/dev/null 2>&1 || NEED="$NEED openssh-client"
    command -v sshpass >/dev/null 2>&1 || NEED="$NEED sshpass"
    command -v adb >/dev/null 2>&1 || NEED="$NEED adb"
    command -v jq >/dev/null 2>&1 || NEED="$NEED jq"
    command -v curl >/dev/null 2>&1 || NEED="$NEED curl"
    
    if [ -n "$NEED" ]; then
        echo -e "${YELLOW}[!] Installing:$NEED${NC}"
        sudo apt-get update -y >/dev/null 2>&1
        sudo apt-get install -y $NEED >/dev/null 2>&1
    fi
    
    echo -e "${GREEN}[OK] Dependencies ready${NC}"
}

# ================== SSH Tunnel ==================
kill_tunnel() {
    echo -e "${CYAN}[*] Cleaning old connections...${NC}"
    pkill -f "ssh.*${SSH_HOST}.*${SSH_PORT}" 2>/dev/null
    killall adb 2>/dev/null
    sleep 1
}

start_tunnel() {
    echo -e "${CYAN}[*] Starting SSH tunnel...${NC}"
    
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    ssh-keyscan -p $SSH_PORT $SSH_HOST >> ~/.ssh/known_hosts 2>&1
    
    echo -e "${CYAN}[*] Connecting to ${SSH_USER}@${SSH_HOST}:${SSH_PORT}...${NC}"
    
    SSH_OUTPUT=$(sshpass -p "$key" ssh \
        -v \
        -oHostKeyAlgorithms=+ssh-rsa \
        -oStrictHostKeyChecking=no \
        -oConnectTimeout=15 \
        -oServerAliveInterval=30 \
        -oServerAliveCountMax=3 \
        -L ${LOCAL_PORT}:${REMOTE_ADB} \
        -Nf \
        ${SSH_USER}@${SSH_HOST} \
        -p ${SSH_PORT} 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK] SSH tunnel established${NC}"
        sleep 2
        return 0
    else
        echo -e "${RED}[FAIL] SSH tunnel${NC}"
        echo "$SSH_OUTPUT" | grep -i "debug1\|denied\|error\|refused" | tail -10
        return 1
    fi
}

check_tunnel() {
    pgrep -f "ssh.*${SSH_HOST}.*${SSH_PORT}" >/dev/null 2>&1
}

ensure_tunnel() {
    if ! check_tunnel; then
        echo -e "${YELLOW}[!] Tunnel lost, reconnecting...${NC}"
        kill_tunnel
        start_tunnel || return 1
        connect_adb || return 1
    fi
}

# ================== ADB ==================
connect_adb() {
    echo -e "${CYAN}[*] Setting up ADB (port ${ADB_SERVER_PORT})...${NC}"
    
    killall adb 2>/dev/null
    sleep 1
    
    rm -rf ~/.android/adbkey* 2>/dev/null
    
    adb kill-server 2>/dev/null
    sleep 1
    
    adb start-server
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FAIL] ADB server start${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[OK] ADB server started on port ${ADB_SERVER_PORT}${NC}"
    sleep 3
    
    local retry=0
    while [ $retry -lt 5 ]; do
        retry=$((retry+1))
        echo -e "${CYAN}[*] Connecting to ${SERIAL} (${retry}/5)${NC}"
        
        adb connect $SERIAL 2>&1
        sleep 2
        
        if adb -s $SERIAL shell echo OK >/dev/null 2>&1; then
            MODEL=$(adb -s $SERIAL shell getprop ro.product.model 2>/dev/null | tr -d '\r\n')
            echo -e "${GREEN}[OK] Connected: ${SERIAL} (${MODEL})${NC}"
            return 0
        fi
        
        sleep 2
    done
    
    echo -e "${RED}[FAIL] ADB connection timeout${NC}"
    echo -e "${YELLOW}[DEBUG] ADB devices:${NC}"
    adb devices -l
    
    echo -e "${YELLOW}[DEBUG] Ports:${NC}"
    netstat -tuln | grep -E "${LOCAL_PORT}|${ADB_SERVER_PORT}"
    
    return 1
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
    echo -e "  ${CYAN}[F+T] $4 ($1,$2) = '$3'${NC}"
    adb -s $SERIAL shell input tap "$1" "$2"
    sleep 0.3
    adb -s $SERIAL shell input text "$3"
    sleep 0.1
    hide_kb
    sleep 0.3
}

# ================== APK Install ==================
install_apk() {
    echo -e "${CYAN}[*] Checking APK...${NC}"
    
    if adb -s "$SERIAL" shell pm list packages 2>/dev/null | grep -q "$PACKAGE"; then
        echo -e "${GREEN}[OK] APK already installed${NC}"
        return 0
    fi

    TMP_APK="/tmp/Pollo.ai_Android.apk"
    
    if [ ! -f "$TMP_APK" ]; then
        echo -e "${CYAN}[*] Downloading APK...${NC}"
        curl -L -o "$TMP_APK" "https://videocdn.pollo.ai/app/android/Pollo.ai_Android.apk"
        if [ $? -ne 0 ] || [ ! -f "$TMP_APK" ]; then
            echo -e "${RED}[FAIL] Download APK${NC}"
            return 1
        fi
    fi

    echo -e "${CYAN}[*] Installing APK...${NC}"
    adb -s "$SERIAL" install -r "$TMP_APK"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK] APK installed${NC}"
        return 0
    else
        echo -e "${RED}[FAIL] APK install${NC}"
        return 1
    fi
}

# ================== Mail/OTP ==================
create_mail() {
    echo -e "${CYAN}[*] Creating email...${NC}"
    local retry=0
    DOMAIN=""
    
    while [ $retry -lt 5 ]; do
        DOMAIN=$(curl -s --max-time 10 https://api.mail.tm/domains | jq -r '.["hydra:member"][0].domain // empty' 2>/dev/null)
        [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ] && break
        retry=$((retry+1))
        sleep 2
    done
    
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        echo -e "${RED}[FAIL] No domain${NC}"
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
        
        if [ -n "$CHECK" ] && [ "$CHECK" != "null" ]; then
            break
        fi
        
        retry=$((retry+1))
        RAND=$(tr -dc a-z0-9 </dev/urandom | head -c 10)
        EMAIL="pf${RAND}@${DOMAIN}"
        MPASS="Xk${RAND}99"
        sleep 2
    done
    
    if [ -z "$CHECK" ] || [ "$CHECK" = "null" ]; then
        echo -e "${RED}[FAIL] Create email${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[OK] Email: $EMAIL${NC}"
    sleep 1

    retry=0
    MAIL_TOKEN=""
    while [ $retry -lt 3 ]; do
        MAIL_TOKEN=$(curl -s --max-time 10 -X POST https://api.mail.tm/token \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null \
            | jq -r '.token // empty' 2>/dev/null)
        
        if [ -n "$MAIL_TOKEN" ] && [ "$MAIL_TOKEN" != "null" ] && [ ${#MAIL_TOKEN} -gt 20 ]; then
            echo -e "${GREEN}[OK] Token received${NC}"
            return 0
        fi
        
        retry=$((retry+1))
        sleep 2
    done
    
    echo -e "${RED}[FAIL] Token${NC}"
    return 1
}

get_otp() {
    if [ -z "$MAIL_TOKEN" ] || [ "$MAIL_TOKEN" = "null" ]; then
        echo "FAILED"
        return 1
    fi
    
    echo -e "${CYAN}[*] Waiting for OTP...${NC}" >&2

    local attempt=0
    while [ $attempt -lt 50 ]; do
        attempt=$((attempt+1))
        
        if [ $((attempt%5)) -eq 0 ]; then
            echo -e "  ${CYAN}⏳ Attempt $attempt/50...${NC}" >&2
        fi

        MSGS=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $MAIL_TOKEN" \
            https://api.mail.tm/messages 2>/dev/null)
        
        if [ -z "$MSGS" ]; then
            sleep 3
            continue
        fi

        TOTAL=$(echo "$MSGS" | jq -r '.["hydra:totalItems"] // 0' 2>/dev/null)
        
        if [ "$TOTAL" = "0" ] || [ -z "$TOTAL" ] || [ "$TOTAL" = "null" ]; then
            sleep 3
            continue
        fi

        MSG_ID=$(echo "$MSGS" | jq -r '.["hydra:member"] | sort_by(.createdAt) | reverse | .[0].id // empty' 2>/dev/null)
        
        if [ -z "$MSG_ID" ] || [ "$MSG_ID" = "null" ]; then
            sleep 3
            continue
        fi

        FULL=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $MAIL_TOKEN" \
            "https://api.mail.tm/messages/$MSG_ID" 2>/dev/null)
        
        if [ -z "$FULL" ]; then
            sleep 3
            continue
        fi

        F_TXT=$(echo "$FULL" | jq -r '.text // ""' 2>/dev/null)
        OTP=$(echo "$F_TXT" | grep -oE '\b[0-9]{4,6}\b' | head -1 | tr -d '\r\n\t ')

        if [[ "$OTP" =~ ^[0-9]{4,6}$ ]]; then
            echo -e "  ${GREEN}✅ OTP: $OTP${NC}" >&2
            echo "$OTP"
            return 0
        fi
        
        sleep 3
    done

    echo -e "${RED}[FAIL] OTP timeout${NC}" >&2
    echo "FAILED"
    return 1
}

# ================== run_one ==================
run_one() {
    ensure_tunnel || return 1

    echo -e "${CYAN}[*] Clearing app data...${NC}"
    adb -s $SERIAL shell pm clear $PACKAGE >/dev/null 2>&1
    sleep 2

    echo -e "${CYAN}[*] Launching app...${NC}"
    adb -s $SERIAL shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 12

    create_mail || return 1
    
    echo -e "${CYAN}[*] Filling email...${NC}"
    focus_and_type 258 556 "$EMAIL" "email"
    sleep 1
    
    echo -e "${CYAN}[*] Requesting OTP...${NC}"
    tap 350 670 "GetOTP"
    sleep 8

    OTP=$(get_otp)
    OTP=$(echo "$OTP" | tr -d '\r\n\t ')
    
    if [[ ! "$OTP" =~ ^[0-9]{4,6}$ ]]; then
        echo -e "${RED}[FAIL] Invalid OTP: [$OTP]${NC}"
        return 1
    fi

    echo -e "${CYAN}[*] Entering OTP...${NC}"
    tap 258 556 "OTP field"
    sleep 0.5
    
    for (( i=0; i<${#OTP}; i++ )); do
        adb -s $SERIAL shell input text "${OTP:$i:1}"
        sleep 0.15
    done
    sleep 1
    
    tap 340 650 "submit"
    sleep 5

    echo -e "${CYAN}[*] Creating account...${NC}"
    focus_and_type 210 580 "Minh" "first"
    focus_and_type 505 567 "Nguyen" "last"
    focus_and_type 154 711 "$PASS" "pass"
    sleep 2
    
    tap 324 843 "CREATE"
    sleep 5

    echo -e "${CYAN}[*] Redeeming invite code...${NC}"
    focus_and_type 173 973 "$INVITE" "invite"
    adb -s $SERIAL shell input keyevent 66
    sleep 1
    
    tap 548 686 "REDEEM"
    sleep 3

    echo "$(date '+%Y-%m-%d %H:%M:%S') | $EMAIL | $INVITE" >> ~/success.txt
    echo -e "${GREEN}[✓] Account created successfully${NC}"
    return 0
}

# ================== Main ==================
clear
echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       POLLO FARM v3.3 (Dynamic Config)       ║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║ SSH:    ${SSH_USER}@${SSH_HOST}:${SSH_PORT}${NC}"
echo -e "${GREEN}║ Tunnel: localhost:${LOCAL_PORT} → ${REMOTE_ADB}${NC}"
echo -e "${GREEN}║ ADB:    ${SERIAL} (port ${ADB_SERVER_PORT})${NC}"
echo -e "${GREEN}║ Invite: ${INVITE}${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"

install_deps
kill_tunnel
start_tunnel || exit 1
connect_adb || exit 1
install_apk || exit 1

echo -e "\n${GREEN}[🚀] Starting farm loop...${NC}\n"
COUNT=1
OK=0
FAIL=0

while true; do
    echo -e "\n${CYAN}━━━━━━━━━━━━━ RUN #${COUNT} ━━━━━━━━━━━━━${NC}\n"
    
    if run_one; then
        OK=$((OK+1))
        COUNT=$((COUNT+1))
        echo -e "\n${GREEN}✅ SUCCESS | Total: OK=${OK} FAIL=${FAIL}${NC}\n"
    else
        FAIL=$((FAIL+1))
        echo -e "\n${RED}❌ FAILED | Total: OK=${OK} FAIL=${FAIL}${NC}"
        echo -e "${YELLOW}⏳ Waiting 15 seconds before retry...${NC}\n"
        sleep 15
    fi
    
    sleep 5
done
