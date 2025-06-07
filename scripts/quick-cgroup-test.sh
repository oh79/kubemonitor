#!/bin/bash

# 빠른 cgroup 패턴 테스트 스크립트
# collector 포드에서 직접 실행하여 cgroup 경로를 빠르게 확인

echo "=========================================="
echo "빠른 cgroup 패턴 테스트"
echo "=========================================="

# collector 포드 찾기
COLLECTOR_POD=$(kubectl get pods -l app=resource-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$COLLECTOR_POD" ]; then
    echo "❌ resource-collector 포드를 찾을 수 없습니다."
    exit 1
fi

echo "✅ Collector 포드: $COLLECTOR_POD"

# 첫 번째 포드 UID 가져오기
POD_UID=$(kubectl get pods -o jsonpath='{.items[0].metadata.uid}' 2>/dev/null)

if [ -z "$POD_UID" ]; then
    echo "❌ 테스트할 포드를 찾을 수 없습니다."
    exit 1
fi

echo "🔍 테스트 포드 UID: $POD_UID"

# 빠른 패턴 테스트 Python 스크립트
cat > /tmp/quick_test.py << EOF
import glob
import os

uid = "$POD_UID"
uid_underscore = uid.replace('-', '_')
uid_no_dash = uid.replace('-', '')

print(f"원본 UID: {uid}")
print(f"언더스코어 UID: {uid_underscore}")
print(f"하이픈 제거 UID: {uid_no_dash}")
print("-" * 40)

# 가장 일반적인 패턴들만 테스트
patterns = [
    f"/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod{uid_underscore}.slice",
    f"/sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod{uid_underscore}.slice",
    f"/sys/fs/cgroup/kubepods.slice/*pod{uid_underscore}*",
    f"/sys/fs/cgroup/kubepods.slice/*pod{uid_no_dash}*",
]

found = False
for pattern in patterns:
    matches = glob.glob(pattern)
    if matches:
        print(f"✅ 발견: {pattern}")
        for match in matches:
            print(f"   경로: {match}")
            # 메트릭 파일 확인
            cpu_file = os.path.join(match, "cpu.stat")
            mem_file = os.path.join(match, "memory.current")
            io_file = os.path.join(match, "io.stat")
            
            print(f"   cpu.stat: {'✅' if os.path.exists(cpu_file) else '❌'}")
            print(f"   memory.current: {'✅' if os.path.exists(mem_file) else '❌'}")
            print(f"   io.stat: {'✅' if os.path.exists(io_file) else '❌'}")
        found = True
        break
    else:
        print(f"❌ 없음: {pattern}")

if not found:
    print("\n🔍 전체 cgroup 구조 탐색:")
    all_pods = glob.glob("/sys/fs/cgroup/kubepods.slice/*pod*")
    for pod_path in all_pods[:5]:  # 처음 5개만
        print(f"   {pod_path}")
EOF

echo ""
echo "🚀 collector 포드에서 패턴 테스트 실행 중..."
kubectl exec -it $COLLECTOR_POD -- python3 -c "$(cat /tmp/quick_test.py)"

# 임시 파일 정리
rm -f /tmp/quick_test.py

echo ""
echo "=========================================="
echo "빠른 테스트 완료!"
echo "==========================================" 