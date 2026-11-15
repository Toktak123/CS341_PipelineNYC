#!/usr/bin/env bash
# TEST 02: re-run the same month -> Check_batch = ALREADY_PROCESSED (stops at StopAtAlreadyProcessed) and row count unchanged
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
NAME="test02-rerun-2024-01-$(stamp)"

BEFORE=$(curated_count 2024-01)
STATUS=$(start_run "$NAME" '{"year_month": "2024-01"}')
CHECK=$(out_field "$NAME" check.status)
AFTER=$(curated_count 2024-01)

if [[ "$STATUS" == SUCCEEDED && "$CHECK" == ALREADY_PROCESSED && "$BEFORE" == "$AFTER" ]]; then
  record test02_rerun_idempotent PASS "$NAME check=$CHECK rows $BEFORE -> $AFTER"
else
  record test02_rerun_idempotent FAIL "$NAME status=$STATUS check=$CHECK rows $BEFORE -> $AFTER"
fi
