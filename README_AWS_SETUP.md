# AWS 포트 설정 스크립트 (mldl 환경)

이 디렉토리에는 AWS mldl 환경에서 Flask Scheduler 애플리케이션을 위한 포트 설정 스크립트가 포함되어 있습니다.

## 📋 포함된 파일

### 스크립트

- **`aws_port_setup.sh`** - 메인 포트 설정 스크립트
  - 로컬 방화벽(UFW, firewalld, iptables) 설정
  - AWS Security Group 설정
  - 포트 상태 확인

- **`aws_security_group.sh`** - AWS Security Group 전용 관리 스크립트
  - Security Group 생성/수정/조회
  - 규칙 추가/제거
  - IP 제한 설정

- **`quick_setup.sh`** - 대화형 빠른 설정 도구
  - 사용자 친화적인 메뉴 인터페이스
  - 단계별 안내

- **`setup_service.sh`** - Systemd 서비스 설정 스크립트
  - 자동으로 systemd 서비스 생성 및 시작
  - 가상 환경 및 의존성 자동 설치
  - 프로덕션 환경 설정

### 문서

- **`AWS_PORT_SETUP_GUIDE.md`** - 상세한 설정 가이드
  - 단계별 설정 방법
  - 문제 해결 가이드
  - 보안 모범 사례

## 🚀 빠른 시작

### 1. 스크립트 실행 권한 부여

```bash
chmod +x aws_port_setup.sh aws_security_group.sh quick_setup.sh setup_service.sh
```

### 2. 대화형 설정 도구 실행

```bash
# 일반 사용자 (AWS Security Group만)
./quick_setup.sh

# Root 권한 (로컬 방화벽 + AWS Security Group)
sudo ./quick_setup.sh
```

### 3. 또는 직접 스크립트 실행

```bash
# 모든 기본 포트 자동 설정
sudo ./aws_port_setup.sh all

# 특정 포트만 설정
sudo ./aws_port_setup.sh custom 8000

# 도움말 보기
./aws_port_setup.sh help
./aws_security_group.sh help
```

## 📚 자세한 사용법

전체 사용 가이드는 [`AWS_PORT_SETUP_GUIDE.md`](./AWS_PORT_SETUP_GUIDE.md)를 참조하세요.

## 🔧 필요한 포트

| 포트 | 용도 |
|------|------|
| 5000 | Flask 개발 서버 |
| 8000 | Gunicorn 프로덕션 서버 |
| 80   | HTTP (Nginx) |
| 443  | HTTPS (Nginx) |
| 22   | SSH |

## 📖 주요 명령어

```bash
# 모든 포트 설정 (Security Group 자동 감지)
sudo ./aws_port_setup.sh all

# Security Group ID 지정하여 설정
sudo ./aws_port_setup.sh all sg-0123456789abcdef

# 현재 열린 포트 확인
./aws_port_setup.sh show

# Security Group ID 확인
./aws_security_group.sh get-id

# Security Group 규칙 확인
./aws_security_group.sh list sg-0123456789abcdef

# 현재 공용 IP 확인
./aws_security_group.sh my-ip

# SSH를 특정 IP로 제한 (보안 강화)
./aws_security_group.sh restrict sg-0123456789abcdef 22 YOUR_IP

# Systemd 서비스로 애플리케이션 설정 및 시작
sudo ./setup_service.sh
```

## 🔒 보안 권장사항

1. **SSH 포트 제한**: SSH(22번 포트)는 특정 IP에서만 접근 가능하도록 설정
2. **개발 포트 비활성화**: 프로덕션에서는 Flask 개발 서버(5000) 비활성화
3. **HTTPS 사용**: 가능한 경우 HTTPS(443)만 사용하고 HTTP(80)는 리다이렉트
4. **정기적 검토**: Security Group 규칙을 정기적으로 검토 및 업데이트

## ⚠️ 주의사항

- AWS CLI가 설치되고 올바르게 설정되어야 합니다 (`aws configure`)
- 로컬 방화벽 설정에는 root 권한이 필요합니다 (`sudo`)
- AWS Security Group 작업에는 적절한 IAM 권한이 필요합니다

## 🐛 문제 해결

자세한 문제 해결 방법은 [`AWS_PORT_SETUP_GUIDE.md`](./AWS_PORT_SETUP_GUIDE.md#문제-해결)를 참조하세요.

## 📞 지원

문제가 발생하거나 질문이 있으면 GitHub 이슈를 생성해주세요:
https://github.com/hyuny86/scheduler/issues
