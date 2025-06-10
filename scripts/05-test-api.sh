#!/bin/bash

# API 테스트 스크립트
# 모든 쿠버네티스 모니터링 API 엔드포인트를 테스트하고 응답을 표시합니다

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# API 서버 URL
API_BASE_URL="http://192.168.49.2:30080"

# 실제 데이터 (kubectl로 확인된 정보)
NODE_NAME="minikube"
POD_NAME="monitor-api-bc867b8d8-8lv86"
NAMESPACE_DEFAULT="default"
NAMESPACE_KUBE_SYSTEM="kube-system"
DEPLOYMENT_NAME="monitor-api"

echo -e "${CYAN}🚀 Kubernetes 모니터링 API 테스트를 시작합니다...${NC}"
echo -e "${BLUE}API 서버: ${API_BASE_URL}${NC}"
echo ""

# API 호출 함수
call_api() {
    local method=$1
    local endpoint=$2
    local description=$3
    
    echo -e "${YELLOW}📋 테스트: ${description}${NC}"
    echo -e "${BLUE}   ${method} ${endpoint}${NC}"
    
    # HTTP 응답 코드와 응답 본문을 함께 가져오기
    response=$(curl -s -w "\n%{http_code}" "${API_BASE_URL}${endpoint}")
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}   ✅ 성공 (HTTP $http_code)${NC}"
        # JSON 응답을 예쁘게 포맷팅 (jq가 설치되어 있는 경우)
        if command -v jq &> /dev/null; then
            echo "$response_body" | jq . 2>/dev/null || echo "$response_body"
        else
            echo "$response_body"
        fi
    else
        echo -e "${RED}   ❌ 실패 (HTTP $http_code)${NC}"
        echo "   응답: $response_body"
    fi
    echo ""
}

# API 서버 상태 확인
echo -e "${CYAN}🔍 API 서버 상태 확인${NC}"
call_api "GET" "/health" "헬스 체크"

echo -e "${CYAN}📊 Swagger UI 접근 정보${NC}"
echo -e "${BLUE}   Swagger UI: ${API_BASE_URL}/docs${NC}"
echo ""

# 1. 노드 기준 API 테스트
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}1️⃣  노드 기준 API 테스트${NC}"
echo -e "${CYAN}========================================${NC}"

call_api "GET" "/api/nodes" "전체 노드 목록 및 리소스 사용량"
call_api "GET" "/api/nodes/${NODE_NAME}" "특정 노드의 리소스 사용량 (호스트 프로세스 포함)"
call_api "GET" "/api/nodes/${NODE_NAME}/pods" "노드에 할당된 모든 포드 목록 (포드 리소스만)"

# 2. 포드 기준 API 테스트  
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}2️⃣  포드 기준 API 테스트${NC}"
echo -e "${CYAN}========================================${NC}"

call_api "GET" "/api/pods" "전체 포드 목록 및 리소스 사용량"
call_api "GET" "/api/pods/${POD_NAME}" "특정 포드의 실시간 리소스 사용량"

# 3. 네임스페이스 기준 API 테스트
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}3️⃣  네임스페이스 기준 API 테스트${NC}"
echo -e "${CYAN}========================================${NC}"

call_api "GET" "/api/namespaces" "전체 네임스페이스 목록 및 리소스 사용량"
call_api "GET" "/api/namespaces/${NAMESPACE_DEFAULT}" "특정 네임스페이스의 리소스 사용량 (default)"
call_api "GET" "/api/namespaces/${NAMESPACE_DEFAULT}/pods" "네임스페이스의 포드 목록 (default)"
call_api "GET" "/api/namespaces/${NAMESPACE_KUBE_SYSTEM}" "특정 네임스페이스의 리소스 사용량 (kube-system)"
call_api "GET" "/api/namespaces/${NAMESPACE_KUBE_SYSTEM}/pods" "네임스페이스의 포드 목록 (kube-system)"

# 4. 디플로이먼트 기준 API 테스트
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}4️⃣  디플로이먼트 기준 API 테스트${NC}"
echo -e "${CYAN}========================================${NC}"

call_api "GET" "/api/namespaces/${NAMESPACE_DEFAULT}/deployments" "네임스페이스의 디플로이먼트 목록 (default)"
call_api "GET" "/api/namespaces/${NAMESPACE_DEFAULT}/deployments/${DEPLOYMENT_NAME}" "특정 디플로이먼트의 리소스 사용량"
call_api "GET" "/api/namespaces/${NAMESPACE_DEFAULT}/deployments/${DEPLOYMENT_NAME}/pods" "디플로이먼트의 포드 목록"
call_api "GET" "/api/namespaces/${NAMESPACE_KUBE_SYSTEM}/deployments" "네임스페이스의 디플로이먼트 목록 (kube-system)"
call_api "GET" "/api/namespaces/${NAMESPACE_KUBE_SYSTEM}/deployments/coredns" "특정 디플로이먼트의 리소스 사용량 (coredns)"

# 5. 시계열 조회 API 테스트 (window 파라미터 사용)
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}⏰  시계열 조회 API 테스트${NC}"
echo -e "${CYAN}========================================${NC}"

call_api "GET" "/api/nodes?window=60" "노드 시계열 조회 (60초간)"
call_api "GET" "/api/nodes/${NODE_NAME}?window=60" "특정 노드 시계열 조회 (60초간)"
call_api "GET" "/api/pods?window=60" "포드 시계열 조회 (60초간)"  
call_api "GET" "/api/pods/${POD_NAME}?window=60" "특정 포드 시계열 조회 (60초간)"
call_api "GET" "/api/namespaces?window=60" "네임스페이스 시계열 조회 (60초간)"
call_api "GET" "/api/namespaces/${NAMESPACE_DEFAULT}?window=60" "특정 네임스페이스 시계열 조회 (60초간)"

# 추가 시계열 테스트 (다른 시간 구간)
echo -e "${CYAN}⏰  시계열 조회 추가 테스트 (다른 시간 구간)${NC}"
call_api "GET" "/api/nodes?window=30" "노드 시계열 조회 (30초간)"
call_api "GET" "/api/pods?window=120" "포드 시계열 조회 (120초간)"

echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}✅ 모든 API 테스트가 완료되었습니다! 🎉${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${BLUE}📋 API 문서 접속:${NC}"
echo -e "${BLUE}   Swagger UI: ${API_BASE_URL}/docs${NC}"
echo -e "${BLUE}   ReDoc: ${API_BASE_URL}/redoc${NC}"
echo ""
echo -e "${YELLOW}💡 참고사항:${NC}"
echo -e "${YELLOW}   - 데이터가 없는 경우 빈 객체 {} 가 반환됩니다${NC}"
echo -e "${YELLOW}   - Collector가 메트릭을 수집하기까지 시간이 걸릴 수 있습니다${NC}"
echo -e "${YELLOW}   - 시계열 데이터는 window 시간 내의 모든 메트릭을 반환합니다${NC}" 