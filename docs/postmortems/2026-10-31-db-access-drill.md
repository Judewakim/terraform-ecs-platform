# Postmortem: Terraform Networked Container App (URL Shortener)

**Date:** 2026-10-31 
**Author:** Jude Wakim

This project showcases a mock production environment using ALB, ECS Fargate, and RDS to exhibit an ability to build, deploy, run, break, repair, and report a containerized application infrastructure, replicating the work of a cloud support, DevOps and SRE role.   

## Summary

An ALB in a public subnet connects to ECS containers in a private subnet which connects to an RDS Postgres in an isolated subnet and returns back as a 302 redirect. A security group ingress rule for RDS is removed. The effect of the removal is not felt until the ALB's health check for the containers after they're updated which then caused CloudWatch + SNS to alert me. Then ECS begins deprovisioning and reprovisioning a new task. This loop continues until Terraform finds drift from the plan, a new resource (the missing security group rule) that needs to be re-added. Once the drift is corrected, a new task is provisioned, and a few minutes later the ALB reports healthy containers and a few minutes after that the CloudWatch + SNS alerts me that the resources are OK. 

## Impact

- **Requests failed / slowed:** Requests from the ECS containers to the RDS via port 5432 were denied due to a missing security group rule.
- **Users affected:** Users are balanced across all containers but no containers were able to access the RDS, so all users were affected.
- **Data lost:** None. Data was just temporarily unreachable.

## Timeline (EDT)

| Time | Event |
| --- | --- |
| 4:48 | Delete the PostgreSQL 5432 rule |
| 4:54 | Cluster tasks stopped|
| 4:54 | ALB reports unhealthy containers & ECS begins reprovisioning unsuccessfully |
| 4:59 | Engineer alerted via SNS email alert |
| 5:04 | Cause identified with drift |
| 5:05 | Fix applied with Terraform redeploy |
| 5:10 | Alarm cleared, service recovered |

**Time to detect:** 5 mins  **Time to recover:** 16 mins

## Root cause
The containers were unable to reach the RDS database because of a rule change of a security group which was causing the application to display a '502 Bad Gateway' error causing the tasks to show unhealthy which was causing ECS Fargate to deprovision and reprovision tasks until its resolved. The removal of the ingress rule became an issue after an update to a task because security groups are stateful so the previous task was still running because it was opened when the rule existed. Once a new task was made the status of the security group began affecting the application. 

## What went well
- The CloudWatch + SNS alerts properly alerted me of unhealthy containers. 
- The cause was properly identified as a drift from the Terraform plan configuration. 
- The fix was applied quickly and via the correct channels, the Terraform deployment not manual changes. 

## What went poorly
- **Stateful security groups:** I initially anticipated that as soon as the security group rule was deleted that the app would feel the change. Realized that security groups are stateful so tasks kept database connections that were opened while the rule existed, and security groups only check new connections.
- **Task recovery:** I thought the task would initially recover once the security group rule was re-added. Crashed tasks must be replaced first; recovery took a few minutes after the apply.

## Action Items
- **Alert on security group changes:** Configure alerts on changes made to security group rules.
- **Run nightly drift detection:** EOD run a check to see if there is any configuration drift from the Terraform plan.