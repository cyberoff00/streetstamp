#!/bin/bash
# Lightweight monitoring script for beta testing
# Usage: ./scripts/monitor.sh          (one-shot)
#        ./scripts/monitor.sh --loop    (every 30s, Ctrl+C to stop)

set -euo pipefail

API_CONTAINER="streetstamps-node-v1"
DB_CONTAINER="streetstamps-postgres"
HEALTH_URL="http://127.0.0.1:18080/v1/health"

print_status() {
  echo "====== $(date '+%Y-%m-%d %H:%M:%S') ======"

  # Health check
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTH_URL" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    echo "API Health:  OK (200)"
  else
    echo "API Health:  FAIL ($HTTP_CODE)"
  fi

  # Docker container stats (CPU%, MEM, MEM%)
  echo ""
  echo "--- Container Resources ---"
  docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" \
    "$API_CONTAINER" "$DB_CONTAINER" 2>/dev/null || echo "(docker stats unavailable)"

  # PG active connections
  echo ""
  echo "--- PostgreSQL Connections ---"
  docker exec "$DB_CONTAINER" psql -U streetstamps -d streetstamps -t -c \
    "SELECT count(*) AS active FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | xargs echo "Active queries:"
  docker exec "$DB_CONTAINER" psql -U streetstamps -d streetstamps -t -c \
    "SELECT count(*) AS total FROM pg_stat_activity;" 2>/dev/null | xargs echo "Total connections:"

  # Recent API errors (last 50 log lines)
  echo ""
  echo "--- Recent Errors (last 50 lines) ---"
  docker logs --tail 50 "$API_CONTAINER" 2>&1 | grep -iE '(error|ERR|fatal|ECONNREFUSED|ENOMEM|killed)' | tail -5 || echo "(none)"

  echo ""
}

if [ "${1:-}" = "--loop" ]; then
  echo "Monitoring every 30s... (Ctrl+C to stop)"
  while true; do
    print_status
    sleep 30
  done
else
  print_status
fi
