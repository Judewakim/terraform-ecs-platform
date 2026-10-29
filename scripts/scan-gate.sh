#!/usr/bin/env bash
# Wait for ECR's scan of an image, then fail if it has CRITICAL findings.
# Works with basic scanning (status COMPLETE) and with Inspector enhanced
# scanning (status ACTIVE once the first scan lands).
#   ./scripts/scan-gate.sh <repository> <tag>
set -euo pipefail

REPO="$1"
TAG="$2"

for _ in $(seq 1 60); do
  status="$(aws ecr describe-image-scan-findings --repository-name "$REPO" --image-id imageTag="$TAG" \
    --query 'imageScanStatus.status' --output text 2>/dev/null || echo PENDING)"
  case "$status" in
    COMPLETE|ACTIVE) break ;;
    FAILED|UNSUPPORTED_IMAGE|SCAN_ELIGIBILITY_EXPIRED)
      echo "Scan status $status for $REPO:$TAG; refusing to deploy an unscanned image." >&2
      exit 1 ;;
  esac
  sleep 10
done

if [ "$status" != "COMPLETE" ] && [ "$status" != "ACTIVE" ]; then
  echo "Timed out waiting for the scan of $REPO:$TAG." >&2
  exit 1
fi

counts="$(aws ecr describe-image-scan-findings --repository-name "$REPO" --image-id imageTag="$TAG" \
  --query 'imageScanFindings.findingSeverityCounts' --output json)"
echo "Scan findings for $REPO:$TAG: $counts"
critical="$(echo "$counts" | jq -r 'if . == null then 0 else (.CRITICAL // 0) end')"
if [ "$critical" -gt 0 ]; then
  echo "Blocked: $critical critical vulnerabilities." >&2
  exit 1
fi
