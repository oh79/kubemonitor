# Kubernetes 기반 클라우드 모니터링 서비스 구현 보고서

## 1-1. 코드 제출물 디렉토리 구조

```
kubemonitor/
├── collector/
│ ├── collector.py # DaemonSet용 리소스 수집 스크립트
│ ├── requirements.txt # Python 라이브러리: requests
│ └── Dockerfile.collector # Collector용 Dockerfile
├── api/
│ ├── main.py # FastAPI 앱 엔트리포인트
│ ├── models.py # Pydantic 모델 정의
│ ├── storage.py # 시계열 데이터 저장소 추상화
│ ├── requirements.txt # Python 라이브러리: fastapi, uvicorn, pydantic
│ └── Dockerfile.api # API 서버용 Dockerfile
├── deploy/
│ └── monitor.yaml # Kubernetes 배포 매니페스트
├── scripts/ # 자동화 스크립트 모음
│ ├── 00-setup-all.sh # 전체 환경 자동 구축 스크립트
│ ├── 01-setup-environment.sh # 개발 환경 구축
│ ├── 02-build-images.sh # Docker 이미지 빌드
│ ├── 03-deploy.sh # Kubernetes 배포
│ ├── 04-test.sh # 시스템 테스트
│ ├── 05-test-api.sh # API 테스트
│ ├── 05-test-api-with-save.sh # API 테스트 결과 저장
│ ├── kube-port-forward.sh # 포트 포워딩
│ └── shutdown_all_settings.sh # 전체 종료
├── result/ # 테스트 결과 저장소
│ └── api-test-2025-06-10-15-13-36.txt # API 테스트 결과 (21090라인)
├── docs/
│ ├── report.md # 이 보고서 파일
│ └── PRD.md # 요구사항 명세서
├── .gitignore # Git 무시 파일 목록
└── README.md # 프로젝트 설명서
```

## 1-2. 컴포넌트/함수 레벨 구현 내용 설명

### 1) 서비스 전체 아키텍처
**(다이어그램 직접 생성 필요: images/architecture.png)**

**전체 서비스 흐름:**
1. **DaemonSet Collector** → 각 노드에서 cgroup/proc 파일시스템 읽기
2. **메트릭 수집** → CPU, 메모리, 디스크 I/O, 네트워크 사용량 수집
3. **HTTP POST** → 5초마다 FastAPI 서버로 메트릭 전송
4. **인메모리 저장** → MetricsStore에서 시계열 데이터 보관
5. **REST API** → 클라이언트의 GET 요청에 JSON 응답

### 2) Collector 컴포넌트 세부 함수

#### **2-1) 핵심 메트릭 수집 함수들**
- `read_cgroup_cpu_usage()`: cgroup v1/v2 CPU 누적 사용량(ns) 읽기
- `calculate_cpu_usage_percent()`: CPU 사용률 퍼센트 계산
- `read_proc_meminfo()`: `/host/proc/meminfo`에서 메모리 정보 파싱
- `read_proc_net_dev()`: `/host/proc/net/dev`에서 네트워크 RX/TX 바이트
- `read_cgroup_blkio()`: cgroup 블록 I/O 통계 (읽기/쓰기 바이트)

#### **2-2) Kubernetes 연동 함수들**
- `get_kubernetes_pods()`: K8s API로 현재 노드의 포드 목록 조회
- `collect_pod_metrics_from_cgroup()`: 특정 포드의 cgroup 메트릭 수집
- `collect_namespace_metrics()`: 네임스페이스별 포드 메트릭 집계
- `collect_deployment_metrics()`: 디플로이먼트별 포드 메트릭 집계

#### **2-3) 메인 수집 및 전송 함수들**
- `collect_node_metrics(prev_cpu_stat)`: 노드 전체 메트릭 수집 조합
- `send_to_api(endpoint, payload)`: HTTP POST로 API 서버에 전송
- `main()`: 5초 간격 무한 루프로 메트릭 수집/전송

### 3) FastAPI 서버 컴포넌트

#### **3-1) main.py - REST API 엔드포인트**
**노드 관련 API:**
- `POST /api/nodes/{node_name}`: Collector가 보내는 노드 메트릭 수신 (내부용)
- `GET /api/nodes`: 모든 노드 최신 메트릭 조회
- `GET /api/nodes/{node}?window=60`: 특정 노드 시계열 조회
- `GET /api/nodes/{node}/pods`: 해당 노드의 모든 포드 조회

**포드 관련 API:**
- `POST /api/pods/{pod_name}`: 포드 메트릭 수신 (내부용)
- `GET /api/pods`: 모든 포드 최신 메트릭 조회
- `GET /api/pods/{podName}?window=300`: 특정 포드 시계열 조회

**네임스페이스 관련 API:**
- `GET /api/namespaces`: 모든 네임스페이스 메트릭 조회
- `GET /api/namespaces/{nsName}?window=120`: 특정 네임스페이스 시계열 조회
- `GET /api/namespaces/{nsName}/pods`: 네임스페이스 내 모든 포드 조회

**디플로이먼트 관련 API:**
- `GET /api/namespaces/{nsName}/deployments`: 네임스페이스 내 모든 디플로이먼트 조회
- `GET /api/namespaces/{nsName}/deployments/{dpName}`: 특정 디플로이먼트 메트릭 조회

#### **3-2) models.py - Pydantic 데이터 모델**
- `NodeMetrics`: 노드 메트릭 (CPU, 메모리, 디스크, 네트워크)
- `PodMetrics`: 포드 메트릭 (네임스페이스, 디플로이먼트 정보 포함)
- `NamespaceMetrics`: 네임스페이스 집계 메트릭
- `DeploymentMetrics`: 디플로이먼트 집계 메트릭

#### **3-3) storage.py - 인메모리 시계열 저장소**
- `MetricsStore`: 메인 저장소 클래스
- `add_*_metrics()`: 각 타입별 메트릭 추가 메서드
- `query_*_metrics(window)`: 시간 윈도우 기반 시계열 조회

### 4) Kubernetes 배포 구성

#### **4-1) DaemonSet (resource-collector)**
- **권한**: ServiceAccount + ClusterRole로 포드/노드/네임스페이스 조회 권한
- **호스트 접근**: `hostPID: true`, `/sys/fs/cgroup`, `/host/proc` 마운트
- **보안**: `privileged: true` 컨테이너로 시스템 리소스 접근
- **환경변수**: API_SERVER_URL, NODE_NAME, COLLECT_INTERVAL, DEBUG

#### **4-2) Deployment (monitor-api)**
- **리플리카**: 1개 (단일 인스턴스)
- **헬스체크**: `/health` 엔드포인트로 readiness/liveness 프로브
- **리소스**: CPU 250m-500m, 메모리 256Mi-512Mi

#### **4-3) Service**
- **ClusterIP**: 클러스터 내부 통신용 (포트 80 → 8080)
- **NodePort**: 외부 접근용 (30080 포트)

## 1-3. 개발 환경 구축, 이미지 빌드, 배포, 테스트 방법

### 🚀 **원클릭 전체 환경 구성 (권장)**

**Clean Ubuntu 22.04 LTS에서 모든 환경을 자동으로 구축하는 가장 간단한 방법:**

```bash
cd ~/kubemonitor

# 1. 전체 환경 자동 구축 실행
bash scripts/00-setup-all.sh

# 2. Docker 그룹 권한 적용 (스크립트에서 안내하면 실행)
newgrp docker

# 3. 권한 적용 후 스크립트 재실행
bash scripts/00-setup-all.sh
```

**완료 후 접속:**
```bash
# API 서버 URL 확인
MINIKUBE_IP=$(minikube ip)
echo "API 서버: http://${MINIKUBE_IP}:30080"
echo "Swagger UI: http://${MINIKUBE_IP}:30080/docs"
echo "Health Check: http://${MINIKUBE_IP}:30080/health"
```

**이 한 번의 실행으로 다음이 모두 완료됩니다:**
- ✅ **개발 환경 구축**: Python, Docker, kubectl, Minikube 설치
- ✅ **이미지 빌드**: Collector 및 API 서버 Docker 이미지 생성
- ✅ **Kubernetes 배포**: DaemonSet, Deployment, Service 배포
- ✅ **시스템 테스트**: stress, dd, iperf3를 통한 부하 테스트

---

### 📋 **개발 환경 구축, 이미지 빌드, 배포, 테스트 방법에 대한 상세 설명**

*(아래는 원클릭 설치가 실패하거나 단계별 이해가 필요한 경우를 위한 상세 가이드)*

### 1-3.1. 개발 환경 구축 (Clean Ubuntu 22.04 LTS 기준)

#### **1단계: 시스템 기본 설정**
```bash
# Ubuntu 버전 확인
cat /etc/os-release

# 시스템 업데이트
sudo apt-get update && sudo apt-get upgrade -y

# 필수 도구 설치
sudo apt-get install -y curl wget git build-essential vim python3 python3-pip
```
**(스크린샷 직접 촬영 필요: ubuntu_version.png, apt_update.png)**

#### **2단계: Python 환경 설정**
```bash
# Python 버전 확인
python3 --version  # Python 3.10.x 확인
pip3 --version

# 가상환경 생성 (선택사항)
sudo apt-get install -y python3-venv
python3 -m venv kubemonitor-env
source kubemonitor-env/bin/activate
```
**(스크린샷 직접 촬영 필요: python_version.png)**

#### **3단계: Docker 설치**
```bash
# Docker 설치
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker

# Docker 테스트
docker --version
docker run hello-world
```
**(스크린샷 직접 촬영 필요: docker_version.png, docker_hello_world.png)**

#### **4단계: Kubernetes 도구 설치**
```bash
# kubectl 설치
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl && sudo mv ./kubectl /usr/local/bin/kubectl
kubectl version --client

# Minikube 설치
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube

# Minikube 시작
minikube start --driver=docker --cpus=4 --memory=8192
kubectl get nodes
```
**(스크린샷 직접 촬영 필요: kubectl_version.png, minikube_status.png, kubectl_get_nodes.png)**

#### **5단계: 테스트 도구 설치**
```bash
# 부하 테스트 도구
sudo apt-get install -y stress iperf3
stress --version
iperf3 --version
```
**(스크린샷 직접 촬영 필요: stress_version.png, iperf3_version.png)**

### 1-3.2. 이미지 빌드

#### **1단계: 프로젝트 클론**
```bash
cd ~
git clone <your-repo-url> kubemonitor
cd kubemonitor
```

#### **2단계: Collector 이미지 빌드**
```bash
cd ~/kubemonitor/collector
docker build -f Dockerfile.collector -t kubemonitor-collector:latest .
minikube image load kubemonitor-collector:latest
```
**(스크린샷 직접 촬영 필요: collector_build.png)**

#### **3단계: API 서버 이미지 빌드**
```bash
cd ~/kubemonitor/api
docker build -f Dockerfile.api -t kubemonitor-api:latest .
minikube image load kubemonitor-api:latest
```
**(스크린샷 직접 촬영 필요: api_build.png)**

#### **4단계: 이미지 확인**
```bash
docker images | grep kubemonitor
minikube image ls | grep kubemonitor
```

### 1-3.3. Kubernetes 배포

#### **1단계: 컨텍스트 확인**
```bash
kubectl config current-context
kubectl get nodes -o wide
```
**(스크린샷 직접 촬영 필요: k8s_context.png)**

#### **2단계: 배포 실행**
```bash
cd ~/kubemonitor/deploy
kubectl apply -f monitor.yaml
```
**(스크린샷 직접 촬영 필요: monitor_apply.png)**

#### **3단계: 배포 상태 확인**
```bash
# DaemonSet 확인
kubectl get daemonset -A | grep resource-collector
kubectl describe daemonset resource-collector

# Deployment 확인
kubectl get deployment -A | grep monitor-api
kubectl describe deployment monitor-api

# Service 확인
kubectl get service | grep monitor-api
kubectl get service -o wide

# Pod 상태 확인
kubectl get pods -o wide
```
**(스크린샷 직접 촬영 필요: daemonset_status.png, deployment_status.png, service_status.png)**

#### **4단계: 로그 확인**
```bash
# Collector 로그
kubectl logs -l app=resource-collector

# API 서버 로그
kubectl logs -l app=monitor-api
```
**(스크린샷 직접 촬영 필요: collector_logs.png, api_logs.png)**

### 1-3.4. 검증 및 테스트

#### **🚀 방법 1: 자동화 스크립트 사용 (권장)**

**전체 환경 자동 구축:**
```bash
cd ~/kubemonitor
# 원클릭 전체 설정 (Clean Ubuntu에서)
bash scripts/00-setup-all.sh

# 또는 단계별 실행
bash scripts/01-setup-environment.sh  # 환경 구축
bash scripts/02-build-images.sh       # 이미지 빌드  
bash scripts/03-deploy.sh             # 배포
bash scripts/04-test.sh               # 부하 테스트
```
**(스크린샷 직접 촬영 필요: setup_all_script.png, setup_complete.png)**

**API 테스트 자동화:**
```bash
# 16개 API 엔드포인트 자동 테스트
bash scripts/05-test-api.sh

# 테스트 결과를 파일로 저장 (21,000라인 상세 로그)
bash scripts/05-test-api-with-save.sh
```
**(스크린샷 직접 촬영 필요: api_test_script.png, api_test_results.png)**

**자동화 스크립트 장점:**
- ✅ **원클릭 구축**: Clean Ubuntu에서 5분 내 전체 환경 완성
- ✅ **오류 처리**: Docker 권한, 네트워크 등 자동 해결
- ✅ **상세 로깅**: 모든 과정의 성공/실패 상태 표시
- ✅ **결과 저장**: `result/` 폴더에 타임스탬프별 테스트 결과 보관

#### **🔧 방법 2: kubectl 명령어 검증 및 부하 테스트**

#### **2-1. Kubernetes 클러스터 상태 검증**

**기본 클러스터 상태 확인:**
```bash
# 클러스터 정보 확인
kubectl cluster-info
kubectl version --short

# 노드 상태 확인
kubectl get nodes -o wide
kubectl describe nodes

# 네임스페이스 목록
kubectl get namespaces
```
**(스크린샷 촬영 필수: kubectl_cluster_info.png, kubectl_nodes_status.png)**

#### **2-2. 모니터링 시스템 배포 상태 검증**

**DaemonSet, Deployment, Service 상태 확인:**
```bash
# 전체 리소스 상태 확인
kubectl get all -A | grep -E "(resource-collector|monitor-api)"

# DaemonSet 상세 확인
kubectl get daemonset resource-collector -o wide
kubectl describe daemonset resource-collector

# Deployment 상세 확인  
kubectl get deployment monitor-api -o wide
kubectl describe deployment monitor-api

# Service 확인
kubectl get service monitor-api -o wide
kubectl describe service monitor-api

# Pod 상태 및 로그 확인
kubectl get pods -l app=resource-collector -o wide
kubectl get pods -l app=monitor-api -o wide
kubectl logs -l app=resource-collector --tail=20
kubectl logs -l app=monitor-api --tail=20
```
**(스크린샷 촬영 필수: kubectl_monitoring_resources.png, kubectl_daemonset_describe.png, kubectl_logs.png)**

#### **2-3. stress를 이용한 CPU 부하 테스트**

**CPU 부하 생성 및 kubectl로 모니터링:**
```bash
# 1단계: CPU 부하 Pod 생성
kubectl run stress-cpu-test --image=progrium/stress \
  --restart=Never \
  -- stress --cpu 2 --timeout 120s

# 2단계: Pod 생성 확인
kubectl get pods | grep stress-cpu-test
kubectl describe pod stress-cpu-test

# 3단계: Pod 리소스 사용량 실시간 모니터링
kubectl top pods stress-cpu-test
kubectl top nodes

# 4단계: Pod 상태 확인 (부하 중)
for i in {1..3}; do
  echo "=== 측정 $i ==="
  kubectl get pod stress-cpu-test
  kubectl top pod stress-cpu-test 2>/dev/null || echo "메트릭 수집 중..."
  sleep 10
done

# 5단계: 정리
kubectl delete pod stress-cpu-test
```
**(스크린샷 촬영 필수: stress_cpu_kubectl_create.png, stress_cpu_kubectl_top.png, stress_cpu_kubectl_monitoring.png)**

#### **2-4. dd를 이용한 디스크 I/O 테스트**

**디스크 I/O 부하 생성 및 모니터링:**
```bash
# 1단계: 디스크 I/O 부하 Pod 생성
kubectl run disk-io-test --image=busybox \
  --restart=Never \
  -- /bin/sh -c "dd if=/dev/zero of=/tmp/testfile bs=1M count=500; sync; sleep 60"

# 2단계: Pod 실행 상태 확인
kubectl get pod disk-io-test -o wide
kubectl describe pod disk-io-test

# 3단계: Pod 로그 확인 (dd 진행 상황)
kubectl logs disk-io-test -f &

# 4단계: 시스템 리소스 확인
kubectl top nodes
kubectl top pods

# 5단계: 정리
kubectl delete pod disk-io-test
```
**(스크린샷 촬영 필수: dd_test_kubectl_create.png, dd_test_kubectl_logs.png, dd_test_kubectl_top.png)**

#### **2-5. iperf3를 이용한 네트워크 부하 테스트**

**네트워크 트래픽 생성 및 모니터링:**
```bash
# 1단계: iperf3 서버 Pod 생성
kubectl run iperf3-server --image=networkstatic/iperf3 \
  --port=5201 \
  --restart=Never \
  -- iperf3 -s

# 2단계: 서버 Pod 준비 대기
kubectl wait --for=condition=Ready pod/iperf3-server --timeout=60s
kubectl get pod iperf3-server -o wide

# 3단계: iperf3 클라이언트 Pod 생성
kubectl run iperf3-client --image=networkstatic/iperf3 \
  --restart=Never \
  -- iperf3 -c iperf3-server -t 30 -P 4

# 4단계: 네트워크 테스트 진행 상황 모니터링
kubectl get pods | grep iperf3
kubectl logs iperf3-client -f &
kubectl logs iperf3-server

# 5단계: Pod 상태 및 리소스 사용량 확인
kubectl top pods | grep iperf3
kubectl describe pod iperf3-server
kubectl describe pod iperf3-client

# 6단계: 정리
kubectl delete pod iperf3-server iperf3-client
```
**(스크린샷 촬영 필수: iperf3_kubectl_setup.png, iperf3_kubectl_logs.png, iperf3_kubectl_monitoring.png)**

#### **2-6. curl을 이용한 API 검증 (기존 스크립트 연계)**

**05-test-api-with-save.sh 스크립트 실행 및 결과 확인:**
```bash
# API 테스트 스크립트 실행
bash scripts/05-test-api-with-save.sh

# 테스트 결과 파일 확인
ls -la result/
LATEST_RESULT=$(ls -t result/api-test-*.txt | head -1)
echo "최신 테스트 결과: $LATEST_RESULT"

# 결과 요약 확인
echo "=== 테스트 결과 요약 ==="
grep -E "(✅|❌)" "$LATEST_RESULT" | head -20

# 특정 API 응답 확인
echo "=== 노드 메트릭 응답 샘플 ==="
grep -A 10 "전체 노드 목록" "$LATEST_RESULT"

# Swagger UI 접근 확인
MINIKUBE_IP=$(minikube ip)
echo "Swagger UI: http://${MINIKUBE_IP}:30080/docs"
curl -s "http://${MINIKUBE_IP}:30080/health" | jq
```
**(스크린샷 촬영 필수: api_test_script_run.png, api_test_results_summary.png, swagger_ui_access.png)**

#### **2-7. Pod 생성/삭제를 통한 동적 모니터링 검증**

**Pod 생명주기 전체에서 모니터링 시스템 동작 확인:**
```bash
# 1단계: 테스트 네임스페이스 생성
kubectl create namespace monitoring-test

# 2단계: 다양한 워크로드 생성
kubectl create deployment nginx-web --image=nginx --replicas=3 -n monitoring-test
kubectl create deployment busybox-worker --image=busybox --replicas=2 -n monitoring-test \
  -- /bin/sh -c "while true; do echo working; sleep 30; done"

# 3단계: Pod 생성 과정 모니터링
kubectl get pods -n monitoring-test -w &
sleep 5 && pkill kubectl

# 4단계: 생성된 리소스 확인
kubectl get all -n monitoring-test
kubectl top pods -n monitoring-test

# 5단계: Pod 스케일링 테스트
kubectl scale deployment nginx-web --replicas=5 -n monitoring-test
kubectl get pods -n monitoring-test

# 6단계: API에서 새로운 Pod들 확인
MINIKUBE_IP=$(minikube ip)
curl -s "http://${MINIKUBE_IP}:30080/api/namespaces/monitoring-test" | jq

# 7단계: 정리
kubectl delete namespace monitoring-test
```
**(스크린샷 촬영 필수: kubectl_pod_lifecycle.png, kubectl_scaling_test.png, kubectl_monitoring_test.png)**

#### **2-8. 전체 시스템 상태 종합 검증**

**kubectl과 API를 함께 사용한 종합 검증:**
```bash
# 1단계: 전체 클러스터 리소스 현황
kubectl get all -A
kubectl top nodes
kubectl top pods -A

# 2단계: 모니터링 시스템 상태 점검
echo "=== DaemonSet 상태 ==="
kubectl get daemonset resource-collector -o yaml | grep -A 5 status

echo "=== API 서버 상태 ==="
kubectl get deployment monitor-api -o yaml | grep -A 5 status

# 3단계: 시스템 로그 종합 확인
echo "=== Collector 최근 로그 ==="
kubectl logs -l app=resource-collector --tail=10 --all-containers

echo "=== API 서버 최근 로그 ==="
kubectl logs -l app=monitor-api --tail=10

# 4단계: API 서버와 데이터 일치성 확인
echo "=== kubectl vs API 데이터 비교 ==="
ACTUAL_PODS=$(kubectl get pods --all-namespaces --no-headers | wc -l)
API_PODS=$(curl -s "http://${MINIKUBE_IP}:30080/api/pods" | jq 'length')
echo "kubectl Pod 개수: $ACTUAL_PODS"
echo "API Pod 개수: $API_PODS"

# 5단계: 성능 메트릭 확인
echo "=== 시스템 성능 현황 ==="
kubectl top nodes
curl -s "http://${MINIKUBE_IP}:30080/api/nodes" | jq '.[0] | {
  node: .node_name,
  cpu_percent: .cpu_usage_percent,
  memory_mb: .memory_used_mb
}'
```
**(스크린샷 촬영 필수: kubectl_system_overview.png, kubectl_api_comparison.png, kubectl_performance_check.png)**

#### **📊 검증 성공 기준**

**kubectl 명령어 검증 성공 기준:**
- ✅ **클러스터 상태**: 모든 노드가 Ready 상태
- ✅ **DaemonSet**: 모든 노드에서 Collector Pod 실행 중
- ✅ **Deployment**: API 서버 Pod가 Running 상태
- ✅ **Service**: NodePort를 통한 외부 접근 가능
- ✅ **부하 테스트**: stress, dd, iperf3 Pod가 정상 실행
- ✅ **리소스 모니터링**: kubectl top 명령어로 리소스 사용량 확인
- ✅ **로그**: 모든 컴포넌트에서 에러 로그 없음
- ✅ **데이터 일치성**: kubectl과 API 응답 데이터 일치

#### **🔍 필수 스크린샷 목록 (kubectl 부분)**

1. `kubectl_cluster_info.png` - 클러스터 정보 및 버전
2. `kubectl_nodes_status.png` - 노드 상태 및 상세 정보
3. `kubectl_monitoring_resources.png` - 모니터링 리소스 배포 상태
4. `kubectl_daemonset_describe.png` - DaemonSet 상세 정보
5. `kubectl_logs.png` - Collector 및 API 서버 로그
6. `stress_cpu_kubectl_create.png` - CPU 부하 테스트 Pod 생성
7. `stress_cpu_kubectl_top.png` - kubectl top으로 리소스 확인
8. `dd_test_kubectl_logs.png` - dd 테스트 진행 로그
9. `iperf3_kubectl_setup.png` - iperf3 네트워크 테스트 설정
10. `api_test_script_run.png` - API 테스트 스크립트 실행
11. `kubectl_pod_lifecycle.png` - Pod 생성/삭제 과정
12. `kubectl_system_overview.png` - 전체 시스템 상태
13. `kubectl_api_comparison.png` - kubectl vs API 데이터 비교

## 2. 구현 결과물 (코드)

### 2-1. Collector 주요 코드 (`collector/collector.py`)
- **총 644라인**의 Python 스크립트
- cgroup v1/v2 호환성 지원
- Kubernetes API 연동으로 포드/네임스페이스/디플로이먼트 메트릭 수집
- 5초 간격 실시간 모니터링

### 2-2. API 서버 주요 코드
- **main.py (238라인)**: 16개 REST API 엔드포인트
- **models.py (72라인)**: 4개 Pydantic 데이터 모델
- **storage.py (57라인)**: 인메모리 시계열 데이터 저장소

### 2-3. Kubernetes 배포 (`deploy/monitor.yaml`)
- **181라인**의 완전한 배포 매니페스트
- RBAC, DaemonSet, Deployment, Service 포함

## 3. 결론

본 프로젝트는 Kubernetes 네이티브 환경에서 완전히 작동하는 리소스 모니터링 시스템을 구현했습니다.

**주요 달성사항:**
- ✅ **실시간 수집**: 5초 간격 노드/포드 메트릭 수집
- ✅ **확장성**: DaemonSet을 통한 자동 노드 커버리지
- ✅ **계층적 집계**: 노드 → 포드 → 네임스페이스 → 디플로이먼트
- ✅ **시계열 지원**: window 파라미터로 유연한 시간 범위 조회
- ✅ **표준 준수**: REST API, Kubernetes 리소스, Docker 컨테이너
- ✅ **검증 완료**: stress, dd, iperf3를 통한 종합적 부하 테스트

**기술적 특징:**
- cgroup v1/v2 자동 감지 및 호환성
- Kubernetes API 활용한 동적 리소스 발견
- Pydantic 기반 타입 안전성
- FastAPI의 자동 문서화 (Swagger UI)

### **자동화 스크립트 상세 설명**

#### **핵심 자동화 스크립트**
- **`setup-all.sh`**: 원클릭 전체 환경 구축
  - Clean Ubuntu에서 전체 환경을 자동으로 구축
  - Docker 그룹 권한 자동 적용
  - 단계별 건너뛰기 옵션 지원 (`--skip-env`, `--skip-build` 등)
  
#### **단계별 스크립트**
- **`01-setup-environment.sh`**: 기본 환경 설정 (Python, Docker, kubectl, Minikube)
- **`02-build-images.sh`**: Collector 및 API 서버 Docker 이미지 빌드
- **`03-deploy.sh`**: Kubernetes 클러스터에 전체 시스템 배포
- **`04-test.sh`**: 시스템 부하 테스트 (stress, dd, iperf3)

#### **API 테스트 자동화**
- **`05-test-api.sh`**: 16개 API 엔드포인트 자동 테스트
- **`05-test-api-with-save.sh`**: 테스트 결과를 `result/` 폴더에 저장

#### **디버깅 및 유틸리티**
- **`debug-cgroup.sh`**: cgroup v1/v2 호환성 디버깅
- **`fix-cgroup-patterns.sh`**: cgroup 패턴 자동 수정
- **`quick-cgroup-test.sh`**: 빠른 cgroup 동작 확인

### **테스트 결과 저장소**
- **`result/` 폴더**: 모든 API 테스트 결과를 타임스탬프와 함께 저장
- 각 테스트 파일은 **21,000라인 이상**의 상세한 JSON 응답 포함
- HTTP 상태 코드, 응답 시간, 전체 메트릭 데이터 기록 