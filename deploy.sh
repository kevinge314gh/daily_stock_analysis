#!/bin/bash
set -e
ECS="root@8.141.121.180"
REMOTE_DIR="/opt/dsa-deploy"

echo "Syncing files to ECS..."
ssh "$ECS" "mkdir -p $REMOTE_DIR/data/vpn $REMOTE_DIR/logs $REMOTE_DIR/reports $REMOTE_DIR/longbridge_tokens"
rsync -av \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='data/' \
  --exclude='logs/' \
  --exclude='reports/' \
  --exclude='longbridge_tokens/' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='.idea/' \
  --exclude='apps/dsa-web/node_modules/' \
  /Users/guowenkai/code/GithubProject/daily_stock_analysis/ \
  "$ECS:$REMOTE_DIR/"

echo "Building image on ECS..."
ssh "$ECS" "cd $REMOTE_DIR && docker build -t dsa:latest -f docker/Dockerfile . 2>&1 | tail -20"

echo "Restarting container..."
ssh "$ECS" "cd $REMOTE_DIR && docker-compose -f docker/docker-compose.yml up -d server"

echo "Logs:"
sleep 5
ssh "$ECS" "docker logs stock-server --tail=30"
