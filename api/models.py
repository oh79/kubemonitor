from pydantic import BaseModel, Field
from typing import Optional, Dict
from datetime import datetime

class NodeMetrics(BaseModel):
    """노드 메트릭 모델"""
    timestamp: datetime = Field(..., example="2025-05-09T23:02:00Z")
    node: str = Field(..., example="ubuntu")
    cpu_usage: Optional[float] = Field(None, example=12.5)
    cgroup_cpu_ns: Optional[int] = Field(None, example=1234567890)
    memory: Optional[Dict[str, int]] = Field(None, example={"total_kb":2048000,"used_kb":1024000,"free_kb":1024000})
    network: Optional[Dict[str, int]] = Field(None, example={"rx_bytes":123456,"tx_bytes":223344})
    disk: Optional[Dict[str, int]] = Field(None, example={"read":135245,"write":24621})

class PodMetrics(BaseModel):
    """포드 메트릭 모델"""
    timestamp: datetime
    pod_name: str
    namespace: str
    cpu_usage: Optional[float]
    memory: Optional[Dict[str, int]]
    network: Optional[Dict[str, int]]
    disk: Optional[Dict[str, int]]

class NamespaceMetrics(BaseModel):
    """네임스페이스 메트릭 모델"""
    timestamp: datetime
    namespace: str
    cpu_usage: Optional[float]
    memory_bytes: Optional[int]
    disk_read_bytes: Optional[int]
    disk_write_bytes: Optional[int]
    network_rx_bytes: Optional[int]
    network_tx_bytes: Optional[int]

class DeploymentMetrics(BaseModel):
    """디플로이먼트 메트릭 모델"""
    timestamp: datetime
    namespace: str
    deployment: str
    cpu_usage: Optional[float]
    memory_bytes: Optional[int]
    disk_read_bytes: Optional[int]
    disk_write_bytes: Optional[int]
    network_rx_bytes: Optional[int]
    network_tx_bytes: Optional[int] 