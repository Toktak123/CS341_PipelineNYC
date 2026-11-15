#!/usr/bin/env bash
# =====================================================================
# teardown.sh — delete the pipeline's AWS resources (saves Learner Lab budget after grading)
#   bash teardown.sh          stop running executions, delete state machine + all nyc_* Lambdas
#                             + Glue database (catalog only; files in S3 are kept)
#   bash teardown.sh --all    also empty and delete the S3 bucket (raw data included)
#                             and the CloudWatch log groups /aws/lambda/nyc_*
# Safe to re-run: anything already deleted is reported as SKIP.
# =====================================================================
set -Euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -f .env ]] && { set -a; source .env; set +a; }

AWS_REGION=${AWS_REGION:-us-east-1}; export AWS_DEFAULT_REGION="$AWS_REGION"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET=${S3_BUCKET:-nyc-taxi-pipeline-$ACCOUNT}
DATABASE=${DATABASE:-nyc_taxi}
STATE_MACHINE_NAME=${STATE_MACHINE_NAME:-nyc-taxi-pipeline}
SM_ARN="arn:aws:states:$AWS_REGION:$ACCOUNT:stateMachine:$STATE_MACHINE_NAME"
ALL=false; [[ "${1:-}" == --all ]] && ALL=true

echo "Account=$ACCOUNT Region=$AWS_REGION Bucket=$S3_BUCKET Database=$DATABASE"
$ALL && echo "Mode: --all (S3 bucket and logs will be deleted too)" || echo "Mode: default (S3 data is kept)"
read -r -p "Delete NYC Taxi pipeline resources in account $ACCOUNT ? (yes/no) " ans
[[ "$ans" == yes ]] || exit 1

# ---------------------------------------------------------------- 1. running executions
# stop them first so nothing writes to S3 / Iceberg while we delete
RUNNING=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" --status-filter RUNNING \
          --query "executions[].executionArn" --output text 2>/dev/null || true)
for arn in $RUNNING; do
  aws stepfunctions stop-execution --execution-arn "$arn" --cause "teardown" >/dev/null && echo "STOPPED $arn"
done
[[ -n "$RUNNING" ]] && sleep 10

# ---------------------------------------------------------------- 2. state machine
if aws stepfunctions delete-state-machine --state-machine-arn "$SM_ARN" 2>/dev/null; then
  echo "DELETED state machine $STATE_MACHINE_NAME"
else
  echo "SKIP state machine (not found)"
fi

# ---------------------------------------------------------------- 3. Lambdas
# by prefix, so functions from older versions (e.g. renamed ones) are removed too
FUNCS=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName,'nyc_')].FunctionName" --output text)
[[ -z "$FUNCS" ]] && echo "SKIP Lambdas (none with prefix nyc_)"
for f in $FUNCS; do
  aws lambda delete-function --function-name "$f" && echo "DELETED Lambda $f"
done

# ---------------------------------------------------------------- 4. Glue database
# Glue API (synchronous) removes the database and all its tables/views from the catalog.
# It does not touch files in S3.
if aws glue delete-database --name "$DATABASE" 2>/dev/null; then
  echo "DELETED Glue database $DATABASE"
else
  echo "SKIP Glue database (not found)"
fi

$ALL || { echo; echo "TEARDOWN OK (S3 data kept in s3://$S3_BUCKET)"; exit 0; }

# ---------------------------------------------------------------- 5. S3 bucket (--all)
empty_bucket() {   # delete current objects + any old versions / delete markers
  aws s3 rm "s3://$S3_BUCKET" --recursive --quiet || true
  aws s3api list-object-versions --bucket "$S3_BUCKET" --output json 2>/dev/null | python3 -c '
import json, subprocess, sys
raw = sys.stdin.read().strip()
d = json.loads(raw) if raw else {}
objs = [{"Key": o["Key"], "VersionId": o["VersionId"]}
        for k in ("Versions", "DeleteMarkers") for o in (d.get(k) or [])]
bucket = sys.argv[1]
for i in range(0, len(objs), 1000):
    subprocess.run(["aws", "s3api", "delete-objects", "--bucket", bucket,
                    "--delete", json.dumps({"Objects": objs[i:i + 1000], "Quiet": True})],
                   check=False, stdout=subprocess.DEVNULL)
' "$S3_BUCKET" || true
}

if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
  # retry: Athena / an in-flight Lambda may still write a file right after we empty the bucket
  for attempt in 1 2 3 4 5; do
    empty_bucket
    if aws s3api delete-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
      echo "DELETED bucket $S3_BUCKET"; break
    fi
    echo "bucket not empty yet (attempt $attempt/5), retrying in 10s ..."
    sleep 10
    [[ $attempt == 5 ]] && { echo "FAILED to delete bucket. Left in it:" >&2
                             aws s3 ls "s3://$S3_BUCKET" --recursive | head >&2; exit 1; }
  done
else
  echo "SKIP bucket (not found)"
fi

# ---------------------------------------------------------------- 6. CloudWatch logs (--all)
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix /aws/lambda/nyc_ \
         --query "logGroups[].logGroupName" --output text 2>/dev/null || true)
for g in $LOG_GROUPS; do
  aws logs delete-log-group --log-group-name "$g" && echo "DELETED log group $g"
done

echo; echo "TEARDOWN OK (everything deleted)"
