#!/bin/bash

# Kubernetes 모니터링 서비스 - 통합 설치 스크립트
# Clean Ubuntu 22.04 LTS에서 전체 환경을 자동으로 구축합니다.

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_header() {
    echo -e "${PURPLE}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🚀 Kubernetes 모니터링 서비스 자동 설치"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${NC}"
}

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

# 스크립트 시작
print_header

# 실행 옵션 확인
SKIP_ENV_SETUP=false
SKIP_BUILD=false
SKIP_DEPLOY=false
SKIP_TEST=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-env)
            SKIP_ENV_SETUP=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        --skip-test)
            SKIP_TEST=true
            shift
            ;;
        --help)
            echo "사용법: $0 [옵션]"
            echo "옵션:"
            echo "  --skip-env     개발 환경 구축 단계 건너뛰기"
            echo "  --skip-build   이미지 빌드 단계 건너뛰기"
            echo "  --skip-deploy  배포 단계 건너뛰기"
            echo "  --skip-test    테스트 단계 건너뛰기"
            echo "  --help         이 도움말 표시"
            exit 0
            ;;
        *)
            print_error "알 수 없는 옵션: $1"
            echo "도움말을 보려면 --help를 사용하세요."
            exit 1
            ;;
    esac
done

# 스크립트 디렉토리 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "프로젝트 루트: ${PROJECT_ROOT}"
cd "$PROJECT_ROOT"

# 1단계: 개발 환경 구축
if [ "$SKIP_ENV_SETUP" = false ]; then
    echo -e "\n${PURPLE}🔧 1단계: 개발 환경 구축${NC}"
    if [ -f "scripts/01-setup-environment.sh" ]; then
        bash scripts/01-setup-environment.sh
        print_success "개발 환경 구축 완료"
        
        # Docker 그룹 적용
        print_warning "Docker 그룹 변경사항 적용 중..."
        newgrp docker << EONG
        echo "Docker 그룹 적용 완료"
EONG
    else
        print_error "scripts/01-setup-environment.sh 파일을 찾을 수 없습니다."
        exit 1
    fi
else
    print_warning "개발 환경 구축 단계를 건너뜁니다."
fi

# 2단계: 이미지 빌드
if [ "$SKIP_BUILD" = false ]; then
    echo -e "\n${PURPLE}🔨 2단계: Docker 이미지 빌드${NC}"
    if [ -f "scripts/02-build-images.sh" ]; then
        bash scripts/02-build-images.sh
        print_success "이미지 빌드 완료"
    else
        print_error "scripts/02-build-images.sh 파일을 찾을 수 없습니다."
        exit 1
    fi
else
    print_warning "이미지 빌드 단계를 건너뜁니다."
fi

# 3단계: Kubernetes 배포
if [ "$SKIP_DEPLOY" = false ]; then
    echo -e "\n${PURPLE}🚀 3단계: Kubernetes 배포${NC}"
    if [ -f "scripts/03-deploy.sh" ]; then
        bash scripts/03-deploy.sh
        print_success "Kubernetes 배포 완료"
    else
        print_error "scripts/03-deploy.sh 파일을 찾을 수 없습니다."
        exit 1
    fi
else
    print_warning "배포 단계를 건너뜁니다."
fi

# 4단계: 테스트
if [ "$SKIP_TEST" = false ]; then
    echo -e "\n${PURPLE}🧪 4단계: 시스템 테스트${NC}"
    if [ -f "scripts/04-test.sh" ]; then
        bash scripts/04-test.sh
        print_success "시스템 테스트 완료"
    else
        print_error "scripts/04-test.sh 파일을 찾을 수 없습니다."
        exit 1
    fi
else
    print_warning "테스트 단계를 건너뜁니다."
fi

# 완료 메시지
echo -e "\n${PURPLE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🎉 Kubernetes 모니터링 서비스 설치 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "MINIKUBE_IP_NOT_FOUND")
if [ "$MINIKUBE_IP" != "MINIKUBE_IP_NOT_FOUND" ]; then
    echo "🌐 API 서버: http://${MINIKUBE_IP}:30080"
    echo "📊 Swagger UI: http://${MINIKUBE_IP}:30080/docs"
    echo "🔍 Health Check: http://${MINIKUBE_IP}:30080/health"
fi

echo ""
echo "📚 유용한 명령어:"
echo "  kubectl get pods                    # 포드 상태 확인"
echo "  kubectl logs -l app=resource-collector  # Collector 로그"
echo "  kubectl logs -l app=monitor-api     # API 서버 로그"
echo "  minikube dashboard                  # Kubernetes 대시보드"

print_success "설치가 성공적으로 완료되었습니다! 🚀" 