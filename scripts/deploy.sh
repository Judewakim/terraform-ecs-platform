#!/usr/bin/env bash
# Deploy the dev stack from your own machine (the GitHub "Deploy (dev)"
# workflow does the same thing). Needs: aws CLI logged in, terraform, docker.
#   ./scripts/deploy.sh
set -euo pipefail

cd "$(dirname "$0")/../infra/envs/dev"
REGION="${AWS_REGION:-us-east-1}"
TAG="$(git rev-parse --short=12 HEAD)"

if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree has uncommitted changes; the image tag would not match the code. Commit first." >&2
  exit 1
fi

terraform init -input=false -backend-config=backend.hcl
terraform apply -input=false -auto-approve -target=module.ecr -var "image_tag=$TAG"

REPO="$(terraform output -raw ecr_repository_url)"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${REPO%%/*}"

if aws ecr describe-images --repository-name shortlink --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  echo "Image $TAG already in ECR; skipping build."
else
  docker build --platform linux/amd64 -t "$REPO:$TAG" ../../../app
  docker push "$REPO:$TAG"
  aws ecr wait image-scan-complete --repository-name shortlink --image-id imageTag="$TAG"
fi

critical="$(aws ecr describe-image-scan-findings --repository-name shortlink --image-id imageTag="$TAG" \
  --query 'imageScanFindings.findingSeverityCounts.CRITICAL' --output text)"
if [ "$critical" != "None" ] && [ "$critical" -gt 0 ]; then
  echo "Blocked: $critical critical vulnerabilities in $TAG." >&2
  exit 1
fi

terraform plan -input=false -var "image_tag=$TAG" -out=tfplan
read -r -p "Apply this plan? [y/N] " ok
[ "$ok" = "y" ] || { echo "Cancelled."; exit 0; }
terraform apply -input=false tfplan

aws ecs wait services-stable --cluster "$(terraform output -raw ecs_cluster)" --services "$(terraform output -raw ecs_service)"
echo "Live: $(terraform output -raw app_url)"
echo "Dashboard: $(terraform output -raw dashboard_url)"
echo "Remember: ./scripts/teardown.sh when you're done (about \$3/day while it's up)."
