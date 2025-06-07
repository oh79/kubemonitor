# cgroup 경로 디버깅 가이드

이 가이드는 Kubernetes 환경에서 cgroup 경로 문제를 진단하고 해결하는 방법을 설명합니다.

## 문제 상황

kubemonitor의 collector가 포드별 메트릭을 수집할 때 cgroup 경로를 찾지 못하는 경우:

```
[DEBUG] 포드 cgroup 경로를 찾을 수 없음: pod-name
[DEBUG] 패턴 시도: /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod...
```

## 제공된 디버깅 도구들

### 1. 전체 디버깅 스크립트 (`debug-cgroup.sh`)

가장 상세한 분석을 제공하는 메인 디버깅 도구입니다.

```bash
./scripts/debug-cgroup.sh
```

**수행하는 작업:**
- 현재 실행 중인 포드 정보 확인
- cgroup 구조 탐색
- 포드 UID 기반 경로 패턴 분석
- cgroup 버전 (v1/v2) 확인
- Python glob 패턴 매칭 테스트
- 실제 메트릭 파일 존재 확인
- collector 로그 분석
- 수정 권장사항 제공

### 2. 빠른 테스트 스크립트 (`quick-cgroup-test.sh`)

간단하고 빠른 cgroup 패턴 확인용 도구입니다.

```bash
./scripts/quick-cgroup-test.sh
```

**수행하는 작업:**
- 가장 일반적인 cgroup 패턴들만 테스트
- 메트릭 파일 존재 여부 확인
- 빠른 결과 제공

### 3. 자동 수정 스크립트 (`fix-cgroup-patterns.sh`)

발견된 올바른 패턴을 collector.py에 자동으로 적용합니다.

```bash
./scripts/fix-cgroup-patterns.sh
```

**수행하는 작업:**
- 실제 작동하는 cgroup 패턴 자동 검색
- collector.py 백업 생성
- cgroup_patterns 배열 자동 업데이트
- 선택적 자동 재배포

## 단계별 문제 해결 과정

### 1단계: 문제 확인

```bash
# collector 로그 확인
kubectl logs -f $(kubectl get pods -l app=resource-collector -o jsonpath='{.items[0].metadata.name}')

# cgroup 관련 오류 메시지 확인
kubectl logs $(kubectl get pods -l app=resource-collector -o jsonpath='{.items[0].metadata.name}') | grep cgroup
```

### 2단계: 빠른 진단

```bash
# 빠른 테스트로 기본 패턴 확인
./scripts/quick-cgroup-test.sh
```

### 3단계: 상세 분석 (필요시)

```bash
# 전체 디버깅 실행
./scripts/debug-cgroup.sh
```

### 4단계: 자동 수정

```bash
# 발견된 패턴을 자동으로 적용
./scripts/fix-cgroup-patterns.sh
```

### 5단계: 수동 수정 (자동 수정 실패시)

1. 디버깅 결과에서 ✅ 표시된 패턴들을 확인
2. `collector/collector.py` 파일 편집
3. `cgroup_patterns` 배열을 올바른 패턴들로 교체

```python
# 예시: 실제 작동하는 패턴들로 교체
if is_cgroup_v2:
    cgroup_patterns = [
        # 실제 테스트에서 검증된 패턴들
        f"/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod{pod_uid_underscore}.slice",
        f"/sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod{pod_uid_underscore}.slice",
        # 추가 패턴들...
    ]
```

4. 재배포

```bash
./scripts/02-build-images.sh
./scripts/03-deploy.sh
```

## 일반적인 cgroup 패턴들

### cgroup v2 (대부분의 최신 Kubernetes)

```
/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod{UID}.slice
/sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod{UID}.slice
/sys/fs/cgroup/kubepods.slice/kubepods-guaranteed.slice/kubepods-guaranteed-pod{UID}.slice
```

### cgroup v1 (구버전 시스템)

```
/sys/fs/cgroup/cpu/kubepods/pod{UID}
/sys/fs/cgroup/memory/kubepods/pod{UID}
```

## UID 변환 규칙

Kubernetes 포드 UID는 다양한 형태로 변환될 수 있습니다:

- **원본**: `12345678-1234-1234-1234-123456789abc`
- **언더스코어**: `12345678_1234_1234_1234_123456789abc`
- **하이픈 제거**: `123456781234123412341234567890abc`

## 환경별 특이사항

### Minikube
- 주로 cgroup v2 사용
- burstable 슬라이스가 일반적

### Docker Desktop
- cgroup v1 또는 v2 (버전에 따라)
- 경로 구조가 다를 수 있음

### 클라우드 환경 (EKS, GKE, AKS)
- 대부분 cgroup v2
- 클라우드별 특별한 경로 구조 가능

## 문제 해결 팁

1. **권한 확인**: collector 포드가 호스트의 cgroup에 접근할 수 있는지 확인
2. **마운트 확인**: `/sys/fs/cgroup`이 올바르게 마운트되었는지 확인
3. **cgroup 버전**: `ls /sys/fs/cgroup/cgroup.controllers` 명령으로 v2 여부 확인
4. **디버그 모드**: `DEBUG=true` 환경변수로 상세 로그 활성화

## 추가 도움

문제가 지속되면:

1. 전체 디버깅 스크립트 결과를 저장하여 분석
2. Kubernetes 클러스터 정보 확인 (`kubectl version`, `kubectl get nodes -o wide`)
3. 컨테이너 런타임 정보 확인 (`docker info` 또는 `crictl info`)

## 관련 파일들

- `collector/collector.py`: 메인 collector 코드
- `scripts/debug-cgroup.sh`: 전체 디버깅 스크립트
- `scripts/quick-cgroup-test.sh`: 빠른 테스트 스크립트
- `scripts/fix-cgroup-patterns.sh`: 자동 수정 스크립트 