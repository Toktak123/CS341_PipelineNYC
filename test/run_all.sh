#!/usr/bin/env bash
# Run tests 01-05 in order (results printed to the screen)
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0
for t in 01_run_2024_01 02_rerun_2024_01 03_force_reprocess_2024_01 04_gate_threshold_zero 05_missing_month_2030; do
  echo "===== $t ====="
  bash "$DIR/$t.sh" || FAILED=$((FAILED + 1))
done
echo "failed $FAILED / 5 tests"
exit "$FAILED"
