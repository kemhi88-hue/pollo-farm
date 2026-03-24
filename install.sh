cat > ~/pollo_farm_vmos.sh << 'EOFMAIN'
#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════
# POLLO FARM - VMOS API AUTO
# Tự động lấy thông số ADB từ API
# ═══════════════════════════════════════

PACKAGE="ai.pollo.ai"
PASS="YourPassword123"
INVITE="L54v43"

# VMOS API
ACCESS_KEY="pFyNHZKNZq1xgp5xx3orHrTWTpMmrzjW"
SECRET_KEY="l2PmAPSzYtjXkR9GvOaXJkVp"
VMOS_API="https://api.vmoscloud.com/v1"

LOG_FILE="$HOME/success.txt"

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

# ═══════════════════════════════════════
# CÀI ĐẶT DEPENDENCIES
# ═══════════════════════════════════════

install_deps() {
    log_info "Kiểm tra dependencies..."
    
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
    
    log_ok "Dependencies OK"
}

# ═══════════════════════════════════════
# VMOS API - LẤY THÔNG SỐ ADB
# ═══════════════════════════════════════

vmos_get_adb_config() {
    log_info "Lấy cấu hình ADB từ VMOS API..."
    
    # 1. Lấy danh sách VM
    log_info "Lấy danh sách VM..."
    VM_RESPONSE=$(curl -s "$VMOS_API/vms" \
        -H "X-Access-Key: $ACCESS_KEY" \
        -H "X-Secret-Key: $SECRET_KEY")
    
    VM_ID=$(echo "$VM_RESPONSE" | jq -r '.vms[0].vmId // empty')
    VM_NAME=$(echo "$VM_RESPONSE" | jq -r '.vms[0].name // empty')
    VM_STATUS=$(echo "$VM_RESPONSE" | jq -r '.vms[0].status // empty')
    
    if [ -z "$VM_ID" ]; then
        log_error "Không tìm thấy VM"
        return 1
    fi
    
    log_ok "VM: $VM_NAME (ID: $VM_ID, Status: $VM_STATUS)"
    
    # 2. Bật VM nếu đang tắt
    if [ "$VM_STATUS" != "running" ]; then
        log_info "Bật VM..."
        curl -s -X POST "$VMOS_API/vms/$VM_ID/start" \
            -H "X-Access-Key: $ACCESS_KEY" \
            -H "X-Secret-Key: $SECRET_KEY" >/dev/null
        
        log_info "Đợi VM khởi động (30s)..."
        sleep 30
    fi
    
    # 3. Bật ADB
    log_info "Bật ADB..."
    curl -s -X POST "$VMOS_API/vms/$VM_ID/adb/enable" \
        -H "X-Access-Key: $ACCESS_KEY" \
        -H "X-Secret-Key: $SECRET_KEY" \
        -H "Content-Type: application/json" >/dev/null
    
    sleep 2
    
    # 4. Lấy thông số ADB
    log_info "Lấy thông số ADB..."
    ADB_INFO=$(curl -s "$VMOS_API/vms/$VM_ID/adb/info" \
        -H "X-Access-Key: $ACCESS_KEY" \
        -H "X-Secret-Key: $SECRET_KEY")
    
    # Parse thông tin
    SSH_HOST=$(echo "$ADB_INFO" | jq -r '.sshTunnel.host // .sshHost // empty')
    SSH_PORT=$(echo "$ADB_INFO" | jq -r '.sshTunnel.port // .sshPort // empty')
    SSH_USER=$(echo "$ADB_INFO" | jq -r '.sshTunnel.username // .sshUser // empty')
    SSH_PASSWORD=$(echo "$ADB_INFO" | jq -r '.sshTunnel.password // .sshPassword // empty')
    REMOTE_ADB=$(echo "$ADB_INFO" | jq -r '.remotePort // .adbPort // empty')
    LOCAL_PORT=$(echo "$ADB_INFO" | jq -r '.localPort // "9163"')
    PROXY_HOST=$(echo "$ADB_INFO" | jq -r '.proxyHost // "adb-proxy"')
    SERIAL="localhost:$LOCAL_PORT"
    
    if [ -z "$SSH_HOST" ] || [ -z "$REMOTE_ADB" ]; then
        log_error "Không lấy được thông số ADB"
        echo "API Response:"
        echo "$ADB_INFO" | jq '.'
        return 1
    fi
    
    log_ok "SSH: $SSH_USER@$SSH_HOST:$SSH_PORT"
    log_ok "ADB: $PROXY_HOST:$REMOTE_ADB → localhost:$LOCAL_PORT"
    
    return 0
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
    log_info "Thiết lập SSH tunnel..."
    
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keyscan -p $SSH_PORT $SSH_HOST >> ~/.ssh/known_hosts 2>/dev/null
    
    sshpass -p "$SSH_PASSWORD" ssh \
        -oHostKeyAlgorithms=+ssh-rsa \
        -oStrictHostKeyChecking=no \
        -oServerAliveInterval=30 \
        -oServerAliveCountMax=3 \
        -L $LOCAL_PORT:$PROXY_HOST:$REMOTE_ADB \
        -Nf \
        $SSH_USER@$SSH_HOST \
        -p $SSH_PORT >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_ok "SSH tunnel OK"
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
        log_ok "ADB OK: $SERIAL"
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
    echo -e "  ${CYAN}→ $3 ($1,$2)${NC}"
    adb -s $SERIAL shell input tap $1 $2
    sleep 0.2
}

type_text() {
    echo -e "  ${CYAN}✎ $2${NC}"
    adb -s $SERIAL shell input text "$1"
    sleep 0.1
    hide_kb
    sleep 0.2
}

focus_type() {
    echo -e "  ${CYAN}⌨ $4 ($1,$2)${NC}"
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
# TẠO EMAIL
# ═══════════════════════════════════════

create_mail() {
    log_info "Tạo email tạm..."

    local retry=0
    local DOMAIN=""
    
    while [ $retry -lt 3 ]; do
        DOMAIN=$(curl -s --max-time 15 https://api.mail.tm/domains \
            | jq -r '.["hydra:member"][0].domain // empty' 2>/dev/null)
        
        if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ]; then
            break
        fi
        
        retry=$((retry + 1))
        log_warn "Retry lấy domain $retry/3..."
        sleep 2
    done

    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        log_error "Không lấy được domain mail.tm"
        return 1
    fi

    RAND=$(cat /dev/urandom | tr -dc a-z0-9 | head -c 8)
    EMAIL="pollo_${RAND}@${DOMAIN}"
    MPASS="Pass${RAND}123"

    log_info "Đăng ký: $EMAIL"

    retry=0
    local CHECK=""
    
    while [ $retry -lt 3 ]; do
        RESULT=$(curl -s --max-time 15 -X POST https://api.mail.tm/accounts \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$EMAIL\",\"password\":\"$MPASS\"}" 2>/dev/null)

        CHECK=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
        
        if [ -n "$CHECK" ] && [ "$CHECK" != "null" ]; then
            break
        fi
        
        retry=$((retry + 1))
        log_warn "Retry tạo email $retry/3..."
        
        RAND=$(cat /dev/urandom | tr -dc a-z0-9 | head -c 8)
        EMAIL="pollo_${RAND}@${DOMAIN}"
        MPASS="Pass${RAND}123"
        
        sleep 2
    done

    if [ -z "$CHECK" ] || [ "$CHECK" = "null" ]; then
        log_error "Tạo email thất bại"
        return 1
    fi

    log_ok "Email: $EMAIL"
    sleep 2
    
    return 0
}

# ═══════════════════════════════════════
# LẤY OTP
# ═══════════════════════════════════════

get_otp() {
    local email=$1
    local mpass=$2

    log_info "Lấy OTP cho $email"

    local retry=0
    local TOKEN=""
    
    while [ $retry -lt 3 ]; do
        local TOKEN_RESP=$(curl -s --max-time 15 -X POST https://api.mail.tm/token \
            -H "Content-Type: application/json" \
            -d "{\"address\":\"$email\",\"password\":\"$mpass\"}" 2>/dev/null)
        
        TOKEN=$(echo "$TOKEN_RESP" | jq -r '.token // empty' 2>/dev/null)
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            break
        fi
        
        retry=$((retry + 1))
        log_warn "Retry lấy token $retry/3..."
        sleep 2
    done

    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        log_error "Không lấy được token"
        echo "FAILED"
        return 1
    fi

    log_ok "Token OK"

    local attempt=0
    local max_attempts=40
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        echo -e "  ${CYAN}⏳ Đợi email OTP... ($attempt/$max_attempts)${NC}"

        local MSGS=$(curl -s --max-time 15 https://api.mail.tm/messages \
            -H "Authorization: Bearer $TOKEN" 2>/dev/null)

        local COUNT=$(echo "$MSGS" | jq -r '.["hydra:member"] | length' 2>/dev/null)
        
        if [ -z "$COUNT" ] || [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ]; then
            sleep 3
            continue
        fi

        log_info "Có $COUNT email, đang đọc..."

        local MSG_ID=$(echo "$MSGS" | jq -r '.["hydra:member"] | sort_by(.createdAt) | reverse | .[0].id // empty' 2>/dev/null)

        if [ -z "$MSG_ID" ] || [ "$MSG_ID" = "null" ]; then
            sleep 3
            continue
        fi

        local MSG=$(curl -s --max-time 15 "https://api.mail.tm/messages/$MSG_ID" \
            -H "Authorization: Bearer $TOKEN" 2>/dev/null)

        local TEXT=$(echo "$MSG" | jq -r '.text // empty' 2>/dev/null)
        local HTML=$(echo "$MSG" | jq -r '.html // empty' 2>/dev/null)
        local INTRO=$(echo "$MSG" | jq -r '.intro // empty' 2>/dev/null)
        local SUBJECT=$(echo "$MSG" | jq -r '.subject // empty' 2>/dev/null)
        
        local COMBINED="$TEXT $HTML $INTRO $SUBJECT"

        local OTP=$(echo "$COMBINED" | grep -oE '\b[0-9]{6}\b' | head -n 1 | tr -d '\r\n\t ')

        if [[ "$OTP" =~ ^[0-9]{6}$ ]]; then
            log_ok "✅ OTP: $OTP"
            echo "$OTP"
            return 0
        fi

        sleep 3
    done

    log_error "⏱ Timeout: Không nhận được OTP"
    echo "FAILED"
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

    OTP=$(get_otp "$EMAIL" "$MPASS")
    
    if [[ ! "$OTP" =~ ^[0-9]{6}$ ]]; then
        log_error "OTP không hợp lệ: $OTP"
        return 1
    fi

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
# MONITOR SSH TUNNEL
# ═══════════════════════════════════════

monitor_tunnel() {
    while true; do
        sleep 60
        
        if ! check_ssh; then
            log_warn "SSH tunnel bị mất, đang reconnect..."
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
echo -e "${GREEN}║                                    ║${NC}"
echo -e "${GREEN}║   🐔 POLLO FARM - VMOS API 🐔     ║${NC}"
echo -e "${GREEN}║   AUTO GET ADB CONFIG              ║${NC}"
echo -e "${GREEN}║                                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo ""

# Bước 1: Cài dependencies
install_deps

# Bước 2: Lấy config ADB từ VMOS API
vmos_get_adb_config || exit 1
echo ""

# Bước 3: Dọn dẹp
kill_tunnel

# Bước 4: SSH tunnel
setup_ssh || exit 1

# Bước 5: ADB
check_adb || exit 1

# Bước 6: Monitor tunnel (background)
monitor_tunnel &
MONITOR_PID=$!
log_info "Monitor PID: $MONITOR_PID"

# Bước 7: Farm loop
echo ""
log_ok "🚀 Bắt đầu farm..."
echo ""

COUNT=1
SUCCESS=0
FAIL=0

while true; do
    if run_one $COUNT; then
        SUCCESS=$((SUCCESS + 1))
        COUNT=$((COUNT + 1))
        echo ""
        log_ok "📊 Stats: ✓ $SUCCESS | ✗ $FAIL"
        echo ""
    else
        FAIL=$((FAIL + 1))
        echo ""
        log_warn "📊 Stats: ✓ $SUCCESS | ✗ $FAIL"
        log_warn "Nghỉ 10s trước khi thử lại..."
        echo ""
        sleep 10
    fi
done
EOFMAIN

chmod +x ~/pollo_farm_vmos.sh && ~/pollo_farm_vmos.sh
