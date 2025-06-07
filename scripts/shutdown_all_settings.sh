# Minikube 완전 삭제 (모든 데이터 삭제)
minikube delete

# 모든 Docker 컨테이너 중지
docker stop $(docker ps -aq)

# 사용하지 않는 Docker 리소스 정리
docker system prune -f