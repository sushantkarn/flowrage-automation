#!/bin/sh
set -e

echo "=== Deploying Flowrage Automation ==="

compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
    return
  fi
  docker compose "$@"
}

DEPLOY_DIR="${DEPLOY_DIR:-/var/www/flowrage-automation}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
COMPOSE_PROFILE="${COMPOSE_PROFILE:-cpu}"
N8N_PORT="${N8N_PORT:-5678}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

cd "$DEPLOY_DIR"

if [ ! -f ".env" ]; then
  echo "ERROR: .env file not found in $DEPLOY_DIR"
  exit 1
fi

check_port() {
  port_name="$1"
  port_value="$2"

  if ss -ltn "( sport = :${port_value} )" | tail -n +2 | grep -q .; then
    echo "ERROR: ${port_name} port ${port_value} is already in use on the host"
    exit 1
  fi
}

check_port "N8N" "$N8N_PORT"
check_port "Qdrant" "$QDRANT_PORT"
check_port "Ollama" "$OLLAMA_PORT"

mkdir -p shared n8n

echo "Validating compose configuration..."
compose -f "$COMPOSE_FILE" --profile "$COMPOSE_PROFILE" config >/dev/null

echo "Pulling latest images..."
compose -f "$COMPOSE_FILE" --profile "$COMPOSE_PROFILE" pull

echo "Starting services..."
compose -f "$COMPOSE_FILE" --profile "$COMPOSE_PROFILE" up -d --remove-orphans

echo "Waiting for n8n to respond..."
for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${N8N_PORT}/" >/dev/null 2>&1; then
    echo "OK n8n is reachable"
    break
  fi
  echo "  Attempt $i/30 failed, retrying in 5s..."
  sleep 5
done

if ! curl -sf "http://127.0.0.1:${N8N_PORT}/" >/dev/null 2>&1; then
  echo "ERROR: n8n did not become reachable"
  docker logs --tail 100 n8n || true
  exit 1
fi

docker compose -f "$COMPOSE_FILE" --profile "$COMPOSE_PROFILE" ps

echo "=== Deployment Complete ==="
