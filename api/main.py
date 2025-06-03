from fastapi import FastAPI, HTTPException, Query
from datetime import datetime, timedelta
from typing import Dict, List
from models import NodeMetrics, PodMetrics, NamespaceMetrics, DeploymentMetrics
from storage import MetricsStore

app = FastAPI(title="Kubernetes Monitoring API", version="1.0.0")
store = MetricsStore()

# ===== 노드 메트릭 엔드포인트 =====

@app.post("/api/nodes/{node_name}")
async def post_node_metrics(node_name: str, metrics: NodeMetrics):
    """노드 메트릭 수집 (Collector가 POST로 전송)"""
    if node_name != metrics.node:
        raise HTTPException(status_code=400, detail="node_name 불일치")
    store.add_node_metrics(metrics)
    return {"status": "ok", "received": datetime.utcnow()}

@app.get("/api/nodes")
async def get_all_nodes():
    """모든 노드의 최신 메트릭 조회"""
    result = {}
    for node, lst in store.node_store.items():
        if lst:
            result[node] = [lst[-1]]  # 최신 1개만
    return result

@app.get("/api/nodes/{node_name}")
async def get_node(node_name: str, window: int = Query(0, ge=0)):
    """특정 노드 메트릭 조회 (시계열 지원)"""
    if node_name not in store.node_store:
        raise HTTPException(status_code=404, detail="해당 노드 없음")
    
    if window > 0:
        return store.query_node_metrics(node_name, window)
    return store.node_store[node_name]

@app.get("/api/nodes/{node_name}/pods")
async def get_node_pods(node_name: str):
    """노드 내 모든 포드 조회"""
    # 간단 예시: 모든 pod 내역 반환 (필요 시 노드 필터링 로직 추가)
    return store.pod_store

# ===== 포드 메트릭 엔드포인트 =====

@app.post("/api/pods/{pod_name}")
async def post_pod_metrics(pod_name: str, metrics: PodMetrics):
    """포드 메트릭 수집"""
    if pod_name != metrics.pod_name:
        raise HTTPException(status_code=400, detail="pod_name 불일치")
    store.add_pod_metrics(metrics)
    return {"status": "ok", "received": datetime.utcnow()}

@app.get("/api/pods")
async def get_all_pods():
    """모든 포드의 최신 메트릭 조회"""
    result = {}
    for pod, lst in store.pod_store.items():
        if lst:
            result[pod] = [lst[-1]]  # 최신 1개만
    return result

@app.get("/api/pods/{pod_name}")
async def get_pod(pod_name: str, window: int = Query(0, ge=0)):
    """특정 포드 메트릭 조회 (시계열 지원)"""
    if pod_name not in store.pod_store:
        raise HTTPException(status_code=404, detail="해당 포드 없음")
    
    if window > 0:
        return store.query_pod_metrics(pod_name, window)
    return store.pod_store[pod_name]

# ===== 네임스페이스 메트릭 엔드포인트 =====

@app.post("/api/namespaces/{ns_name}")
async def post_namespace_metrics(ns_name: str, metrics: NamespaceMetrics):
    """네임스페이스 메트릭 수집"""
    if ns_name != metrics.namespace:
        raise HTTPException(status_code=400, detail="namespace 불일치")
    store.add_namespace_metrics(metrics)
    return {"status": "ok", "received": datetime.utcnow()}

@app.get("/api/namespaces")
async def get_all_namespaces():
    """모든 네임스페이스의 최신 메트릭 조회"""
    result = {}
    for ns, lst in store.namespace_store.items():
        if lst:
            result[ns] = [lst[-1]]  # 최신 1개만
    return result

@app.get("/api/namespaces/{ns_name}")
async def get_namespace(ns_name: str, window: int = Query(0, ge=0)):
    """특정 네임스페이스 메트릭 조회 (시계열 지원)"""
    if ns_name not in store.namespace_store:
        raise HTTPException(status_code=404, detail="해당 네임스페이스 없음")
    
    if window > 0:
        return store.query_namespace_metrics(ns_name, window)
    return store.namespace_store[ns_name]

@app.get("/api/namespaces/{ns_name}/pods")
async def get_namespace_pods(ns_name: str):
    """네임스페이스 내 모든 포드 조회"""
    # 예시: 모든 pod 반환 (필요 시 namespace 필터링 로직 추가)
    return store.pod_store

@app.get("/api/namespaces/{ns_name}/deployments")
async def get_namespace_deployments(ns_name: str):
    """네임스페이스 내 모든 디플로이먼트의 최신 메트릭 조회"""
    result = {}
    for key, lst in store.deployment_store.items():
        if key.startswith(f"{ns_name}/") and lst:
            result[key] = [lst[-1]]  # 최신 1개만
    return result

# ===== 디플로이먼트 메트릭 엔드포인트 =====

@app.post("/api/namespaces/{ns_name}/deployments/{dp_name}")
async def post_deployment_metrics(ns_name: str, dp_name: str, metrics: DeploymentMetrics):
    """디플로이먼트 메트릭 수집"""
    if ns_name != metrics.namespace or dp_name != metrics.deployment:
        raise HTTPException(status_code=400, detail="namespace/deployment 불일치")
    store.add_deployment_metrics(metrics)
    return {"status": "ok", "received": datetime.utcnow()}

@app.get("/api/namespaces/{ns_name}/deployments/{dp_name}")
async def get_deployment(ns_name: str, dp_name: str, window: int = Query(0, ge=0)):
    """특정 디플로이먼트 메트릭 조회 (시계열 지원)"""
    key = f"{ns_name}/{dp_name}"
    if key not in store.deployment_store:
        raise HTTPException(status_code=404, detail="해당 디플로이먼트 없음")
    
    if window > 0:
        return store.query_deployment_metrics(ns_name, dp_name, window)
    return store.deployment_store[key]

@app.get("/api/namespaces/{ns_name}/deployments/{dp_name}/pods")
async def get_deployment_pods(ns_name: str, dp_name: str):
    """특정 디플로이먼트의 모든 포드 조회"""
    # 예시: 모든 pod 반환 (필요 시 배포 기준 필터링 로직 추가)
    return store.pod_store

# ===== 헬스체크 엔드포인트 =====

@app.get("/")
async def root():
    """API 서버 상태 확인"""
    return {"message": "Kubernetes Monitoring API", "status": "running"}

@app.get("/health")
async def health_check():
    """헬스체크 엔드포인트"""
    return {"status": "healthy", "timestamp": datetime.utcnow()} 