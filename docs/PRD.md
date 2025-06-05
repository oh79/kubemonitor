GitHub 프로젝트를 분석하여 PRD를 개선하겠습니다.

# 쿠버네티스 클라우드 모니터링 서비스 PRD (개선판)

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
   - 각 노드에서 실행되는 privileged 파드
   - cgroup v2 파일시스템에서 직접 리소스 정보 수집
   - gRPC를 통해 API 서버로 데이터 전송
   - 10초 주기로 메트릭 수집

2. **API Server**
   - gRPC 서버로 수집된 데이터 수신
   - RESTful API 엔드포인트 제공
   - 인메모리 시계열 데이터 저장 (최대 1시간)
   - Kubernetes API 서버와 연동하여 파드/디플로이먼트 정보 조회

3. **Monitoring Dashboard (선택사항)**
   - React 기반 웹 대시보드
   - 실시간 리소스 사용량 시각화

## 리소스 수집 방법

### cgroup v2 기반 수집
1. **CPU 사용량**
   - 경로: `/sys/fs/cgroup/system.slice/containerd.service/<container-id>/cpu.stat`
   - 계산: usage_usec 델타값으로 CPU 사용률 계산
   - 단위: millicores

2. **메모리 사용량**
   - 경로: `/sys/fs/cgroup/system.slice/containerd.service/<container-id>/memory.current`
   - 단위: bytes

3. **디스크 I/O**
   - 경로: `/sys/fs/cgroup/system.slice/containerd.service/<container-id>/io.stat`
   - 파싱: 디바이스별 rbytes, wbytes 추출
   - 단위: bytes (read/write 구분)

4. **네트워크 I/O**
   - 경로: `/proc/<pid>/net/dev`
   - 파싱: 인터페이스별 rx_bytes, tx_bytes 추출
   - 단위: bytes (rx/tx 구분)

### 컨테이너 ID 매핑
```go
// 파드 -> 컨테이너 ID 매핑을 위한 구조
type ContainerInfo struct {
    PodName       string
    PodNamespace  string
    ContainerID   string
    ContainerName string
}
```

## 프로젝트 구조

```
kubemonitor/
├── cmd/
│   ├── collector/
│   │   └── main.go          # DaemonSet 엔트리포인트
│   └── apiserver/
│       └── main.go          # API 서버 엔트리포인트
├── pkg/
│   ├── collector/
│   │   ├── collector.go     # 메트릭 수집 로직
│   │   ├── cgroup.go        # cgroup v2 파싱
│   │   └── sender.go        # gRPC 클라이언트
│   ├── apiserver/
│   │   ├── server.go        # gRPC/HTTP 서버
│   │   ├── handlers.go      # REST API 핸들러
│   │   └── storage.go       # 시계열 데이터 저장
│   └── common/
│       ├── types.go         # 공통 타입 정의
│       └── utils.go         # 유틸리티 함수
├── api/
│   └── proto/
│       └── metrics.proto    # gRPC 프로토콜 정의
├── deployments/
│   ├── monitor.yaml         # 전체 배포 파일
│   ├── daemonset.yaml       # DaemonSet 정의
│   ├── apiserver.yaml       # API 서버 Deployment
│   └── rbac.yaml           # RBAC 권한 설정
├── build/
│   ├── collector.Dockerfile
│   └── apiserver.Dockerfile
└── scripts/
    ├── build.sh             # 빌드 스크립트
    └── deploy.sh            # 배포 스크립트
```

## API 명세

### 노드 관련 API
```
GET /api/v1/nodes
- 전체 노드 목록 및 리소스 사용량
- Query Parameters:
  - window: 시계열 조회 기간 (초)

GET /api/v1/nodes/{nodeName}
- 특정 노드의 리소스 사용량
- 호스트 프로세스 포함

GET /api/v1/nodes/{nodeName}/pods
- 해당 노드의 모든 파드 목록 및 리소스 사용량
```

### 파드 관련 API
```
GET /api/v1/pods
- 전체 파드 목록 및 리소스 사용량
- Query Parameters:
  - namespace: 네임스페이스 필터
  - window: 시계열 조회 기간

GET /api/v1/namespaces/{namespace}/pods/{podName}
- 특정 파드의 실시간 리소스 사용량
```

### 네임스페이스 관련 API
```
GET /api/v1/namespaces
- 전체 네임스페이스 목록 및 집계된 리소스 사용량

GET /api/v1/namespaces/{namespace}
- 특정 네임스페이스의 리소스 사용량

GET /api/v1/namespaces/{namespace}/pods
- 해당 네임스페이스의 파드 목록 및 리소스 사용량
```

### 디플로이먼트 관련 API
```
GET /api/v1/namespaces/{namespace}/deployments
- 해당 네임스페이스의 디플로이먼트 목록 및 리소스 사용량

GET /api/v1/namespaces/{namespace}/deployments/{deploymentName}
- 특정 디플로이먼트의 리소스 사용량

GET /api/v1/namespaces/{namespace}/deployments/{deploymentName}/pods
- 해당 디플로이먼트의 파드 목록 및 리소스 사용량
```

## 구현 세부사항

### DaemonSet Collector
```go
// 메인 수집 루프
func (c *Collector) Start() {
    ticker := time.NewTicker(10 * time.Second)
    for range ticker.C {
        metrics := c.collectMetrics()
        c.sendToAPIServer(metrics)
    }
}

// cgroup v2 메트릭 수집
func (c *Collector) collectMetrics() []Metric {
    // 1. 컨테이너 목록 조회
    containers := c.getContainers()
    
    // 2. 각 컨테이너별 메트릭 수집
    for _, container := range containers {
        cpu := c.collectCPU(container.ID)
        memory := c.collectMemory(container.ID)
        disk := c.collectDisk(container.ID)
        network := c.collectNetwork(container.PID)
    }
}
```

### API Server
```go
// 시계열 데이터 저장 구조
type TimeSeriesStorage struct {
    mu      sync.RWMutex
    metrics map[string]*CircularBuffer // key: resourceID
}

// REST API 핸들러
func (s *APIServer) setupRoutes() {
    r := mux.NewRouter()
    r.HandleFunc("/api/v1/nodes", s.getNodes)
    r.HandleFunc("/api/v1/nodes/{nodeName}", s.getNode)
    r.HandleFunc("/api/v1/pods", s.getPods)
    // ... 추가 라우트
}
```

### gRPC 통신
```protobuf
syntax = "proto3";

service MetricsService {
    rpc SendMetrics(MetricsRequest) returns (MetricsResponse);
}

message Metric {
    string pod_name = 1;
    string namespace = 2;
    int64 cpu_millicores = 3;
    int64 memory_bytes = 4;
    int64 disk_read_bytes = 5;
    int64 disk_write_bytes = 6;
    int64 network_rx_bytes = 7;
    int64 network_tx_bytes = 8;
    int64 timestamp = 9;
}
```

## Kubernetes 배포

### DaemonSet 설정
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: resource-collector
spec:
  selector:
    matchLabels:
      app: resource-collector
  template:
    spec:
      hostPID: true
      hostNetwork: true
      containers:
      - name: collector
        image: kubemonitor/collector:latest
        securityContext:
          privileged: true
        volumeMounts:
        - name: cgroup
          mountPath: /sys/fs/cgroup
          readOnly: true
        - name: proc
          mountPath: /proc
          readOnly: true
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: API_SERVER_ADDR
          value: "monitor-apiserver:50051"
```

### RBAC 설정
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: resource-monitor
rules:
- apiGroups: [""]
  resources: ["pods", "nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list"]
```

## 테스트 방법

### 부하 생성 테스트
```bash
# CPU 부하
kubectl run stress-cpu --image=progrium/stress --rm -it -- --cpu 2

# 메모리 부하
kubectl run stress-mem --image=progrium/stress --rm -it -- --vm 1 --vm-bytes 512M

# 디스크 I/O 부하
kubectl run stress-io --image=busybox --rm -it -- dd if=/dev/zero of=/tmp/test bs=1M count=1000

# 네트워크 부하
kubectl run iperf-server --image=networkstatic/iperf3 -- -s
kubectl run iperf-client --image=networkstatic/iperf3 --rm -it -- -c iperf-server
```

### API 검증
```bash
# 노드 메트릭 조회
curl http://localhost:8080/api/v1/nodes

# 특정 파드 메트릭 조회
curl http://localhost:8080/api/v1/namespaces/default/pods/stress-cpu

# 시계열 데이터 조회 (최근 5분)
curl http://localhost:8080/api/v1/nodes?window=300
```

## 개발 환경 구축

### 필수 패키지 설치 (Ubuntu 22.04)
```bash
# Go 1.21 설치
wget https://go.dev/dl/go1.21.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc

# Docker 설치
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER

# kubectl 설치
curl -LO https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 프로토콜 버퍼 컴파일러
sudo apt-get install -y protobuf-compiler
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
```

### 빌드 및 배포
```bash
# 이미지 빌드
make build-images

# 쿠버네티스 배포
kubectl apply -f deployments/monitor.yaml

# 로그 확인
kubectl logs -f daemonset/resource-collector
kubectl logs -f deployment/monitor-apiserver
```

## 주의사항
- cgroup v2를 사용하는 시스템에서만 동작
- Kubernetes 1.24+ 버전 필요
- Containerd 런타임 환경 가정
- 노드당 약 100MB 메모리 사용 예상