#!/bin/bash

# Kubernetes 모니터링 서비스 - 개발 환경 구축 스크립트
# Clean Ubuntu 22.04 LTS 기준

set -e  # 오류 발생 시 스크립트 중단

echo "🚀 Kubernetes 모니터링 서비스 개발 환경 구축을 시작합니다..."

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 1. 시스템 업데이트
print_step "시스템 패키지 업데이트 중..."
sudo apt-get update -y
sudo apt-get upgrade -y
print_success "시스템 업데이트 완료"

# 2. 필수 도구 설치
print_step "필수 도구 설치 중..."
sudo apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    vim \
    python3 \
    python3-pip \
    python3-venv \
    docker.io \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    tree
print_success "필수 도구 설치 완료"

# 3. Docker 설정
print_step "Docker 설정 중..."
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
print_success "Docker 설정 완료"

# 4. kubectl 설치
print_step "kubectl 설치 중..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
print_success "kubectl 설치 완료 (버전: ${KUBECTL_VERSION})"

# 5. Minikube 설치
print_step "Minikube 설치 중..."
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube-linux-amd64
sudo mv minikube-linux-amd64 /usr/local/bin/minikube
print_success "Minikube 설치 완료"

# 6. Helm 설치 (선택사항)
print_step "Helm 설치 중..."
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm -y
print_success "Helm 설치 완료"

# 7. 버전 확인
print_step "설치된 도구 버전 확인..."
echo "Docker: $(docker --version)"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || echo 'kubectl client version')"
echo "Minikube: $(minikube version --short)"
echo "Helm: $(helm version --short)"
echo "Python: $(python3 --version)"
echo "Git: $(git --version)"

print_warning "Docker 그룹 변경사항을 적용하려면 다음 명령어를 실행하거나 재로그인하세요:"
echo "newgrp docker"

print_success "개발 환경 구축이 완료되었습니다! 🎉" 