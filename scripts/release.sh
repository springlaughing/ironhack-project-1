#!/usr/bin/env bash
# Build the app images and push them to Docker Hub, tagged with the Git commit ID.
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; [ -f .env ] && . ./.env; set +a
: "${REGISTRY_USER:?set REGISTRY_USER in .env}"

if [ -n "$(git status --porcelain)" ]; then
  echo "Uncommitted changes: commit first, so the tag matches the code." >&2
  exit 1
fi

export IMAGE_TAG="$(git rev-parse --short HEAD)"
docker compose build vote result worker

# Push one image at a time, up to 3 tries each: home uploads to Docker Hub can time out.
for s in vote result worker; do
  image="${REGISTRY_USER}/voting-${s}:${IMAGE_TAG}"
  for try in 1 2 3; do
    if docker push "$image"; then break; fi
    if [ "$try" = 3 ]; then echo "Giving up on $image after 3 tries" >&2; exit 1; fi
    echo "Push of $image failed (try $try), retrying in 5 s…" >&2
    sleep 5
  done
done
echo "Pushed ${REGISTRY_USER}/voting-{vote,result,worker}:${IMAGE_TAG}"