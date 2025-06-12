#!/bin/bash

# 종합 테스트 스크립트 (API + kubectl 검증) - 개선된 버전
# Kubernetes 모니터링 API와 kubectl 명령어 결과를 비교하여 검증합니다
# 개발환경 구축부터 배포, 테스트까지 전 과정을 문서화합니다

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 설정 - 동적으로 감지하도록 개선
NODE_NAME="minikube"
NAMESPACE_DEFAULT="default"
NAMESPACE_KUBE_SYSTEM="kube-system"
DEPLOYMENT_NAME="monitor-api"

# 출력 제한 설정
MAX_DISPLAY_LINES=20
MAX_API_DISPLAY_LINES=30

# API URL 동적 감지
detect_api_url() {
    echo -e "${YELLOW}🔍 API 서버 URL 자동 감지 중...${NC}"
    
    # 1. minikube service를 통한 URL 감지 시도
    if command -v minikube &> /dev/null; then
        if API_BASE_URL=$(minikube service monitor-api-nodeport --url 2>/dev/null); then
            echo -e "${GREEN}   ✅ minikube service로 URL 감지: $API_BASE_URL${NC}"
            return 0
        fi
    fi
    
    # 2. kubectl과 minikube ip를 통한 URL 구성
    if MINIKUBE_IP=$(minikube ip 2>/dev/null) && NODEPORT=$(kubectl get svc monitor-api-nodeport -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null); then
        API_BASE_URL="http://${MINIKUBE_IP}:${NODEPORT}"
        echo -e "${GREEN}   ✅ kubectl + minikube ip로 URL 구성: $API_BASE_URL${NC}"
        return 0
    fi
    
    # 3. 기본값 사용
    API_BASE_URL="http://192.168.49.2:30080"
    echo -e "${YELLOW}   ⚠️  기본 URL 사용: $API_BASE_URL${NC}"
    return 0
}

# Metrics Server 상태 확인 및 활성화
check_and_enable_metrics_server() {
    echo -e "${YELLOW}🔍 Metrics Server 상태 확인 중...${NC}"
    
    # metrics-server 포드 확인
    if kubectl get pods -n kube-system | grep -q "metrics-server.*Running"; then
        echo -e "${GREEN}   ✅ Metrics Server가 이미 실행 중입니다${NC}"
        METRICS_AVAILABLE=true
    else
        echo -e "${YELLOW}   ⚠️  Metrics Server가 실행되지 않고 있습니다${NC}"
        echo -e "${BLUE}   🔧 Metrics Server 활성화 시도 중...${NC}"
        
        if command -v minikube &> /dev/null; then
            if minikube addons enable metrics-server; then
                echo -e "${GREEN}   ✅ Metrics Server 활성화 성공${NC}"
                echo -e "${BLUE}   ⏰ Metrics Server 시작 대기 중... (30초)${NC}"
                sleep 30
                
                # 다시 확인
                if kubectl get pods -n kube-system | grep -q "metrics-server.*Running"; then
                    echo -e "${GREEN}   ✅ Metrics Server 정상 실행 확인${NC}"
                    METRICS_AVAILABLE=true
                else
                    echo -e "${YELLOW}   ⚠️  Metrics Server가 아직 준비되지 않았습니다${NC}"
                    METRICS_AVAILABLE=false
                fi
            else
                echo -e "${RED}   ❌ Metrics Server 활성화 실패${NC}"
                METRICS_AVAILABLE=false
            fi
        else
            echo -e "${YELLOW}   ⚠️  minikube 명령어를 찾을 수 없습니다${NC}"
            METRICS_AVAILABLE=false
        fi
    fi
}

# API 응답 스마트 요약 기능 (models.py 구조 기반)
smart_summarize_api_response() {
    local response_body="$1"
    local endpoint="$2"
    
    if ! command -v jq &> /dev/null; then
        echo "$response_body"
        return
    fi
    
    # JSON 파싱 시도
    if ! echo "$response_body" | jq . &> /dev/null; then
        echo "$response_body"
        return
    fi
    
    echo -e "${BLUE}📊 API 응답 요약 (주요 메트릭):${NC}"
    
    # 엔드포인트별 스마트 요약
    case "$endpoint" in
        */api/nodes|*/api/nodes/*)
            # 노드 메트릭 요약
            echo "$response_body" | jq -r '
                if type == "object" then
                    to_entries[] | 
                    "🖥️  노드: " + .key + 
                    " | 데이터 포인트: " + (.value | length | tostring) + "개" +
                    if (.value | length > 0) then
                        " | 최신 CPU: " + (.value[-1].cpu_millicores // "N/A" | tostring) + "m" +
                        " | 메모리: " + ((.value[-1].memory_bytes // 0) / 1024 / 1024 | floor | tostring) + "MB" +
                        " | 시간: " + (.value[-1].timestamp // "N/A")
                    else ""
                    end
                elif type == "array" then
                    "📈 시계열 데이터: " + (length | tostring) + "개 포인트" +
                    if length > 0 then
                        " | 최신 CPU: " + (.[0].cpu_millicores // "N/A" | tostring) + "m" +
                        " | 메모리: " + ((.[0].memory_bytes // 0) / 1024 / 1024 | floor | tostring) + "MB"
                    else ""
                    end
                else
                    "알 수 없는 형식"
                end' 2>/dev/null || echo "파싱 실패"
            ;;
        */api/pods|*/api/pods/*)
            # 포드 메트릭 요약
            echo "$response_body" | jq -r '
                if type == "object" then
                    to_entries[] |
                    "🐳 포드: " + .key +
                    " | 데이터 포인트: " + (.value | length | tostring) + "개" +
                    if (.value | length > 0) then
                        " | 네임스페이스: " + (.value[-1].namespace // "N/A") +
                        " | CPU: " + (.value[-1].cpu_millicores // "N/A" | tostring) + "m" +
                        " | 메모리: " + ((.value[-1].memory_bytes // 0) / 1024 / 1024 | floor | tostring) + "MB"
                    else ""
                    end
                elif type == "array" then
                    "📈 시계열 데이터: " + (length | tostring) + "개 포인트" +
                    if length > 0 then
                        " | 포드: " + (.[0].pod // "N/A") +
                        " | CPU: " + (.[0].cpu_millicores // "N/A" | tostring) + "m" +
                        " | 메모리: " + ((.[0].memory_bytes // 0) / 1024 / 1024 | floor | tostring) + "MB"
                    else ""
                    end
                else
                    "알 수 없는 형식"
                end' 2>/dev/null || echo "파싱 실패"
            ;;
        */api/namespaces|*/api/namespaces/*)
            # 네임스페이스 메트릭 요약
            echo "$response_body" | jq -r '
                if type == "object" then
                    to_entries[] |
                    "📁 네임스페이스: " + .key +
                    " | 데이터 포인트: " + (.value | length | tostring) + "개" +
                    if (.value | length > 0) then
                        " | 총 CPU: " + (.value[-1].cpu_millicores // "N/A" | tostring) + "m" +
                        " | 총 메모리: " + ((.value[-1].memory_bytes // 0) / 1024 / 1024 | floor | tostring) + "MB"
                    else ""
                    end
                elif type == "array" then
                    "📈 시계열 데이터: " + (length | tostring) + "개 포인트" +
                    if length > 0 then
                        " | 네임스페이스: " + (.[0].namespace // "N/A") +
                        " | CPU: " + (.[0].cpu_millicores // "N/A" | tostring) + "m"
                    else ""
                    end
                else
                    "알 수 없는 형식"
                end' 2>/dev/null || echo "파싱 실패"
            ;;
        */deployments|*/deployments/*)
            # 디플로이먼트 메트릭 요약
            echo "$response_body" | jq -r '
                if type == "object" then
                    to_entries[] |
                    "🚀 디플로이먼트: " + .key +
                    " | 데이터 포인트: " + (.value | length | tostring) + "개" +
                    if (.value | length > 0) then
                        " | CPU: " + (.value[-1].cpu_millicores // "N/A" | tostring) + "m" +
                        " | 메모리: " + ((.value[-1].memory_bytes // 0) / 1024 / 1024 | floor | tostring) + "MB"
                    else ""
                    end
                elif type == "array" then
                    "📈 시계열 데이터: " + (length | tostring) + "개 포인트" +
                    if length > 0 then
                        " | 디플로이먼트: " + (.[0].deployment // "N/A")
                    else ""
                    end
                else
                    "알 수 없는 형식"
                end' 2>/dev/null || echo "파싱 실패"
            ;;
        *)
            # 기본 요약
            echo "$response_body" | jq -r '
                if type == "object" then
                    "📊 객체 형태 | 키 개수: " + (keys | length | tostring)
                elif type == "array" then
                    "📋 배열 형태 | 항목 개수: " + (length | tostring)
                else
                    "기타 형태"
                end' 2>/dev/null || echo "파싱 실패"
            ;;
    esac
    
    echo ""
    echo -e "${BLUE}📄 상세 JSON 응답 (처음 ${MAX_API_DISPLAY_LINES}줄):${NC}"
    local formatted_json=$(echo "$response_body" | jq . 2>/dev/null || echo "$response_body")
    local line_count=$(echo "$formatted_json" | wc -l)
    
    if [ "$line_count" -gt "$MAX_API_DISPLAY_LINES" ]; then
        echo "$formatted_json" | head -"$MAX_API_DISPLAY_LINES"
        echo -e "${YELLOW}   ... (총 $line_count 줄, 처음 ${MAX_API_DISPLAY_LINES}줄만 표시)${NC}"
        echo -e "${BLUE}   💡 전체 응답은 로그 파일에서 확인하세요${NC}"
    else
        echo "$formatted_json"
    fi
}

# 결과 저장 파일명 생성
TIMESTAMP=$(date '+%Y-%m-%d-%H-%M-%S')
RESULT_FILE="result/comprehensive-test-${TIMESTAMP}.txt"
KUBECTL_LOG="result/kubectl-output-${TIMESTAMP}.txt"

# result 디렉토리 생성
mkdir -p result

# 로그 함수들
log_output() {
    echo -e "$@" | tee -a "$RESULT_FILE"
}

log_to_file() {
    echo "$@" >> "$RESULT_FILE"
}

log_kubectl() {
    echo "$@" >> "$KUBECTL_LOG"
}

# 섹션 헤더 출력
print_section() {
    local title="$1"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$title${NC}"
    echo -e "${CYAN}========================================${NC}"
    log_to_file "========================================"
    log_to_file "$title"
    log_to_file "========================================"
}

# kubectl 명령어 실행 및 출력 (개선된 버전)
execute_kubectl() {
    local description="$1"
    local command="$2"
    local fallback_desc="$3"
    local fallback_cmd="$4"
    
    echo -e "${PURPLE}🔍 kubectl 검증: ${description}${NC}"
    echo -e "${BLUE}   명령어: ${command}${NC}"
    
    log_to_file "🔍 kubectl 검증: ${description}"
    log_to_file "   명령어: ${command}"
    log_kubectl "========== ${description} =========="
    log_kubectl "명령어: ${command}"
    
    # kubectl 명령어 실행
    if kubectl_output=$(eval $command 2>&1); then
        echo -e "${GREEN}   ✅ kubectl 명령어 성공${NC}"
        log_to_file "   ✅ kubectl 명령어 성공"
        
        # 출력이 너무 길면 처음 MAX_DISPLAY_LINES줄만 표시
        line_count=$(echo "$kubectl_output" | wc -l)
        if [ "$line_count" -gt "$MAX_DISPLAY_LINES" ]; then
            echo "$kubectl_output" | head -"$MAX_DISPLAY_LINES"
            echo -e "${YELLOW}   ... (총 $line_count 줄, 처음 ${MAX_DISPLAY_LINES}줄만 표시)${NC}"
            echo -e "${BLUE}   💡 전체 출력은 kubectl 로그 파일에서 확인하세요${NC}"
            log_to_file "   ... (총 $line_count 줄, 처음 ${MAX_DISPLAY_LINES}줄만 표시)"
        else
            echo "$kubectl_output"
        fi
        
        # 전체 출력을 kubectl 로그 파일에 저장
        log_kubectl "$kubectl_output"
        return 0
    else
        echo -e "${RED}   ❌ kubectl 명령어 실패${NC}"
        echo "   오류: $kubectl_output"
        log_to_file "   ❌ kubectl 명령어 실패"
        log_to_file "   오류: $kubectl_output"
        log_kubectl "오류: $kubectl_output"
        
        # 대체 명령어가 있는 경우 실행
        if [ -n "$fallback_cmd" ]; then
            echo -e "${BLUE}   🔄 대체 명령어 실행: ${fallback_desc}${NC}"
            echo -e "${BLUE}   명령어: ${fallback_cmd}${NC}"
            log_to_file "   🔄 대체 명령어 실행: ${fallback_desc}"
            log_to_file "   명령어: ${fallback_cmd}"
            
            if fallback_output=$(eval $fallback_cmd 2>&1); then
                echo -e "${GREEN}   ✅ 대체 명령어 성공${NC}"
                echo "$fallback_output"
                log_to_file "   ✅ 대체 명령어 성공"
                log_to_file "$fallback_output"
                log_kubectl "대체 명령어 성공: $fallback_output"
            else
                echo -e "${RED}   ❌ 대체 명령어도 실패${NC}"
                log_to_file "   ❌ 대체 명령어도 실패"
                log_kubectl "대체 명령어 실패: $fallback_output"
            fi
        fi
        return 1
    fi
    
    echo ""
    log_to_file ""
    log_kubectl ""
}

# API 호출 및 kubectl 비교 (개선된 버전)
call_api_with_kubectl() {
    local method="$1"
    local endpoint="$2"
    local description="$3"
    local kubectl_desc="$4"
    local kubectl_cmd="$5"
    local fallback_desc="$6"
    local fallback_cmd="$7"
    
    echo -e "${YELLOW}📋 API 테스트: ${description}${NC}"
    echo -e "${BLUE}   ${method} ${endpoint}${NC}"
    
    log_to_file "📋 API 테스트: ${description}"
    log_to_file "   ${method} ${endpoint}"
    
    # API 호출
    response=$(curl -s -w "\n%{http_code}" "${API_BASE_URL}${endpoint}")
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}   ✅ API 호출 성공 (HTTP $http_code)${NC}"
        log_to_file "   ✅ API 호출 성공 (HTTP $http_code)"
        
        # 스마트 요약 출력
        smart_summarize_api_response "$response_body" "$endpoint"
        
        # 전체 응답을 파일에 저장
        log_to_file "=== API 응답 전체 내용 ==="
        if command -v jq &> /dev/null; then
            echo "$response_body" | jq . >> "$RESULT_FILE" 2>/dev/null || echo "$response_body" >> "$RESULT_FILE"
        else
            echo "$response_body" >> "$RESULT_FILE"
        fi
        log_to_file "=== API 응답 끝 ==="
    else
        echo -e "${RED}   ❌ API 호출 실패 (HTTP $http_code)${NC}"
        echo "   응답: $response_body"
        log_to_file "   ❌ API 호출 실패 (HTTP $http_code)"
        log_to_file "   응답: $response_body"
    fi
    
    echo ""
    log_to_file ""
    
    # kubectl 명령어 실행 (제공된 경우)
    if [ -n "$kubectl_cmd" ]; then
        execute_kubectl "$kubectl_desc" "$kubectl_cmd" "$fallback_desc" "$fallback_cmd"
    fi
    
    echo -e "${CYAN}----------------------------------------${NC}"
    log_to_file "----------------------------------------"
}

# 데이터 통계 요약 표시
show_data_statistics() {
    local response_body="$1"
    local endpoint="$2"
    
    if ! command -v jq &> /dev/null; then
        return
    fi
    
    echo -e "${BLUE}📈 데이터 통계:${NC}"
    
    case "$endpoint" in
        */api/nodes?window=*|*/api/pods?window=*)
            # 시계열 데이터 통계
            echo "$response_body" | jq -r '
                if type == "object" then
                    to_entries[] |
                    .key as $resource |
                    .value |
                    "  📊 " + $resource + ": " + (length | tostring) + "개 데이터 포인트" +
                    if length > 0 then
                        " | 시간 범위: " + (.[0].timestamp // "N/A")[0:19] + " ~ " + (.[-1].timestamp // "N/A")[0:19]
                    else ""
                    end
                else
                    empty
                end' 2>/dev/null || true
            ;;
    esac
}

# 메인 테스트 시작
echo -e "${CYAN}🚀 Kubernetes 모니터링 시스템 종합 테스트 (개선된 버전)${NC}"

# API URL 자동 감지
detect_api_url

# Metrics Server 확인
check_and_enable_metrics_server

echo -e "${BLUE}API 서버: ${API_BASE_URL}${NC}"
echo -e "${BLUE}결과 저장 파일: ${RESULT_FILE}${NC}"
echo -e "${BLUE}kubectl 로그 파일: ${KUBECTL_LOG}${NC}"
echo -e "${BLUE}Metrics API 사용 가능: ${METRICS_AVAILABLE}${NC}"
echo -e "${BLUE}출력 제한: kubectl ${MAX_DISPLAY_LINES}줄, API ${MAX_API_DISPLAY_LINES}줄${NC}"
echo ""

# 헤더 정보 기록
log_to_file "=============================================="
log_to_file "Kubernetes 모니터링 시스템 종합 테스트 결과 (개선된 버전)"
log_to_file "테스트 시간: $(date '+%Y-%m-%d %H:%M:%S')"
log_to_file "API 서버: ${API_BASE_URL}"
log_to_file "Metrics API 사용 가능: ${METRICS_AVAILABLE}"
log_to_file "=============================================="
log_to_file ""

# 환경 확인
print_section "🔧 환경 확인"
execute_kubectl "클러스터 정보 확인" "kubectl cluster-info"
execute_kubectl "노드 상태 확인" "kubectl get nodes -o wide"
execute_kubectl "네임스페이스 목록" "kubectl get namespaces"
execute_kubectl "전체 시스템 포드 상태" "kubectl get pods --all-namespaces"

# Metrics Server 상세 확인
execute_kubectl "Metrics Server 상태 확인" "kubectl get pods -n kube-system | grep metrics-server" \
    "애드온 상태 확인" "minikube addons list | grep metrics-server"

# API 서버 상태 확인
print_section "🔍 API 서버 상태 확인"
call_api_with_kubectl "GET" "/health" "API 헬스 체크" "" ""

# 노드 기준 테스트
print_section "1️⃣ 노드 기준 API vs kubectl 비교"

if [ "$METRICS_AVAILABLE" = true ]; then
    call_api_with_kubectl "GET" "/api/nodes" "전체 노드 목록 및 리소스 사용량" \
        "kubectl로 노드 리소스 사용량 확인" "kubectl top nodes" \
        "노드 기본 정보 확인" "kubectl get nodes -o wide --show-labels"
else
    call_api_with_kubectl "GET" "/api/nodes" "전체 노드 목록 및 리소스 사용량" \
        "kubectl로 노드 기본 정보 확인" "kubectl get nodes -o wide --show-labels"
fi

call_api_with_kubectl "GET" "/api/nodes/${NODE_NAME}" "특정 노드의 리소스 사용량" \
    "kubectl로 특정 노드 상세 정보 확인" "kubectl describe node ${NODE_NAME}"

call_api_with_kubectl "GET" "/api/nodes/${NODE_NAME}/pods" "노드에 할당된 포드 목록" \
    "kubectl로 노드의 포드 목록 확인" "kubectl get pods --all-namespaces --field-selector spec.nodeName=${NODE_NAME} -o wide"

# 포드 기준 테스트
print_section "2️⃣ 포드 기준 API vs kubectl 비교"

if [ "$METRICS_AVAILABLE" = true ]; then
    call_api_with_kubectl "GET" "/api/pods" "전체 포드 목록 및 리소스 사용량" \
        "kubectl로 포드 리소스 사용량 확인" "kubectl top pods --all-namespaces" \
        "포드 기본 정보 확인" "kubectl get pods --all-namespaces -o wide"
else
    call_api_with_kubectl "GET" "/api/pods" "전체 포드 목록 및 리소스 사용량" \
        "kubectl로 포드 기본 정보 확인" "kubectl get pods --all-namespaces -o wide"
fi

# 실제 존재하는 포드 찾기
echo -e "${YELLOW}🔍 실제 포드 이름 확인 중...${NC}"
ACTUAL_POD=$(kubectl get pods -n default -l app=monitor-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$ACTUAL_POD" ]; then
    POD_NAME="$ACTUAL_POD"
    echo -e "${GREEN}   실제 포드 이름: ${POD_NAME}${NC}"
    log_to_file "   실제 포드 이름: ${POD_NAME}"
else
    echo -e "${YELLOW}   monitor-api 포드를 찾을 수 없습니다. 기본값 사용: ${POD_NAME}${NC}"
    log_to_file "   monitor-api 포드를 찾을 수 없습니다. 기본값 사용: ${POD_NAME}"
fi

if [ "$METRICS_AVAILABLE" = true ]; then
    call_api_with_kubectl "GET" "/api/pods/${POD_NAME}" "특정 포드의 리소스 사용량" \
        "kubectl로 포드 리소스 사용량 확인" "kubectl top pod ${POD_NAME} -n default" \
        "포드 상세 정보 확인" "kubectl describe pod ${POD_NAME} -n default"
else
    call_api_with_kubectl "GET" "/api/pods/${POD_NAME}" "특정 포드의 리소스 사용량" \
        "kubectl로 포드 상세 정보 확인" "kubectl describe pod ${POD_NAME} -n default"
fi

# 네임스페이스 기준 테스트
print_section "3️⃣ 네임스페이스 기준 API vs kubectl 비교"

if [ "$METRICS_AVAILABLE" = true ]; then
    call_api_with_kubectl "GET" "/api/namespaces" "전체 네임스페이스 리소스 사용량" \
        "kubectl로 네임스페이스별 리소스 확인" "kubectl get namespaces && kubectl top pods --all-namespaces | head -15" \
        "네임스페이스 기본 정보" "kubectl get namespaces -o wide"
else
    call_api_with_kubectl "GET" "/api/namespaces" "전체 네임스페이스 리소스 사용량" \
        "kubectl로 네임스페이스 정보 확인" "kubectl get namespaces -o wide"
fi

call_api_with_kubectl "GET" "/api/namespaces/${NAMESPACE_DEFAULT}" "default 네임스페이스 리소스" \
    "kubectl로 default 네임스페이스 확인" "kubectl get all -n default"

call_api_with_kubectl "GET" "/api/namespaces/${NAMESPACE_DEFAULT}/pods" "default 네임스페이스 포드" \
    "kubectl로 default 네임스페이스 포드 확인" "kubectl get pods -n default -o wide"

# 디플로이먼트 기준 테스트
print_section "4️⃣ 디플로이먼트 기준 API vs kubectl 비교"
call_api_with_kubectl "GET" "/api/namespaces/${NAMESPACE_DEFAULT}/deployments" "디플로이먼트 목록" \
    "kubectl로 디플로이먼트 확인" "kubectl get deployments -n default -o wide"

call_api_with_kubectl "GET" "/api/namespaces/${NAMESPACE_DEFAULT}/deployments/${DEPLOYMENT_NAME}" "monitor-api 디플로이먼트" \
    "kubectl로 monitor-api 디플로이먼트 확인" "kubectl describe deployment ${DEPLOYMENT_NAME} -n default"

call_api_with_kubectl "GET" "/api/namespaces/${NAMESPACE_DEFAULT}/deployments/${DEPLOYMENT_NAME}/pods" "monitor-api 디플로이먼트의 포드 목록" \
    "kubectl로 monitor-api 포드 확인" "kubectl get pods -n default -l app=monitor-api -o wide"

# 시계열 데이터 테스트
print_section "⏰ 시계열 데이터 API 테스트"

if [ "$METRICS_AVAILABLE" = true ]; then
    call_api_with_kubectl "GET" "/api/nodes?window=60" "노드 시계열 데이터 (60초)" \
        "kubectl로 현재 노드 메트릭 확인" "kubectl top nodes" \
        "노드 상태 확인" "kubectl get nodes -o wide"
        
    call_api_with_kubectl "GET" "/api/pods?window=60" "포드 시계열 데이터 (60초)" \
        "kubectl로 현재 포드 메트릭 확인" "kubectl top pods -n default" \
        "포드 상태 확인" "kubectl get pods -n default -o wide"
        
    call_api_with_kubectl "GET" "/api/namespaces/${NAMESPACE_DEFAULT}?window=60" "default 네임스페이스 시계열 데이터 (60초)" \
        "kubectl로 default 네임스페이스 리소스 확인" "kubectl top pods -n default" \
        "default 네임스페이스 포드 상태" "kubectl get pods -n default -o wide"
else
    call_api_with_kubectl "GET" "/api/nodes?window=60" "노드 시계열 데이터 (60초)" \
        "kubectl로 노드 상태 확인" "kubectl get nodes -o wide"
        
    call_api_with_kubectl "GET" "/api/pods?window=60" "포드 시계열 데이터 (60초)" \
        "kubectl로 포드 상태 확인" "kubectl get pods -n default -o wide"
        
    call_api_with_kubectl "GET" "/api/namespaces/${NAMESPACE_DEFAULT}?window=60" "default 네임스페이스 시계열 데이터 (60초)" \
        "kubectl로 default 네임스페이스 상태 확인" "kubectl get pods -n default -o wide"
fi

# 추가 검증 명령어
print_section "🔍 추가 시스템 검증"
execute_kubectl "서비스 상태 확인" "kubectl get services --all-namespaces"
execute_kubectl "PV/PVC 확인" "kubectl get pv,pvc --all-namespaces"
execute_kubectl "이벤트 확인" "kubectl get events --all-namespaces --sort-by=.lastTimestamp | tail -15"

if [ "$METRICS_AVAILABLE" = true ]; then
    execute_kubectl "리소스 사용량 요약" "kubectl top nodes && echo '---포드 리소스---' && kubectl top pods --all-namespaces | head -15" \
        "기본 리소스 상태" "kubectl get nodes,pods --all-namespaces"
else
    execute_kubectl "리소스 상태 요약" "kubectl get nodes,pods --all-namespaces -o wide"
fi

# 컨테이너 및 이미지 정보
execute_kubectl "컨테이너 이미지 정보 확인" "kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{\": \"}{.spec.containers[*].image}{\"\\n\"}{end}' --all-namespaces"

# Swagger 문서 접근 테스트
print_section "📚 API 문서 접근 테스트"
echo -e "${BLUE}Swagger UI 접근 테스트: ${API_BASE_URL}/docs${NC}"
swagger_response=$(curl -s -w "%{http_code}" -o /dev/null "${API_BASE_URL}/docs")
if [ "$swagger_response" = "200" ]; then
    echo -e "${GREEN}✅ Swagger UI 접근 성공${NC}"
    log_to_file "✅ Swagger UI 접근 성공"
else
    echo -e "${RED}❌ Swagger UI 접근 실패 (HTTP $swagger_response)${NC}"
    log_to_file "❌ Swagger UI 접근 실패 (HTTP $swagger_response)"
fi

echo -e "${BLUE}ReDoc 접근 테스트: ${API_BASE_URL}/redoc${NC}"
redoc_response=$(curl -s -w "%{http_code}" -o /dev/null "${API_BASE_URL}/redoc")
if [ "$redoc_response" = "200" ]; then
    echo -e "${GREEN}✅ ReDoc 접근 성공${NC}"
    log_to_file "✅ ReDoc 접근 성공"
else
    echo -e "${RED}❌ ReDoc 접근 실패 (HTTP $redoc_response)${NC}"
    log_to_file "❌ ReDoc 접근 실패 (HTTP $redoc_response)"
fi

# 완료 메시지 및 요약
print_section "✅ 테스트 완료 요약"
echo -e "${GREEN}🎉 모든 테스트가 완료되었습니다!${NC}"
echo ""
echo -e "${BLUE}📁 생성된 파일:${NC}"
echo -e "${BLUE}   - 종합 테스트 결과: ${RESULT_FILE}${NC}"
echo -e "${BLUE}   - kubectl 출력 로그: ${KUBECTL_LOG}${NC}"
echo ""
echo -e "${BLUE}📋 접근 URL:${NC}"
echo -e "${BLUE}   - API 서버: ${API_BASE_URL}${NC}"
echo -e "${BLUE}   - Swagger UI: ${API_BASE_URL}/docs${NC}"
echo -e "${BLUE}   - ReDoc: ${API_BASE_URL}/redoc${NC}"
echo ""
echo -e "${YELLOW}💡 참고사항:${NC}"
echo -e "${YELLOW}   - API와 kubectl 결과를 비교하여 데이터 일관성을 확인하세요${NC}"
echo -e "${YELLOW}   - 메트릭 수집에는 시간이 걸릴 수 있습니다${NC}"
echo -e "${YELLOW}   - Metrics API 사용 가능: ${METRICS_AVAILABLE}${NC}"
echo -e "${YELLOW}   - 화면 출력은 요약된 것이며, 전체 데이터는 로그 파일에 저장됩니다${NC}"
echo -e "${YELLOW}   - 상세한 로그는 생성된 파일들을 참조하세요${NC}"

if [ "$METRICS_AVAILABLE" = false ]; then
    echo ""
    echo -e "${YELLOW}🔧 Metrics Server 문제 해결 방법:${NC}"
    echo -e "${BLUE}   1. minikube addons enable metrics-server${NC}"
    echo -e "${BLUE}   2. kubectl get pods -n kube-system | grep metrics-server${NC}"
    echo -e "${BLUE}   3. 포드가 Running 상태가 될 때까지 대기${NC}"
fi

log_to_file ""
log_to_file "✅ 테스트 완료 요약"
log_to_file "생성된 파일:"
log_to_file "   - 종합 테스트 결과: ${RESULT_FILE}"
log_to_file "   - kubectl 출력 로그: ${KUBECTL_LOG}"
log_to_file "Metrics API 사용 가능: ${METRICS_AVAILABLE}"
log_to_file "테스트 완료 시간: $(date '+%Y-%m-%d %H:%M:%S')" 