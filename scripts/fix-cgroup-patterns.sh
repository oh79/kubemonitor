#!/bin/bash

# cgroup 패턴 자동 수정 스크립트
# 실제 작동하는 cgroup 패턴을 collector.py에 적용

echo "=========================================="
echo "cgroup 패턴 자동 수정 스크립트"
echo "=========================================="

# 현재 디렉토리 확인
if [ ! -f "collector/collector.py" ]; then
    echo "❌ collector/collector.py 파일을 찾을 수 없습니다."
    echo "   kubemonitor 프로젝트 루트 디렉토리에서 실행하세요."
    exit 1
fi

# collector 포드 확인
COLLECTOR_POD=$(kubectl get pods -l app=resource-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$COLLECTOR_POD" ]; then
    echo "❌ resource-collector 포드를 찾을 수 없습니다."
    echo "   먼저 애플리케이션을 배포하세요: ./scripts/03-deploy.sh"
    exit 1
fi

echo "✅ Collector 포드: $COLLECTOR_POD"

# 테스트 포드 UID 가져오기
POD_UID=$(kubectl get pods -o jsonpath='{.items[0].metadata.uid}' 2>/dev/null)
if [ -z "$POD_UID" ]; then
    echo "❌ 테스트할 포드를 찾을 수 없습니다."
    exit 1
fi

echo "🔍 테스트 포드 UID: $POD_UID"

# 실제 작동하는 패턴 찾기
echo "🔍 실제 작동하는 cgroup 패턴 검색 중..."

cat > /tmp/find_working_patterns.py << EOF
import glob
import os

uid = "$POD_UID"
uid_underscore = uid.replace('-', '_')
uid_no_dash = uid.replace('-', '')

# 테스트할 패턴들 (우선순위 순)
test_patterns = [
    f"/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod{uid_underscore}.slice",
    f"/sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod{uid_underscore}.slice",
    f"/sys/fs/cgroup/kubepods.slice/kubepods-guaranteed.slice/kubepods-guaranteed-pod{uid_underscore}.slice",
    f"/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod{uid_no_dash}.slice",
    f"/sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod{uid_no_dash}.slice",
    f"/sys/fs/cgroup/kubepods.slice/kubepods-guaranteed.slice/kubepods-guaranteed-pod{uid_no_dash}.slice",
]

working_patterns = []

for pattern in test_patterns:
    matches = glob.glob(pattern)
    if matches:
        for match in matches:
            # 필수 메트릭 파일들이 존재하는지 확인
            cpu_file = os.path.join(match, "cpu.stat")
            mem_file = os.path.join(match, "memory.current")
            
            if os.path.exists(cpu_file) and os.path.exists(mem_file):
                # 패턴을 일반화 (UID 부분을 변수로 변경)
                if uid_underscore in pattern:
                    general_pattern = pattern.replace(uid_underscore, "{pod_uid_underscore}")
                elif uid_no_dash in pattern:
                    general_pattern = pattern.replace(uid_no_dash, "{pod_uid_no_dash}")
                else:
                    general_pattern = pattern.replace(uid, "{pod_uid}")
                
                working_patterns.append(general_pattern)
                print(f"WORKING:{general_pattern}")

# 추가 와일드카드 패턴들도 테스트
wildcard_patterns = [
    f"/sys/fs/cgroup/kubepods.slice/kubepods-*-pod{uid_underscore}.slice",
    f"/sys/fs/cgroup/kubepods.slice/kubepods-*-pod{uid_no_dash}.slice",
    f"/sys/fs/cgroup/kubepods.slice/*pod{uid_underscore}*",
    f"/sys/fs/cgroup/kubepods.slice/*pod{uid_no_dash}*",
]

for pattern in wildcard_patterns:
    matches = glob.glob(pattern)
    if matches:
        for match in matches:
            cpu_file = os.path.join(match, "cpu.stat")
            mem_file = os.path.join(match, "memory.current")
            
            if os.path.exists(cpu_file) and os.path.exists(mem_file):
                if uid_underscore in pattern:
                    general_pattern = pattern.replace(uid_underscore, "{pod_uid_underscore}")
                elif uid_no_dash in pattern:
                    general_pattern = pattern.replace(uid_no_dash, "{pod_uid_no_dash}")
                else:
                    general_pattern = pattern.replace(uid, "{pod_uid}")
                
                if general_pattern not in working_patterns:
                    working_patterns.append(general_pattern)
                    print(f"WORKING:{general_pattern}")

if not working_patterns:
    print("NO_PATTERNS_FOUND")
EOF

# collector 포드에서 패턴 검색 실행
WORKING_PATTERNS=$(kubectl exec -it $COLLECTOR_POD -- python3 -c "$(cat /tmp/find_working_patterns.py)" | grep "WORKING:" | cut -d: -f2- | tr -d '\r')

if [ -z "$WORKING_PATTERNS" ]; then
    echo "❌ 작동하는 cgroup 패턴을 찾을 수 없습니다."
    echo "   전체 디버깅을 위해 다음 명령을 실행하세요:"
    echo "   ./scripts/debug-cgroup.sh"
    exit 1
fi

echo "✅ 작동하는 패턴들을 발견했습니다:"
echo "$WORKING_PATTERNS"

# collector.py 백업
echo "📁 collector.py 백업 중..."
cp collector/collector.py collector/collector.py.backup.$(date +%Y%m%d_%H%M%S)

# 새로운 패턴 배열 생성
echo "🔧 새로운 cgroup 패턴 배열 생성 중..."

NEW_PATTERNS=""
while IFS= read -r pattern; do
    if [ -n "$pattern" ]; then
        # 패턴을 Python 코드 형식으로 변환
        if [[ "$pattern" == *"{pod_uid_underscore}"* ]]; then
            py_pattern=$(echo "$pattern" | sed 's/{pod_uid_underscore}/{pod_uid_underscore}/g')
            NEW_PATTERNS="${NEW_PATTERNS}            f\"${py_pattern}\",\n"
        elif [[ "$pattern" == *"{pod_uid_no_dash}"* ]]; then
            py_pattern=$(echo "$pattern" | sed 's/{pod_uid_no_dash}/{pod_uid.replace("-", "")}/g')
            NEW_PATTERNS="${NEW_PATTERNS}            f\"${py_pattern}\",\n"
        else
            py_pattern=$(echo "$pattern" | sed 's/{pod_uid}/{pod_uid}/g')
            NEW_PATTERNS="${NEW_PATTERNS}            f\"${py_pattern}\",\n"
        fi
    fi
done <<< "$WORKING_PATTERNS"

# collector.py 수정
echo "✏️  collector.py 수정 중..."

# Python 스크립트로 정확한 수정 수행
cat > /tmp/update_collector.py << EOF
import re

# collector.py 읽기
with open('collector/collector.py', 'r', encoding='utf-8') as f:
    content = f.read()

# cgroup_patterns 배열 찾기 및 교체
pattern_start = r'cgroup_patterns = \['
pattern_end = r'\]'

# 기존 패턴 배열 찾기
match = re.search(f'{pattern_start}.*?{pattern_end}', content, re.DOTALL)

if match:
    # 새로운 패턴 배열 생성
    new_patterns = '''cgroup_patterns = [
            # 실제 테스트를 통해 검증된 패턴들 (자동 생성됨)
$(echo -e "$NEW_PATTERNS" | sed 's/$//')
        ]'''
    
    # 교체
    new_content = content.replace(match.group(0), new_patterns)
    
    # 파일 저장
    with open('collector/collector.py', 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    print("SUCCESS: cgroup_patterns 배열이 업데이트되었습니다.")
else:
    print("ERROR: cgroup_patterns 배열을 찾을 수 없습니다.")
EOF

python3 /tmp/update_collector.py

if [ $? -eq 0 ]; then
    echo "✅ collector.py 수정 완료!"
    
    echo ""
    echo "🚀 다음 단계:"
    echo "1. 변경사항 확인:"
    echo "   git diff collector/collector.py"
    echo ""
    echo "2. 이미지 재빌드 및 배포:"
    echo "   ./scripts/02-build-images.sh"
    echo "   ./scripts/03-deploy.sh"
    echo ""
    echo "3. 로그 확인:"
    echo "   kubectl logs -f \$(kubectl get pods -l app=resource-collector -o jsonpath='{.items[0].metadata.name}')"
    
    # 자동으로 재배포할지 물어보기
    echo ""
    read -p "지금 바로 재배포하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🚀 재배포 시작..."
        ./scripts/02-build-images.sh
        ./scripts/03-deploy.sh
        
        echo ""
        echo "✅ 재배포 완료! 로그를 확인하세요:"
        echo "kubectl logs -f \$(kubectl get pods -l app=resource-collector -o jsonpath='{.items[0].metadata.name}')"
    fi
else
    echo "❌ collector.py 수정 실패"
    echo "   백업 파일에서 복원하세요: cp collector/collector.py.backup.* collector/collector.py"
fi

# 임시 파일 정리
rm -f /tmp/find_working_patterns.py /tmp/update_collector.py

echo ""
echo "=========================================="
echo "cgroup 패턴 수정 스크립트 완료!"
echo "==========================================" 