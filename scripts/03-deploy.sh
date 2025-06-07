#!/bin/bash

# Kubernetes 모니터링 서비스 - 배포 스크립트

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

echo "🚀 Kubernetes 배포를 시작합니다..."

# 프로젝트 루트 디렉토리 확인
if [ ! -f "README.md" ] || [ ! -d "deploy" ]; then
    print_error "프로젝트 루트 디렉토리에서 실행해주세요."
    exit 1
fi

# kubectl 연결 확인
print_step "Kubernetes 클러스터 연결 확인..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    print_error "Kubernetes 클러스터에 연결할 수 없습니다. Minikube가 실행 중인지 확인하세요."
    exit 1
fi
print_success "Kubernetes 클러스터 연결 확인 완료"

# 기존 배포 정리 (선택사항)
print_step "기존 배포 확인 및 정리..."
if kubectl get deployment monitor-api > /dev/null 2>&1; then
    print_warning "기존 배포를 발견했습니다. 삭제 후 재배포합니다."
    kubectl delete -f deploy/monitor.yaml --ignore-not-found=true
    sleep 5
fi

# 매니페스트 적용
print_step "Kubernetes 매니페스트 적용 중..."
cd deploy
if [ ! -f "monitor.yaml" ]; then
    print_error "deploy/monitor.yaml 파일이 없습니다."
    exit 1
fi

kubectl apply -f monitor.yaml
print_success "매니페스트 적용 완료"

cd ..

# 배포 상태 확인
print_step "배포 상태 확인 중..."
echo "DaemonSet, Deployment, Service 상태:"
kubectl get daemonset,deployment,service

echo ""
echo "Collector 포드 상태:"
kubectl get pods -l app=resource-collector

echo ""
echo "API 서버 포드 상태:"
kubectl get pods -l app=monitor-api

# 포드가 Ready 상태가 될 때까지 대기
print_step "포드가 Ready 상태가 될 때까지 대기 중..."
kubectl wait --for=condition=ready pod -l app=resource-collector --timeout=300s
kubectl wait --for=condition=ready pod -l app=monitor-api --timeout=300s

print_success "모든 포드가 Ready 상태입니다"

# 서비스 정보 출력
print_step "서비스 접근 정보..."
MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: ${MINIKUBE_IP}"
echo "API 서버 접근 URL: http://${MINIKUBE_IP}:30080"
echo "Swagger UI: http://${MINIKUBE_IP}:30080/docs"

print_success "Kubernetes 배포가 완료되었습니다! 🎉" 