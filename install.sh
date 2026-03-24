cat > ~/pollo_farm.sh << 'EOFMAIN'
#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════
# POLLO FARM - FULL AUTO (FIX OTP v3)
# ═══════════════════════════════════════

PACKAGE="ai.pollo.ai"
PASS="YourPassword123"
INVITE="L54v43"
SERIAL="localhost:9163"

APK_URL="https://videocdn.pollo.ai/app/android/Pollo.ai_Android.apk"
APK_FILE="$HOME/Pollo.ai_Android.apk"
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

log_info() { echo -e "${CYAN}[INFO] $1${NC}" >&2; }
log_ok()   { echo -e "${GREEN}[✓] $1${NC}" >&2; }
log_warn() { echo -e "${YELLOW}[!] $1${NC}" >&2; }
log_error(){ echo -e "${RED}[✗] $1${NC}" >&2; }
log_step() { echo -e "${WHITE}[$1] $2${NC}" >&2; }
log_show() { echo -e "${CYAN}[INFO] $1${NC}"; }
log_show_ok(){ echo -e "${GREEN}[✓] $1${NC}"; }

# ═══════════════════════════════════════
# CÀI ĐẶT DEPENDENCIES
# ═══════════════════════════════════════

install_deps() {
    log_show "Kiểm tra dependencies..."
    
    local NEED_INSTALL=""
    
    command -v ssh >/dev/null 2>&1 || NEED_INSTALL="$NEED_INSTALL openssh"
    command -v sshpass >/dev/null 2>&1 || NEED_INSTALL="$NEED_INSTALL sshpass"
    command -v adb >/dev/null 2>&1 || NEED_INSTALL="$NEED_INSTALL android-tools"
    command -v jq >/dev/null 2>&1 || NEED_INSTALL="$NEED_INSTALL jq"
    command -v curl >/dev/null 2>&1 || NEED_INSTALL="$NEED_INSTALL curl"
    
    if [ -n "$NEED_INSTALL" ]; then
        log_warn "Đang cài:$NEED_INSTALL"
        pkg update -y >/dev/null 2>&1
        pkg install -y $NEED_INSTALL
    fi
    
    log_show_ok "Dependencies OK"
}

# ═══════════════════════════════════════
# SSH TUNNEL
# ═══════════════════════════════════════

kill_tunnel() {
    pkill -f "ssh.*$SSH_HOST.*$SSH_PORT" 2>/dev/null
    adb kill-server 2>/dev/null
    sleep 1
}

setup_ssh() {
    log_show "Thiết lập SSH tunnel..."
    
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
    
    if [ $? -eq 0 ]; then
        log_show_ok "SSH tunnel OK"
        sleep 1
        return 0
    else
        log_error "SSH tunnel FAILED"
        return 1
    fi
}

check_ssh() {
    pgrep -f "ssh.*$SSH_HOST.*$SSH_PORT" >/dev/null
}

# ═══════════════════════════════════════
# ADB
# ═══════════════════════════════════════

check_adb() {
    adb start-server >/dev/null 2>&1
    sleep 1
    adb connect $SERIAL >/dev/null 2>&1
    sleep 1
    
    if adb -s $SERIAL shell echo "OK" >/dev/null 2>&1; then
        log_show_ok "ADB OK: $SERIAL"
        return 0
    else
        log_error "ADB FAILED"
        return 1
    fi
}

hide_kb() {
    adb -s $SERIAL shell input keyevent 4 >/dev/null 2>&1
    sleep 0.1
}

tap() {
    echo -e "  ${CYAN}→ $3 ($1,$2)${NC}" >&2
    adb -s $SERIAL shell input tap $1 $2
    sleep 0.2
}

type_text() {
    echo -e "  ${CYAN}✎ $2${NC}" >&2
    adb -s $SERIAL shell input text "$1"
    sleep 0.1
    hide_kb
    sleep 0.2
}

focus_type() {
    echo -e "  ${CYAN}⌨ $4 ($1,$2)${NC}" >&2
    adb -s $SERIAL shell input tap $1 $2
    sleep 0.3
    adb -s $SERIAL shell input text "$3"
    sleep 0.1
    hide_kb
    sleep 0.2
}

enter_key() {
    adb -s $SERIAL shell input keyevent 66
    sleep 0.5
}

swipe_down() {
    adb -s $SERIAL shell input swipe 500 1000 500 200 1000
    sleep 1
}

# ═══════════════════════════════════════
# CÀI APK
# ═══════════════════════════════════════

install_apk() {
    if adb -s $SERIAL shell pm list packages 2>/dev/null | grep -q "$PACKAGE"; then
        log_show_ok "APK đã cài"
        return 0
    fi

    log_warn "Đang tải APK..."

    if [ ! -f "$APK_FILE" ]; then
        curl -L -o "$APK_FILE" "$APK_URL" --progress-bar
        
        if [ ! -f "$APK_FILE" ]; then
            log_error "Tải APK thất bại"
            return 1
        fi
        
        FILE_SIZE=$(wc -c < "$APK_FILE" 2>/dev/null)
        if [ "$FILE_SIZE" -lt 1000000 ]; then
            log_error "File APK quá nhỏ ($FILE_SIZE bytes)"
            rm -f "$APK_FILE"
            return 1
        fi
    fi

    log_show "Đang cài APK..."
    adb -s $SERIAL install -r -g "$APK_FILE" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_show_ok "Cài APK thành công"
        return 0
    else
        log_error "Cài APK thất bại"
        return 1
    fi
}

# ═══════════════════════════════════════
# TẠO EMAIL - DÙNG NHIỀU PROVIDER
# ═══════════════════════════════════════

# Provider 1: mail.tm
create_mail_tm() {
    local retry=0
    local DOMAIN=""
    
    while [ $retry -lt 3 ]; do
        DOMAIN=$(curl -s --max-time 10 https://api.mail.tm/domains \
            | jq -r '.["hydra:member"][0].domain // empty' 2>/dev/null)
        
        if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ]; then
            break
        fi
        retry=$((retry + 1))
        sleep 2
    done

    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        return 1
    fi

    RAND=$(cat /dev/urandom | tr -dc a-z0-9 | head -c 8)
    EMAIL="pollo_${RAND}@${DOMAIN}"
    MPASS="Pass${RAND}123"
    MAIL_PROVIDER="mail.tm"

    retry=0
    while [ $retry -lt 3 ]; do
        RESULT=$(curl -s --max-time 10 -X POST https://api.mail.tm/accounts \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null)

        CHECK=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
        
        if [ -n "$CHECK" ] && [ "$CHECK" != "null" ]; then
            return 0
        fi
        
        retry=$((retry + 1))
        RAND=$(cat /dev/urandom | tr -dc a-z0-9 | head -c 8)
        EMAIL="pollo_${RAND}@${DOMAIN}"
        MPASS="Pass${RAND}123"
        sleep 2
    done

    return 1
}

# Provider 2: mail.gw (backup)
create_mail_gw() {
    local retry=0
    local DOMAIN=""
    
    while [ $retry -lt 3 ]; do
        DOMAIN=$(curl -s --max-time 10 https://api.mail.gw/domains \
            | jq -r '.["hydra:member"][0].domain // empty' 2>/dev/null)
        
        if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ]; then
            break
        fi
        retry=$((retry + 1))
        sleep 2
    done

    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        return 1
    fi

    RAND=$(cat /dev/urandom | tr -dc a-z0-9 | head -c 8)
    EMAIL="pollo_${RAND}@${DOMAIN}"
    MPASS="Pass${RAND}123"
    MAIL_PROVIDER="mail.gw"

    retry=0
    while [ $retry -lt 3 ]; do
        RESULT=$(curl -s --max-time 10 -X POST https://api.mail.gw/accounts \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null)

        CHECK=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
        
        if [ -n "$CHECK" ] && [ "$CHECK" != "null" ]; then
            return 0
        fi
        
        retry=$((retry + 1))
        RAND=$(cat /dev/urandom | tr -dc a-z0-9 | head -c 8)
        EMAIL="pollo_${RAND}@${DOMAIN}"
        MPASS="Pass${RAND}123"
        sleep 2
    done

    return 1
}

create_mail() {
    log_info "Tạo email tạm..."
    
    # Thử mail.tm trước
    if create_mail_tm; then
        log_ok "Email OK (mail.tm): $EMAIL"
        sleep 2
        return 0
    fi
    
    log_warn "mail.tm failed, thử mail.gw..."
    
    # Backup: mail.gw
    if create_mail_gw; then
        log_ok "Email OK (mail.gw): $EMAIL"
        sleep 2
        return 0
    fi
    
    log_error "Tất cả mail provider đều fail"
    return 1
}

# ═══════════════════════════════════════
# LẤY OTP - FIX: LOG → STDERR, OTP → STDOUT
# ═══════════════════════════════════════

get_otp() {
    local email=$1
    local mpass=$2
    local provider=${3:-"mail.tm"}

    # Chọn API URL theo provider
    local API_BASE=""
    case "$provider" in
        "mail.gw") API_BASE="https://api.mail.gw" ;;
        *)         API_BASE="https://api.mail.tm" ;;
    esac

    # ★★★ TẤT CẢ log đều đi stderr (>&2) ★★★
    log_info "Lấy OTP: $email (provider: $provider)"

    # === Lấy token ===
    local retry=0
    local TOKEN=""
    
    while [ $retry -lt 5 ]; do
        local TOKEN_RESP=$(curl -s --max-time 15 -X POST "$API_BASE/token" \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$email\",\"password\":\"$mpass\"}" 2>/dev/null)
        
        TOKEN=$(echo "$TOKEN_RESP" | jq -r '.token // empty' 2>/dev/null)
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            break
        fi
        
        retry=$((retry + 1))
        log_warn "Retry token $retry/5..."
        sleep 3
    done

    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        log_error "Không lấy được token"
        # KHÔNG echo gì ra stdout khi fail
        return 1
    fi

    log_ok "Token OK"

    # === Chờ email OTP (tối đa 3 phút) ===
    local attempt=0
    local max_attempts=60
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        # Log đi stderr
        echo -e "  ${CYAN}⏳ Đợi OTP... ($attempt/$max_attempts)${NC}" >&2

        local MSGS=$(curl -s --max-time 15 "$API_BASE/messages" \
            -H "Authorization: Bearer $TOKEN" 2>/dev/null)

        # Kiểm tra response hợp lệ
        if [ -z "$MSGS" ]; then
            sleep 3
            continue
        fi

        local COUNT=$(echo "$MSGS" | jq -r '.["hydra:member"] | length' 2>/dev/null)
        
        if [ -z "$COUNT" ] || [ "$COUNT" = "null" ] || [ "$COUNT" = "0" ]; then
            sleep 3
            continue
        fi

        log_info "Có $COUNT email"

        # Đọc TẤT CẢ email (không chỉ cái mới nhất)
        local i=0
        while [ $i -lt $COUNT ]; do
            local MSG_ID=$(echo "$MSGS" | jq -r ".\"hydra:member\"[$i].id // empty" 2>/dev/null)
            
            if [ -z "$MSG_ID" ] || [ "$MSG_ID" = "null" ]; then
                i=$((i + 1))
                continue
            fi

            local MSG=$(curl -s --max-time 15 "$API_BASE/messages/$MSG_ID" \
                -H "Authorization: Bearer $TOKEN" 2>/dev/null)

            # Lấy TẤT CẢ nội dung
            local TEXT=$(echo "$MSG" | jq -r '.text // ""' 2>/dev/null)
            local HTML=$(echo "$MSG" | jq -r '.html // ""' 2>/dev/null | sed 's/<[^>]*>//g')
            local INTRO=$(echo "$MSG" | jq -r '.intro // ""' 2>/dev/null)
            local SUBJECT=$(echo "$MSG" | jq -r '.subject // ""' 2>/dev/null)
            
            local COMBINED="$SUBJECT $INTRO $TEXT $HTML"

            # Debug log (stderr)
            log_info "Email #$i Subject: $SUBJECT"

            # === TÌM OTP: nhiều pattern ===
            local OTP=""
            
            # Pattern 1: verification/code + 6 digits
            OTP=$(echo "$COMBINED" | grep -oiP '(?:code|otp|verify|verification)[^0-9]*\K[0-9]{6}' 2>/dev/null | head -1)
            
            # Pattern 2: 6 digits đứng riêng
            if [ -z "$OTP" ]; then
                OTP=$(echo "$COMBINED" | grep -oP '\b[0-9]{6}\b' 2>/dev/null | head -1)
            fi
            
            # Pattern 3: grep cơ bản (fallback)
            if [ -z "$OTP" ]; then
                OTP=$(echo "$COMBINED" | grep -oE '[0-9]{6}' 2>/dev/null | head -1)
            fi

            # Trim whitespace
            OTP=$(echo "$OTP" | tr -d '\r\n\t ')

            if [[ "$OTP" =~ ^[0-9]{6}$ ]]; then
                log_ok "✅ OTP: $OTP"
                # ★★★ CHỈ echo OTP ra stdout ★★★
                echo "$OTP"
                return 0
            fi

            i=$((i + 1))
        done

        sleep 3
    done

    log_error "Timeout: Không nhận OTP sau 3 phút"
    return 1
}

# ═══════════════════════════════════════
# CHẠY 1 LƯỢT
# ═══════════════════════════════════════

run_one() {
    local run_num=$1

    echo ""
    echo -e "${YELLOW}╔════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║       RUN #$run_num                  ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════╝${NC}"

    log_step "1" "Clear data"
    adb -s $SERIAL shell pm clear $PACKAGE >/dev/null 2>&1

    log_step "2" "Mở app"
    adb -s $SERIAL shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 12

    log_step "3" "Điều hướng"
    tap 110 457 "menu"; sleep 3
    tap 623 1232 "login/register"; sleep 2
    tap 360 725 "login"; sleep 1
    tap 94 1210 "register"; sleep 1
    tap 283 1100 "next"; sleep 1
    tap 489 452 "next"; sleep 1
    tap 258 556 "email field"; sleep 1

    log_step "4" "Tạo email"
    create_mail || return 1

    log_step "5" "Nhập email + Get OTP"
    focus_type 258 556 "$EMAIL" "email"
    sleep 1
    tap 350 670 "Get OTP"
    sleep 5

    # ★★★ FIX: Chỉ stdout (OTP) vào biến, stderr (log) hiện ra terminal ★★★
    OTP=$(get_otp "$EMAIL" "$MPASS" "$MAIL_PROVIDER")
    local OTP_STATUS=$?
    
    if [ $OTP_STATUS -ne 0 ] || [ -z "$OTP" ]; then
        log_error "Lấy OTP thất bại"
        return 1
    fi
    
    # Double check
    OTP=$(echo "$OTP" | tr -d '\r\n\t ')
    
    if [[ ! "$OTP" =~ ^[0-9]{6}$ ]]; then
        log_error "OTP không hợp lệ: [$OTP]"
        return 1
    fi

    echo -e "${GREEN}[✓] Dùng OTP: $OTP${NC}"

    log_step "6" "Nhập OTP"
    tap 258 556 "OTP field"
    sleep 0.3
    type_text "$OTP" "OTP"
    sleep 1
    tap 340 650 "Submit OTP"
    sleep 5

    log_step "7" "Nhập thông tin"
    focus_type 210 580 "Minh" "First name"
    sleep 1
    focus_type 505 567 "Nguyen" "Last name"
    sleep 1
    focus_type 154 711 "$PASS" "Password"
    sleep 2
    tap 324 843 "CREATE"
    sleep 5

    log_step "8" "Đăng nhập"
    tap 352 457 "Email field"
    sleep 2
    focus_type 209 677 "$PASS" "Password"
    sleep 1
    tap 361 783 "Login submit"
    sleep 4

    log_step "9" "Skip intro"
    tap 444 85 "Skip 1"
    sleep 2
    tap 580 1018 "Skip 2"
    sleep 2

    log_step "10" "Scroll"
    swipe_down
    sleep 2

    log_step "11" "Nhập invite"
    focus_type 173 973 "$INVITE" "Invite code"
    sleep 1
    enter_key
    sleep 1

    log_step "12" "Redeem"
    tap 548 686 "REDEEM"
    sleep 3

    echo ""
    echo -e "${GREEN}╔════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ✅ SUCCESS #$run_num              ║${NC}"
    echo -e "${GREEN}║  $EMAIL  ${NC}"
    echo -e "${GREEN}╚════════════════════════════════╝${NC}"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | #$run_num | $EMAIL | $PASS" >> "$LOG_FILE"
    return 0
}

# ═══════════════════════════════════════
# MONITOR
# ═══════════════════════════════════════

monitor_tunnel() {
    while true; do
        sleep 60
        if ! check_ssh; then
            log_warn "SSH mất, reconnect..."
            kill_tunnel
            setup_ssh
            check_adb
        fi
    done
}

# ═══════════════════════════════════════
# MAIN
# ═══════════════════════════════════════

clear

echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🐔 POLLO FARM v3.0 - FIX OTP   ║${NC}"
echo -e "${GREEN}║   SSH: $SSH_HOST:$SSH_PORT          ║${NC}"
echo -e "${GREEN}║   ADB: $SERIAL               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo ""

install_deps
kill_tunnel
setup_ssh || exit 1
check_adb || exit 1
install_apk || exit 1

monitor_tunnel &
MONITOR_PID=$!

echo ""
log_show_ok "🚀 Bắt đầu farm..."
echo ""

COUNT=1
SUCCESS=0
FAIL=0

while true; do
    if run_one $COUNT; then
        SUCCESS=$((SUCCESS + 1))
        COUNT=$((COUNT + 1))
        echo -e "${GREEN}📊 Stats: ✓ $SUCCESS | ✗ $FAIL${NC}"
    else
        FAIL=$((FAIL + 1))
        echo -e "${YELLOW}📊 Stats: ✓ $SUCCESS | ✗ $FAIL${NC}"
        sleep 10
    fi
done
EOFMAIN

chmod +x ~/pollo_farm.sh && ~/pollo_farm.sh
