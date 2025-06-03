# Kubernetes 기반 클라우드 모니터링 서비스 구현 보고서

## 1-1. 코드 제출물 디렉토리 구조
![디렉토리 구조](images/dir_structure.png)

```
kubemonitor/
├── collector/
│   ├── collector.py           # DaemonSet용 리소스 수집 스크립트
│   ├── requirements.txt       # Python 라이브러리 목록
│   └── Dockerfile.collector   # Collector용 Dockerfile
├── api/
│   ├── main.py               # FastAPI 앱 엔트리포인트
│   ├── models.py             # Pydantic 모델 정의
│   ├── storage.py            # 시계열 데이터 저장소 추상화
│   ├── requirements.txt      # Python 라이브러리 목록
│   └── Dockerfile.api        # API 서버용 Dockerfile
├── deploy/
│   └── monitor.yaml          # Kubernetes 배포 매니페스트
├── docs/
│   ├── report.md            # 이 보고서 파일
│   └── images/              # 스크린샷 및 다이어그램 폴더
├── .gitignore              # Git 무시 파일 목록
└── README.md               # 프로젝트 설명서
```

## 1-2. 컴포넌트/함수 레벨 구현 내용 설명

### 1) 서비스 전체 흐름도
![서비스 전체 흐름도](images/flowchart.png)

**그림 1. 전체 서비스 아키텍처**  
- Collector DaemonSet 파드는 호스트의 `/sys/fs/cgroup`과 `/host/proc`를 직접 읽어 CPU, 메모리, 디스크, 네트워크 사용량을 수집  
- 수집된 메트릭을 HTTP POST로 FastAPI 서버(`POST /api/nodes/{node}` 등)로 전송  
- FastAPI 서버는 Pydantic 모델로 파싱해 MetricsStore(인메모리 저장소)에 보관  
- 사용자가 GET 요청(`GET /api/nodes/{node}?window=<sec>` 등)을 보내면, MetricsStore에서 해당 데이터를 집계 후 JSON으로 반환

### 2) Collector 컴포넌트 다이어그램
![Collector 컴포넌트 다이어그램](images/component_diagram.png)

**그림 2. Collector 내부 함수 호출 흐름**  
- `read_cgroup_cpu_usage()`: cgroup v1 cpuacct.usage에서 누적 CPU 시간(나노초) 읽기  
- `read_proc_meminfo()`: `/host/proc/meminfo`에서 메모리 총량/사용량/여유량 파싱  
- `read_cgroup_blkio()`: cgroup blkio.throttle.io_service_bytes에서 디스크 I/O 바이트 읽기  
- `read_proc_net_dev()`: `/host/proc/net/dev`에서 네트워크 RX/TX 바이트 읽기  
- `collect_node_metrics(prev_cpu_stat)`: 위 함수들을 조합해 노드 메트릭 수집  
- `send_to_api(endpoint, payload)`: 수집된 메트릭을 API 서버로 HTTP POST 전송

### 3) FastAPI 컴포넌트 다이어그램
![API 컴포넌트 다이어그램](images/api_component_diagram.png)

**그림 3. FastAPI 서버 컴포넌트 구성**  
- **main.py**: 모든 엔드포인트 정의  
  - POST `/api/nodes/{node_name}`: Collector가 보내는 노드 메트릭 수신  
  - GET `/api/nodes` 및 `/api/nodes/{node_name}`: 노드별 시계열 혹은 최신 메트릭 조회  
  - POST `/api/pods/{pod_name}`, GET `/api/pods` 등 유사 패턴으로 포드, 네임스페이스, 디플로이먼트 엔드포인트 구현  
- **models.py**: Pydantic 모델 정의 (NodeMetrics, PodMetrics, NamespaceMetrics, DeploymentMetrics)  
- **storage.py**: MetricsStore 클래스  
  - add_* 계열 메서드로 메트릭 추가  
  - query_* 계열 메서드로 윈도우 기반 시계열 조회  
  - 인메모리 딕셔너리(`Dict[str, List[BaseModel]]`)를 사용해 간단히 보관  

### 4) 주요 API 엔드포인트
- **노드 관련**:
  - `POST /api/nodes/{node_name}`: 노드 메트릭 수집
  - `GET /api/nodes`: 모든 노드 최신 메트릭 조회
  - `GET /api/nodes/{node_name}?window=60`: 특정 노드 시계열 조회 (60초간)

- **포드 관련**:
  - `POST /api/pods/{pod_name}`: 포드 메트릭 수집
  - `GET /api/pods`: 모든 포드 최신 메트릭 조회
  - `GET /api/pods/{pod_name}?window=300`: 특정 포드 시계열 조회 (300초간)

- **네임스페이스 관련**:
  - `GET /api/namespaces/{ns_name}`: 특정 네임스페이스 메트릭 조회
  - `GET /api/namespaces/{ns_name}/pods`: 네임스페이스 내 모든 포드 조회

- **디플로이먼트 관련**:
  - `GET /api/namespaces/{ns_name}/deployments/{dp_name}`: 특정 디플로이먼트 메트릭 조회

## 1-3. 개발 환경 구축, 이미지 빌드, 배포, 테스트 방법

### 1-3.1. 개발 환경 구축 (Clean Ubuntu 22.04 LTS 기준)

1. **Ubuntu 버전 확인**
   ```bash
   cat /etc/os-release  # Ubuntu 22.04 확인
   ```
   ![Ubuntu 버전 확인](images/ubuntu_version.png)

2. **시스템 업데이트 & 필수 도구 설치**
   ```bash
   sudo apt-get update && sudo apt-get upgrade -y
   sudo apt-get install -y curl wget git build-essential vim python3 python3-pip
   ```
   ![시스템 업데이트](images/apt_update.png)
   ![필수 도구 설치](images/apt_install_tools.png)

3. **Python 버전 확인**
   ```bash
   python3 --version  # Python 3.10.x
   pip3 --version
   ```
   ![Python 버전](images/python_version.png)

4. **Docker 설치 및 테스트**
   ```bash
   sudo apt-get install -y docker.io
   sudo systemctl enable --now docker
   sudo usermod -aG docker $USER
   newgrp docker
   docker --version
   docker run hello-world
   ```
   ![Docker 버전](images/docker_version.png)
   ![Docker 헬로월드](images/docker_hello_world.png)

5. **kubectl, Minikube 설치**
   ```bash
   # kubectl 설치
   curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x ./kubectl && sudo mv ./kubectl /usr/local/bin/kubectl
   kubectl version --client
   
   # Minikube 설치
   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
   chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
   minikube start --driver=docker --cpus=4 --memory=8192
   ```
   ![kubectl 버전](images/kubectl_version.png)
   ![Minikube 상태](images/minikube_status.png)
   ![kubectl 노드 확인](images/kubectl_get_nodes.png)

6. **테스트 도구 설치**
   ```bash
   sudo apt-get install -y stress iperf3
   stress --version
   iperf3 --version
   ```
   ![stress 버전](images/stress_version.png)
   ![iperf3 버전](images/iperf3_version.png)

### 1-3.2. 이미지 빌드

1. **Collector 이미지 빌드**
   ```bash
   cd ~/kubemonitor/collector
   docker build -f Dockerfile.collector -t kubemonitor-collector:latest .
   minikube image load kubemonitor-collector:latest
   ```
   ![Collector 이미지 빌드](images/collector_build.png)

2. **API 서버 이미지 빌드**
   ```bash
   cd ~/kubemonitor/api
   docker build -f Dockerfile.api -t kubemonitor-api:latest .
   minikube image load kubemonitor-api:latest
   ```
   ![API 이미지 빌드](images/api_build.png)

### 1-3.3. 쿠버네티스 배포

1. **컨텍스트 확인 및 배포**
   ```bash
   kubectl config current-context
   kubectl get nodes -o wide
   cd ~/kubemonitor/deploy
   kubectl apply -f monitor.yaml
   ```
   ![K8s 컨텍스트](images/k8s_context.png)
   ![monitor.yaml 적용](images/monitor_apply.png)

2. **리소스 상태 확인**
   ```bash
   kubectl get daemonset -A | grep resource-collector
   kubectl get deployment -A | grep monitor-api
   kubectl get service | grep monitor-api
   ```
   ![DaemonSet 상태](images/daemonset_status.png)
   ![Deployment 상태](images/deployment_status.png)
   ![Service 상태](images/service_status.png)

3. **로그 확인**
   ```bash
   kubectl logs -l app=resource-collector
   kubectl logs -l app=monitor-api
   ```
   ![Collector 로그](images/collector_logs.png)
   ![API 서버 로그](images/api_logs.png)

### 1-3.4. 검증 및 테스트

#### 1) CPU 부하(stress) 테스트
```bash
kubectl run stress-test --image=progrium/stress -- stress --cpu 2 --timeout 60s
# API 서버에서 CPU 사용량 확인
curl "http://$(minikube ip):30080/api/nodes/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
```
![CPU 부하 테스트](images/stress_cpu.png)
![CPU 사용량 조회](images/get_node_cpu.png)

#### 2) 디스크 I/O(dd) 테스트
```bash
kubectl run disk-test --image=busybox -- /bin/sh -c "dd if=/dev/zero of=/tmp/testfile bs=1M count=100"
curl "http://$(minikube ip):30080/api/nodes/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
```
![디스크 I/O 테스트](images/dd_disk.png)
![디스크 사용량 조회](images/get_node_disk.png)

#### 3) 네트워크 부하(iperf3) 테스트
```bash
kubectl run iperf3-server --image=networkstatic/iperf3 -- iperf3 -s
kubectl run iperf3-client --image=networkstatic/iperf3 -- iperf3 -c iperf3-server -t 30
curl "http://$(minikube ip):30080/api/nodes/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
```
![네트워크 부하 테스트](images/iperf3.png)
![네트워크 사용량 조회](images/get_node_network.png)

#### 4) Pod별 메트릭 조회
```bash
kubectl create deployment nginx --image=nginx --replicas=2
curl "http://$(minikube ip):30080/api/pods"
```
![Pod 메트릭 조회](images/get_pod.png)

#### 5) 네임스페이스/디플로이먼트 집계
```bash
kubectl create namespace test-ns
kubectl create deployment test-dep --image=busybox --replicas=2 -n test-ns
curl "http://$(minikube ip):30080/api/namespaces/test-ns"
curl "http://$(minikube ip):30080/api/namespaces/test-ns/deployments"
```
![네임스페이스 조회](images/get_namespace.png)
![디플로이먼트 조회](images/get_deployment.png)

#### 6) 시계열 조회 (?window=)
```bash
curl "http://$(minikube ip):30080/api/nodes/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')?window=60"
```
![시계열 조회](images/get_node_window.png)

## 2. 구현 결과물 (코드)

### 2-1. Collector 코드 (`collector/collector.py`)
- DaemonSet으로 배포되어 각 노드에서 실행
- cgroup v1과 /proc 파일시스템을 직접 읽어 시스템 메트릭 수집
- 5초마다 API 서버로 HTTP POST 전송

### 2-2. API 서버 코드 (`api/main.py`, `api/models.py`, `api/storage.py`)
- FastAPI 기반 REST API 서버
- Pydantic 모델을 사용한 데이터 검증
- 인메모리 시계열 데이터 저장소
- 노드/포드/네임스페이스/디플로이먼트별 메트릭 조회 지원

### 2-3. Kubernetes 매니페스트 (`deploy/monitor.yaml`)
- DaemonSet: 각 노드에서 메트릭 수집
- Deployment: API 서버 운영
- Service: ClusterIP와 NodePort로 외부 접근 제공

## 3. 결론

본 프로젝트는 Kubernetes 환경에서 노드와 포드의 리소스 사용량을 실시간으로 모니터링하는 완전한 시스템을 구현했습니다. 

**주요 특징:**
- **확장성**: DaemonSet을 통한 모든 노드 커버리지
- **실시간성**: 5초 간격 메트릭 수집
- **유연성**: 시계열 조회를 위한 window 파라미터 지원
- **완전성**: 노드/포드/네임스페이스/디플로이먼트 계층별 메트릭 제공
- **표준성**: REST API와 Kubernetes 네이티브 리소스 활용

**개선 가능 영역:**
- CPU 사용률 정확한 계산 로직 추가
- 영구 저장소(예: InfluxDB, Prometheus) 연동
- 대시보드 UI 구현
- 알림 기능 추가 