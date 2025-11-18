#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "================================================"
echo "   ComfyUI Stable Diffusion 배포"
echo "================================================"
echo -e "${NC}"

# GPU 확인
echo -e "${YELLOW}[1/5] GPU 확인 중...${NC}"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    echo -e "${GREEN}✓ GPU 감지됨${NC}"
else
    echo -e "${RED}✗ GPU를 찾을 수 없습니다${NC}"
    echo "GPU 없이 계속하려면 CPU 버전을 사용하세요."
    exit 1
fi
echo ""

# Namespace 확인
echo -e "${YELLOW}[2/5] Namespace 확인 중...${NC}"
if ! kubectl get namespace ai-serving &> /dev/null; then
    echo "ai-serving namespace를 생성합니다..."
    kubectl create namespace ai-serving
fi
echo -e "${GREEN}✓ Namespace 준비 완료${NC}"
echo ""

# 기존 SD 배포 삭제 (있다면)
echo -e "${YELLOW}[3/5] 기존 배포 확인 중...${NC}"
if kubectl get deployment sd-serving -n ai-serving &> /dev/null; then
    echo "기존 SD 배포를 삭제합니다..."
    kubectl delete deployment sd-serving -n ai-serving
    sleep 5
fi
echo -e "${GREEN}✓ 준비 완료${NC}"
echo ""

# ComfyUI 배포
echo -e "${YELLOW}[4/5] ComfyUI 배포 중...${NC}"
kubectl apply -f sd-deployment-comfyui-gpu.yaml

echo "ComfyUI Pod가 생성될 때까지 대기 중..."
for i in {1..60}; do
    POD_COUNT=$(kubectl get pods -n ai-serving -l app=sd-serving --no-headers 2>/dev/null | wc -l)
    if [ "$POD_COUNT" -gt 0 ]; then
        echo "✓ ComfyUI Pod가 생성되었습니다."
        break
    fi
    echo "  대기 중... ($i/60)"
    sleep 5
done

# Pod 준비 대기
kubectl wait --namespace ai-serving \
  --for=condition=ready pod \
  --selector=app=sd-serving \
  --timeout=600s || {
    echo -e "${YELLOW}경고: Pod 준비 시간이 초과되었습니다. 수동으로 확인하세요.${NC}"
  }

echo -e "${GREEN}✓ ComfyUI 배포 완료${NC}"
echo ""

# Ingress 업데이트
echo -e "${YELLOW}[5/5] Ingress 확인 중...${NC}"
if kubectl get ingress sd-ingress -n ai-serving &> /dev/null; then
    echo -e "${GREEN}✓ Ingress가 이미 설정되어 있습니다${NC}"
else
    echo "Ingress를 생성합니다..."
    kubectl apply -f ingress.yaml
fi
echo ""

# 배포 상태 확인
echo -e "${BLUE}=== 배포 상태 ===${NC}"
echo "Pods:"
kubectl get pods -n ai-serving -l app=sd-serving
echo ""
echo "Services:"
kubectl get svc -n ai-serving sd-service
echo ""
echo "Ingress:"
kubectl get ingress -n ai-serving sd-ingress
echo ""

# Minikube IP
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "Minikube가 실행 중이 아닙니다")

echo -e "${BLUE}"
echo "================================================"
echo "   ComfyUI 배포 완료!"
echo "================================================"
echo -e "${NC}"

echo "접속 정보:"
echo -e "   엔드포인트: ${GREEN}https://sd.ai-serving.local${NC}"
echo -e "   Minikube IP: ${BLUE}${MINIKUBE_IP}${NC}"
echo -e "   ✓ GPU 가속 활성화됨"
echo ""

echo "포트 포워딩 (선택):"
echo -e "   ${BLUE}kubectl port-forward -n ai-serving --address 0.0.0.0 svc/sd-service 8188:80${NC}"
echo ""

echo "브라우저 접속:"
echo -e "   ${BLUE}http://<YOUR-IP>:8188${NC}"
echo ""

echo "Pod 로그 확인:"
POD_NAME=$(kubectl get pod -n ai-serving -l app=sd-serving -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    echo -e "   ${BLUE}kubectl logs -n ai-serving $POD_NAME -f${NC}"
fi
echo ""

echo "GPU 사용 확인:"
if [ -n "$POD_NAME" ]; then
    echo -e "   ${BLUE}kubectl exec -n ai-serving $POD_NAME -- nvidia-smi${NC}"
fi
echo ""

echo -e "${YELLOW}주의: ComfyUI는 초기 시작 시 모델을 다운로드합니다 (수 분 소요)${NC}"
echo -e "${YELLOW}Pod 로그를 확인하여 진행 상황을 모니터링하세요.${NC}"