#!/usr/bin/env bash
# Starts LocalStack on the VM (S3 + Lambda emulation) and deploys the receipt
# chain. Pods reach it at host.minikube.internal:4566; the VM at localhost:4566.
#
#   bash capstone/scripts/setup-localstack.sh
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME=kijani-localstack
IMAGE=localstack/localstack:3.8

if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" --restart unless-stopped \
    -p 4566:4566 \
    -e SERVICES=s3,lambda,logs,iam,sts \
    -e LAMBDA_RUNTIME_ENVIRONMENT_TIMEOUT=120 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$ROOT/serverless:/opt/kijani-serverless:ro" \
    "$IMAGE" >/dev/null
  echo "started $NAME ($IMAGE)"
fi

echo -n "waiting for LocalStack"
for _ in $(seq 1 60); do
  curl -sf http://localhost:4566/_localstack/health | grep -q '"s3": *"\(running\|available\)"' && break
  echo -n "."; sleep 2
done
echo
curl -sf http://localhost:4566/_localstack/health >/dev/null || { echo "LocalStack did not become healthy"; exit 1; }

docker exec "$NAME" bash /opt/kijani-serverless/deploy-chain.sh
echo "LocalStack ready: http://localhost:4566"
