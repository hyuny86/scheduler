# AWS 환경에서 Port 설정 가이드 (mldl 환경)

이 문서는 hyuny86/scheduler Flask 애플리케이션을 AWS 환경(mldl)에 배포할 때 필요한 포트 설정 방법을 설명합니다.

## 목차

1. [개요](#개요)
2. [필수 도구](#필수-도구)
3. [기본 포트 구성](#기본-포트-구성)
4. [스크립트 사용법](#스크립트-사용법)
5. [수동 설정 방법](#수동-설정-방법)
6. [보안 고려사항](#보안-고려사항)
7. [문제 해결](#문제-해결)

## 개요

scheduler 애플리케이션은 Flask 기반 웹 애플리케이션으로, AWS EC2 인스턴스에서 실행됩니다. 적절한 포트 설정과 보안 그룹 구성이 필요합니다.

### 사용되는 포트

| 포트 | 용도 | 프로토콜 |
|------|------|---------|
| 5000 | Flask 개발 서버 | TCP |
| 8000 | Gunicorn 프로덕션 서버 | TCP |
| 80 | HTTP (Nginx) | TCP |
| 443 | HTTPS (Nginx) | TCP |
| 22 | SSH 접근 | TCP |

## 필수 도구

### AWS CLI 설치

```bash
# Linux (Ubuntu/Debian)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# macOS
brew install awscli

# 설치 확인
aws --version
```

### AWS CLI 설정

```bash
# AWS 자격 증명 설정
aws configure

# 입력 항목:
# AWS Access Key ID: [your-access-key]
# AWS Secret Access Key: [your-secret-key]
# Default region name: ap-northeast-2  # 서울 리전
# Default output format: json
```

## 기본 포트 구성

### 방법 1: 자동 스크립트 사용 (권장)

#### 1. 스크립트 실행 권한 부여

```bash
chmod +x aws_port_setup.sh
chmod +x aws_security_group.sh
```

#### 2. 모든 기본 포트 설정

```bash
# Security Group ID 자동 감지하여 모든 포트 설정
sudo ./aws_port_setup.sh all

# Security Group ID를 직접 지정
sudo ./aws_port_setup.sh all sg-0123456789abcdef
```

#### 3. 특정 포트만 설정

```bash
# 포트 8000만 설정
sudo ./aws_port_setup.sh custom 8000

# Security Group과 함께 설정
sudo ./aws_port_setup.sh custom 8000 tcp sg-0123456789abcdef "Gunicorn server"
```

#### 4. 현재 열린 포트 확인

```bash
./aws_port_setup.sh show
```

### 방법 2: Security Group 관리 스크립트 사용

#### 1. 새 Security Group 생성

```bash
./aws_security_group.sh create "mldl-scheduler-sg" "mldl 스케줄러 애플리케이션용 보안 그룹"
```

#### 2. 스케줄러 포트 자동 설정

```bash
# 모든 IP에서 접근 허용
./aws_security_group.sh setup sg-0123456789abcdef

# 특정 CIDR에서만 접근 허용
./aws_security_group.sh setup sg-0123456789abcdef 203.0.113.0/24
```

#### 3. 개별 포트 추가

```bash
# 기본 (모든 IP 허용)
./aws_security_group.sh add sg-0123456789abcdef 8000

# 특정 IP에서만 허용
./aws_security_group.sh add sg-0123456789abcdef 8000 tcp 203.0.113.1/32 "Office IP"
```

#### 4. Security Group 규칙 확인

```bash
./aws_security_group.sh list sg-0123456789abcdef
```

#### 5. 현재 인스턴스의 Security Group ID 확인

```bash
./aws_security_group.sh get-id
```

## 수동 설정 방법

### AWS 콘솔에서 설정

1. **AWS Management Console 로그인**
   - https://console.aws.amazon.com/ 접속

2. **EC2 서비스로 이동**
   - Services → EC2 선택

3. **Security Groups 설정**
   - 왼쪽 메뉴에서 "Security Groups" 선택
   - 해당 인스턴스의 Security Group 선택
   - "Inbound rules" 탭 선택
   - "Edit inbound rules" 클릭

4. **규칙 추가**
   
   각 포트에 대해 다음 정보 입력:
   
   | Type | Protocol | Port Range | Source | Description |
   |------|----------|------------|--------|-------------|
   | Custom TCP | TCP | 5000 | 0.0.0.0/0 | Flask dev server |
   | Custom TCP | TCP | 8000 | 0.0.0.0/0 | Gunicorn server |
   | HTTP | TCP | 80 | 0.0.0.0/0 | HTTP access |
   | HTTPS | TCP | 443 | 0.0.0.0/0 | HTTPS access |
   | SSH | TCP | 22 | My IP | SSH access |

5. **저장**
   - "Save rules" 클릭

### AWS CLI로 수동 설정

```bash
# Security Group ID 가져오기
SG_ID=$(aws ec2 describe-instances \
  --instance-ids i-0123456789abcdef \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)

# 포트 5000 열기
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 5000 \
  --cidr 0.0.0.0/0 \
  --description "Flask development server"

# 포트 8000 열기
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8000 \
  --cidr 0.0.0.0/0 \
  --description "Gunicorn production server"

# HTTP (포트 80) 열기
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --description "HTTP access"

# HTTPS (포트 443) 열기
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --description "HTTPS access"
```

### 리눅스 방화벽 설정

#### UFW (Ubuntu/Debian)

```bash
# UFW 활성화
sudo ufw enable

# 포트 열기
sudo ufw allow 5000/tcp
sudo ufw allow 8000/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp

# 상태 확인
sudo ufw status
```

#### firewalld (CentOS/RHEL)

```bash
# 포트 열기
sudo firewall-cmd --permanent --add-port=5000/tcp
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=22/tcp

# 재로드
sudo firewall-cmd --reload

# 상태 확인
sudo firewall-cmd --list-all
```

## 보안 고려사항

### 1. SSH 포트 제한

SSH 접근은 특정 IP에서만 허용하는 것이 좋습니다:

```bash
# 현재 공용 IP 확인
./aws_security_group.sh my-ip

# SSH를 특정 IP로 제한
./aws_security_group.sh restrict sg-0123456789abcdef 22 YOUR_IP_ADDRESS
```

또는 AWS CLI 사용:

```bash
# 기존 SSH 규칙 제거
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# 특정 IP에서만 SSH 허용
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32 \
  --description "SSH from my IP"
```

### 2. 개발 포트 (5000) 제한

프로덕션 환경에서는 Flask 개발 서버 포트(5000)를 비활성화해야 합니다:

```bash
# 포트 5000 규칙 제거
./aws_security_group.sh remove sg-0123456789abcdef 5000
```

### 3. HTTPS 강제 사용

프로덕션 환경에서는 HTTPS만 사용하도록 설정:

```bash
# HTTP (포트 80)는 HTTPS로 리다이렉트하도록 Nginx 설정
# 자세한 내용은 Nginx 설정 참조
```

### 4. 네트워크 ACL 설정

추가 보안 계층으로 Network ACL을 설정할 수 있습니다:

```bash
# VPC의 Network ACL ID 가져오기
NACL_ID=$(aws ec2 describe-network-acls \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkAcls[0].NetworkAclId' \
  --output text)

# Inbound 규칙 추가
aws ec2 create-network-acl-entry \
  --network-acl-id $NACL_ID \
  --rule-number 100 \
  --protocol tcp \
  --port-range From=8000,To=8000 \
  --cidr-block 0.0.0.0/0 \
  --rule-action allow \
  --ingress
```

## 애플리케이션 실행

### 개발 환경

```bash
# Flask 개발 서버 (포트 5000)
python app.py
```

### 프로덕션 환경

```bash
# Gunicorn 설치
pip install gunicorn

# Gunicorn으로 실행 (포트 8000)
gunicorn -w 4 -b 0.0.0.0:8000 app:app

# 백그라운드 실행
nohup gunicorn -w 4 -b 0.0.0.0:8000 app:app > gunicorn.log 2>&1 &
```

### Systemd 서비스로 실행

#### 방법 1: 자동 설정 스크립트 사용 (권장)

```bash
# 스크립트를 실행하여 자동으로 서비스 설정
sudo ./setup_service.sh

# 또는 특정 디렉토리와 사용자 지정
sudo ./setup_service.sh /path/to/scheduler username
```

이 스크립트는 자동으로:
- 가상 환경 생성
- 의존성 설치 (gunicorn 포함)
- systemd 서비스 파일 생성
- 서비스 활성화 및 시작

#### 방법 2: 수동 설정

1. 서비스 파일 생성:

```bash
sudo nano /etc/systemd/system/scheduler.service
```

2. 내용 입력:

```ini
[Unit]
Description=Scheduler Flask Application
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/scheduler
Environment="PATH=/home/ubuntu/scheduler/venv/bin"
ExecStart=/home/ubuntu/scheduler/venv/bin/gunicorn -w 4 -b 0.0.0.0:8000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
```

3. 서비스 시작:

```bash
sudo systemctl daemon-reload
sudo systemctl start scheduler
sudo systemctl enable scheduler
sudo systemctl status scheduler
```

## 문제 해결

### 포트가 이미 사용 중인 경우

```bash
# 포트 사용 확인
sudo netstat -tulpn | grep :8000

# 프로세스 종료
sudo kill -9 <PID>

# 또는 스크립트 사용
./aws_port_setup.sh show
```

### Security Group 규칙이 적용되지 않는 경우

```bash
# 현재 규칙 확인
./aws_security_group.sh list sg-0123456789abcdef

# 인스턴스에 올바른 Security Group이 할당되었는지 확인
aws ec2 describe-instances \
  --instance-ids i-0123456789abcdef \
  --query 'Reservations[0].Instances[0].SecurityGroups'
```

### 연결이 안 되는 경우

1. **Security Group 확인**
   ```bash
   ./aws_security_group.sh list
   ```

2. **방화벽 확인**
   ```bash
   sudo ufw status
   # 또는
   sudo firewall-cmd --list-all
   ```

3. **애플리케이션 실행 확인**
   ```bash
   ps aux | grep python
   # 또는
   ps aux | grep gunicorn
   ```

4. **포트 리스닝 확인**
   ```bash
   sudo netstat -tulpn | grep :8000
   ```

5. **로그 확인**
   ```bash
   # Gunicorn 로그
   tail -f gunicorn.log
   
   # Systemd 서비스 로그
   sudo journalctl -u scheduler -f
   ```

### AWS CLI 권한 오류

```bash
# IAM 사용자에게 다음 권한이 필요합니다:
# - ec2:DescribeInstances
# - ec2:DescribeSecurityGroups
# - ec2:AuthorizeSecurityGroupIngress
# - ec2:RevokeSecurityGroupIngress
# - ec2:CreateSecurityGroup
# - ec2:CreateTags

# 현재 IAM 권한 확인
aws iam get-user
aws sts get-caller-identity
```

## 추가 리소스

- [AWS EC2 Security Groups 문서](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)
- [Gunicorn 문서](https://docs.gunicorn.org/)
- [Flask 배포 가이드](https://flask.palletsprojects.com/en/2.3.x/deploying/)
- [AWS CLI 레퍼런스](https://docs.aws.amazon.com/cli/latest/reference/ec2/)

## 빠른 참조

```bash
# 스크립트 실행 권한 부여
chmod +x aws_port_setup.sh aws_security_group.sh

# 모든 포트 자동 설정
sudo ./aws_port_setup.sh all

# Security Group ID 확인
./aws_security_group.sh get-id

# 모든 규칙 확인
./aws_security_group.sh list

# 현재 공용 IP 확인
./aws_security_group.sh my-ip

# 특정 포트 추가
./aws_security_group.sh add sg-xxxx 8000

# 도움말
./aws_port_setup.sh help
./aws_security_group.sh help
```

## 연락처 및 지원

문제가 발생하거나 질문이 있으면 GitHub 이슈를 생성해주세요:
https://github.com/hyuny86/scheduler/issues
