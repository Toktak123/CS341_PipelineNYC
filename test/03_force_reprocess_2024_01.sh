#!/usr/bin/env bash
# TEST 03: force reprocessing of 2024-01 -> PUBLISHED and same row count (DELETE + INSERT never duplicates data)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
NAME="test03-force-2024-01-$(stamp)"

BEFORE=$(curated_count 2024-01)
STATUS=$(start_run "$NAME" '{"year_month": "2024-01", "force_reprocess": true}')
FINAL=$(out_field "$NAME" finalize.status)
AFTER=$(curated_count 2024-01)

if [[ "$STATUS" == SUCCEEDED && "$FINAL" == PUBLISHED && "$BEFORE" == "$AFTER" ]]; then
  record test03_force_reprocess_no_duplicates PASS "$NAME rows $BEFORE -> $AFTER"
else
  record test03_force_reprocess_no_duplicates FAIL "$NAME status=$STATUS finalize=$FINAL rows $BEFORE -> $AFTER"
fi
