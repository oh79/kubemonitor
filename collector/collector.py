#!/usr/bin/env python3
import os
import time
import json
import requests
import glob

# 환경 변수 설정
API_SERVER_URL = os.getenv("API_SERVER_URL", "http://localhost:8080")
NODE_NAME       = os.getenv("NODE_NAME", "unknown-node")
INTERVAL        = int(os.getenv("COLLECT_INTERVAL", "5"))

def read_cgroup_cpu_usage():
    """cgroup v1에서 CPU 사용량(nanoseconds) 읽기"""
    path = "/sys/fs/cgroup/cpu,cpuacct/cpuacct.usage"
    try:
        with open(path, "r") as f:
            return int(f.read().strip())
    except:
        return None

def read_proc_meminfo():
    """호스트의 /proc/meminfo에서 메모리 정보 읽기"""
    meminfo = {}
    try:
        with open("/host/proc/meminfo", "r") as f:
            for line in f:
                key, val = line.split(":", 1)
                meminfo[key.strip()] = int(val.strip().split()[0])
        total   = meminfo.get("MemTotal", 0)
        free    = meminfo.get("MemFree", 0)
        buffers = meminfo.get("Buffers", 0)
        cached  = meminfo.get("Cached", 0)
        used    = total - free - buffers - cached
        return {"total_kb": total, "used_kb": used, "free_kb": free}
    except Exception as e:
        print(f"[ERROR] 메모리 정보 읽기 실패: {e}")
        return {}

def read_proc_net_dev():
    """호스트의 /proc/net/dev에서 네트워크 통계 읽기"""
    rx, tx = 0, 0
    try:
        with open("/host/proc/net/dev", "r") as f:
            for line in f.readlines()[2:]:  # 헤더 2줄 건너뛰기
                parts = line.split()
                rx += int(parts[1])  # RX bytes
                tx += int(parts[9])  # TX bytes
    except Exception as e:
        print(f"[ERROR] 네트워크 정보 읽기 실패: {e}")
    return {"rx_bytes": rx, "tx_bytes": tx}

def read_cgroup_blkio():
    """cgroup v1에서 블록 I/O 통계 읽기"""
    io_stat = {"read": 0, "write": 0}
    path = "/sys/fs/cgroup/blkio/blkio.throttle.io_service_bytes"
    try:
        with open(path, "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3:
                    if parts[1] == "Read":
                        io_stat["read"] += int(parts[2])
                    elif parts[1] == "Write":
                        io_stat["write"] += int(parts[2])
    except Exception as e:
        print(f"[ERROR] 블록 I/O 정보 읽기 실패: {e}")
    return io_stat

def collect_node_metrics(prev_cpu_stat=None):
    """노드 메트릭 수집 - CPU, 메모리, 네트워크, 디스크"""
    # TODO: CPU 사용률 계산 로직 추가 (proc/stat 기반 또는 cgroup 사용)
    cpu_usage    = None
    cgroup_cpu_ns = read_cgroup_cpu_usage()
    mem          = read_proc_meminfo()
    net          = read_proc_net_dev()
    blk          = read_cgroup_blkio()
    timestamp    = int(time.time())
    
    return {
        "timestamp": timestamp,
        "node": NODE_NAME,
        "cpu_usage": cpu_usage,
        "cgroup_cpu_ns": cgroup_cpu_ns,
        "memory": mem,
        "network": net,
        "disk": blk
    }

def collect_pod_metrics():
    """포드별 메트릭 수집 (cgroup 경로 기반)"""
    pod_metrics = []
    # 예시: cgroup 경로 패턴 탐색 (실제 환경에 맞게 경로를 조정해야 함)
    for pod_cg in glob.glob("/sys/fs/cgroup/*pod*:"):
        # TODO: pod 단위 메트릭 추출 로직 구현
        pod_metrics.append({})
    return pod_metrics

def send_to_api(endpoint, payload):
    """API 서버로 메트릭 데이터 전송"""
    url = f"{API_SERVER_URL}/{endpoint}"
    headers = {"Content-Type": "application/json"}
    try:
        resp = requests.post(url, data=json.dumps(payload), headers=headers, timeout=5)
        if resp.status_code != 200:
            print(f"[WARN] API 응답 {resp.status_code}: {resp.text}")
        else:
            print(f"[INFO] 메트릭 전송 성공: {endpoint}")
    except Exception as e:
        print(f"[ERROR] API 전송 실패: {e}")

def main():
    """메인 루프 - 주기적으로 메트릭 수집 및 전송"""
    print(f"[INFO] Collector 시작 - Node: {NODE_NAME}, API: {API_SERVER_URL}, Interval: {INTERVAL}s")
    prev_cpu_stat = None
    
    while True:
        try:
            # 노드 메트릭 수집 및 전송
            node_data = collect_node_metrics(prev_cpu_stat)
            send_to_api(f"api/nodes/{NODE_NAME}", node_data)
            
            # Pod 메트릭 수집 및 전송 (필요 시 구현)
            pod_list = collect_pod_metrics()
            for pod in pod_list:
                # send_to_api(f"api/pods/{pod_name}", pod)
                pass
                
            time.sleep(INTERVAL)
        except KeyboardInterrupt:
            print("[INFO] Collector 종료")
            break
        except Exception as e:
            print(f"[ERROR] 수집 루프 오류: {e}")
            time.sleep(INTERVAL)

if __name__ == "__main__":
    main() 