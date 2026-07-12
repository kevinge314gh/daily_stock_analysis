#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

# 确保本地数据目录存在
mkdir -p "$DIR/data" "$DIR/logs" "$DIR/reports" "$DIR/longbridge_tokens"

# 初始化本地 .env.local（如果不存在则从示例复制）
if [ ! -f "$DIR/.env.local" ]; then
  cp "$DIR/.env.example" "$DIR/.env.local"
  echo "已生成 .env.local，请编辑后重新运行。"
  exit 0
fi

echo "Building frontend..."
cd "$DIR/apps/dsa-web"
npm ci --silent
npm run build
cd "$DIR"

echo "Building image..."
docker compose -f "$DIR/docker/docker-compose.local.yml" build \
  --build-arg CACHEBUST="$(date +%s)" server

echo "Starting container..."
docker compose -f "$DIR/docker/docker-compose.local.yml" up -d --force-recreate server

echo "Logs:"
sleep 5
docker logs stock-server-local --tail=20
