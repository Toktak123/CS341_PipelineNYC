#!/usr/bin/env bash
# TEST 04: set dq_threshold_pct = 0 (unrealistically strict) -> IsValid? = NOT_PASSED -> Quarantine_batch
#          must end at Quarantined, add a row to batch_quarantine, and leave that month's curated data untouched
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
NAME="test04-gate-2024-01-$(stamp)"

BEFORE=$(curated_count 2024-01)
BQ_BEFORE=$(athena_scalar "SELECT COUNT(*) FROM $DATABASE.batch_quarantine")
STATUS=$(start_run "$NAME" '{"year_month": "2024-01", "force_reprocess": true, "dq_threshold_pct": 0}')
Q=$(out_field "$NAME" quarantine.status)
AFTER=$(curated_count 2024-01)
BQ_AFTER=$(athena_scalar "SELECT COUNT(*) FROM $DATABASE.batch_quarantine")

if [[ "$STATUS" == SUCCEEDED && "$Q" == QUARANTINED && "$BEFORE" == "$AFTER" && "$BQ_AFTER" -gt "$BQ_BEFORE" ]]; then
  record test04_quality_gate_blocks PASS "$NAME quarantine=$Q rows $BEFORE -> $AFTER batch_quarantine $BQ_BEFORE -> $BQ_AFTER"
else
  record test04_quality_gate_blocks FAIL "$NAME status=$STATUS quarantine=$Q rows $BEFORE -> $AFTER"
fi
