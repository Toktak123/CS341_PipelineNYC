"""Lambda finalize_iceberg (app.handler)
1) Check that the row count in the Iceberg tables for this month = the count in staging
2) Write the success marker (row counts + run_id) -> Check_batch uses it to skip this month next time
3) Delete this run's staging

output: {**input, "finalize": {"status": "PUBLISHED", ...}}
"""
from datetime import datetime, timezone

from nyc_common import (delete_prefix, marker_key, query_rows, render, require_month, require_run_id,
                        staging_prefixes, write_json)


def handler(event, context):
    ym = require_month(event)
    run_id = require_run_id(event)
    v = event["verify"]

    r = query_rows(render("batch/count_published", year_month=ym))[0]
    curated, quarantine = int(r["curated_rows"]), int(r["quarantine_rows"])
    if curated != v["curated_rows"] or quarantine != v["rejected_rows"]:
        raise RuntimeError(f"{ym}: published curated={curated} quarantine={quarantine} "
                           f"!= staged curated={v['curated_rows']} rejected={v['rejected_rows']}")

    marker = {"status": "SUCCESS", "year_month": ym, "run_id": run_id,
              "raw_rows": v["raw_rows"], "curated_rows": curated, "quarantine_rows": quarantine,
              "published_at": datetime.now(timezone.utc).isoformat()}
    write_json(marker_key(ym), marker)
    for p in staging_prefixes(run_id, ym):
        delete_prefix(p)
    return {**event, "finalize": {"status": "PUBLISHED", "marker_key": marker_key(ym),
                                  "curated_rows": curated, "quarantine_rows": quarantine}}
