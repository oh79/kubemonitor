#!/bin/bash

# cgroup 경로 디버깅 스크립트
# 이 스크립트는 Kubernetes 환경에서 cgroup 경로 문제를 진단하고 해결하는데 도움을 줍니다.

set -e

echo "=========================================="
echo "cgroup 경로 디버깅 스크립트 시작"
echo "=========================================="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수들
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1단계: 현재 실행 중인 포드 정보 확인
echo ""
echo "=========================================="
echo "1단계: 현재 실행 중인 포드 정보 확인"
echo "=========================================="

log_info "현재 포드 목록과 UID 확인 중..."
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.uid}{"\n"}{end}' > /tmp/pod_list.txt

if [ -s /tmp/pod_list.txt ]; then
    log_success "포드 목록 조회 성공:"
    cat /tmp/pod_list.txt
    POD_COUNT=$(wc -l < /tmp/pod_list.txt)
    log_info "총 ${POD_COUNT}개의 포드 발견"
else
    log_error "포드를 찾을 수 없습니다. kubectl 권한을 확인하세요."
    exit 1
fi

# collector 포드 확인
COLLECTOR_POD=$(kubectl get pods -l app=resource-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$COLLECTOR_POD" ]; then
    log_error "resource-collector 포드를 찾을 수 없습니다."
    exit 1
fi
log_success "Collector 포드 발견: $COLLECTOR_POD"

# 2단계: 실제 cgroup 구조 탐색
echo ""
echo "=========================================="
echo "2단계: 실제 cgroup 구조 탐색"
echo "=========================================="

log_info "cgroup 구조 확인 중..."
kubectl exec -it $COLLECTOR_POD -- find /sys/fs/cgroup -name "*pod*" -type d 2>/dev/null | head -20 > /tmp/cgroup_structure.txt

if [ -s /tmp/cgroup_structure.txt ]; then
    log_success "cgroup 포드 디렉토리 발견:"
    cat /tmp/cgroup_structure.txt
else
    log_warning "포드 관련 cgroup 디렉토리를 찾을 수 없습니다."
fi

# cgroup 버전 확인
log_info "cgroup 버전 확인 중..."
if kubectl exec -it $COLLECTOR_POD -- ls -la /sys/fs/cgroup/cgroup.controllers >/dev/null 2>&1; then
    log_success "cgroup v2 감지됨"
    CGROUP_VERSION="v2"
else
    log_success "cgroup v1 감지됨"
    CGROUP_VERSION="v1"
fi

# 3단계: 특정 포드의 cgroup 경로 패턴 분석
echo ""
echo "=========================================="
echo "3단계: 특정 포드의 cgroup 경로 패턴 분석"
echo "=========================================="

# 첫 번째 포드 선택
FIRST_POD_INFO=$(head -1 /tmp/pod_list.txt)
POD_NAME=$(echo $FIRST_POD_INFO | awk '{print $1}')
POD_UID=$(echo $FIRST_POD_INFO | awk '{print $2}')

log_info "테스트 포드: $POD_NAME"
log_info "포드 UID: $POD_UID"

# UID를 언더스코어로 변환
POD_UID_UNDERSCORE=$(echo $POD_UID | tr '-' '_')
log_info "언더스코어 UID: $POD_UID_UNDERSCORE"

# 실제 cgroup 경로 확인
log_info "UID 기반 cgroup 경로 검색 중..."
kubectl exec -it $COLLECTOR_POD -- find /sys/fs/cgroup -name "*$POD_UID_UNDERSCORE*" -type d 2>/dev/null > /tmp/uid_paths.txt

if [ -s /tmp/uid_paths.txt ]; then
    log_success "UID 기반 경로 발견:"
    cat /tmp/uid_paths.txt
else
    log_warning "UID 기반 경로를 찾을 수 없습니다."
    
    # 하이픈 제거된 UID로도 시도
    POD_UID_NO_DASH=$(echo $POD_UID | tr -d '-')
    log_info "하이픈 제거 UID로 재시도: $POD_UID_NO_DASH"
    kubectl exec -it $COLLECTOR_POD -- find /sys/fs/cgroup -name "*$POD_UID_NO_DASH*" -type d 2>/dev/null > /tmp/uid_paths_no_dash.txt
    
    if [ -s /tmp/uid_paths_no_dash.txt ]; then
        log_success "하이픈 제거 UID 기반 경로 발견:"
        cat /tmp/uid_paths_no_dash.txt
    fi
fi

# 4단계: cgroup 버전 및 구조 확인
echo ""
echo "=========================================="
echo "4단계: cgroup 구조 상세 확인"
echo "=========================================="

if [ "$CGROUP_VERSION" = "v2" ]; then
    log_info "cgroup v2 구조 확인 중..."
    
    # kubepods 슬라이스 구조 확인
    log_info "kubepods.slice 구조:"
    kubectl exec -it $COLLECTOR_POD -- ls -la /sys/fs/cgroup/kubepods.slice/ 2>/dev/null || log_warning "kubepods.slice 접근 실패"
    
    # burstable과 besteffort 슬라이스 확인
    log_info "burstable 슬라이스의 포드들:"
    kubectl exec -it $COLLECTOR_POD -- ls -la /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/ 2>/dev/null | grep pod || log_warning "burstable 포드 없음"
    
    log_info "besteffort 슬라이스의 포드들:"
    kubectl exec -it $COLLECTOR_POD -- ls -la /sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/ 2>/dev/null | grep pod || log_warning "besteffort 포드 없음"
else
    log_info "cgroup v1 구조 확인 중..."
    kubectl exec -it $COLLECTOR_POD -- ls -la /sys/fs/cgroup/cpu/kubepods/ 2>/dev/null | grep pod || log_warning "v1 kubepods 구조 확인 실패"
fi

# 5단계: 패턴 매칭 테스트
echo ""
echo "=========================================="
echo "5단계: Python glob 패턴 매칭 테스트"
echo "=========================================="

log_info "Python으로 패턴 매칭 테스트 실행 중..."

# Python 테스트 스크립트 생성
cat > /tmp/test_patterns.py << 'EOF'
#!/usr/bin/env python3
import glob
import os
import sys

# 명령행 인수에서 UID 받기
if len(sys.argv) != 2:
    print("사용법: python3 test_patterns.py <POD_UID>")
    sys.exit(1)

uid = sys.argv[1]
uid_underscore = uid.replace('-', '_')
uid_no_dash = uid.replace('-', '')

print(f'원본 UID: {uid}')
print(f'언더스코어 UID: {uid_underscore}')
print(f'하이픈 제거 UID: {uid_no_dash}')
print('=' * 50)

# cgroup v2 패턴들
patterns_v2 = [
    f'/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod{uid_underscore}.slice',
    f'/sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod{uid_underscore}.slice',
    f'/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod{uid_no_dash}.slice',
    f'/sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod{uid_no_dash}.slice',
    f'/sys/fs/cgroup/kubepods.slice/kubepods-*-pod{uid_underscore}.slice',
    f'/sys/fs/cgroup/kubepods.slice/kubepods-*-pod{uid_no_dash}.slice',
    f'/sys/fs/cgroup/kubepods.slice/*pod{uid_underscore}*',
    f'/sys/fs/cgroup/kubepods.slice/*pod{uid_no_dash}*',
    f'/sys/fs/cgroup/kubepods.slice/*pod{uid}*',
]

# cgroup v1 패턴들
patterns_v1 = [
    f'/sys/fs/cgroup/cpu/kubepods/pod{uid}',
    f'/sys/fs/cgroup/memory/kubepods/pod{uid}',
    f'/sys/fs/cgroup/*/kubepods/pod{uid}',
]

# cgroup 버전 확인
is_v2 = os.path.exists('/sys/fs/cgroup/cgroup.controllers')
patterns = patterns_v2 if is_v2 else patterns_v1

print(f'cgroup 버전: {"v2" if is_v2 else "v1"}')
print('=' * 50)

found_paths = []
for i, pattern in enumerate(patterns, 1):
    matches = glob.glob(pattern)
    print(f'{i:2d}. 패턴: {pattern}')
    if matches:
        print(f'    ✓ 매치: {matches}')
        found_paths.extend(matches)
    else:
        print(f'    ✗ 매치 없음')
    print()

if found_paths:
    print('=' * 50)
    print('발견된 경로들:')
    for path in set(found_paths):
        print(f'  - {path}')
        # 메트릭 파일 존재 확인
        cpu_stat = os.path.join(path, 'cpu.stat')
        memory_current = os.path.join(path, 'memory.current')
        io_stat = os.path.join(path, 'io.stat')
        
        print(f'    cpu.stat: {"✓" if os.path.exists(cpu_stat) else "✗"}')
        print(f'    memory.current: {"✓" if os.path.exists(memory_current) else "✗"}')
        print(f'    io.stat: {"✓" if os.path.exists(io_stat) else "✗"}')
        print()
else:
    print('❌ 매칭되는 cgroup 경로를 찾을 수 없습니다!')
EOF

# Python 스크립트 실행
kubectl cp /tmp/test_patterns.py $COLLECTOR_POD:/tmp/test_patterns.py
kubectl exec -it $COLLECTOR_POD -- python3 /tmp/test_patterns.py "$POD_UID"

# 6단계: 실제 메트릭 파일 확인
echo ""
echo "=========================================="
echo "6단계: 실제 메트릭 파일 확인"
echo "=========================================="

log_info "발견된 cgroup 경로에서 메트릭 파일 확인 중..."

# 첫 번째로 발견된 경로 사용
CGROUP_PATH=$(kubectl exec -it $COLLECTOR_POD -- find /sys/fs/cgroup -name "*pod*" -type d 2>/dev/null | head -1 | tr -d '\r')

if [ -n "$CGROUP_PATH" ]; then
    log_success "테스트 cgroup 경로: $CGROUP_PATH"
    
    log_info "디렉토리 내용:"
    kubectl exec -it $COLLECTOR_POD -- ls -la "$CGROUP_PATH" 2>/dev/null || log_warning "디렉토리 접근 실패"
    
    log_info "CPU 통계 (cpu.stat):"
    kubectl exec -it $COLLECTOR_POD -- cat "$CGROUP_PATH/cpu.stat" 2>/dev/null | head -5 || log_warning "cpu.stat 읽기 실패"
    
    log_info "메모리 사용량 (memory.current):"
    kubectl exec -it $COLLECTOR_POD -- cat "$CGROUP_PATH/memory.current" 2>/dev/null || log_warning "memory.current 읽기 실패"
    
    log_info "I/O 통계 (io.stat):"
    kubectl exec -it $COLLECTOR_POD -- cat "$CGROUP_PATH/io.stat" 2>/dev/null | head -3 || log_warning "io.stat 읽기 실패"
else
    log_error "테스트할 cgroup 경로를 찾을 수 없습니다."
fi

# 7단계: collector 로그에서 실제 시도된 패턴 확인
echo ""
echo "=========================================="
echo "7단계: Collector 로그 분석"
echo "=========================================="

log_info "현재 collector 로그에서 cgroup 관련 메시지 확인 중..."
kubectl logs $COLLECTOR_POD --tail=50 | grep -E "(패턴 시도|cgroup|포드 메트릭)" || log_warning "관련 로그를 찾을 수 없습니다."

# 8단계: 권장 사항 및 수정 가이드
echo ""
echo "=========================================="
echo "8단계: 권장 사항 및 수정 가이드"
echo "=========================================="

log_info "분석 결과를 바탕으로 한 권장 사항:"

echo ""
echo "1. 발견된 실제 cgroup 패턴을 collector.py에 적용하세요:"
echo "   - 위의 Python 테스트에서 ✓ 표시된 패턴들을 사용"
echo "   - collector.py의 cgroup_patterns 배열을 수정"

echo ""
echo "2. 다음 명령으로 collector를 재배포하세요:"
echo "   cd /path/to/kubemonitor"
echo "   ./scripts/02-build-images.sh"
echo "   ./scripts/03-deploy.sh"

echo ""
echo "3. 배포 후 로그 확인:"
echo "   kubectl logs -f \$(kubectl get pods -l app=resource-collector -o jsonpath='{.items[0].metadata.name}')"

echo ""
echo "4. 만약 여전히 문제가 있다면:"
echo "   - DEBUG=true 환경변수로 collector 재배포"
echo "   - 이 스크립트를 다시 실행하여 추가 분석"

# 임시 파일 정리
rm -f /tmp/pod_list.txt /tmp/cgroup_structure.txt /tmp/uid_paths.txt /tmp/uid_paths_no_dash.txt /tmp/test_patterns.py

log_success "cgroup 디버깅 스크립트 완료!"
echo "==========================================" 