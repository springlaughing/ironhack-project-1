#!/usr/bin/env bash
# Load test 2: the brief's spike (2,000 votes in 5 seconds) against AWS,
# after 60 seconds of normal traffic (50 votes per second) as a warm-up.
# Usage: bash loadtest/run-aws.sh                      (k6 runs here, on the laptop)
#        K6_WHERE=cloudshell bash loadtest/run-aws.sh  (k6 runs in AWS CloudShell; this script
#                                                      prepares C1, measures, and prints the results)
#        WARMUP= bash loadtest/run-aws.sh              (no warm-up, burst only)
set -euo pipefail
cd "$(dirname "$0")/.."

export TARGET="${TARGET:-https://vote.springlaughing.dev/}"
export WARMUP="${WARMUP-60s}"      # normal traffic before the burst ("" = none)
export WARMUP_RATE="${WARMUP_RATE:-50}"
export PRE_VUS="${PRE_VUS:-800}"   # virtual users created before the test: enough for the whole burst
export MAX_VUS="${MAX_VUS:-1200}"  # upper limit, in case even more are needed
K6_WHERE="${K6_WHERE:-laptop}"     # laptop | cloudshell

# Run one command on C1 through Ansible (Session Manager) and print only its output.
c1() { (cd ansible && ansible evgenia-voting-c1 -b -o -m command -a "$1" 2>/dev/null) | sed 's/.*(stdout) //'; }
count() { c1 "docker exec voting-db-1 psql -U postgres -tAc \"SELECT COUNT(*) FROM votes WHERE id LIKE '$1'\""; }

echo "Removing earlier test votes..."
c1 "docker exec voting-db-1 psql -U postgres -qc \"DELETE FROM votes WHERE id LIKE 'k6%'\"" > /dev/null

echo "Starting the measuring loop on C1 (it waits for the burst)..."
(cd ansible && ansible evgenia-voting-c1 -b -m script -a "../loadtest/measure-c1.sh" > /dev/null 2>&1) &
measure_pid=$!

if [ "$K6_WHERE" = "cloudshell" ]; then
  echo
  echo "Now start k6 in CloudShell (within the next 2 minutes):"
  echo "  ~/k6 run -e TARGET=$TARGET -e WARMUP=$WARMUP -e WARMUP_RATE=$WARMUP_RATE -e PRE_VUS=$PRE_VUS -e MAX_VUS=$MAX_VUS vote-burst.js"
  echo
  echo "Waiting for the measuring loop on C1 (it ends 5 s after the last burst vote is saved)..."
  wait "$measure_pid" || true
else
  echo "Running k6: ${WARMUP:-no} warm-up at ${WARMUP_RATE}/s, then ${RATE:-400}/s for ${DURATION:-5s}..."
  docker run --rm -i -e RATE -e DURATION -e TARGET -e WARMUP -e WARMUP_RATE -e PRE_VUS -e MAX_VUS \
    grafana/k6:0.54.0 run - < loadtest/vote-burst.js > loadtest/last-k6-aws.txt 2>&1 || true
  echo "k6 done, waiting for the measuring loop to finish..."
  wait "$measure_pid" || true
  echo
  grep -E "checks|http_req_duration|http_req_failed|http_reqs|dropped_iterations|vus_max|iteration_duration|http_req_tls_handshaking|scenario:burst" loadtest/last-k6-aws.txt \
    || cat loadtest/last-k6-aws.txt
fi
echo
echo "Measured on C1: $(c1 "cat /tmp/loadtest-measure.txt")"
echo "Saved in PostgreSQL: burst $(count 'k6-%'), warm-up $(count 'k6w-%')"