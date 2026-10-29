output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "backend_hcl" {
  description = "Paste into infra/envs/dev/backend.hcl"
  value       = "bucket = \"${aws_s3_bucket.state.bucket}\"\nregion = \"${var.region}\"\n"
}

output "plan_role_arn" {
  description = "GitHub secret AWS_PLAN_ROLE_ARN"
  value       = aws_iam_role.plan.arn
}

output "deploy_role_arn" {
  description = "GitHub secret AWS_DEPLOY_ROLE_ARN (store it on the dev environment)"
  value       = aws_iam_role.deploy.arn
}

output "workload_boundary_arn" {
  value = aws_iam_policy.workload_boundary.arn
}
