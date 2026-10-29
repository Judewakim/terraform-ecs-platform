#!/usr/bin/env bash
# Generate traffic so you can watch autoscaling and the dashboard react.
# Uses only curl and xargs. Default: 20 parallel workers for 5 minutes.
#   ./scripts/load-test.sh [workers] [seconds]
set -euo pipefail

WORKERS="${1:-20}"
SECONDS_TO_RUN="${2:-300}"
URL="$(terraform -chdir="$(dirname "$0")/../infra/envs/dev" output -raw app_url)"

code="$(curl -fsS -X POST "$URL/links" -H 'content-type: application/json' -d '{"url":"https://example.com"}' | sed -E 's/.*"code":"([^"]+)".*/\1/')"
echo "Hitting $URL/$code with $WORKERS workers for ${SECONDS_TO_RUN}s. Watch the dashboard and: aws ecs describe-services"

end=$(( $(date +%s) + SECONDS_TO_RUN ))
worker() {
  while [ "$(date +%s)" -lt "$1" ]; do
    curl -s -o /dev/null "$2"
  done
}
export -f worker
seq "$WORKERS" | xargs -P "$WORKERS" -I{} bash -c "worker $end $URL/$code"
echo "Done."
