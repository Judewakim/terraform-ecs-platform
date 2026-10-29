# Design decisions

Short records of the choices that shape this platform, the alternatives, and
what would change for production.

## 1. ECS Fargate, not EKS

**Chose:** ECS on Fargate.
**Why:** The EKS control plane alone costs about $73/month before any
workload runs. Fargate removes node management entirely: no AMIs to patch, no
cluster autoscaler. For one stateless service, Kubernetes adds operational
weight without adding capability.
**Would revisit when:** many services need shared platform tooling (service
mesh, Helm-based delivery), or the team already runs Kubernetes.

## 2. Three subnet tiers, and the database tier has no route out

Public subnets hold only the load balancer and NAT. Tasks run in private
subnets and reach AWS APIs through NAT. The database subnets have a route
table with no internet or NAT route at all, so even a misconfigured database
cannot reach or be reached from outside the VPC. A module test enforces this.

## 3. One NAT gateway by default

**Tradeoff:** One NAT costs about $33/month; one per AZ doubles that. With a
single NAT, an outage in its AZ cuts outbound traffic (ECR pulls, secret
fetches) for tasks in the other AZ too. Running tasks keep serving; new tasks
can't start.
**Dev:** `single_nat_gateway = true`. **Prod:** `false`.

## 4. Security-group rules wired in the environment, not the modules

Each tier's module creates its own security group. The rules *between* tiers
(ALB → app, app → DB) live in `infra/envs/dev/security_groups.tf`, each as an
ingress rule on the receiver and a matching egress rule on the sender, both
referencing security groups rather than CIDRs. This keeps modules independent
(no module needs another's group as input), avoids dependency cycles, and puts
the whole traffic path on one screen for review.

## 5. The database password never exists outside AWS

`manage_master_user_password = true`: RDS generates the password, stores it in
Secrets Manager encrypted with this stack's KMS key, and rotates it every 7
days. It never appears in Terraform state, CI logs, the task definition or
this repo.

The app reads the secret itself each time it opens a database connection
(cached for 5 minutes, refetched immediately if a login fails). Injecting it
as an environment variable at container start would break a week after every
deploy: the password rotates, the pool opens a new connection, and login fails.
A test against a real Postgres in CI rotates the password mid-run to prove it.
**Prod upgrade:** a separate least-privilege app user via IAM database
authentication (already enabled on the instance), instead of the master user.

## 6. Two IAM roles per task

The execution role (used by ECS to start the task) can pull this image and
write this log group. The task role (used by the app's own code) can read this
one secret and decrypt it only through Secrets Manager. If the app is
compromised, its credentials reach nothing else in AWS.

## 7. Readiness vs liveness

`/health` never touches the database; `/ready` checks it. The load balancer
uses `/ready`, so a task that can't reach Postgres stops receiving traffic.
Tradeoff: during a full database outage, ECS replaces tasks that keep failing
readiness. Acceptable here because every request needs the database anyway.

## 8. CI with no cloud access, deploys with approval

Everything that can run without AWS does: unit tests, image build and smoke
test, `terraform validate`, module tests against a mocked provider, Checkov.
Only plan, deploy and destroy assume AWS roles, through GitHub OIDC (short-lived
tokens, no stored keys). The deploy role trusts only jobs in the `dev` GitHub
environment, which requires a reviewer and only deploys from `main`.

The deploy role gets PowerUserAccess plus IAM limited to `shortlink-*` roles.
A role that can create roles can usually make itself admin: create a role with
an admin policy, then assume it. Two guards close that: it can only create or
edit roles that carry the `shortlink-workload-boundary` permissions boundary
(a ceiling of logs, image pull, secret read and decrypt), and it is denied
removing or swapping boundaries, attaching managed policies, and touching the
CI roles. The plan role can read state and take the lock, but can't write state.
**Prod upgrade:** replace PowerUserAccess with a service-scoped policy.

## 9. Checkov findings are skipped inline, with a reason

Each accepted finding is a `#checkov:skip=ID:reason` comment on the resource
it applies to, so the exception is reviewed with the code. Most are dev cost
choices that a variable flips for production (multi-AZ, deletion protection,
log retention).

## What changes for production

| Setting | Dev | Prod |
| --- | --- | --- |
| NAT gateways | 1 | 1 per AZ |
| RDS Multi-AZ | off | on |
| Deletion protection (ALB, RDS) | off | on |
| HTTPS | optional | required (ACM cert, HTTP redirects) |
| WAF on the ALB | none | AWS managed rule groups |
| Log retention | 30 days | 1 year+ |
| Performance Insights / enhanced monitoring | off | on |
| Interface VPC endpoints (ECR, Secrets, Logs) | none, via NAT | yes, keep AWS traffic off NAT |
| Container Insights | standard | enhanced |
| Deploy role | PowerUser + scoped IAM | scoped policy + permissions boundary |
