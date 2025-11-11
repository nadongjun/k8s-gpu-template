#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}================================================${NC}"
echo -e "${YELLOW}Minikube 클러스터 삭제 중...${NC}"
echo -e "${YELLOW}================================================${NC}"
echo ""

# 클러스터 삭제 확인
read -p "정말로 Minikube 클러스터를 삭제하시겠습니까? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}삭제가 취소되었습니다.${NC}"
    exit 0
fi

# Minikube 클러스터 삭제
if minikube status > /dev/null 2>&1; then
    echo -e "${YELLOW}클러스터 삭제 중...${NC}"
    minikube delete
    echo -e "${GREEN}✓ 클러스터가 삭제되었습니다.${NC}"
else
    echo -e "${YELLOW}실행 중인 Minikube 클러스터가 없습니다.${NC}"
fi

# CA 인증서 파일 삭제
if [ -f "ca-cert.crt" ]; then
    rm ca-cert.crt
    echo -e "${GREEN}✓ CA 인증서 파일이 삭제되었습니다.${NC}"
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}클러스터 정리가 완료되었습니다.${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}추가 정리 (선택사항):${NC}"
echo ""
echo "# Minikube 캐시 및 설정 삭제"
echo "rm -rf ~/.minikube"
echo ""
echo "# Docker 이미지 정리"
echo "docker system prune -a"
