#!/usr/bin/env bash
# Real run over several months (1 execution per month, one at a time so Iceberg commits never collide)
#   bash test/06_run_months.sh 2024-01 2024-06
#   bash test/06_run_months.sh 2024-07 2024-07        # add a new month (incremental)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ $# -ge 2 ]] || { echo "usage: $0 START END (YYYY-MM)"; exit 1; }

MONTHS=$(python3 - "$1" "$2" <<'PY'
import sys
(y, m), (y2, m2) = (map(int, a.split("-")) for a in sys.argv[1:3])
while (y, m) <= (y2, m2):
    print(f"{y:04d}-{m:02d}"); y, m = (y + 1, 1) if m == 12 else (y, m + 1)
PY
)
FAILED=0
for YM in $MONTHS; do
  NAME="nyc-$YM-$(stamp)"
  STATUS=$(start_run "$NAME" "{\"year_month\": \"$YM\"}")
  RESULT=$(out_field "$NAME" finalize.status)
  [[ -z "$RESULT" ]] && RESULT=$(out_field "$NAME" check.status)
  [[ -z "$RESULT" ]] && RESULT=$(out_field "$NAME" quarantine.status)
  printf '%-8s %-10s %s\n' "$YM" "$STATUS" "$RESULT"
  [[ "$STATUS" == SUCCEEDED ]] || { FAILED=$((FAILED + 1)); echo "  error: $(out_field "$NAME" error)"; }
done
echo "FAILED months: $FAILED"
exit "$FAILED"
