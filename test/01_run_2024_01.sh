#!/usr/bin/env bash
# TEST 01: run one month (2024-01) for the first time -> SUCCEEDED and FinalizeIceberg = PUBLISHED
#          (if it was already run, ALREADY_PROCESSED also counts as a pass)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
NAME="test01-2024-01-$(stamp)"

STATUS=$(start_run "$NAME" '{"year_month": "2024-01"}')
FINAL=$(out_field "$NAME" finalize.status)
CHECK=$(out_field "$NAME" check.status)

if [[ "$STATUS" == SUCCEEDED && ( "$FINAL" == PUBLISHED || "$CHECK" == ALREADY_PROCESSED ) ]]; then
  record test01_first_run PASS "$NAME finalize=$FINAL check=$CHECK curated_rows_2024_01=$(curated_count 2024-01)"
else
  record test01_first_run FAIL "$NAME status=$STATUS finalize=$FINAL error=$(out_field "$NAME" error)"
fi
