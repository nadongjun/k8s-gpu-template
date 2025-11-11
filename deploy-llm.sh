#!/bin/bash

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   LLM 모델 배포 (vLLM + Mistral 7B)${NC}"
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

# Stable Diffusion 배포 확인 및 제거
echo -e "${YELLOW}[1/4] 기존 배포 확인 중...${NC}"
if kubectl get deployment sd-serving -n ai-serving > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Stable Diffusion이 실행 중입니다. 제거합니다...${NC}"
    kubectl delete deployment sd-serving -n ai-serving
    kubectl delete ingress sd-ingress -n ai-serving 2>/dev/null || true
    echo "제거 완료를 기다리는 중..."
    sleep 5
    echo -e "${GREEN}✓ Stable Diffusion 제거 완료${NC}"
else
    echo -e "${GREEN}✓ 제거할 배포가 없습니다.${NC}"
fi
echo ""

# LLM이 이미 실행 중인지 확인
if kubectl get deployment llm-serving -n ai-serving > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ LLM이 이미 실행 중입니다. 재배포합니다...${NC}"
    kubectl delete deployment llm-serving -n ai-serving
    sleep 3
fi

# LLM 배포
echo -e "${YELLOW}[2/4] LLM 배포 중 (vLLM)...${NC}"
if [ "$USE_GPU" = "true" ]; then
    echo -e "${GREEN}   ✓ GPU 가속 모드로 배포${NC}"
    kubectl apply -f llm-deployment-vllm-gpu.yaml
else
    echo -e "${YELLOW}   ⚠ CPU 모드로 배포 (성능 제한)${NC}"
    kubectl apply -f llm-deployment-vllm.yaml
fi

echo "   모델 다운로드 시작: mistralai/Mistral-7B-Instruct-v0.2 (~14GB)"
echo ""

# Pod 생성 대기
echo -e "${YELLOW}[3/4] LLM Pod 생성 대기 중...${NC}"
for i in {1..30}; do
  POD_COUNT=$(kubectl get pods -n ai-serving -l app=llm-serving --no-headers 2>/dev/null | wc -l)
  if [ "$POD_COUNT" -gt 0 ]; then
    echo "✓ LLM Pod가 생성되었습니다."
    break
  fi
  echo "  대기 중... ($i/30)"
  sleep 5
done

# Pod 준비 대기 (모델 다운로드 포함)
echo ""
echo -e "${YELLOW}LLM Pod가 준비될 때까지 대기 중...${NC}"
echo -e "${YELLOW}⏳ 모델 다운로드 시간이 포함되어 10-20분 소요될 수 있습니다.${NC}"
echo ""
echo "진행 상황을 보려면 다른 터미널에서:"
echo "  ${BLUE}kubectl logs -n ai-serving -l app=llm-serving -f${NC}"
echo ""

kubectl wait --namespace ai-serving \
  --for=condition=ready pod \
  --selector=app=llm-serving \
  --timeout=1200s || {
    echo -e "${RED}✗ LLM Pod 대기 시간 초과${NC}"
    echo ""
    echo "문제 해결:"
    echo "  1. Pod 상태 확인: kubectl get pods -n ai-serving"
    echo "  2. Pod 로그 확인: kubectl logs -n ai-serving -l app=llm-serving"
    echo "  3. Pod 상세 정보: kubectl describe pod -n ai-serving -l app=llm-serving"
    exit 1
  }

echo -e "${GREEN}✓ LLM Pod 준비 완료${NC}"
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
echo -e "${GREEN}   LLM 배포 완료!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}접속 정보:${NC}"
echo ""
echo "   엔드포인트: ${GREEN}https://llm.ai-serving.local${NC}"
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
echo "   # Health Check"
echo "   ${BLUE}curl -k https://llm.ai-serving.local/health${NC}"
echo ""
echo "   # 모델 목록"
echo "   ${BLUE}curl -k https://llm.ai-serving.local/v1/models${NC}"
echo ""
echo "   # 채팅 (OpenAI 호환)"
echo "   ${BLUE}curl -k https://llm.ai-serving.local/v1/chat/completions \\${NC}"
echo "   ${BLUE}  -H 'Content-Type: application/json' \\${NC}"
echo "   ${BLUE}  -d '{${NC}"
echo "   ${BLUE}    \"model\": \"mistralai/Mistral-7B-Instruct-v0.2\",${NC}"
echo "   ${BLUE}    \"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}],${NC}"
echo "   ${BLUE}    \"max_tokens\": 100${NC}"
echo "   ${BLUE}  }'${NC}"
echo ""
echo -e "${YELLOW}상세 테스트:${NC}"
echo "   ${GREEN}./test-api-vllm.sh${NC}"
echo ""
echo -e "${YELLOW}GPU 사용량 확인 (GPU 사용 시):${NC}"
if [ "$USE_GPU" = "true" ]; then
    POD_NAME=$(kubectl get pod -n ai-serving -l app=llm-serving -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD_NAME" ]; then
        echo "   ${BLUE}kubectl exec -n ai-serving ${POD_NAME} -- nvidia-smi${NC}"
    fi
fi
echo ""
echo -e "${GREEN}================================================${NC}"
