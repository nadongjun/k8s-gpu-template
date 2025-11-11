#!/bin/bash

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   Stable Diffusion 모델 배포${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# 환경 설정 파일 확인
if [ ! -f ".ai-serving-config" ]; then
    echo -e "${RED}✗ 환경이 설정되지 않았습니다.${NC}"
    echo "먼저 './setup-minikube.sh'를 실행하세요."
    exit 1
fi

source .ai-serving-config

# 클러스터 상태 확인
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}✗ Kubernetes 클러스터에 연결할 수 없습니다.${NC}"
    echo "먼저 './setup-minikube.sh'를 실행하세요."
    exit 1
fi

# LLM 배포 확인 및 제거
echo -e "${YELLOW}[1/4] 기존 배포 확인 중...${NC}"
if kubectl get deployment llm-serving -n ai-serving > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ LLM이 실행 중입니다. 제거합니다...${NC}"
    kubectl delete deployment llm-serving -n ai-serving
    kubectl delete ingress llm-ingress -n ai-serving 2>/dev/null || true
    echo "제거 완료를 기다리는 중..."
    sleep 5
    echo -e "${GREEN}✓ LLM 제거 완료${NC}"
else
    echo -e "${GREEN}✓ 제거할 배포가 없습니다.${NC}"
fi
echo ""

# SD가 이미 실행 중인지 확인
if kubectl get deployment sd-serving -n ai-serving > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Stable Diffusion이 이미 실행 중입니다. 재배포합니다...${NC}"
    kubectl delete deployment sd-serving -n ai-serving
    sleep 3
fi

# Stable Diffusion 배포
echo -e "${YELLOW}[2/4] Stable Diffusion 배포 중...${NC}"
if [ "$USE_GPU" = "true" ]; then
    echo -e "${GREEN}   ✓ GPU 가속 모드로 배포${NC}"
    kubectl apply -f sd-deployment-gpu.yaml
else
    echo -e "${YELLOW}   ⚠ CPU 모드로 배포 (성능 매우 제한)${NC}"
    kubectl apply -f sd-deployment.yaml
fi
echo ""

# Pod 생성 대기
echo -e "${YELLOW}[3/4] SD Pod 생성 대기 중...${NC}"
for i in {1..30}; do
  POD_COUNT=$(kubectl get pods -n ai-serving -l app=sd-serving --no-headers 2>/dev/null | wc -l)
  if [ "$POD_COUNT" -gt 0 ]; then
    echo "✓ SD Pod가 생성되었습니다."
    break
  fi
  echo "  대기 중... ($i/30)"
  sleep 5
done

# Pod 준비 대기
echo ""
echo -e "${YELLOW}SD Pod가 준비될 때까지 대기 중...${NC}"
echo ""
echo "진행 상황을 보려면 다른 터미널에서:"
echo "  ${BLUE}kubectl logs -n ai-serving -l app=sd-serving -f${NC}"
echo ""

kubectl wait --namespace ai-serving \
  --for=condition=ready pod \
  --selector=app=sd-serving \
  --timeout=600s || {
    echo -e "${RED}✗ SD Pod 대기 시간 초과${NC}"
    echo ""
    echo "문제 해결:"
    echo "  1. Pod 상태 확인: kubectl get pods -n ai-serving"
    echo "  2. Pod 로그 확인: kubectl logs -n ai-serving -l app=sd-serving"
    echo "  3. Pod 상세 정보: kubectl describe pod -n ai-serving -l app=sd-serving"
    exit 1
  }

echo -e "${GREEN}✓ SD Pod 준비 완료${NC}"
echo ""

# Ingress 배포
echo -e "${YELLOW}[4/4] HTTPS Ingress 설정 중...${NC}"
kubectl apply -f ingress.yaml
sleep 3
echo -e "${GREEN}✓ Ingress 설정 완료${NC}"
echo ""

# 배포 상태 확인
echo "=== 배포 상태 ==="
echo ""
echo "Pods:"
kubectl get pods -n ai-serving
echo ""
echo "Services:"
kubectl get svc -n ai-serving
echo ""
echo "Ingress:"
kubectl get ingress -n ai-serving
echo ""

# Minikube IP
MINIKUBE_IP=$(minikube ip)

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   Stable Diffusion 배포 완료!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}접속 정보:${NC}"
echo ""
echo "   엔드포인트: ${GREEN}https://sd.ai-serving.local${NC}"
echo "   Minikube IP: ${BLUE}${MINIKUBE_IP}${NC}"
echo ""
if [ "$USE_GPU" = "true" ]; then
    echo -e "   ${GREEN}✓ GPU 가속 활성화됨${NC}"
else
    echo -e "   ${YELLOW}⚠ CPU 모드 (GPU 미사용)${NC}"
fi
echo ""
echo -e "${YELLOW}테스트 명령어:${NC}"
echo ""
echo "   # 서비스 확인"
echo "   ${BLUE}curl -k https://sd.ai-serving.local${NC}"
echo ""
echo -e "${YELLOW}참고:${NC}"
echo "   현재 배포된 이미지는 플레이스홀더입니다."
echo "   프로덕션 환경에서는 다음을 사용하세요:"
echo "   - AUTOMATIC1111 WebUI"
echo "   - ComfyUI"
echo "   - Stable Diffusion WebUI"
echo ""
echo -e "${YELLOW}GPU 사용량 확인 (GPU 사용 시):${NC}"
if [ "$USE_GPU" = "true" ]; then
    POD_NAME=$(kubectl get pod -n ai-serving -l app=sd-serving -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD_NAME" ]; then
        echo "   ${BLUE}kubectl exec -n ai-serving ${POD_NAME} -- nvidia-smi${NC}"
    fi
fi
echo ""
echo -e "${GREEN}================================================${NC}"
