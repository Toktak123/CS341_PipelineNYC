#!/usr/bin/env bash
# TEST 05: month TLC has not published yet (2030-01) -> Fetch_batch error SourceNotAvailable -> PipelineFailed
#          and no broken file may be left in raw
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
NAME="test05-missing-2030-01-$(stamp)"

STATUS=$(start_run "$NAME" '{"year_month": "2030-01"}')
ERR=$(out_field "$NAME" error)
LEFT=$(aws s3 ls "s3://$S3_BUCKET/raw/" --recursive | grep -c "year_month=2030-01" || true)

if [[ "$STATUS" == FAILED && "$ERR" == SourceNotAvailable && "$LEFT" == 0 ]]; then
  record test05_missing_source PASS "$NAME error=$ERR raw_files_2030_01=$LEFT"
else
  record test05_missing_source FAIL "$NAME status=$STATUS error=$ERR raw_files_2030_01=$LEFT"
fi
