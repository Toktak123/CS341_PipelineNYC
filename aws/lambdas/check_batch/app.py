"""Lambda check_batch (app.handler): decide whether this month needs processing
output: {**input, "check": {"status": ...}}
  INVALID_INPUT      raw files incomplete -> state machine goes to InvalidInput (Fail)
  ALREADY_PROCESSED  success marker of this month exists -> stop (Succeed)
  NOT_PROCESSED      no marker yet / force_reprocess -> continue
If a source file is replaced later, re-run that month with "force_reprocess": true.
"""
from nyc_common import TAXI_TYPES, marker_key, object_exists, raw_key, read_json, require_month, require_run_id


def handler(event, context):
    ym = require_month(event)
    require_run_id(event)

    for t in TAXI_TYPES:
        if not object_exists(raw_key(t, ym)):
            return {**event, "check": {"status": "INVALID_INPUT", "reason": f"missing raw file: {t}"}}

    saved = read_json(marker_key(ym))
    done = bool(saved) and saved.get("status") == "SUCCESS"
    force = bool(event.get("force_reprocess", False))

    if done and not force:
        status, reason = "ALREADY_PROCESSED", "marker_exists"
    else:
        status, reason = "NOT_PROCESSED", ("forced" if done else "no_marker")

    return {**event, "check": {"status": status, "reason": reason, "marker_key": marker_key(ym),
                               "previous_run_id": saved.get("run_id") if saved else None}}
