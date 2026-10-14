#!/usr/bin/env bash
# Failover test (#20): runs ON C2, in the background, started before zone a goes down.
# Once a second it adds one line to /tmp/failover-log.csv:
#   time (UTC), k6f votes in C2's database, votes waiting in Redis b, C2 still a copy (t) or primary (f)
# Reading it afterwards: the saved count stops growing when C1 goes down,
# and grows again once C2 is promoted and the Worker reaches it. That gap is the recovery time.
# Stops by itself after 40 minutes (or the number of seconds given as $1), or: pkill -f measure-failover
set -u
out=/tmp/failover-log.csv
end=$(( $(date +%s) + ${1:-2400} ))

sql() { docker exec voting-db-1 psql -U postgres -tAc "$1" 2>/dev/null || echo "?"; }   # ? = no answer

echo "time_utc,saved_k6f,queue_redis_b,c2_is_copy" > "$out"
while [ "$(date +%s)" -lt "$end" ]; do
  saved=$(sql "SELECT COUNT(*) FROM votes WHERE id LIKE 'k6f-%'")
  queue=$(docker exec voting-redis-1 redis-cli LLEN votes 2>/dev/null || echo "?")
  copy=$(sql "SELECT pg_is_in_recovery()")
  echo "$(date -u +%T),$saved,$queue,$copy" >> "$out"
  sleep 1
done