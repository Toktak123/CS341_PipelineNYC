"""Lambda validate_batch (app.handler): data quality checks for the month + quality gate

1) Athena: count quality issues for all sources (sql/batch/dq_check.sql) -> append to Iceberg table dq_results
2) gate: PASSED when (a) all sources are present (b) every source has > 0 rows (c) % rejected <= dq_threshold_pct

output: {**input, "validation": {"status": "PASSED" | "NOT_PASSED", "failed_checks": [...], ...}}
"""
from nyc_common import TAXI_TYPES, query_rows, render, require_month, require_run_id, run_query


def handler(event, context):
    ym = require_month(event)
    run_id = require_run_id(event)
    threshold = float(event.get("dq_threshold_pct", 5))
    if not 0 <= threshold <= 100:
        raise ValueError("dq_threshold_pct must be between 0 and 100")

    run_query(render("batch/dq_check", year_month=ym, run_id=run_id))
    rows = query_rows(render("batch/dq_rows", year_month=ym, run_id=run_id))

    metrics = {r["taxi_type"]: {"total_rows": int(r["total_rows"]),
                                "rejected_rows": int(r["rejected_rows"]),
                                "rejected_pct": float(r["rejected_pct"])} for r in rows}
    failed = [f"{t}: missing source" for t in TAXI_TYPES if t not in metrics]
    for t, m in metrics.items():
        if m["total_rows"] == 0:
            failed.append(f"{t}: 0 rows")
        if m["rejected_pct"] > threshold:
            failed.append(f"{t}: rejected {m['rejected_pct']}% > {threshold}%")

    return {**event, "validation": {
        "status": "NOT_PASSED" if failed else "PASSED",
        "failed_checks": failed,
        "threshold_pct": threshold,
        "metrics": metrics,
        "raw_rows": sum(m["total_rows"] for m in metrics.values()),
    }}
