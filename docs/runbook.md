# Runbook

Each alarm's description links to its section here. Start with the dashboard
(`terraform -chdir=infra/envs/dev output dashboard_url`), then follow the steps.

Useful commands (run from `infra/envs/dev`):

```bash
CLUSTER=$(terraform output -raw ecs_cluster)
SERVICE=$(terraform output -raw ecs_service)
LOGS=$(terraform output -raw log_group)

aws ecs describe-services --cluster $CLUSTER --services $SERVICE \
  --query 'services[0].{running:runningCount,desired:desiredCount,deployments:deployments[].{status:rolloutState,task:taskDefinition}, events:events[:5].message}'
aws logs tail $LOGS --since 15m --follow
aws logs tail $LOGS --since 15m --filter-pattern '{ $.status >= 500 }'
```

## app-5xx

The app is returning server errors.

1. Was there a deploy in the last hour? Check `deployments` in the command above. If yes and errors started with it, roll back: rerun *Deploy (dev)* from the last good commit, or `terraform apply -var image_tag=<last good tag>`.
2. Tail the logs for `"level": "ERROR"` and status 500 lines. The `request_id` ties a log line to the response header a user saw.
3. If errors mention the database, go to [database](#database).

## unhealthy-tasks

The load balancer's `/ready` check is failing on at least one task.

1. Check service events for "unhealthy" or "failed to start".
2. `/ready` fails when the task can't reach Postgres. Check the app → DB security-group rules: `terraform plan` should show no changes. If it shows a missing rule, someone changed it outside Terraform; `terraform apply` restores it.
3. If tasks fail to start at all, the events will say why (image pull, secret access, out of memory). Image pull failures through NAT point at the NAT gateway or a missing image tag.

## high-latency

p95 response time is over 1 second.

1. Is traffic up? Compare request count on the dashboard. Autoscaling should add tasks within a few minutes; check `desiredCount` vs `maxCapacity` (4). If it's pinned at max, raise `max_tasks`.
2. Is the database the bottleneck? Check DB CPU and connections. Slow queries over 500 ms are written to the RDS PostgreSQL log.

## high-cpu

Service CPU stayed above 85% for 8 of 10 minutes, so autoscaling isn't keeping up.

1. Check whether the service is at `max_tasks`. If so, raise it or the task CPU size.
2. If traffic is normal and CPU is high, suspect a code regression from the last deploy; roll back.

## database

DB CPU high or free storage under 2 GB.

1. CPU: look for slow queries in the RDS log group `/aws/rds/instance/<id>/postgresql`.
2. Storage autoscales up to 50 GB. If it's near that, raise `max_allocated_storage_gb`.
3. Connection errors from the app: confirm the instance is `available` (`aws rds describe-db-instances`) and the security-group rules are intact (`terraform plan`).

## Rollback

Every image is tagged with its commit SHA and tags are immutable, so rolling
back means deploying an older SHA. ECS also rolls back on its own if a new
deployment's tasks fail health checks (deployment circuit breaker).
