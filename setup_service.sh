#!/bin/bash

###############################################################################
# Systemd Service Setup Script for Scheduler Application
# This script creates and configures a systemd service for the Flask app
###############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "이 스크립트는 root 권한으로 실행해야 합니다"
    print_info "실행: sudo $0"
    exit 1
fi

# Get application directory
APP_DIR="${1:-$(pwd)}"
if [ ! -d "$APP_DIR" ]; then
    print_error "디렉토리를 찾을 수 없습니다: $APP_DIR"
    exit 1
fi

# Get user
APP_USER="${2:-$SUDO_USER}"
if [ -z "$APP_USER" ]; then
    APP_USER=$(whoami)
fi

print_info "애플리케이션 디렉토리: $APP_DIR"
print_info "실행 사용자: $APP_USER"

# Create virtual environment if it doesn't exist
if [ ! -d "$APP_DIR/venv" ]; then
    print_info "가상 환경을 생성합니다..."
    sudo -u $APP_USER python3 -m venv "$APP_DIR/venv"
fi

# Install dependencies
print_info "의존성을 설치합니다..."
sudo -u $APP_USER "$APP_DIR/venv/bin/pip" install -q --upgrade pip
sudo -u $APP_USER "$APP_DIR/venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"
sudo -u $APP_USER "$APP_DIR/venv/bin/pip" install -q gunicorn

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/scheduler.service"

print_info "Systemd 서비스 파일을 생성합니다: $SERVICE_FILE"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Flask Scheduler Application for mldl
After=network.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
ExecStart=$APP_DIR/venv/bin/gunicorn \\
    --workers 4 \\
    --bind 0.0.0.0:8000 \\
    --timeout 120 \\
    --access-logfile $APP_DIR/access.log \\
    --error-logfile $APP_DIR/error.log \\
    --log-level info \\
    app:app

# Restart policy
Restart=always
RestartSec=10

# Security settings
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions
chmod 644 "$SERVICE_FILE"

# Reload systemd
print_info "Systemd를 다시 로드합니다..."
systemctl daemon-reload

# Enable and start service
print_info "서비스를 활성화하고 시작합니다..."
systemctl enable scheduler.service
systemctl start scheduler.service

# Wait a moment for the service to start
sleep 2

# Check status
print_info "서비스 상태를 확인합니다..."
if systemctl is-active --quiet scheduler.service; then
    print_info "✓ 서비스가 성공적으로 시작되었습니다!"
    echo ""
    systemctl status scheduler.service --no-pager -l
else
    print_error "✗ 서비스 시작 실패"
    echo ""
    print_info "로그를 확인하세요:"
    journalctl -u scheduler.service -n 50 --no-pager
    exit 1
fi

echo ""
print_info "=========================================="
print_info "서비스 관리 명령어:"
print_info "=========================================="
echo "  상태 확인:   sudo systemctl status scheduler"
echo "  시작:        sudo systemctl start scheduler"
echo "  중지:        sudo systemctl stop scheduler"
echo "  재시작:      sudo systemctl restart scheduler"
echo "  로그 확인:   sudo journalctl -u scheduler -f"
echo "  비활성화:    sudo systemctl disable scheduler"
echo ""
print_info "애플리케이션이 포트 8000에서 실행 중입니다"
print_info "접속: http://your-server-ip:8000"
echo ""
