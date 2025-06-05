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
    echo "포드 목록 API 응답:"
    curl -s "${API_URL}/api/pods" | jq '.' || curl -s "${API_URL}/api/pods"
    print_success "포드 메트릭 API 테스트 통과"
else
    print_warning "포드 메트릭 API 응답 없음"
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
    curl -s "${API_URL}/api/nodes/${NODE_NAME}" | jq '.cpu_usage_percent' || echo "CPU 사용률 정보 확인 불가"
    print_success "부하 테스트 완료"
else
    print_warning "부하 테스트 후 메트릭 확인 실패"
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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

print_success "모든 테스트가 완료되었습니다! 🎉" 