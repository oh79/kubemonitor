from pydantic import BaseModel, Field
from typing import Optional, Dict
from datetime import datetime

class NodeMetrics(BaseModel):
    """노드 메트릭 모델 (예시 응답 형식 기준)"""
    timestamp: datetime = Field(..., example="2025-05-09T23:02:00Z")
    node: str = Field(..., example="ubuntu")
    cpu_millicores: Optional[int] = Field(None, example=132, description="CPU 사용량 (밀리코어)")
    memory_bytes: Optional[int] = Field(None, example=45219840, description="메모리 사용량 (bytes)")
    disk_read_bytes: Optional[int] = Field(None, example=135245, description="디스크 읽기 (bytes)")
    disk_write_bytes: Optional[int] = Field(None, example=24621, description="디스크 쓰기 (bytes)")
    network_rx_bytes: Optional[int] = Field(None, example=123456, description="네트워크 수신 (bytes)")
    network_tx_bytes: Optional[int] = Field(None, example=223344, description="네트워크 송신 (bytes)")
    
    # 기존 호환성을 위한 추가 필드들 (내부 처리용)
    cpu_usage: Optional[float] = Field(None, example=12.5, description="CPU 사용률 (퍼센트) - 내부용")
    cpu_usage_percent: Optional[float] = Field(None, example=12.5, description="CPU 사용률 (퍼센트) - 테스트 호환성")
    cgroup_cpu_ns: Optional[int] = Field(None, example=1234567890, description="CPU 누적 사용량 (나노초)")
    memory: Optional[Dict[str, int]] = Field(None, example={"total_kb":2048000,"used_kb":1024000,"free_kb":1024000}, description="메모리 상세 정보")
    network: Optional[Dict[str, int]] = Field(None, example={"rx_bytes":123456,"tx_bytes":223344}, description="네트워크 상세 정보")
    disk: Optional[Dict[str, int]] = Field(None, example={"read_bytes":135245,"write_bytes":24621}, description="디스크 상세 정보")

class PodMetrics(BaseModel):
    """포드 메트릭 모델 (예시 응답 형식 기준)"""
    timestamp: datetime = Field(..., example="2025-05-09T23:02:00Z")
    node: str = Field(..., example="ubuntu", description="포드가 실행 중인 노드")
    namespace: str = Field(..., example="default")
    deployment: Optional[str] = Field(None, example="test", description="포드가 속한 디플로이먼트")
    pod: str = Field(..., example="myapp-12345", description="포드 이름")
    cpu_millicores: Optional[int] = Field(None, example=132, description="CPU 사용량 (밀리코어)")
    memory_bytes: Optional[int] = Field(None, example=45219840, description="메모리 사용량 (bytes)")
    disk_read_bytes: Optional[int] = Field(None, example=135245, description="디스크 읽기 (bytes)")
    disk_write_bytes: Optional[int] = Field(None, example=24621, description="디스크 쓰기 (bytes)")
    network_rx_bytes: Optional[int] = Field(None, example=123456, description="네트워크 수신 (bytes)")
    network_tx_bytes: Optional[int] = Field(None, example=223344, description="네트워크 송신 (bytes)")
    
    # 기존 호환성을 위한 필드들 (내부 처리용)
    pod_name: Optional[str] = Field(None, example="myapp-12345", description="포드 이름 (호환성)")
    cpu_usage: Optional[float] = Field(None, example=5.2, description="CPU 사용률 (퍼센트)")
    memory: Optional[Dict[str, int]] = Field(None, example={"used_bytes":134217728})
    network: Optional[Dict[str, int]] = Field(None, example={"rx_bytes":12345,"tx_bytes":67890})
    disk: Optional[Dict[str, int]] = Field(None, example={"read_bytes":1024,"write_bytes":2048})

class NamespaceMetrics(BaseModel):
    """네임스페이스 메트릭 모델 (예시 응답 형식 기준)"""
    timestamp: datetime = Field(..., example="2025-05-09T23:02:00Z")
    namespace: str = Field(..., example="default")
    cpu_millicores: Optional[int] = Field(None, example=345, description="네임스페이스 내 총 CPU 사용량 (밀리코어)")
    memory_bytes: Optional[int] = Field(None, example=93748190, description="네임스페이스 내 총 메모리 사용량 (bytes)")
    disk_read_bytes: Optional[int] = Field(None, example=39852215, description="네임스페이스 내 총 디스크 읽기 (bytes)")
    disk_write_bytes: Optional[int] = Field(None, example=2244582, description="네임스페이스 내 총 디스크 쓰기 (bytes)")
    network_rx_bytes: Optional[int] = Field(None, example=390563, description="네임스페이스 내 총 네트워크 수신 (bytes)")
    network_tx_bytes: Optional[int] = Field(None, example=452852, description="네임스페이스 내 총 네트워크 송신 (bytes)")
    
    # 기존 호환성을 위한 필드 (내부 처리용)
    cpu_usage: Optional[float] = Field(None, example=25.7, description="CPU 사용률 (퍼센트)")

class DeploymentMetrics(BaseModel):
    """디플로이먼트 메트릭 모델 (예시 응답 형식 기준)"""
    timestamp: datetime = Field(..., example="2025-05-09T23:02:00Z")
    namespace: str = Field(..., example="default")
    deployment: str = Field(..., example="test")
    cpu_millicores: Optional[int] = Field(None, example=345, description="디플로이먼트 내 총 CPU 사용량 (밀리코어)")
    memory_bytes: Optional[int] = Field(None, example=93748190, description="디플로이먼트 내 총 메모리 사용량 (bytes)")
    disk_read_bytes: Optional[int] = Field(None, example=39852215, description="디플로이먼트 내 총 디스크 읽기 (bytes)")
    disk_write_bytes: Optional[int] = Field(None, example=2244582, description="디플로이먼트 내 총 디스크 쓰기 (bytes)")
    network_rx_bytes: Optional[int] = Field(None, example=390563, description="디플로이먼트 내 총 네트워크 수신 (bytes)")
    network_tx_bytes: Optional[int] = Field(None, example=452852, description="디플로이먼트 내 총 네트워크 송신 (bytes)")
    
    # 기존 호환성을 위한 필드 (내부 처리용)
    cpu_usage: Optional[float] = Field(None, example=15.3, description="CPU 사용률 (퍼센트)") 