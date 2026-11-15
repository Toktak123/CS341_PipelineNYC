"""Lambda publish_iceberg (app.handler): staging (already verified) -> Iceberg tables

1) Delete this month's success marker first (if publish fails midway, the next run will not skip this month)
2) DELETE this month from trips_curated, then INSERT from staging_curated
3) DELETE this month from trips_quarantine, then INSERT from staging_rejected
Iceberg makes each statement an atomic commit, and re-runs never duplicate data

output: {**input, "publish": {"status": "WRITTEN", ...}}
"""
from nyc_common import BUCKET, marker_key, render, require_month, require_run_id, run_query, s3


def handler(event, context):
    ym = require_month(event)
    run_id = require_run_id(event)
    if event.get("verify", {}).get("status") != "STAGED":
        raise ValueError("Verify_batch has not passed")

    s3.delete_object(Bucket=BUCKET, Key=marker_key(ym))
    queries = {}
    for step in ("delete_curated", "insert_curated", "delete_quarantine", "insert_quarantine"):
        q = run_query(render(f"batch/{step}", year_month=ym, run_id=run_id))
        queries[step] = q["QueryExecutionId"]
    return {**event, "publish": {"status": "WRITTEN", "athena_queries": queries}}
