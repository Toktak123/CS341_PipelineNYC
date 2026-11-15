#!/usr/bin/env bash
# =====================================================================
# deploy.sh — deploy the whole NYC Taxi pipeline (re-runnable: unchanged resources are SKIPPED)
#   1) S3 bucket
#   2) 9 Lambdas (deterministic zip -> compare CodeSha256 -> update only functions whose code changed)
#   3) Tables / views in Athena + Glue Data Catalog (CREATE IF NOT EXISTS / CREATE OR REPLACE VIEW)
#   4) Step Functions state machine (updated only when the definition changes)
# Usage:  bash deploy.sh        (settings in .env — see .env.example)
# =====================================================================
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -f .env ]] && { set -a; source .env; set +a; }

for cmd in aws python3; do command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }; done

AWS_REGION=${AWS_REGION:-us-east-1}
export AWS_DEFAULT_REGION="$AWS_REGION"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET=${S3_BUCKET:-nyc-taxi-pipeline-$ACCOUNT}
DATABASE=${DATABASE:-nyc_taxi}
IAM_ROLE=${IAM_ROLE:-LabRole}
STATE_MACHINE_NAME=${STATE_MACHINE_NAME:-nyc-taxi-pipeline}
LAMBDA_RUNTIME=${LAMBDA_RUNTIME:-python3.12}
ATHENA_WORKGROUP=${ATHENA_WORKGROUP:-primary}
ATHENA_OUTPUT="s3://$S3_BUCKET/athena-results/"

ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE" --query Role.Arn --output text 2>/dev/null \
           || echo "arn:aws:iam::$ACCOUNT:role/$IAM_ROLE")
echo "Account=$ACCOUNT Region=$AWS_REGION Bucket=$S3_BUCKET Database=$DATABASE Role=$ROLE_ARN"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- 1. S3
if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
  echo "SKIP existing bucket: $S3_BUCKET"
else
  if [[ "$AWS_REGION" == us-east-1 ]]; then
    aws s3api create-bucket --bucket "$S3_BUCKET" >/dev/null
  else
    aws s3api create-bucket --bucket "$S3_BUCKET" --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
  aws s3api put-public-access-block --bucket "$S3_BUCKET" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  echo "CREATED bucket: $S3_BUCKET"
fi

# ---------------------------------------------------------------- 2. Lambda
# Each Lambda zip = app.py + common/nyc_common.py + sql/batch + sql/result + sql/quality (fixed timestamps -> same hash if code is unchanged)
python3 - "$TMP" > "$TMP/builds.txt" <<'PY'
import base64, hashlib, pathlib, sys, zipfile
out = pathlib.Path(sys.argv[1]); root = pathlib.Path("aws/lambdas")
extra = [(pathlib.Path("aws/lambdas/common/nyc_common.py"), "nyc_common.py")]
for d in ("sql/batch", "sql/result", "sql/quality"):
    extra += [(p, p.as_posix()) for p in sorted(pathlib.Path(d).glob("*.sql"))]
for fn_dir in sorted(p for p in root.iterdir() if p.is_dir() and p.name != "common"):
    files = [(fn_dir / "app.py", "app.py")] + extra
    zpath = out / f"{fn_dir.name}.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arc in files:
            info = zipfile.ZipInfo(arc, date_time=(2024, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, src.read_bytes())
    sha = base64.b64encode(hashlib.sha256(zpath.read_bytes()).digest()).decode()
    print(fn_dir.name, sha, zpath)
PY

ENV_JSON="{\"Variables\":{\"BUCKET\":\"$S3_BUCKET\",\"DATABASE\":\"$DATABASE\",\"ATHENA_WORKGROUP\":\"$ATHENA_WORKGROUP\"}}"

while read -r NAME SHA ZIP; do
  FN="nyc_$NAME"
  MEM=256; [[ "$NAME" == fetch_batch ]] && MEM=1024     # fetch: Lambda network speed scales with memory
  if aws lambda get-function --function-name "$FN" >/dev/null 2>&1; then
    REMOTE_SHA=$(aws lambda get-function --function-name "$FN" --query Configuration.CodeSha256 --output text)
    if [[ "$REMOTE_SHA" == "$SHA" ]]; then
      echo "SKIP unchanged Lambda code: $FN"
    else
      aws lambda update-function-code --function-name "$FN" --zip-file "fileb://$ZIP" >/dev/null
      aws lambda wait function-updated --function-name "$FN"
      echo "UPDATED Lambda code: $FN"
    fi
    aws lambda get-function-configuration --function-name "$FN" --output json > "$TMP/cfg.json"
    if python3 - "$TMP/cfg.json" "$LAMBDA_RUNTIME" "$ROLE_ARN" "$MEM" "$ENV_JSON" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); runtime, role, mem, env = sys.argv[2], sys.argv[3], int(sys.argv[4]), json.loads(sys.argv[5])
same = (c["Runtime"] == runtime and c["Handler"] == "app.handler" and c["Timeout"] == 900
        and c["MemorySize"] == mem and c["Role"] == role
        and c.get("Environment", {}).get("Variables", {}) == env["Variables"])
sys.exit(0 if same else 1)
PY
    then
      echo "SKIP unchanged Lambda config: $FN"
    else
      aws lambda update-function-configuration --function-name "$FN" --runtime "$LAMBDA_RUNTIME" \
        --handler app.handler --timeout 900 --memory-size "$MEM" --role "$ROLE_ARN" \
        --environment "$ENV_JSON" >/dev/null
      aws lambda wait function-updated --function-name "$FN"
      echo "UPDATED Lambda config: $FN"
    fi
  else
    aws lambda create-function --function-name "$FN" --runtime "$LAMBDA_RUNTIME" --role "$ROLE_ARN" \
      --handler app.handler --timeout 900 --memory-size "$MEM" --environment "$ENV_JSON" \
      --zip-file "fileb://$ZIP" >/dev/null
    aws lambda wait function-active --function-name "$FN"
    echo "CREATED Lambda: $FN"
  fi
done < "$TMP/builds.txt"

# ---------------------------------------------------------------- 3. Athena / Glue Data Catalog
athena_run() {
  local qid state
  qid=$(aws athena start-query-execution --query-string "$1" --work-group "$ATHENA_WORKGROUP" \
        --result-configuration "OutputLocation=$ATHENA_OUTPUT" --query QueryExecutionId --output text)
  while true; do
    state=$(aws athena get-query-execution --query-execution-id "$qid" --query QueryExecution.Status.State --output text)
    case "$state" in
      SUCCEEDED) return 0 ;;
      FAILED|CANCELLED)
        aws athena get-query-execution --query-execution-id "$qid" \
          --query QueryExecution.Status.StateChangeReason --output text >&2
        return 1 ;;
      *) sleep 2 ;;
    esac
  done
}
for f in sql/setup/*.sql; do
  # substitute {{DB}} {{BUCKET}} + strip comments (Athena DDL rejects leading comments)
  SQL=$(sed -e "s|{{DB}}|$DATABASE|g" -e "s|{{BUCKET}}|$S3_BUCKET|g" -e 's/--.*$//' "$f" | grep -v '^[[:space:]]*$')
  athena_run "$SQL"
  echo "APPLIED Athena DDL: $(basename "$f")"
done

# ---------------------------------------------------------------- 4. Step Functions
SM_ARN="arn:aws:states:$AWS_REGION:$ACCOUNT:stateMachine:$STATE_MACHINE_NAME"
sed -e "s|__REGION__|$AWS_REGION|g" -e "s|__ACCOUNT__|$ACCOUNT|g" aws/step_function/state_machine.json > "$TMP/sm.json"
if aws stepfunctions describe-state-machine --state-machine-arn "$SM_ARN" --output json > "$TMP/remote_sm.json" 2>/dev/null; then
  if python3 - "$TMP/remote_sm.json" "$TMP/sm.json" "$ROLE_ARN" <<'PY'
import json, sys
remote = json.load(open(sys.argv[1])); local = json.load(open(sys.argv[2]))
same = json.loads(remote["definition"]) == local and remote["roleArn"] == sys.argv[3]
sys.exit(0 if same else 1)
PY
  then
    echo "SKIP unchanged state machine: $STATE_MACHINE_NAME"
  else
    aws stepfunctions update-state-machine --state-machine-arn "$SM_ARN" \
      --definition "file://$TMP/sm.json" --role-arn "$ROLE_ARN" >/dev/null
    echo "UPDATED state machine: $STATE_MACHINE_NAME"
  fi
else
  aws stepfunctions create-state-machine --name "$STATE_MACHINE_NAME" --type STANDARD \
    --definition "file://$TMP/sm.json" --role-arn "$ROLE_ARN" >/dev/null
  echo "CREATED state machine: $STATE_MACHINE_NAME"
fi

echo
echo "DEPLOY OK"
echo "  State machine : $SM_ARN"
echo "  Bucket        : s3://$S3_BUCKET"
echo "  Next          : bash test/01_run_2024_01.sh   or   bash test/06_run_months.sh 2024-01 2024-06"
