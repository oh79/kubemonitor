from typing import Dict, List
from datetime import datetime, timedelta
from models import NodeMetrics, PodMetrics, NamespaceMetrics, DeploymentMetrics

class MetricsStore:
    """인메모리 메트릭 저장소"""
    
    def __init__(self):
        self.node_store: Dict[str, List[NodeMetrics]] = {}
        self.pod_store: Dict[str, List[PodMetrics]] = {}
        self.namespace_store: Dict[str, List[NamespaceMetrics]] = {}
        self.deployment_store: Dict[str, List[DeploymentMetrics]] = {}

    def add_node_metrics(self, data: NodeMetrics):
        """노드 메트릭 추가"""
        self.node_store.setdefault(data.node, []).append(data)

    def query_node_metrics(self, node: str, window: int):
        """노드 메트릭 시계열 조회 (window: 초 단위)"""
        now = datetime.utcnow()
        cutoff = now - timedelta(seconds=window)
        return [m for m in self.node_store.get(node, []) if m.timestamp >= cutoff]

    def add_pod_metrics(self, data: PodMetrics):
        """포드 메트릭 추가"""
        key = data.pod_name
        self.pod_store.setdefault(key, []).append(data)

    def query_pod_metrics(self, pod_name: str, window: int):
        """포드 메트릭 시계열 조회"""
        now = datetime.utcnow()
        cutoff = now - timedelta(seconds=window)
        return [m for m in self.pod_store.get(pod_name, []) if m.timestamp >= cutoff]

    def add_namespace_metrics(self, data: NamespaceMetrics):
        """네임스페이스 메트릭 추가"""
        self.namespace_store.setdefault(data.namespace, []).append(data)

    def query_namespace_metrics(self, ns: str, window: int):
        """네임스페이스 메트릭 시계열 조회"""
        now = datetime.utcnow()
        cutoff = now - timedelta(seconds=window)
        return [m for m in self.namespace_store.get(ns, []) if m.timestamp >= cutoff]

    def add_deployment_metrics(self, data: DeploymentMetrics):
        """디플로이먼트 메트릭 추가"""
        key = f"{data.namespace}/{data.deployment}"
        self.deployment_store.setdefault(key, []).append(data)

    def query_deployment_metrics(self, ns: str, dp: str, window: int):
        """디플로이먼트 메트릭 시계열 조회"""
        key = f"{ns}/{dp}"
        now = datetime.utcnow()
        cutoff = now - timedelta(seconds=window)
        return [m for m in self.deployment_store.get(key, []) if m.timestamp >= cutoff] 