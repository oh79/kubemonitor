from fastapi import FastAPI, HTTPException, Query
from datetime import datetime, timedelta
from typing import Dict, List
from models import NodeMetrics, PodMetrics, NamespaceMetrics, DeploymentMetrics
from storage import MetricsStore

# 과제 요구사항에 따른 FastAPI 애플리케이션
app = FastAPI(
    title="Kubernetes Monitoring API", 
    version="1.0.0",
    description="쿠버네티스를 활용한 클라우드 모니터링 서비스"
)
store = MetricsStore()

# ===== 내부 메트릭 수집용 POST 엔드포인트 (Swagger에서 숨김) =====

@app.post("/api/nodes/{node_name}", include_in_schema=False)
async def post_node_metrics(node_name: str, metrics: NodeMetrics):
    """노드 메트릭 수집 (Collector가 POST로 전송) - 내부용"""
    if node_name != metrics.node:
        raise HTTPException(status_code=400, detail="node_name 불일치")
    store.add_node_metrics(metrics)
    return {"status": "ok"}

@app.post("/api/pods/{pod_name}", include_in_schema=False)
async def post_pod_metrics(pod_name: str, metrics: PodMetrics):
    """포드 메트릭 수집 - 내부용"""
    pod_field = getattr(metrics, 'pod', None) or getattr(metrics, 'pod_name', None)
    if pod_name != pod_field:
        raise HTTPException(status_code=400, detail="pod_name 불일치")
    store.add_pod_metrics(metrics)
    return {"status": "ok"}

@app.post("/api/namespaces/{ns_name}", include_in_schema=False)
async def post_namespace_metrics(ns_name: str, metrics: NamespaceMetrics):
    """네임스페이스 메트릭 수집 - 내부용"""
    if ns_name != metrics.namespace:
        raise HTTPException(status_code=400, detail="namespace 불일치")
    store.add_namespace_metrics(metrics)
    return {"status": "ok"}

@app.post("/api/namespaces/{ns_name}/deployments/{dp_name}", include_in_schema=False)
async def post_deployment_metrics(ns_name: str, dp_name: str, metrics: DeploymentMetrics):
    """디플로이먼트 메트릭 수집 - 내부용"""
    if ns_name != metrics.namespace or dp_name != metrics.deployment:
        raise HTTPException(status_code=400, detail="namespace/deployment 불일치")
    store.add_deployment_metrics(metrics)
    return {"status": "ok"}

# ===== 1. 노드 기준 API =====

@app.get("/api/nodes", 
         tags=["1️⃣ 노드 기준"],
         summary="전체 노드 목록 및 리소스 사용량 / 시계열 조회",
         description="전체 노드 목록 및 리소스 사용량 조회. window 파라미터가 있으면 시계열 데이터 반환")
async def get_all_nodes(window: int = Query(None, gt=0, description="시계열 조회 시간(초). 없으면 최신 데이터만 반환")):
    """전체 노드 목록 및 리소스 사용량 조회 / 시계열 조회"""
    result = {}
    for node, lst in store.node_store.items():
        if lst:
            if window is not None:
                # 시계열 조회: GET /api/nodes?window=<second>
                result[node] = store.query_node_metrics(node, window)
            else:
                # 최신 데이터만: GET /api/nodes
                result[node] = [lst[-1]]
    return result

@app.get("/api/nodes/{node}", 
         tags=["1️⃣ 노드 기준"],
         summary="특정 노드의 리소스 사용량 / 시계열 조회",
         description="특정 노드의 리소스 사용량 조회. 호스트 프로세스의 리소스 사용량도 포함됨. window 파라미터가 있으면 시계열 데이터 반환")
async def get_node(node: str, window: int = Query(None, gt=0, description="시계열 조회 시간(초). 없으면 전체 데이터 반환")):
    """특정 노드의 리소스 사용량 조회 (호스트 프로세스의 리소스 사용량도 포함됨) / 시계열 조회"""
    if node not in store.node_store:
        raise HTTPException(status_code=404, detail="해당 노드 없음")
    
    if window is not None:
        # 시계열 조회: GET /api/nodes/<nodeName>?window=<second>
        return store.query_node_metrics(node, window)
    else:
        # 전체 데이터: GET /api/nodes/<node>
        return store.node_store[node]

@app.get("/api/nodes/{node}/pods", 
         tags=["1️⃣ 노드 기준"],
         summary="해당 노드에 할당된 모든 포드 목록 및 리소스 사용량",
         description="해당 노드에 할당된 모든 포드 목록 및 리소스 사용량 조회. 포드들에 의한 리소스 사용량만 포함됨")
async def get_node_pods(node: str):
    """해당 노드에 할당된 모든 포드 목록 및 리소스 사용량 조회 (포드들에 의한 리소스 사용량만 포함됨)"""
    result = {}
    for pod_name, pod_list in store.pod_store.items():
        if pod_list:
            latest_pod = pod_list[-1]
            # 해당 노드의 포드만 필터링
            if latest_pod.node == node:
                result[pod_name] = [latest_pod]
    return result

# ===== 2. 포드 기준 API =====

@app.get("/api/pods", 
         tags=["2️⃣ 포드 기준"],
         summary="전체 포드 목록 및 리소스 사용량 / 시계열 조회",
         description="전체 포드 목록 및 리소스 사용량 조회. window 파라미터가 있으면 시계열 데이터 반환")
async def get_all_pods(window: int = Query(None, gt=0, description="시계열 조회 시간(초). 없으면 최신 데이터만 반환")):
    """전체 포드 목록 및 리소스 사용량 조회 / 시계열 조회"""
    result = {}
    for pod, lst in store.pod_store.items():
        if lst:
            if window is not None:
                # 시계열 조회: GET /api/pods?window=<second>
                result[pod] = store.query_pod_metrics(pod, window)
            else:
                # 최신 데이터만: GET /api/pods
                result[pod] = [lst[-1]]
    return result

@app.get("/api/pods/{podName}", 
         tags=["2️⃣ 포드 기준"],
         summary="특정 포드의 실시간 리소스 사용량 / 시계열 조회",
         description="특정 포드의 실시간 리소스 사용량 조회. window 파라미터가 있으면 시계열 데이터 반환")
async def get_pod(podName: str, window: int = Query(None, gt=0, description="시계열 조회 시간(초). 없으면 전체 데이터 반환")):
    """특정 포드의 실시간 리소스 사용량 조회 / 시계열 조회"""
    if podName not in store.pod_store:
        raise HTTPException(status_code=404, detail="해당 포드 없음")
    
    if window is not None:
        # 시계열 조회: GET /api/pods/<podName>?window=<second>
        return store.query_pod_metrics(podName, window)
    else:
        # 전체 데이터: GET /api/pods/<podName>
        return store.pod_store[podName]

# ===== 3. 네임스페이스 기준 API =====

@app.get("/api/namespaces", 
         tags=["3️⃣ 네임스페이스 기준"],
         summary="전체 네임스페이스 목록 및 리소스 사용량 / 시계열 조회",
         description="전체 네임스페이스 목록 및 리소스 사용량 조회. window 파라미터가 있으면 시계열 데이터 반환")
async def get_all_namespaces(window: int = Query(None, gt=0, description="시계열 조회 시간(초). 없으면 최신 데이터만 반환")):
    """전체 네임스페이스 목록 및 리소스 사용량 조회 / 시계열 조회"""
    result = {}
    for ns, lst in store.namespace_store.items():
        if lst:
            if window is not None:
                # 시계열 조회: GET /api/namespaces?window=<second>
                result[ns] = store.query_namespace_metrics(ns, window)
            else:
                # 최신 데이터만: GET /api/namespaces
                result[ns] = [lst[-1]]
    return result

@app.get("/api/namespaces/{nsName}", 
         tags=["3️⃣ 네임스페이스 기준"],
         summary="특정 네임스페이스의 리소스 사용량 / 시계열 조회",
         description="특정 네임스페이스의 리소스 사용량 조회. window 파라미터가 있으면 시계열 데이터 반환")
async def get_namespace(nsName: str, window: int = Query(None, gt=0, description="시계열 조회 시간(초). 없으면 전체 데이터 반환")):
    """특정 네임스페이스의 리소스 사용량 조회 / 시계열 조회"""
    if nsName not in store.namespace_store:
        raise HTTPException(status_code=404, detail="해당 네임스페이스 없음")
    
    if window is not None:
        # 시계열 조회: GET /api/namespaces/<nsName>?window=<second>
        return store.query_namespace_metrics(nsName, window)
    else:
        # 전체 데이터: GET /api/namespaces/<nsName>
        return store.namespace_store[nsName]

@app.get("/api/namespaces/{nsName}/pods", 
         tags=["3️⃣ 네임스페이스 기준"],
         summary="해당 네임스페이스의 포드 목록 및 리소스 사용량",
         description="해당 네임스페이스의 포드 목록 및 리소스 사용량 조회")
async def get_namespace_pods(nsName: str):
    """해당 네임스페이스의 포드 목록 및 리소스 사용량 조회"""
    result = {}
    for pod_name, pod_list in store.pod_store.items():
        if pod_list:
            latest_pod = pod_list[-1]
            # 네임스페이스가 일치하는 포드만 필터링
            if latest_pod.namespace == nsName:
                result[pod_name] = [latest_pod]
    return result

# ===== 4. 디플로이먼트 기준 API =====

@app.get("/api/namespaces/{nsName}/deployments", 
         tags=["4️⃣ 디플로이먼트 기준"],
         summary="해당 네임스페이스의 디플로이먼트 목록 및 리소스 사용량",
         description="해당 네임스페이스의 디플로이먼트 목록 및 리소스 사용량 조회")
async def get_namespace_deployments(nsName: str):
    """해당 네임스페이스의 디플로이먼트 목록 및 리소스 사용량 조회"""
    result = {}
    for key, lst in store.deployment_store.items():
        if key.startswith(f"{nsName}/") and lst:
            deployment_name = key.split("/", 1)[1]
            result[deployment_name] = [lst[-1]]  # 최신 1개만
    return result

@app.get("/api/namespaces/{nsName}/deployments/{dpName}", 
         tags=["4️⃣ 디플로이먼트 기준"],
         summary="해당 디플로이먼트의 리소스 사용량",
         description="해당 디플로이먼트의 리소스 사용량 조회")
async def get_deployment(nsName: str, dpName: str):
    """특정 디플로이먼트의 리소스 사용량 조회"""
    key = f"{nsName}/{dpName}"
    if key not in store.deployment_store:
        raise HTTPException(status_code=404, detail="해당 디플로이먼트 없음")
    return store.deployment_store[key]

@app.get("/api/namespaces/{nsName}/deployments/{dpName}/pods", 
         tags=["4️⃣ 디플로이먼트 기준"],
         summary="해당 디플로이먼트의 포드 목록 및 리소스 사용량",
         description="해당 디플로이먼트의 포드 목록 및 리소스 사용량 조회")
async def get_deployment_pods(nsName: str, dpName: str):
    """해당 디플로이먼트의 포드 목록 및 리소스 사용량 조회"""
    result = {}
    for pod_name, pod_list in store.pod_store.items():
        if pod_list:
            latest_pod = pod_list[-1]
            # 네임스페이스와 디플로이먼트가 일치하는 포드만 필터링
            if (latest_pod.namespace == nsName and 
                hasattr(latest_pod, 'deployment') and 
                latest_pod.deployment == dpName):
                result[pod_name] = [latest_pod]
    return result

# ===== 헬스체크 엔드포인트 =====

@app.get("/", include_in_schema=False)
async def root():
    """API 서버 상태 확인"""
    return {"message": "Kubernetes Monitoring API", "status": "running"}

@app.get("/health", include_in_schema=False)
async def health_check():
    """헬스체크 엔드포인트"""
    return {"status": "healthy", "timestamp": datetime.utcnow()} 