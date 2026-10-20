#!/usr/bin/env bash
set -euo pipefail

#
# bootstrap-state.sh — Create the Terraform remote state backend
#
# Provisions the S3 bucket (versioned, AES256-encrypted, public access blocked)
# and the DynamoDB lock table used by terraform/environments/{dev,prod}.
# One-time setup, done outside Terraform. Idempotent: safe to re-run.
#
# Usage:
#   ./scripts/bootstrap-state.sh                      # default region eu-central-1
#   ./scripts/bootstrap-state.sh --region eu-west-1
#

REGION="eu-central-1"
TABLE="petclinic-terraform-locks"
TAGS_KV='Key=Project,Value=petclinic Key=ManagedBy,Value=terraform'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="${2:?--region requires a value}"; shift 2 ;;
    -h|--help) sed -n '3,14p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="petclinic-terraform-state-${ACCOUNT_ID}"

echo "Account: ${ACCOUNT_ID}  Region: ${REGION}"
echo "Bucket:  ${BUCKET}"
echo "Table:   ${TABLE}"

# --- S3 bucket ---
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
  echo "Bucket exists, skipping create."
else
  echo "Creating bucket..."
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi

# These calls are idempotent, so always apply them to correct any drift.
aws s3api put-bucket-versioning --bucket "$BUCKET" --region "$REGION" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET" --region "$REGION" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-tagging --bucket "$BUCKET" --region "$REGION" \
  --tagging 'TagSet=[{Key=Project,Value=petclinic},{Key=ManagedBy,Value=terraform}]'

# --- DynamoDB lock table ---
if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "Table exists, skipping create."
else
  echo "Creating lock table..."
  aws dynamodb create-table --table-name "$TABLE" --region "$REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags $TAGS_KV >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
fi

echo "Done. Backend ready: s3://${BUCKET} / ${TABLE}"
