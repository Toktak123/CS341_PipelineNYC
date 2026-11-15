"""Lambda verify_batch (app.handler): reconcile staging counts before publish
raw_rows (from Validate_batch) must equal curated_rows + rejected_rows in staging
On mismatch -> raise VerificationError (state machine goes to PipelineFailed, Iceberg tables untouched)

output: {**input, "verify": {"status": "STAGED", "curated_rows": ..., "rejected_rows": ..., "manifest_key": ...}}
"""
from datetime import datetime, timezone

from nyc_common import query_rows, render, require_month, require_run_id, write_json


class VerificationError(Exception):
    pass


def handler(event, context):
    ym = require_month(event)
    run_id = require_run_id(event)
    raw_rows = int(event["validation"]["raw_rows"])

    r = query_rows(render("batch/count_staging", year_month=ym, run_id=run_id))[0]
    curated, rejected = int(r["curated_rows"]), int(r["rejected_rows"])
    if raw_rows != curated + rejected:
        raise VerificationError(f"{ym}: raw {raw_rows} != curated {curated} + rejected {rejected}")

    manifest = {"status": "STAGED", "year_month": ym, "run_id": run_id, "raw_rows": raw_rows,
                "curated_rows": curated, "rejected_rows": rejected,
                "verified_at": datetime.now(timezone.utc).isoformat()}
    key = f"staging/manifests/run_id={run_id}/year_month={ym}/manifest.json"
    write_json(key, manifest)
    return {**event, "verify": {**manifest, "manifest_key": key}}
