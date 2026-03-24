cat > ~/af.sh << 'BASH_SCRIPT'
#!/bin/bash

PACKAGE="ai.pollo.ai"
PASS="YourPassword123"
INVITE="bnqOrS"

SSH_USER="10.12.11.115_1774374783100"
SSH_HOST="98.98.37.2"
SSH_PORT="1824"
REMOTE_ADB="adb-proxy:63494"
SSH_PASS="54XaO77/Txe7ecBkeGLn4EzJiyXE5s5fPgyKZDo1Q0VSwYfpU3kRptSUUTXc2JwZ8Cm39I6obpjcx68+QK5vmw=="

LOCAL_PORT=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE=""
MULTI_FILE=""

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
        -h|--help)
            echo "Usage:"
            echo "  $0 --ssh-host HOST --ssh-port PORT --ssh-user USER --ssh-pass PASS --remote-adb ADB"
            echo "  $0 -f config.txt"
            echo "  $0 -m devices.csv"
            exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

find_free_port() {
    local START=${1:-9999}
    local END=${2:-10050}
    for port in $(seq $START $END); do
        if ! ss -tlnp 2>/dev/null | grep -q ":${port} " && \
           ! netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            echo "$port"
            return 0
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
            SSH_USER)   SSH_USER="$value" ;;
            SSH_HOST)   SSH_HOST="$value" ;;
            SSH_PORT)   SSH_PORT="$value" ;;
            SSH_PASS)   SSH_PASS="$value" ;;
            REMOTE_ADB) REMOTE_ADB="$value" ;;
            LOCAL_PORT) LOCAL_PORT="$value" ;;
            INVITE)     INVITE="$value" ;;
            PASS)       PASS="$value" ;;
        esac
    done < "$file"
    echo -e "${GREEN}[OK] Loaded${NC}"
}

[ -n "$CONFIG_FILE" ] && load_config "$CONFIG_FILE"

install_deps() {
    echo -e "${CYAN}[*] Check deps...${NC}"
    local NEED=""
    command -v ssh     >/dev/null 2>&1 || NEED="$NEED openssh-client"
    command -v sshpass >/dev/null 2>&1 || NEED="$NEED sshpass"
    command -v adb     >/dev/null 2>&1 || NEED="$NEED adb"
    command -v jq      >/dev/null 2>&1 || NEED="$NEED jq"
    command -v curl    >/dev/null 2>&1 || NEED="$NEED curl"
    if [ -n "$NEED" ]; then
        sudo apt-get update -y >/dev/null 2>&1
        sudo apt-get install -y $NEED >/dev/null 2>&1
    fi
    echo -e "${GREEN}[OK] Deps${NC}"
}

kill_tunnel() {
    pkill -f "ssh.*-L ${LOCAL_PORT}:" 2>/dev/null
    sleep 1
}

start_tunnel() {
    echo -e "${CYAN}[*] SSH ${SSH_HOST}:${SSH_PORT} → :${LOCAL_PORT}${NC}"
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
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
        echo -e "${GREEN}[OK] Tunnel :${LOCAL_PORT}${NC}"
        sleep 2; return 0
    else
        echo -e "${RED}[FAIL] Tunnel${NC}"
        return 1
    fi
}

check_tunnel() { pgrep -f "ssh.*-L ${LOCAL_PORT}:" >/dev/null 2>&1; }

ensure_tunnel() {
    if ! check_tunnel; then
        echo -e "${YELLOW}[!] Tunnel lost${NC}"
        kill_tunnel; start_tunnel || return 1; connect_adb || return 1
    fi
}

connect_adb() {
    echo -e "${CYAN}[*] ADB → ${SERIAL}${NC}"
    adb disconnect $SERIAL 2>/dev/null; sleep 1
    adb connect $SERIAL 2>/dev/null; sleep 2
    if adb -s $SERIAL shell echo OK >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] ADB: $SERIAL${NC}"; return 0
    else
        echo -e "${RED}[FAIL] ADB${NC}"; return 1
    fi
}

hide_kb() { adb -s $SERIAL shell input keyevent 4 >/dev/null 2>&1; sleep 0.1; }
tap() { echo -e "  ${CYAN}[TAP] $3 ($1,$2)${NC}"; adb -s $SERIAL shell input tap "$1" "$2"; sleep 0.2; }
focus_and_type() { echo -e "  ${CYAN}[F+T] $4 ($1,$2)${NC}"; adb -s $SERIAL shell input tap "$1" "$2"; sleep 0.3; adb -s $SERIAL shell input text "$3"; sleep 0.1; hide_kb; sleep 0.3; }

create_mail() {
    echo -e "${CYAN}[*] Creating email...${NC}"
    local retry=0 DOMAIN=""
    while [ $retry -lt 5 ]; do
        DOMAIN=$(curl -s --max-time 10 https://api.mail.tm/domains \
            | jq -r '.["hydra:member"][0].domain // empty' 2>/dev/null)
        [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ] && break
        retry=$((retry+1)); sleep 2
    done
    [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ] && return 1

    RAND=$(tr -dc a-z0-9 </dev/urandom | head -c 10)
    EMAIL="pf${RAND}@${DOMAIN}"; MPASS="Xk${RAND}99"

    retry=0
    while [ $retry -lt 3 ]; do
        RESULT=$(curl -s --max-time 10 -X POST https://api.mail.tm/accounts \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}")
        CHECK=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
        [ -n "$CHECK" ] && [ "$CHECK" != "null" ] && break
        retry=$((retry+1))
        RAND=$(tr -dc a-z0-9 </dev/urandom | head -c 10)
        EMAIL="pf${RAND}@${DOMAIN}"; MPASS="Xk${RAND}99"; sleep 2
    done
    [ -z "$CHECK" ] || [ "$CHECK" = "null" ] && return 1

    echo -e "${GREEN}[OK] $EMAIL${NC}"
    retry=0; MAIL_TOKEN=""
    while [ $retry -lt 3 ]; do
        MAIL_TOKEN=$(curl -s --max-time 10 -X POST https://api.mail.tm/token \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" \
            | jq -r '.token // empty' 2>/dev/null)
        [ -n "$MAIL_TOKEN" ] && [ "$MAIL_TOKEN" != "null" ] && [ ${#MAIL_TOKEN} -gt 20 ] && return 0
        retry=$((retry+1)); sleep 2
    done
    return 1
}

get_otp() {
    local TOKEN="$MAIL_TOKEN"
    [ -z "$TOKEN" ] && echo "FAILED" && return 1
    echo -e "${CYAN}[*] Waiting OTP...${NC}" >&2
    local attempt=0
    while [ $attempt -lt 50 ]; do
        attempt=$((attempt+1))
        [ $((attempt%5)) -eq 0 ] && echo -e "  ${CYAN}⏳ ($attempt/50)${NC}" >&2
        local MSGS=$(curl -s --max-time 10 -H "Authorization: Bearer $TOKEN" https://api.mail.tm/messages 2>/dev/null)
        [ -z "$MSGS" ] && sleep 3 && continue
        local TOTAL=$(echo "$MSGS" | jq -r '.["hydra:totalItems"] // 0' 2>/dev/null)
        [ "$TOTAL" = "0" ] || [ -z "$TOTAL" ] && sleep 3 && continue
        local MSG_ID=$(echo "$MSGS" | jq -r '.["hydra:member"] | sort_by(.createdAt) | reverse | .[0].id // empty' 2>/dev/null)
        [ -z "$MSG_ID" ] && sleep 3 && continue
        local FULL=$(curl -s --max-time 10 -H "Authorization: Bearer $TOKEN" "https://api.mail.tm/messages/$MSG_ID" 2>/dev/null)
        local ALL="$(echo "$FULL" | jq -r '"\(.subject // "") \(.intro // "") \(.text // "")"' 2>/dev/null)"
        local OTP=$(echo "$ALL" | grep -oE '[0-9]{4,6}' | head -1 | tr -d '\r\n\t ')
        if [[ "$OTP" =~ ^[0-9]{4,6}$ ]]; then
            echo -e "  ${GREEN}✅ OTP: $OTP${NC}" >&2
            echo "$OTP"; return 0
        fi
        sleep 3
    done
    echo "FAILED"; return 1
}

run_one() {
    echo -e "\n${YELLOW}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}  #$1 │ ${SSH_HOST}:${SSH_PORT} → :${LOCAL_PORT}${NC}"
    echo -e "${YELLOW}══════════════════════════════════════${NC}"

    ensure_tunnel || return 1

    adb -s $SERIAL shell pm clear $PACKAGE >/dev/null 2>&1; sleep 2
    adb -s $SERIAL shell input keyevent 26 >/dev/null 2>&1; sleep 0.5
    adb -s $SERIAL shell input keyevent 82 >/dev/null 2>&1; sleep 1
    adb -s $SERIAL shell am start -n ai.pollo.ai/.MainActivity 2>&1 | head -5; sleep 12

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
    [[ ! "$OTP" =~ ^[0-9]{4,6}$ ]] && return 1

    tap 258 556 "OTP field"; sleep 0.5
    for (( i=0; i<${#OTP}; i++ )); do
        adb -s $SERIAL shell input text "${OTP:$i:1}"; sleep 0.15
    done; sleep 1
    tap 340 650 "submit"; sleep 5

    focus_and_type 210 580 "Minh" "first"; sleep 1
    focus_and_type 505 567 "Nguyen" "last"; sleep 1
    focus_and_type 154 711 "$PASS" "pass"; sleep 2
    tap 324 843 "CREATE"; sleep 5

    tap 352 457 "email"; sleep 2
    focus_and_type 209 677 "$PASS" "pass"; sleep 1
    tap 361 783 "submit"; sleep 4

    tap 444 85 "skip1"; sleep 2
    tap 580 1018 "skip2"; sleep 2
    adb -s $SERIAL shell input swipe 500 1000 500 200 1000; sleep 2
    focus_and_type 173 973 "$INVITE" "invite"; sleep 1
    adb -s $SERIAL shell input keyevent 66; sleep 1
    tap 548 686 "REDEEM"; sleep 3

    echo -e "${GREEN}✅ #$1 | $EMAIL | ${SSH_HOST}:${SSH_PORT}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | #$1 | $EMAIL | ${SSH_HOST}:${SSH_PORT}" >> ~/log.txt
    return 0
}

run_multi() {
    local CSV_FILE="$1"
    [ ! -f "$CSV_FILE" ] && echo -e "${RED}[FAIL] $CSV_FILE${NC}" && exit 1

    declare -a HOSTS PORTS USERS PASSES ADBS
    local idx=0
    while IFS='|' read -r h p u pw adb_r; do
        [[ "$h" =~ ^#.*$ ]] && continue
        [ -z "$h" ] && continue
        HOSTS[$idx]="$h"; PORTS[$idx]="$p"; USERS[$idx]="$u"
        PASSES[$idx]="$pw"; ADBS[$idx]="$adb_r"
        idx=$((idx+1))
    done < "$CSV_FILE"

    local TOTAL_SSH=$idx
    echo -e "${GREEN}[OK] $TOTAL_SSH devices${NC}"
    for (( i=0; i<TOTAL_SSH; i++ )); do
        echo -e "  ${CYAN}[$((i+1))] ${HOSTS[$i]}:${PORTS[$i]}${NC}"
    done

    local COUNT=1 OK=0 FL=0 SSH_IDX=0
    while true; do
        SSH_HOST="${HOSTS[$SSH_IDX]}"; SSH_PORT="${PORTS[$SSH_IDX]}"
        SSH_USER="${USERS[$SSH_IDX]}"; SSH_PASS="${PASSES[$SSH_IDX]}"
        REMOTE_ADB="${ADBS[$SSH_IDX]}"
        kill_tunnel 2>/dev/null
        LOCAL_PORT=$(find_free_port $((9999 + SSH_IDX)) $((9999 + SSH_IDX + 50)))
        SERIAL="127.0.0.1:${LOCAL_PORT}"

        if start_tunnel && connect_adb; then
            run_one $COUNT && OK=$((OK+1)) || FL=$((FL+1))
            COUNT=$((COUNT+1))
        else
            FL=$((FL+1))
        fi
        kill_tunnel
        echo -e "${GREEN}📊 OK:$OK FAIL:$FL${NC}"
        SSH_IDX=$(( (SSH_IDX + 1) % TOTAL_SSH ))
        sleep 5
    done
}

# ═══ MAIN ═══
clear
install_deps
curl -s --max-time 10 https://api.mail.tm/domains >/dev/null 2>&1 || { echo -e "${RED}[FAIL] mail.tm${NC}"; exit 1; }
echo -e "${GREEN}[OK] mail.tm${NC}"

if [ -n "$MULTI_FILE" ]; then
    run_multi "$MULTI_FILE"
    exit 0
fi

set_port
echo -e "${GREEN}╔════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🐔 AF v4.1                    ║${NC}"
echo -e "${GREEN}║  ${SSH_HOST}:${SSH_PORT} → :${LOCAL_PORT}${NC}"
echo -e "${GREEN}╚════════════════════════════════╝${NC}"

kill_tunnel
start_tunnel || exit 1
connect_adb || exit 1

COUNT=1 OK=0 FL=0
while true; do
    run_one $COUNT && { OK=$((OK+1)); COUNT=$((COUNT+1)); } || { FL=$((FL+1)); sleep 15; }
    echo -e "${GREEN}📊 OK:$OK FAIL:$FL${NC}"
    sleep 5
done
BASH_SCRIPT
chmod +x ~/af.sh
bash ~/af.sh
