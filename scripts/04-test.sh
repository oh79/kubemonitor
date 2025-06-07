#!/bin/bash

# Kubernetes 모니터링 서비스 - 테스트 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo "🧪 API 서버 테스트를 시작합니다..."

# Minikube IP 가져오기
MINIKUBE_IP=$(minikube ip)
API_URL="http://${MINIKUBE_IP}:30080"

print_step "API 서버 연결 테스트..."

# Health check
print_step "Health Check 테스트..."
if curl -s "${API_URL}/health" > /dev/null; then
    HEALTH_RESPONSE=$(curl -s "${API_URL}/health")
    echo "Health Check 응답: ${HEALTH_RESPONSE}"
    print_success "Health Check 통과"
else
    print_error "Health Check 실패"
    exit 1
fi

# 노드 메트릭 테스트
print_step "노드 메트릭 API 테스트..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "테스트 대상 노드: ${NODE_NAME}"

if curl -s "${API_URL}/api/nodes" > /dev/null; then
    echo "노드 목록 API 응답:"
    curl -s "${API_URL}/api/nodes" | jq '.' || curl -s "${API_URL}/api/nodes"
    print_success "노드 메트릭 API 테스트 통과"
else
    print_warning "노드 메트릭 API 응답 없음 (데이터 수집 대기 중일 수 있음)"
fi

# 특정 노드 메트릭 테스트
print_step "특정 노드 메트릭 테스트..."
if curl -s "${API_URL}/api/nodes/${NODE_NAME}" > /dev/null; then
    echo "특정 노드 메트릭 응답:"
    curl -s "${API_URL}/api/nodes/${NODE_NAME}" | jq '.' || curl -s "${API_URL}/api/nodes/${NODE_NAME}"
    print_success "특정 노드 메트릭 테스트 통과"
else
    print_warning "특정 노드 메트릭 응답 없음"
fi

# 포드 메트릭 테스트
print_step "포드 메트릭 API 테스트..."
if curl -s "${API_URL}/api/pods" > /dev/null; then
    PODS_RESPONSE=$(curl -s "${API_URL}/api/pods")
    echo "포드 목록 API 응답:"
    echo "${PODS_RESPONSE}" | jq '.' || echo "${PODS_RESPONSE}"
    
    # 포드 개수 확인
    POD_COUNT=$(echo "${PODS_RESPONSE}" | jq 'length' 2>/dev/null || echo "0")
    if [ "${POD_COUNT}" -gt 0 ]; then
        print_success "포드 메트릭 API 테스트 통과 (${POD_COUNT}개 포드 발견)"
    else
        print_warning "포드 메트릭 데이터 없음 (수집 대기 중일 수 있음)"
    fi
else
    print_warning "포드 메트릭 API 응답 없음"
fi

# 네임스페이스 메트릭 테스트
print_step "네임스페이스 메트릭 API 테스트..."
if curl -s "${API_URL}/api/namespaces" > /dev/null; then
    NAMESPACES_RESPONSE=$(curl -s "${API_URL}/api/namespaces")
    echo "네임스페이스 목록 API 응답:"
    echo "${NAMESPACES_RESPONSE}" | jq '.' || echo "${NAMESPACES_RESPONSE}"
    
    # 네임스페이스 개수 확인
    NS_COUNT=$(echo "${NAMESPACES_RESPONSE}" | jq 'length' 2>/dev/null || echo "0")
    if [ "${NS_COUNT}" -gt 0 ]; then
        print_success "네임스페이스 메트릭 API 테스트 통과 (${NS_COUNT}개 네임스페이스 발견)"
    else
        print_warning "네임스페이스 메트릭 데이터 없음"
    fi
else
    print_warning "네임스페이스 메트릭 API 응답 없음"
fi

# 성능 테스트 포드 생성
print_step "성능 테스트를 위한 부하 생성..."
echo "CPU 부하 테스트 포드 생성 중..."
kubectl run stress-test --image=progrium/stress --restart=Never -- stress --cpu 1 --timeout 30s || true

echo "30초 대기 후 메트릭 변화 확인..."
sleep 30

print_step "부하 테스트 후 메트릭 확인..."
if curl -s "${API_URL}/api/nodes/${NODE_NAME}" > /dev/null; then
    echo "부하 테스트 후 노드 메트릭:"
    NODE_RESPONSE=$(curl -s "${API_URL}/api/nodes/${NODE_NAME}")
    
    # CPU 사용률 확인 (수정된 필드명 사용)
    CPU_USAGE=$(echo "${NODE_RESPONSE}" | jq -r '.[0].cpu_usage_percent // .[0].cpu_usage // "null"' 2>/dev/null || echo "null")
    if [ "${CPU_USAGE}" != "null" ] && [ "${CPU_USAGE}" != "" ]; then
        echo "CPU 사용률: ${CPU_USAGE}%"
        print_success "부하 테스트 완료 - CPU 사용률 측정됨"
    else
        echo "CPU 사용률 정보 확인 불가 (첫 번째 수집 주기일 수 있음)"
        print_warning "CPU 사용률 측정 실패"
    fi
    
    # 전체 응답 출력
    echo "전체 노드 메트릭:"
    echo "${NODE_RESPONSE}" | jq '.' || echo "${NODE_RESPONSE}"
else
    print_warning "부하 테스트 후 메트릭 확인 실패"
fi

# 시계열 조회 테스트
print_step "시계열 조회 테스트..."
if curl -s "${API_URL}/api/nodes/${NODE_NAME}?window=60" > /dev/null; then
    TIMESERIES_RESPONSE=$(curl -s "${API_URL}/api/nodes/${NODE_NAME}?window=60")
    TIMESERIES_COUNT=$(echo "${TIMESERIES_RESPONSE}" | jq 'length' 2>/dev/null || echo "0")
    echo "60초간 시계열 데이터: ${TIMESERIES_COUNT}개 포인트"
    if [ "${TIMESERIES_COUNT}" -gt 0 ]; then
        print_success "시계열 조회 테스트 통과"
    else
        print_warning "시계열 데이터 없음"
    fi
else
    print_warning "시계열 조회 실패"
fi

# 테스트 포드 정리
print_step "테스트 포드 정리..."
kubectl delete pod stress-test --ignore-not-found=true

# 접근 정보 출력
print_step "서비스 접근 정보"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 API 서버: ${API_URL}"
echo "📊 Swagger UI: ${API_URL}/docs"
echo "🔍 Health Check: ${API_URL}/health"
echo "📈 노드 메트릭: ${API_URL}/api/nodes"
echo "🏷️  포드 메트릭: ${API_URL}/api/pods"
echo "📦 네임스페이스: ${API_URL}/api/namespaces"
echo "🔄 시계열 조회: ${API_URL}/api/nodes/${NODE_NAME}?window=60"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

print_success "모든 테스트가 완료되었습니다! 🎉"

# 디버깅을 위한 로그 확인 추가
print_step "Collector 로그 확인..."
echo "최근 Collector 로그:"
kubectl logs -l app=resource-collector --tail=20

print_step "API 서버 로그 확인..."
echo "최근 API 서버 로그:"
kubectl logs -l app=monitor-api --tail=20

# 포드 상태 상세 확인
print_step "포드 상태 상세 확인..."
kubectl get pods -o wide
kubectl describe pods -l app=resource-collector 