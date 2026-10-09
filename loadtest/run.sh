#!/usr/bin/env bash
# Load test 1: send a burst of votes, then watch the queue until every vote is saved.
# Usage: bash loadtest/run.sh            (2,000 votes in 5 s)
#        RATE=1000 bash loadtest/run.sh  (5,000 votes in 5 s)
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose exec -T db psql -U postgres -qc "DELETE FROM votes WHERE id LIKE 'k6-%';"

start=$(date +%s)
docker run --rm -i -e RATE -e DURATION --network ironhack-project-1_back-tier \
  grafana/k6:0.54.0 run - < loadtest/vote-burst.js > loadtest/last-k6.txt 2>&1 &
k6pid=$!

peak=0
sleep 1
while true; do
  n=$(docker compose exec -T redis redis-cli LLEN votes)
  if [ "$n" -gt "$peak" ]; then peak=$n; fi
  echo "$(( $(date +%s) - start )) s: $n waiting"
  if [ "$n" = "0" ] && ! kill -0 "$k6pid" 2>/dev/null; then break; fi
  sleep 1
done
wait "$k6pid" || true

saved=$(docker compose exec -T db psql -U postgres -tAc "SELECT COUNT(*) FROM votes WHERE id LIKE 'k6-%';")
echo
grep -E "checks|http_req_duration|http_req_failed|http_reqs" loadtest/last-k6.txt || cat loadtest/last-k6.txt
echo "Peak queue: $peak   All saved after: $(( $(date +%s) - start )) s   Saved: $saved"
