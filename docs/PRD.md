# 쿠버네티스 클라우드 모니터링 서비스 PRD (개선판 v0.2)

## 프로젝트 개요
쿠버네티스 클러스터의 리소스 사용량을 실시간으로 모니터링하는 서비스 개발

### 주요 목표
- DaemonSet을 활용한 각 노드의 리소스 사용량 수집
- API 서버를 통한 중앙집중식 모니터링 데이터 제공
- 노드, 파드, 네임스페이스, 디플로이먼트 단위의 리소스 모니터링

### 제약사항
- Metrics-server, Prometheus/Grafana 사용 금지
- Privileged DaemonSet을 활용하여 직접 리소스 수집

## 시스템 아키텍처

### 구성 요소
1. **Resource Collector (DaemonSet)**
   - Python 3.9 기반 수집기
   - 각 노드에서 실행되는 privileged 파드
   - cgroup v1 및 /proc 파일시스템에서 직접 리소스 정보 수집
   - HTTP POST를 통해 API 서버로 데이터 전송
   - 5초 주기로 메트릭 수집

2. **API Server**
   - FastAPI 기반 REST API 서버
   - Pydantic을 활용한 데이터 검증
   - 인메모리 시계열 데이터 저장
   - Uvicorn ASGI 서버로 실행

## 프로젝트 구조

```
kubemonitor/
├── README.md                    # 프로젝트 설명서
├── api/
│   ├── Dockerfile.api          # API 서버 Docker 이미지
│   ├── main.py                 # FastAPI 애플리케이션
│   ├── models.py               # Pydantic 데이터 모델
│   ├── requirements.txt        # Python 의존성
│   └── storage.py              # 시계열 데이터 저장소
├── collector/
│   ├── Dockerfile.collector    # Collector Docker 이미지
│   ├── collector.py            # 메트릭 수집기
│   └── requirements.txt        # Python 의존성
├── deploy/
│   └── monitor.yaml            # Kubernetes 배포 매니페스트
├── docs/
│   ├── PRD.md                  # 제품 요구사항 문서
│   ├── images/                 # 스크린샷 및 다이어그램
│   └── report.md               # 구현 보고서
└── scripts/
    ├── 01-setup-environment.sh # 개발 환경 구축
    ├── 02-build-images.sh      # Docker 이미지 빌드
    ├── 03-deploy.sh            # Kubernetes 배포
    ├── 04-test.sh              # 시스템 테스트
    └── setup-all.sh            # 통합 설치 스크립트
```

## 리소스 수집 방법

### cgroup v1 기반 수집
1. **CPU 사용량**
   - 경로: `/sys/fs/cgroup/cpu,cpuacct/cpuacct.usage`
   - 계산: 누적 나노초 값에서 델타 계산
   - 단위: millicores 변환

2. **메모리 사용량**
   - 경로: `/proc/meminfo`
   - 파싱: MemTotal, MemFree, Buffers, Cached
   - 계산: used = total - free - buffers - cached
   - 단위: KB → bytes 변환

3. **디스크 I/O**
   - 경로: `/sys/fs/cgroup/blkio/blkio.throttle.io_service_bytes`
   - 파싱: Read/Write 바이트 추출
   - 단위: bytes (read/write 구분)

4. **네트워크 I/O**
   - 경로: `/proc/net/dev`
   - 파싱: 인터페이스별 RX/TX 바이트
   - 단위: bytes (rx/tx 구분)

## API 명세

### 데이터 모델 (Pydantic)
```python
class NodeMetrics(BaseModel):
    timestamp: datetime
    node: str
    cpu_usage: Optional[float]
    memory: Optional[Dict[str, int]]
    network: Optional[Dict[str, int]]
    disk: Optional[Dict[str, int]]

class PodMetrics(BaseModel):
    timestamp: datetime
    pod_name: str
    namespace: str
    cpu_usage: Optional[float]
    memory: Optional[Dict[str, int]]
    network: Optional[Dict[str, int]]
    disk: Optional[Dict[str, int]]
```

### API 엔드포인트

#### 노드 관련
```
GET /api/nodes
- 전체 노드 목록 및 리소스 사용량 조회

GET /api/nodes/{node}
- 특정 노드의 리소스 사용량 조회

GET /api/nodes/{node}/pods
- 해당 노드에 할당된 모든 파드 목록 및 리소스 사용량 조회
```

#### 파드 관련
```
GET /api/pods
- 전체 파드 목록 및 리소스 사용량 조회

GET /api/pods/{pod}
- 특정 파드의 실시간 리소스 사용량 조회
```

#### 네임스페이스 관련
```
GET /api/namespaces
- 전체 네임스페이스 목록 및 리소스 사용량 조회

GET /api/namespaces/{namespace}
- 특정 네임스페이스의 리소스 사용량 조회

GET /api/namespaces/{namespace}/pods
- 해당 네임스페이스의 파드 목록 및 리소스 사용량 조회
```

#### 디플로이먼트 관련
```
GET /api/namespaces/{namespace}/deployments
- 해당 네임스페이스의 디플로이먼트 목록 및 리소스 사용량 조회

GET /api/namespaces/{namespace}/deployments/{deployment}
- 특정 디플로이먼트의 리소스 사용량 조회

GET /api/namespaces/{namespace}/deployments/{deployment}/pods
- 해당 디플로이먼트의 파드 목록 및 리소스 사용량 조회
```

### 시계열 조회
```
GET /api/nodes/{node}?window={seconds}
- 특정 노드의 리소스 사용량 시계열 조회

GET /api/pods/{pod}?window={seconds}
- 특정 파드의 리소스 사용량 시계열 조회

GET /api/namespaces/{namespace}?window={seconds}
- 특정 네임스페이스의 리소스 사용량 시계열 조회

GET /api/namespaces/{namespace}/deployments/{deployment}?window={seconds}
- 특정 디플로이먼트의 리소스 사용량 시계열 조회
```
## 구현 세부사항

### Collector 구현
```python
# 메인 수집 루프
def main():
    while True:
        try:
            # 노드 메트릭 수집
            node_data = collect_node_metrics()
            send_to_api(f"api/nodes/{NODE_NAME}", node_data)
            
            # 파드 메트릭 수집
            pod_list = collect_pod_metrics()
            for pod in pod_list:
                send_to_api(f"api/pods/{pod_name}", pod)
                
            time.sleep(INTERVAL)
        except Exception as e:
            print(f"[ERROR] {e}")
            time.sleep(INTERVAL)
```

### API Server 구현
```python
# FastAPI 애플리케이션
app = FastAPI(title="Kubernetes Monitoring API")
store = MetricsStore()

@app.post("/api/nodes/{node_name}")
async def post_node_metrics(node_name: str, metrics: NodeMetrics):
    store.add_node_metrics(metrics)
    return {"status": "ok"}

@app.get("/api/nodes/{node_name}")
async def get_node(node_name: str, window: int = Query(0, ge=0)):
    if window > 0:
        return store.query_node_metrics(node_name, window)
    return store.node_store.get(node_name, [])
```

## Kubernetes 배포

### DaemonSet 설정
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: resource-collector
spec:
  template:
    spec:
      hostPID: true
      hostNetwork: true
      containers:
      - name: resource-collector
        image: kubemonitor-collector:latest
        securityContext:
          privileged: true
        env:
        - name: API_SERVER_URL
          value: "http://monitor-api-service:80"
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        volumeMounts:
        - name: cgroup
          mountPath: /sys/fs/cgroup
          readOnly: true
        - name: proc
          mountPath: /host/proc
          readOnly: true
```

### Service 설정
```yaml
apiVersion: v1
kind: Service
metadata:
  name: monitor-api-nodeport
spec:
  type: NodePort
  selector:
    app: monitor-api
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080
```

## 개발 환경 구축

### 필수 패키지 설치 (Ubuntu 22.04)
```bash
# Python 및 필수 도구
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv docker.io

# kubectl 설치
curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Minikube 설치
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

### 빌드 및 배포
```bash
# 통합 설치 스크립트 실행
bash scripts/setup-all.sh

# 또는 개별 실행
bash scripts/01-setup-environment.sh
bash scripts/02-build-images.sh
bash scripts/03-deploy.sh
bash scripts/04-test.sh
```

## 테스트 방법

### 부하 생성 테스트
```bash
# CPU 부하
kubectl run stress-cpu --image=progrium/stress --restart=Never -- stress --cpu 2 --timeout 60s

# 디스크 I/O 부하
kubectl run disk-test --image=busybox --restart=Never -- dd if=/dev/zero of=/tmp/test bs=1M count=100

# 네트워크 부하
kubectl run iperf-server --image=networkstatic/iperf3 -- -s
kubectl run iperf-client --image=networkstatic/iperf3 --restart=Never -- -c iperf-server -t 30
```

### API 검증
```bash
# Minikube IP 확인
MINIKUBE_IP=$(minikube ip)

# 노드 메트릭 조회
curl http://${MINIKUBE_IP}:30080/api/nodes

# 시계열 데이터 조회
curl "http://${MINIKUBE_IP}:30080/api/nodes/minikube?window=60"

# Swagger UI 접속
# http://${MINIKUBE_IP}:30080/docs
```

## 주요 개선사항

### 완료된 구현
- ✅ Python FastAPI 기반 API 서버
- ✅ Pydantic 모델을 통한 데이터 검증
- ✅ 시계열 데이터 저장소 (MetricsStore)
- ✅ Docker 이미지 및 Kubernetes 매니페스트
- ✅ 자동화된 설치 스크립트

### 진행 중인 작업
- 🔄 CPU 사용률 계산 로직 구현
- 🔄  파드별 메트릭 수집 로직
- 🔄 네임스페이스/디플로이먼트 집계 로직

## 주의사항
- Python 3.9+ 필요
- Minikube 환경에서 테스트됨
- cgroup v1 기반 (Ubuntu 22.04 기준)
- 노드당 약 128MB 메모리 사용 예상