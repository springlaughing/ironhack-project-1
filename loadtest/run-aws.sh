#!/usr/bin/env bash
# Load test 2: the same burst of votes as load test 1, now against AWS.
# Usage: bash loadtest/run-aws.sh                         (400 votes/s for 5 s = 2,000 votes)
#        RATE=100 DURATION=10s bash loadtest/run-aws.sh   (1,000 votes)
set -euo pipefail
cd "$(dirname "$0")/.."

export TARGET="${TARGET:-https://vote.springlaughing.dev/}"

# Run one command on C1 through Ansible (Session Manager) and print only its output.
c1() { (cd ansible && ansible role_data -b -o -m command -a "$1" 2>/dev/null) | sed 's/.*(stdout) //'; }
queue() { c1 "docker exec voting-redis-1 redis-cli LLEN votes"; }
saved() { c1 "docker exec voting-db-1 psql -U postgres -tAc \"SELECT COUNT(*) FROM votes WHERE id LIKE 'k6-%'\""; }

echo "Removing earlier test votes..."
c1 "docker exec voting-db-1 psql -U postgres -qc \"DELETE FROM votes WHERE id LIKE 'k6-%'\"" > /dev/null

start=$(date +%s)
docker run --rm -i -e RATE -e DURATION -e TARGET \
  grafana/k6:0.54.0 run - < loadtest/vote-burst.js > loadtest/last-k6-aws.txt 2>&1 &
k6pid=$!

peak=0
sleep 2
while true; do
  n=$(queue)
  if [ "$n" -gt "$peak" ]; then peak=$n; fi
  echo "$(( $(date +%s) - start )) s: $n waiting in Redis"
  if [ "$n" = "0" ] && ! kill -0 "$k6pid" 2>/dev/null; then break; fi
  sleep 1
done
wait "$k6pid" || true

echo
grep -E "checks|http_req_duration|http_req_failed|http_reqs" loadtest/last-k6-aws.txt || cat loadtest/last-k6-aws.txt
echo "Peak queue seen: $peak   All saved after: $(( $(date +%s) - start )) s   Saved: $(saved)"