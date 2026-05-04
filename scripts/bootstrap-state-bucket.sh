#!/usr/bin/env bash
# Idempotent: creates an S3 bucket for Terraform remote state (versioned,
# encrypted, public access blocked) and a DynamoDB table for state locking.
# Safe to re-run.
#
# These resources are intentionally not managed by Terraform — they are the
# chicken that lays the egg. Destroy them manually if you ever need to.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="hashtopolis-tfstate-${ACCOUNT_ID}"
LOCK_TABLE="hashtopolis-tfstate-lock"

echo "==> Region:      ${REGION}"
echo "==> Bucket:      ${BUCKET}"
echo "==> Lock table:  ${LOCK_TABLE}"

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "==> Bucket already exists, ensuring config..."
else
  echo "==> Creating bucket..."
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi

echo "==> Enabling versioning..."
aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

echo "==> Enabling default encryption (SSE-S3)..."
aws s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
      "BucketKeyEnabled": true
    }]
  }'

echo "==> Blocking all public access..."
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

if aws dynamodb describe-table --region "${REGION}" --table-name "${LOCK_TABLE}" >/dev/null 2>&1; then
  echo "==> Lock table already exists."
else
  echo "==> Creating DynamoDB lock table..."
  aws dynamodb create-table --region "${REGION}" \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists --region "${REGION}" --table-name "${LOCK_TABLE}"
fi

cat <<EOF

==> Done. Initialize Terraform with:

  terraform init -migrate-state \\
    -backend-config="bucket=${BUCKET}" \\
    -backend-config="key=hashtopolis/terraform.tfstate" \\
    -backend-config="region=${REGION}" \\
    -backend-config="dynamodb_table=${LOCK_TABLE}" \\
    -backend-config="encrypt=true"

  Terraform will ask whether to migrate the existing local state into S3.
  Answer "yes" to copy your current state up. After a successful migration
  the local terraform.tfstate becomes a stale backup — delete it.

EOF
