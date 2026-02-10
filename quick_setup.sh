#!/bin/bash

###############################################################################
# Quick Setup Script for mldl AWS Environment
# This script provides a simple interactive setup for ports
###############################################################################

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║      mldl AWS 포트 설정 도구 (Scheduler Application)      ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running as root for local firewall
IS_ROOT=0
if [ "$EUID" -eq 0 ]; then
    IS_ROOT=1
    echo -e "${GREEN}✓ Root 권한으로 실행 중 (로컬 방화벽 설정 가능)${NC}"
else
    echo -e "${YELLOW}⚠ Root 권한 없음 (AWS Security Group만 설정됩니다)${NC}"
    echo -e "${YELLOW}  로컬 방화벽도 설정하려면 'sudo $0'로 실행하세요${NC}"
fi

echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${YELLOW}⚠ AWS CLI가 설치되어 있지 않습니다${NC}"
    echo "  AWS Security Group 설정을 건너뜁니다"
    HAS_AWS=0
else
    if aws sts get-caller-identity &> /dev/null; then
        echo -e "${GREEN}✓ AWS CLI 설정 완료${NC}"
        HAS_AWS=1
    else
        echo -e "${YELLOW}⚠ AWS 자격 증명이 설정되지 않았습니다${NC}"
        echo "  'aws configure'를 실행하여 설정하세요"
        HAS_AWS=0
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo ""

# Interactive menu
PS3="선택하세요 (1-6): "
options=(
    "모든 기본 포트 설정 (5000, 8000, 80, 443, 22)"
    "커스텀 포트 설정"
    "현재 열린 포트 확인"
    "Security Group 정보 확인"
    "SSH 포트를 현재 IP로 제한"
    "종료"
)

select opt in "${options[@]}"
do
    case $opt in
        "모든 기본 포트 설정 (5000, 8000, 80, 443, 22)")
            echo ""
            echo "기본 포트를 설정합니다..."
            
            if [ $HAS_AWS -eq 1 ]; then
                read -p "Security Group ID를 입력하세요 (Enter를 누르면 자동 감지): " sg_id
                
                if [ $IS_ROOT -eq 1 ]; then
                    ./aws_port_setup.sh all "$sg_id"
                else
                    if [ -n "$sg_id" ]; then
                        ./aws_security_group.sh setup "$sg_id"
                    else
                        echo "Root 권한 없이는 Security Group ID를 직접 입력해야 합니다"
                    fi
                fi
            else
                if [ $IS_ROOT -eq 1 ]; then
                    ./aws_port_setup.sh all
                else
                    echo "AWS CLI와 root 권한이 모두 없어 포트를 설정할 수 없습니다"
                fi
            fi
            
            echo ""
            read -p "Enter를 눌러 계속..."
            ;;
            
        "커스텀 포트 설정")
            echo ""
            read -p "포트 번호를 입력하세요: " port
            
            if [ -z "$port" ]; then
                echo "포트 번호를 입력해야 합니다"
            else
                if [ $HAS_AWS -eq 1 ]; then
                    read -p "Security Group ID (선택사항, Enter로 건너뛰기): " sg_id
                    
                    if [ $IS_ROOT -eq 1 ]; then
                        ./aws_port_setup.sh custom "$port" tcp "$sg_id"
                    else
                        if [ -n "$sg_id" ]; then
                            ./aws_security_group.sh add "$sg_id" "$port"
                        else
                            echo "Root 권한 없이는 Security Group ID를 직접 입력해야 합니다"
                        fi
                    fi
                else
                    if [ $IS_ROOT -eq 1 ]; then
                        ./aws_port_setup.sh custom "$port"
                    else
                        echo "포트를 설정할 수 없습니다 (root 권한 또는 AWS CLI 필요)"
                    fi
                fi
            fi
            
            echo ""
            read -p "Enter를 눌러 계속..."
            ;;
            
        "현재 열린 포트 확인")
            echo ""
            ./aws_port_setup.sh show
            
            echo ""
            read -p "Enter를 눌러 계속..."
            ;;
            
        "Security Group 정보 확인")
            echo ""
            if [ $HAS_AWS -eq 0 ]; then
                echo "AWS CLI가 설정되어 있지 않습니다"
            else
                read -p "Security Group ID (Enter를 누르면 자동 감지): " sg_id
                ./aws_security_group.sh list "$sg_id"
            fi
            
            echo ""
            read -p "Enter를 눌러 계속..."
            ;;
            
        "SSH 포트를 현재 IP로 제한")
            echo ""
            if [ $HAS_AWS -eq 0 ]; then
                echo "AWS CLI가 설정되어 있지 않습니다"
            else
                echo "현재 공용 IP를 확인합니다..."
                MY_IP=$(./aws_security_group.sh my-ip | tail -1)
                
                if [ -n "$MY_IP" ]; then
                    echo "현재 IP: $MY_IP"
                    read -p "Security Group ID: " sg_id
                    
                    if [ -n "$sg_id" ]; then
                        read -p "SSH 포트 22를 $MY_IP로만 제한하시겠습니까? (y/N): " confirm
                        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                            ./aws_security_group.sh restrict "$sg_id" 22 "$MY_IP"
                        else
                            echo "취소되었습니다"
                        fi
                    else
                        echo "Security Group ID를 입력해야 합니다"
                    fi
                else
                    echo "현재 IP를 확인할 수 없습니다"
                fi
            fi
            
            echo ""
            read -p "Enter를 눌러 계속..."
            ;;
            
        "종료")
            echo ""
            echo "종료합니다."
            break
            ;;
            
        *)
            echo "잘못된 선택입니다"
            ;;
    esac
    
    # Show menu again
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
done

echo ""
echo -e "${GREEN}완료!${NC}"
echo ""
