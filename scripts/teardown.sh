#!/usr/bin/env bash
# Destroy the whole dev stack. After this the only cost left is the state
# bucket (cents per month). The KMS key waits 7 days before deletion at no charge.
#   ./scripts/teardown.sh
set -euo pipefail

cd "$(dirname "$0")/../infra/envs/dev"
terraform init -input=false -backend-config=backend.hcl >/dev/null
terraform destroy -input=false -var "image_tag=teardown"

echo "Checking for anything left that bills by the hour..."
REGION="${AWS_REGION:-us-east-1}"
left=0
for check in \
  "ec2 describe-nat-gateways --filter Name=tag:Project,Values=shortlink Name=state,Values=available,pending --query NatGateways[].NatGatewayId" \
  "elbv2 describe-load-balancers --query LoadBalancers[?starts_with(LoadBalancerName,'shortlink')].LoadBalancerName" \
  "rds describe-db-instances --query DBInstances[?starts_with(DBInstanceIdentifier,'shortlink')].DBInstanceIdentifier" \
  "ec2 describe-addresses --filters Name=tag:Project,Values=shortlink --query Addresses[].PublicIp"; do
  # shellcheck disable=SC2086
  out="$(aws --region "$REGION" $check --output text)"
  if [ -n "$out" ] && [ "$out" != "None" ]; then echo "  still running: $out"; left=1; fi
done
[ "$left" -eq 0 ] && echo "Clean. Nothing billable left."
