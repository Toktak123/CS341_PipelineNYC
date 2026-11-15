#!/usr/bin/env bash
# =====================================================================
# test/common.sh — functions shared by all test scripts
#   start_run NAME INPUT_JSON   start 1 Step Functions execution and wait until it ends -> echo status
#   out_field NAME PATH         read a value from an execution's output, e.g. out_field x check.status
#   athena_scalar SQL           run an Athena query that returns a single value
#   record TEST PASS|FAIL MSG   print a test result to the screen (no files written to the repo)
# =====================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
[[ -f "$PROJECT_ROOT/.env" ]] && { set -a; source "$PROJECT_ROOT/.env"; set +a; }

AWS_REGION=${AWS_REGION:-us-east-1}; export AWS_DEFAULT_REGION="$AWS_REGION"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET=${S3_BUCKET:-nyc-taxi-pipeline-$ACCOUNT}
DATABASE=${DATABASE:-nyc_taxi}
STATE_MACHINE_NAME=${STATE_MACHINE_NAME:-nyc-taxi-pipeline}
ATHENA_WORKGROUP=${ATHENA_WORKGROUP:-primary}
SM_ARN="arn:aws:states:$AWS_REGION:$ACCOUNT:stateMachine:$STATE_MACHINE_NAME"
EXEC_PREFIX="arn:aws:states:$AWS_REGION:$ACCOUNT:execution:$STATE_MACHINE_NAME"

stamp() { date '+%Y%m%d-%H%M%S'; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

start_run() {
  local name="$1" input="$2" arn status
  arn=$(aws stepfunctions start-execution --state-machine-arn "$SM_ARN" --name "$name" \
        --input "$input" --query executionArn --output text)
  log "START $name  input=$input"
  while true; do
    status=$(aws stepfunctions describe-execution --execution-arn "$arn" --query status --output text)
    [[ "$status" != RUNNING ]] && break
    log "  ... $status"
    sleep 20
  done
  log "END   $name -> $status"
  echo "$status"
}

out_field() {   # out_field <execution_name> <dotted.path>   (read from the execution's output or error on AWS)
  aws stepfunctions describe-execution --execution-arn "$EXEC_PREFIX:$1" --output json \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
path = sys.argv[1]
if path in ("error", "cause"):
    print(d.get(path, "")); sys.exit()
v = json.loads(d.get("output") or "{}")
for k in path.split("."):
    v = v.get(k, {}) if isinstance(v, dict) else {}
print(v if v != {} else "")
' "$2"
}

athena_scalar() {
  local qid state
  qid=$(aws athena start-query-execution --query-string "$1" --work-group "$ATHENA_WORKGROUP" \
        --result-configuration "OutputLocation=s3://$S3_BUCKET/athena-results/" --query QueryExecutionId --output text)
  while true; do
    state=$(aws athena get-query-execution --query-execution-id "$qid" --query QueryExecution.Status.State --output text)
    [[ "$state" == SUCCEEDED ]] && break
    [[ "$state" == FAILED || "$state" == CANCELLED ]] && { echo "athena $state" >&2; return 1; }
    sleep 2
  done
  aws athena get-query-results --query-execution-id "$qid" --query 'ResultSet.Rows[1].Data[0].VarCharValue' --output text
}

curated_count() {   # curated_count [year_month]
  local where=""; [[ -n "${1:-}" ]] && where="WHERE year_month = '$1'"
  athena_scalar "SELECT COUNT(*) FROM $DATABASE.trips_curated $where"
}

record() {
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3"
  [[ "$2" == PASS ]]
}
