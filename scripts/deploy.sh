#!/usr/bin/env bash
# Deploy the dev stack from your own machine (the GitHub "Deploy (dev)"
# workflow does the same thing). Needs: aws CLI logged in, terraform, docker.
#   ./scripts/deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../infra/envs/dev"
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
# Base image registry: logged-in pulls avoid the anonymous per-IP rate limit.
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws

if aws ecr describe-images --repository-name shortlink --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  echo "Image $TAG already in ECR; skipping build."
else
  docker build --platform linux/amd64 -t "$REPO:$TAG" ../../../app
  docker push "$REPO:$TAG"
fi

"$SCRIPT_DIR/scan-gate.sh" shortlink "$TAG"

terraform plan -input=false -var "image_tag=$TAG" -out=tfplan
read -r -p "Apply this plan? [y/N] " ok
[ "$ok" = "y" ] || { echo "Cancelled."; exit 0; }
terraform apply -input=false tfplan

aws ecs wait services-stable --cluster "$(terraform output -raw ecs_cluster)" --services "$(terraform output -raw ecs_service)"
echo "Live: $(terraform output -raw app_url)"
echo "Dashboard: $(terraform output -raw dashboard_url)"
echo "Remember: ./scripts/teardown.sh when you're done (about \$3/day while it's up)."
