#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}    AI Serving API 테스트 (vLLM + SD)${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Minikube IP 확인
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "127.0.0.1")
echo -e "${YELLOW}Minikube IP: ${MINIKUBE_IP}${NC}"
echo ""

# /etc/hosts 확인
echo -e "${YELLOW}[1/5] /etc/hosts 설정 확인...${NC}"
if grep -q "llm.ai-serving.local" /etc/hosts && grep -q "sd.ai-serving.local" /etc/hosts; then
    echo -e "${GREEN}✓ /etc/hosts 설정이 확인되었습니다.${NC}"
else
    echo -e "${YELLOW}⚠ /etc/hosts에 다음을 추가해주세요:${NC}"
    echo "   ${MINIKUBE_IP}  llm.ai-serving.local"
    echo "   ${MINIKUBE_IP}  sd.ai-serving.local"
    echo ""
    echo "   빠른 추가 명령어:"
    echo "   echo \"${MINIKUBE_IP}  llm.ai-serving.local\" | sudo tee -a /etc/hosts"
    echo "   echo \"${MINIKUBE_IP}  sd.ai-serving.local\" | sudo tee -a /etc/hosts"
fi
echo ""

# LLM API Health Check
echo -e "${YELLOW}[2/5] LLM API (vLLM) Health Check...${NC}"
echo -n "GET https://llm.ai-serving.local/health ... "
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" https://llm.ai-serving.local/health)
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ 연결 성공 (HTTP $HTTP_CODE)${NC}"
else
    echo -e "${YELLOW}⚠ 연결 실패 (HTTP $HTTP_CODE) - Pod가 아직 준비 중일 수 있습니다${NC}"
fi
echo ""

# LLM 모델 목록 확인
echo -e "${YELLOW}[3/5] 사용 가능한 LLM 모델 확인...${NC}"
echo "GET https://llm.ai-serving.local/v1/models"
curl -sk https://llm.ai-serving.local/v1/models 2>/dev/null | jq -r '.data[]?.id // "모델 로드 중..."' 2>/dev/null || {
    echo "jq가 설치되지 않았거나 모델이 아직 로드 중입니다."
    curl -sk https://llm.ai-serving.local/v1/models 2>/dev/null
}
echo ""

# SD API 테스트
echo -e "${YELLOW}[4/5] Stable Diffusion API 연결 테스트...${NC}"
echo -n "GET https://sd.ai-serving.local ... "
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" https://sd.ai-serving.local)
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ 연결 성공 (HTTP $HTTP_CODE)${NC}"
else
    echo -e "${YELLOW}⚠ 연결 실패 (HTTP $HTTP_CODE)${NC}"
fi
echo ""

# Pod 상태 확인
echo -e "${YELLOW}[5/5] Pod 상태 확인...${NC}"
kubectl get pods -n ai-serving
echo ""

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}    vLLM 채팅 예제 (OpenAI 호환 API)${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "다음 명령어로 LLM과 대화할 수 있습니다:"
echo ""
echo -e "${GREEN}# 1. Completions API${NC}"
echo -e "${YELLOW}curl -k https://llm.ai-serving.local/v1/completions \\${NC}"
echo -e "${YELLOW}  -H 'Content-Type: application/json' \\${NC}"
echo -e "${YELLOW}  -d '{${NC}"
echo -e "${YELLOW}    \"model\": \"mistralai/Mistral-7B-Instruct-v0.2\",${NC}"
echo -e "${YELLOW}    \"prompt\": \"Explain quantum computing in simple terms\",${NC}"
echo -e "${YELLOW}    \"max_tokens\": 200,${NC}"
echo -e "${YELLOW}    \"temperature\": 0.7${NC}"
echo -e "${YELLOW}  }'${NC}"
echo ""
echo -e "${GREEN}# 2. Chat Completions API (권장)${NC}"
echo -e "${YELLOW}curl -k https://llm.ai-serving.local/v1/chat/completions \\${NC}"
echo -e "${YELLOW}  -H 'Content-Type: application/json' \\${NC}"
echo -e "${YELLOW}  -d '{${NC}"
echo -e "${YELLOW}    \"model\": \"mistralai/Mistral-7B-Instruct-v0.2\",${NC}"
echo -e "${YELLOW}    \"messages\": [${NC}"
echo -e "${YELLOW}      {\"role\": \"system\", \"content\": \"You are a helpful assistant.\"},${NC}"
echo -e "${YELLOW}      {\"role\": \"user\", \"content\": \"What is AI?\"}${NC}"
echo -e "${YELLOW}    ],${NC}"
echo -e "${YELLOW}    \"max_tokens\": 200,${NC}"
echo -e "${YELLOW}    \"temperature\": 0.7${NC}"
echo -e "${YELLOW}  }'${NC}"
echo ""
echo -e "${GREEN}# 3. Streaming (실시간 응답)${NC}"
echo -e "${YELLOW}curl -k https://llm.ai-serving.local/v1/chat/completions \\${NC}"
echo -e "${YELLOW}  -H 'Content-Type: application/json' \\${NC}"
echo -e "${YELLOW}  -d '{${NC}"
echo -e "${YELLOW}    \"model\": \"mistralai/Mistral-7B-Instruct-v0.2\",${NC}"
echo -e "${YELLOW}    \"messages\": [{\"role\": \"user\", \"content\": \"Hi!\"}],${NC}"
echo -e "${YELLOW}    \"stream\": true${NC}"
echo -e "${YELLOW}  }'${NC}"
echo ""

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}    Python 클라이언트 예제${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${YELLOW}from openai import OpenAI${NC}"
echo -e "${YELLOW}${NC}"
echo -e "${YELLOW}# vLLM을 OpenAI 클라이언트로 사용${NC}"
echo -e "${YELLOW}client = OpenAI(${NC}"
echo -e "${YELLOW}    base_url=\"https://llm.ai-serving.local/v1\",${NC}"
echo -e "${YELLOW}    api_key=\"dummy\"  # vLLM은 API 키가 필요없음${NC}"
echo -e "${YELLOW})${NC}"
echo -e "${YELLOW}${NC}"
echo -e "${YELLOW}response = client.chat.completions.create(${NC}"
echo -e "${YELLOW}    model=\"mistralai/Mistral-7B-Instruct-v0.2\",${NC}"
echo -e "${YELLOW}    messages=[${NC}"
echo -e "${YELLOW}        {\"role\": \"user\", \"content\": \"Hello!\"}${NC}"
echo -e "${YELLOW}    ]${NC}"
echo -e "${YELLOW})${NC}"
echo -e "${YELLOW}${NC}"
echo -e "${YELLOW}print(response.choices[0].message.content)${NC}"
echo ""

echo -e "${GREEN}테스트가 완료되었습니다!${NC}"
