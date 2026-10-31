# Postmortem: App lost database access after a manual security-group change (drill)

**Date:** 2026-10-31   **Impact window:** about 16:57 to 17:07 EDT (about 10 minutes)   **Severity:** SEV-2 (full outage, dev environment, planned drill)
**Author:** Jude Wakim   **Status:** reviewed

Blameless: this describes what the system allowed, not who made a mistake. The
change was made deliberately to test detection and recovery.

## Summary

The inbound rule that lets the app containers reach Postgres was deleted by
hand in the console. Nothing broke for about nine minutes, because security
groups are stateful and the containers kept their already-open database
connections. When the containers were replaced, the new ones could not open a
connection, failed to start, and the app returned 502 errors. The
unhealthy-tasks alarm fired two minutes after the outage began. Re-running the
Deploy pipeline let Terraform detect the missing rule and recreate it; the app
recovered within about four minutes of the apply.

## Impact

- All requests failed (HTTP 502 from the load balancer) for about 10 minutes.
- No data was lost. Links created before the outage worked after recovery.

## Timeline (EDT)

| Time | Event | Source |
| --- | --- | --- |
| 16:48:05 | Inbound rule (Postgres 5432 from the app security group) deleted on `shortlink-dev-db` | CloudTrail `RevokeSecurityGroupIngress` |
| 16:48 to 16:57 | No impact. Existing database connections stayed open. | Manual checks of `/ready` and a short link |
| ~16:57 | Both tasks stopped, simulating a routine replacement. Outage begins. | CloudWatch dashboard (healthy count drops) |
| 16:57 onward | New tasks start, can't reach Postgres, crash; ECS keeps replacing them. Load balancer returns 502. | ECS events, browser |
| 16:59:30 | `shortlink-dev-unhealthy-tasks` alarm fires, email sent | CloudWatch alarm history |
| TBD | Deploy (dev) run started and approved | GitHub Actions run history |
| — | Plan shows the rule missing ("AWS resource not found during refresh") and recreates it | Deploy run, Plan step |
| ~17:07 | Tasks healthy again, app serving | CloudWatch dashboard |
| 17:10:30 | Alarm returns to OK | CloudWatch alarm history |

**Time to detect:** about 2 minutes from outage start.
**Time to recover:** about 10 minutes from outage start; under 4 minutes from the apply finishing.

Open item: get the exact `StopTask` time from CloudTrail and the fix run's start
and end times from GitHub Actions to firm up the times marked "~".

## Root cause

A security-group rule managed by Terraform was changed outside Terraform.
Nothing prevented the change, and nothing alerted on it. Because security
groups only evaluate new connections, the break stayed hidden until the
containers were replaced. In production, that delay could be days, and the
outage would surface during an unrelated event (a deploy, a crash, a scale-out),
which makes it much harder to trace.

## What went well

- The alarm detected the outage within 2 minutes and emailed.
- Terraform detected the drift on its own; the fix was a pipeline run, with no hand edits.
- CloudTrail recorded exactly who changed the rule and when.
- Two tasks across two availability zones meant a single task loss would not have been noticed by users.

## What went poorly

- **Nothing caught the change itself.** It took a task replacement to expose it.
- **The fix deploy mixed unrelated changes.** The plan also replaced the task definition (a new image from an unrelated commit) and showed a parameter-group change that appears on every plan. The one relevant line had to be picked out of the noise.
- **The app's failure was hard to find in logs.** The containers crashed at startup with a stack trace rather than a clear, searchable "database unreachable" log line, and the evidence was lost when the stack was destroyed.
- **The same alarm fired falsely during the first deploy** (14:17:30 to 14:29:30). It treats "no data" as an outage, and a brand-new target group has no data. False alarms teach people to ignore real ones.

## Action items

| Action | Type | Owner | Status |
| --- | --- | --- | --- |
| Alert within minutes on any security-group change to Terraform-managed groups (EventBridge rule on `AuthorizeSecurityGroup*`/`RevokeSecurityGroup*` → SNS) | Detect | Jude | Open |
| Nightly drift detection: scheduled `terraform plan` with the read-only plan role; alert if it shows changes | Detect | Jude | Open |
| Fix the alarm false positive: treat missing data as not breaching, and add a "healthy tasks < 1" alarm for full outages | Detect | Jude | Open |
| Log a clear structured error when the app can't reach the database at startup | Diagnose | Jude | Open |
| Fix the `rds.force_ssl` perpetual diff (`apply_method = "pending-reboot"`) so plans only show real changes | Mitigate | Jude | Open |
| Production: deny console changes to Terraform-managed security groups for human roles, with a break-glass role for emergencies | Prevent | Jude | Open |
