#!/bin/bash

# Kubernetes 모니터링 서비스 - 이미지 빌드 스크립트

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

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo "🔨 Docker 이미지 빌드를 시작합니다..."

# 프로젝트 루트 디렉토리 확인
if [ ! -f "README.md" ] || [ ! -d "collector" ] || [ ! -d "api" ]; then
    print_error "프로젝트 루트 디렉토리에서 실행해주세요."
    exit 1
fi

# Minikube 실행 상태 확인
print_step "Minikube 상태 확인..."
if ! minikube status > /dev/null 2>&1; then
    print_step "Minikube 시작 중..."
    minikube start --driver=docker --cpus=4 --memory=8192
    print_success "Minikube 시작 완료"
else
    print_success "Minikube가 이미 실행 중입니다"
fi

# Docker 환경을 Minikube로 설정
print_step "Docker 환경을 Minikube로 설정..."
eval $(minikube docker-env)
print_success "Docker 환경 설정 완료"

# Collector 이미지 빌드
print_step "Collector 이미지 빌드 중..."
cd collector
if [ ! -f "Dockerfile.collector" ]; then
    print_error "collector/Dockerfile.collector 파일이 없습니다."
    exit 1
fi

docker build -f Dockerfile.collector -t kubemonitor-collector:latest .
print_success "Collector 이미지 빌드 완료"

# API 서버 이미지 빌드
print_step "API 서버 이미지 빌드 중..."
cd ../api
if [ ! -f "Dockerfile.api" ]; then
    print_error "api/Dockerfile.api 파일이 없습니다."
    exit 1
fi

docker build -f Dockerfile.api -t kubemonitor-api:latest .
print_success "API 서버 이미지 빌드 완료"

cd ..

# 빌드된 이미지 확인
print_step "빌드된 이미지 확인..."
echo "Minikube 내 이미지 목록:"
minikube image ls | grep kubemonitor || echo "kubemonitor 이미지를 찾을 수 없습니다."

print_success "모든 이미지 빌드가 완료되었습니다! 🎉" 