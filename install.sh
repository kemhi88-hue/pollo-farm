cat > ~/pollo_farm.sh << 'EOFMAIN'
#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════
# POLLO FARM - AUTO SSH + FIX OTP
# ═══════════════════════════════════════

PACKAGE="ai.pollo.ai"
PASS="YourPassword123"
INVITE="L54v43"
SERIAL="localhost:9163"

# ═══ SSH CONFIG ═══
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

# ═══════════════════════════════════════
# CÀI DEPENDENCIES
# ═══════════════════════════════════════

install_deps() {
    echo -e "${CYAN}[*] Kiểm tra dependencies...${NC}"
    local NEED=""
    command -v ssh      >/dev/null 2>&1 || NEED="$NEED openssh"
    command -v sshpass  >/dev/null 2>&1 || NEED="$NEED sshpass"
    command -v adb      >/dev/null 2>&1 || NEED="$NEED android-tools"
    command -v jq       >/dev/null 2>&1 || NEED="$NEED jq"
    command -v curl     >/dev/null 2>&1 || NEED="$NEED curl"

    if [ -n "$NEED" ]; then
        echo -e "${YELLOW}[!] Cài:$NEED${NC}"
        pkg update -y >/dev/null 2>&1
        pkg install -y $NEED >/dev/null 2>&1
    fi
    echo -e "${GREEN}[✓] Dependencies OK${NC}"
}

# ═══════════════════════════════════════
# SSH TUNNEL
# ═══════════════════════════════════════

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

# ═══════════════════════════════════════
# ADB
# ═══════════════════════════════════════

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

# ═══════════════════════════════════════
# TẠO EMAIL
# ═══════════════════════════════════════

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

    # ═══ LẤY TOKEN NGAY ═══
    sleep 1
    retry=0
    MAIL_TOKEN=""
    while [ $retry -lt 3 ]; do
        MAIL_TOKEN=$(curl -s --max-time 10 -X POST https://api.mail.tm/token \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null \
            | jq -r '.token // empty' 2>/dev/null)

        if [ -n "$MAIL_TOKEN" ] && [ "$MAIL_TOKEN" != "null" ] && [ ${#MAIL_TOKEN} -gt 20 ]; then
            echo -e "${GREEN}[✓] Token OK (${#MAIL_TOKEN} chars)${NC}"
            return 0
        fi

        retry=$((retry + 1))
        echo -e "  ${YELLOW}Retry token $retry/3...${NC}"
        sleep 2
    done

    echo -e "${RED}[✗] Lấy token thất bại${NC}"
    return 1
}

# ═══════════════════════════════════════
# LẤY OTP (FIX HOÀN TOÀN)
# ═══════════════════════════════════════
# stdout = CHỈ OTP
# stderr = tất cả log
# ═══════════════════════════════════════

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

        # Log mỗi 5 lần
        if [ $((attempt % 5)) -eq 0 ]; then
            echo -e "  ${CYAN}⏳ Đợi OTP ($attempt/$max)...${NC}" >&2
        fi

        # Lấy messages
        local MSGS=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $TOKEN" \
            https://api.mail.tm/messages 2>/dev/null)

        [ -z "$MSGS" ] && sleep 3 && continue

        # Đếm
        local TOTAL=$(echo "$MSGS" | jq -r '.["hydra:totalItems"] // 0' 2>/dev/null)
        [ "$TOTAL" = "0" ] || [ -z "$TOTAL" ] || [ "$TOTAL" = "null" ] && sleep 3 && continue

        echo -e "  ${GREEN}📨 Có $TOTAL email${NC}" >&2

        # Lấy message ID mới nhất
        local MSG_ID=$(echo "$MSGS" | jq -r '
            .["hydra:member"]
            | sort_by(.createdAt)
            | reverse
            | .[0].id // empty
        ' 2>/dev/null)

        [ -z "$MSG_ID" ] || [ "$MSG_ID" = "null" ] && sleep 3 && continue

        echo -e "  ${CYAN}MSG ID: $MSG_ID${NC}" >&2

        # Đọc nội dung
        local FULL=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $TOKEN" \
            "https://api.mail.tm/messages/$MSG_ID" 2>/dev/null)

        [ -z "$FULL" ] && sleep 3 && continue

        # Trích xuất mọi trường
        local F_SUBJECT=$(echo "$FULL" | jq -r '.subject // ""' 2>/dev/null)
        local F_TEXT=$(echo "$FULL" | jq -r '.text // ""' 2>/dev/null)
        local F_INTRO=$(echo "$FULL" | jq -r '.intro // ""' 2>/dev/null)
        local F_HTML=$(echo "$FULL" | jq -r '.html // ""' 2>/dev/null)

        # Strip HTML tags
        local F_HTML_CLEAN=""
        if [ -n "$F_HTML" ] && [ "$F_HTML" != "null" ]; then
            F_HTML_CLEAN=$(echo "$F_HTML" | sed 's/<[^>]*>//g; s/&nbsp;/ /g; s/&#[0-9]*;//g')
        fi

        echo -e "  ${CYAN}Subject: $F_SUBJECT${NC}" >&2

        # Gộp tất cả
        local ALL="$F_SUBJECT $F_INTRO $F_TEXT $F_HTML_CLEAN"

        # ═══ TÌM OTP ═══

        # Cách 1: Tìm gần keyword
        local OTP=""
        OTP=$(echo "$ALL" | grep -oiE '(code|otp|verification|verify|mã|is)[^0-9]{0,20}[0-9]{4,6}' \
            | grep -oE '[0-9]{4,6}' | head -1)

        # Cách 2: Số 6 chữ số đứng riêng
        if [ -z "$OTP" ]; then
            OTP=$(echo "$ALL" | grep -oE '\b[0-9]{6}\b' | head -1)
        fi

        # Cách 3: Số 4 chữ số
        if [ -z "$OTP" ]; then
            OTP=$(echo "$ALL" | grep -oE '\b[0-9]{4}\b' | head -1)
        fi

        # Trim
        OTP=$(echo "$OTP" | tr -d '\r\n\t ')

        # Validate
        if [[ "$OTP" =~ ^[0-9]{4,6}$ ]]; then
            echo -e "  ${GREEN}✅ OTP: $OTP${NC}" >&2
            echo "$OTP"  # ← CHỈ DÒNG NÀY RA STDOUT
            return 0
        fi

        # Debug nếu có email nhưng không tìm được
        echo -e "  ${YELLOW}Có email nhưng chưa tìm được OTP${NC}" >&2
        echo -e "  ${YELLOW}Text: ${F_TEXT:0:150}${NC}" >&2

        sleep 3
    done

    echo -e "${RED}[✗] Timeout OTP${NC}" >&2
    echo "FAILED"
    return 1
}

# ═══════════════════════════════════════
# CHẠY 1 LƯỢT
# ═══════════════════════════════════════

run_one() {
    echo -e "\n${YELLOW}════════════════════════════════${NC}"
    echo -e "${YELLOW}  RUN #$1${NC}"
    echo -e "${YELLOW}════════════════════════════════${NC}"

    # Kiểm tra tunnel
    ensure_tunnel || return 1

    echo -e "${CYAN}[1] Clear${NC}"
    adb -s $SERIAL shell pm clear $PACKAGE >/dev/null 2>&1
    sleep 2

    echo -e "${CYAN}[2] Open${NC}"
    adb -s $SERIAL shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 12

    echo -e "${CYAN}[3] Navigate${NC}"
    tap 110 457 "menu";      sleep 3
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

    echo -e "${CYAN}[*] Chờ 8s cho server gửi OTP...${NC}"
    sleep 8

    echo -e "${CYAN}[5] OTP${NC}"
    OTP=$(get_otp)
    OTP=$(echo "$OTP" | tr -d '\r\n\t ')

    echo -e "${CYAN}[*] OTP nhận được: [$OTP]${NC}"

    if [[ ! "$OTP" =~ ^[0-9]{4,6}$ ]]; then
        echo -e "${RED}[✗] OTP không hợp lệ: [$OTP]${NC}"
        return 1
    fi

    echo -e "${GREEN}[✓] OTP: $OTP${NC}"

    # Nhập OTP từng số
    tap 258 556 "OTP field"; sleep 0.5
    for (( i=0; i<${#OTP}; i++ )); do
        adb -s $SERIAL shell input text "${OTP:$i:1}"
        sleep 0.15
    done
    sleep 1
    tap 340 650 "submit"; sleep 5

    echo -e "${CYAN}[6] Info${NC}"
    focus_and_type 210 580 "Minh" "name"
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

    echo -e "${CYAN}[8] Next${NC}"
    tap 444 85 "qua"; sleep 2
    tap 580 1018 "qua"; sleep 2

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

    echo -e "${GREEN}╔════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ SUCCESS #$1                 ║${NC}"
    echo -e "${GREEN}║  $EMAIL${NC}"
    echo -e "${GREEN}╚════════════════════════════════╝${NC}"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | #$1 | $EMAIL | $PASS" >> ~/success.txt
    return 0
}

# ═══════════════════════════════════════
# MAIN
# ═══════════════════════════════════════

clear

echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                    ║${NC}"
echo -e "${GREEN}║   🐔 POLLO FARM v3.0 🐔           ║${NC}"
echo -e "${GREEN}║   AUTO SSH + FIX OTP               ║${NC}"
echo -e "${GREEN}║                                    ║${NC}"
echo -e "${GREEN}║   SSH : ${SSH_HOST}:${SSH_PORT}     ║${NC}"
echo -e "${GREEN}║   ADB : ${SERIAL}          ║${NC}"
echo -e "${GREEN}║                                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo ""

# 1. Dependencies
install_deps

# 2. Test mail.tm
echo -e "${CYAN}[*] Test mail.tm...${NC}"
if ! curl -s --max-time 10 https://api.mail.tm/domains >/dev/null 2>&1; then
    echo -e "${RED}[✗] Không kết nối được mail.tm${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] mail.tm OK${NC}"

# 3. Kill cũ
kill_tunnel

# 4. SSH tunnel
start_tunnel || exit 1

# 5. ADB
connect_adb || exit 1

# 6. Farm loop
echo ""
echo -e "${GREEN}[🚀] Bắt đầu farm...${NC}"
echo ""

COUNT=1
OK=0
FAIL=0

while true; do
    if run_one $COUNT; then
        OK=$((OK + 1))
        COUNT=$((COUNT + 1))
        echo -e "${GREEN}📊 OK: $OK | FAIL: $FAIL${NC}"
    else
        FAIL=$((FAIL + 1))
        echo -e "${YELLOW}📊 OK: $OK | FAIL: $FAIL${NC}"
        echo -e "${YELLOW}[!] Nghỉ 15s...${NC}"
        sleep 15
    fi
    sleep 5
done
EOFMAIN

chmod +x ~/pollo_farm.sh && ~/pollo_farm.sh
