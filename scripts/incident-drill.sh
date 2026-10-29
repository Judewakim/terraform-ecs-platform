#!/usr/bin/env bash
# Incident drill: simulate a bad manual change in the console, watch the
# platform detect it, then let Terraform repair the drift.
#
# What it breaks: deletes the security-group rule that lets the app reach
# Postgres. Effect: /ready fails, the ALB marks tasks unhealthy, the
# unhealthy-tasks alarm fires. Fix: terraform plan shows the missing rule;
# terraform apply restores it. Write it up with docs/postmortem-template.md.
#   ./scripts/incident-drill.sh break
#   ./scripts/incident-drill.sh fix
set -euo pipefail

cd "$(dirname "$0")/../infra/envs/dev"
REGION="${AWS_REGION:-us-east-1}"

case "${1:-}" in
  break)
    rule_id="$(terraform state show -no-color aws_vpc_security_group_ingress_rule.db_from_app | awk -F'"' '/security_group_rule_id/ {print $2}')"
    sg_id="$(terraform state show -no-color aws_vpc_security_group_ingress_rule.db_from_app | awk -F'"' '/ security_group_id/ {print $2}')"
    echo "$(date -u +%FT%TZ) Deleting rule $rule_id on $sg_id (app -> Postgres)."
    aws --region "$REGION" ec2 revoke-security-group-ingress --group-id "$sg_id" --security-group-rule-ids "$rule_id" >/dev/null
    echo "Done. Expect: /ready returns 503 within ~30s; unhealthy-tasks alarm within ~3 min."
    echo "Note the times for the postmortem. Then run: $0 fix"
    ;;
  fix)
    tag="$(terraform output -raw image_tag)"
    echo "$(date -u +%FT%TZ) Detecting drift (exit code 2 = changes needed):"
    terraform plan -input=false -detailed-exitcode -var "image_tag=$tag" || true
    echo "Restoring only the missing rule:"
    terraform apply -input=false -target=aws_vpc_security_group_ingress_rule.db_from_app -var "image_tag=$tag"
    echo "$(date -u +%FT%TZ) Fixed. Expect /ready to recover within ~30s and the alarm to clear."
    ;;
  *)
    echo "usage: $0 break|fix" >&2
    exit 1
    ;;
esac
