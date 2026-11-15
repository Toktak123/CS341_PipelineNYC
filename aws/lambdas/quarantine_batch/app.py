"""Lambda quarantine_batch (app.handler): month that failed the quality gate
Record the reasons in the Iceberg table batch_quarantine and do NOT publish (existing curated data untouched, raw files kept)

output: {**input, "quarantine": {"status": "QUARANTINED", ...}}
"""
import json
from datetime import datetime, timezone

from nyc_common import render, require_month, require_run_id, run_query


def handler(event, context):
    ym = require_month(event)
    run_id = require_run_id(event)
    failed = event.get("validation", {}).get("failed_checks", [])
    text = json.dumps(failed, ensure_ascii=False).replace("'", "''")    # escape for a SQL string literal
    run_query(render("batch/batch_quarantine_insert", run_id=run_id, year_month=ym,
                     quarantined_at=datetime.now(timezone.utc).isoformat(), failed_checks=text))
    return {**event, "quarantine": {"status": "QUARANTINED", "failed_checks": failed}}
