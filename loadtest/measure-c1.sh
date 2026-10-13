#!/usr/bin/env bash
# Runs ON C1 during load test 2 (run-aws.sh sends it there through Ansible).
# Watches, as often as it can (several times a second):
#   - the Redis queue (how many votes are waiting)
#   - the burst votes saved in PostgreSQL (voter IDs k6-...)
# The clock runs here, next to the data, so Session Manager's delay doesn't count.
# Writes one line of results to /tmp/loadtest-measure.txt.
set -u
out=/tmp/loadtest-measure.txt
echo "still running" > "$out"

now()   { date +%s.%N; }
queue() { docker exec voting-redis-1 redis-cli LLEN votes; }
saved() { docker exec voting-db-1 psql -U postgres -tAc "SELECT COUNT(*) FROM votes WHERE id LIKE 'k6-%'"; }
gt()    { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }   # true if a > b (decimals)

start=$(now)
deadline=$(( $(date +%s) + 300 ))   # give up after 5 minutes
first=""; last=""; prev=0; peak=0; samples=0

while [ "$(date +%s)" -lt "$deadline" ]; do
  t=$(now); q=$(queue); n=$(saved); samples=$((samples + 1))
  [ "$q" -gt "$peak" ] && peak=$q
  [ "$n" -gt 0 ] && [ -z "$first" ] && first=$t          # first burst vote saved
  if [ "$n" -gt "$prev" ]; then last=$t; prev=$n; fi    # last time the count grew
  # Done: burst votes arrived, queue empty, and nothing new saved for 5 seconds
  if [ -n "$first" ] && [ "$q" = "0" ] && gt "$(awk -v a="$t" -v b="$last" 'BEGIN { print a - b }')" 5; then
    break
  fi
  sleep 0.1
done

awk -v f="$first" -v l="$last" -v s="$start" -v e="$(now)" -v n="$prev" -v p="$peak" -v k="$samples" 'BEGIN {
  if (f == "") { print "no burst votes seen"; exit }
  printf "first to last burst vote saved: %.1f s | highest queue: %d | burst votes saved: %d | one look every %.2f s\n",
         l - f, p, n, (e - s) / k
}' > "$out"