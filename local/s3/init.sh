#!/bin/sh
# Creates the videos bucket with CORS and lifecycle rules (ADR-0008). Idempotent.
set -eu

S3="aws --endpoint-url http://s3:9000 s3api"

if $S3 head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "bucket $BUCKET already exists"
else
  $S3 create-bucket --bucket "$BUCKET"
  echo "bucket $BUCKET created"
fi

$S3 put-bucket-cors --bucket "$BUCKET" --cors-configuration file:///fiapx/s3/cors.json
echo "CORS applied"

# Lifecycle support varies between S3-compatible servers: report instead of failing the stack.
if $S3 put-bucket-lifecycle-configuration --bucket "$BUCKET" \
     --lifecycle-configuration file:///fiapx/s3/lifecycle.json; then
  echo "lifecycle applied"
else
  echo "WARN: lifecycle rules not supported by this S3 server; objects are not expired locally"
fi
