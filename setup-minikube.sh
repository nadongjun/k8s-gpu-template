#!/bin/bash

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 시간 측정 시작
START_TIME=$(date +%s)

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}AI Serving 기본 환경 설치${NC}"
echo -e "${GREEN}(Minikube + GPU + Ingress + Cert-Manager)${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# 필수 도구 확인
echo -e "${YELLOW}[1/8] 필수 도구 확인 중...${NC}"
command -v minikube >/dev/null 2>&1 || { echo -e "${RED}minikube가 설치되지 않았습니다. 설치 후 다시 시도하세요.${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl이 설치되지 않았습니다. 설치 후 다시 시도하세요.${NC}"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm이 설치되지 않았습니다. 설치 후 다시 시도하세요.${NC}"; exit 1; }
echo -e "${GREEN}✓ 모든 필수 도구가 설치되어 있습니다.${NC}"
echo ""

# NVIDIA Driver 확인
echo -e "${YELLOW}[2/8] NVIDIA GPU 확인 중...${NC}"
if command -v nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓ NVIDIA Driver 발견${NC}"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    GPU_SUPPORT="--gpus all"
    USE_GPU=true
    echo ""
    echo "GPU 정보를 환경 파일에 저장..."
    echo "USE_GPU=true" > .ai-serving-config
else
    echo -e "${YELLOW}⚠ NVIDIA GPU를 찾을 수 없습니다. CPU 모드로 실행합니다.${NC}"
    GPU_SUPPORT=""
    USE_GPU=false
    echo "USE_GPU=false" > .ai-serving-config
fi
echo ""

# 기존 클러스터 삭제 (있는 경우)
if minikube status > /dev/null 2>&1; then
    echo -e "${YELLOW}기존 Minikube 클러스터 삭제 중...${NC}"
    minikube delete
    sleep 5
fi

# Minikube 클러스터 생성
echo -e "${YELLOW}[3/8] Minikube 클러스터 생성 중...${NC}"

# 시스템 메모리 확인
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
echo "시스템 총 메모리: ${TOTAL_MEM}MB"

# 사용 가능한 메모리의 75%를 할당 (안전한 범위)
SAFE_MEM=$((TOTAL_MEM * 75 / 100))
echo "Minikube에 할당할 메모리: ${SAFE_MEM}MB"

if [ "$USE_GPU" = true ]; then
    echo "GPU 지원으로 클러스터 생성..."
    minikube start \
        --driver=docker \
        --container-runtime=docker \
        --gpus all \
        --cpus=4 \
        --memory=${SAFE_MEM} \
        --disk-size=60g \
        --addons=ingress \
        --kubernetes-version=v1.28.0
else
    echo "CPU 모드로 클러스터 생성..."
    minikube start \
        --driver=docker \
        --cpus=4 \
        --memory=${SAFE_MEM} \
        --disk-size=50g \
        --addons=ingress \
        --kubernetes-version=v1.28.0
fi

kubectl config use-context minikube
echo -e "${GREEN}✓ Minikube 클러스터 생성 완료${NC}"
echo ""

# GPU Device Plugin 설치 (GPU가 있는 경우)
if [ "$USE_GPU" = true ]; then
    echo -e "${YELLOW}[4/8] NVIDIA Device Plugin 확인 중...${NC}"
    
    # Minikube addon으로 이미 설치되었는지 확인
    if kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system > /dev/null 2>&1; then
        echo -e "${GREEN}✓ NVIDIA Device Plugin이 이미 설치되어 있습니다 (Minikube addon)${NC}"
    else
        echo -e "${YELLOW}NVIDIA Device Plugin 설치 중...${NC}"
        kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
        
        echo "Device Plugin이 준비될 때까지 대기 중..."
        for i in {1..30}; do
            POD_COUNT=$(kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds --no-headers 2>/dev/null | wc -l)
            if [ "$POD_COUNT" -gt 0 ]; then
                echo "✓ Device Plugin Pod가 생성되었습니다."
                break
            fi
            echo "  대기 중... ($i/30)"
            sleep 5
        done
    fi
    
    # Pod 준비 대기
    kubectl wait --namespace kube-system \
      --for=condition=ready pod \
      --selector=name=nvidia-device-plugin-ds \
      --timeout=300s 2>/dev/null || {
        echo -e "${YELLOW}경고: Device Plugin 대기 시간 초과${NC}"
      }
    echo -e "${GREEN}✓ NVIDIA Device Plugin 준비 완료${NC}"
    echo ""
    
    # GPU 리소스 확인
    echo "=== GPU 리소스 확인 ==="
    kubectl get nodes -o json | jq -r '.items[0].status.capacity | to_entries[] | select(.key | contains("nvidia")) | "\(.key): \(.value)"' 2>/dev/null || {
        kubectl describe nodes | grep -A 5 "Capacity:" | grep nvidia
    }
    echo ""
else
    echo -e "${YELLOW}[4/8] GPU 미지원 - Device Plugin 설치 건너뜀${NC}"
    echo ""
fi

# Ingress 활성화 확인
echo -e "${YELLOW}[5/8] Ingress Controller 확인 중...${NC}"
echo "Ingress Controller Pod가 생성될 때까지 대기 중..."
for i in {1..24}; do
  POD_COUNT=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | wc -l)
  if [ "$POD_COUNT" -gt 0 ]; then
    echo "✓ Ingress Controller Pod가 생성되었습니다."
    break
  fi
  echo "  대기 중... ($i/24)"
  sleep 5
done

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s || {
    echo -e "${YELLOW}경고: Ingress Controller 대기 시간 초과${NC}"
  }
echo -e "${GREEN}✓ Ingress Controller 준비 완료${NC}"
echo ""

# cert-manager 설치
echo -e "${YELLOW}[6/8] cert-manager 설치 중...${NC}"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

echo "cert-manager Pod가 생성될 때까지 대기 중..."
for i in {1..24}; do
  POD_COUNT=$(kubectl get pods -n cert-manager -l app.kubernetes.io/instance=cert-manager --no-headers 2>/dev/null | wc -l)
  if [ "$POD_COUNT" -gt 0 ]; then
    echo "✓ cert-manager Pod가 생성되었습니다."
    break
  fi
  echo "  대기 중... ($i/24)"
  sleep 5
done

kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=300s || {
    echo -e "${YELLOW}경고: cert-manager 대기 시간 초과${NC}"
  }
echo -e "${GREEN}✓ cert-manager 설치 완료${NC}"
echo ""

# Namespace 및 인증서 생성
echo -e "${YELLOW}[7/8] Namespace 및 인증서 설정 중...${NC}"
kubectl apply -f certificates.yaml
sleep 15  # 인증서 생성 대기

# 인증서 생성 확인
echo "인증서 생성 확인 중..."
for i in {1..10}; do
    CERT_READY=$(kubectl get certificate -n ai-serving llm-tls-cert -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$CERT_READY" = "True" ]; then
        echo "✓ LLM 인증서 생성 완료"
        break
    fi
    echo "  대기 중... ($i/10)"
    sleep 3
done

echo -e "${GREEN}✓ Namespace 및 인증서 설정 완료${NC}"
echo ""

# CA 인증서 추출
echo -e "${YELLOW}[8/8] CA 인증서 추출 중...${NC}"
kubectl get secret ai-serving-ca-secret -n ai-serving -o jsonpath='{.data.ca\.crt}' | base64 -d > ca-cert.crt
echo -e "${GREEN}✓ CA 인증서가 ca-cert.crt에 저장되었습니다.${NC}"
echo ""

# 배포 상태 확인
echo "=== 현재 클러스터 상태 ==="
echo ""
echo "Nodes:"
kubectl get nodes
echo ""
echo "Namespaces:"
kubectl get ns | grep -E "NAME|ai-serving|cert-manager|ingress"
echo ""
echo "Certificates:"
kubectl get certificate -n ai-serving
echo ""

# 시간 측정 종료
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED_TIME / 60))
SECONDS=$((ELAPSED_TIME % 60))

# Minikube IP 확인
MINIKUBE_IP=$(minikube ip)

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}기본 환경 설치 완료! 총 소요 시간: ${MINUTES}분 ${SECONDS}초${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${BLUE}Minikube IP: ${MINIKUBE_IP}${NC}"
echo ""
if [ "$USE_GPU" = true ]; then
    echo -e "${GREEN}✓ GPU 지원 활성화됨${NC}"
else
    echo -e "${YELLOW}⚠ CPU 모드로 실행 중${NC}"
fi
echo ""
echo -e "${YELLOW}다음 단계:${NC}"
echo ""
echo "1. /etc/hosts 파일 설정:"
echo "   echo \"${MINIKUBE_IP}  llm.ai-serving.local\" | sudo tee -a /etc/hosts"
echo "   echo \"${MINIKUBE_IP}  sd.ai-serving.local\" | sudo tee -a /etc/hosts"
echo ""
echo "2. LLM 모델 배포:"
echo "   ${GREEN}./deploy-llm.sh${NC}"
echo ""
echo "3. Stable Diffusion 배포:"
echo "   ${GREEN}./deploy-sd.sh${NC}"
echo ""
echo "참고: GPU는 한 번에 하나의 모델만 실행됩니다."
echo "      다른 모델을 배포하면 기존 모델은 자동으로 제거됩니다."
echo ""
echo -e "${GREEN}================================================${NC}"