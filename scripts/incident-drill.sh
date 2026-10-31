#!/usr/bin/env bash
# Incident drill: simulate a bad manual change in the console, watch the
# platform detect it, then let Terraform repair the drift.
#
# What it breaks: deletes the security-group rule that lets the app reach
# Postgres, then stops the running tasks (open connections survive a rule
# change, because security groups are stateful). Effect: new tasks can't reach
# the database, the app goes down, alarms fire. Fix: terraform plan shows the missing rule;
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
    # Security groups are stateful: connections already open keep working after
    # a rule is removed. The outage starts when tasks are replaced and have to
    # open new connections, so stop the running tasks to simulate that.
    cluster="$(terraform output -raw ecs_cluster)"
    for task in $(aws --region "$REGION" ecs list-tasks --cluster "$cluster" --query 'taskArns[]' --output text); do
      aws --region "$REGION" ecs stop-task --cluster "$cluster" --task "$task" --reason "incident drill" >/dev/null
    done
    echo "Done. Expect: replacement tasks can't reach Postgres and fail to start; the app"
    echo "goes down and the unhealthy-tasks or app-5xx alarm fires within a few minutes."
    echo "Note the times for the postmortem. Then run: $0 fix (or re-run Deploy)"
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
