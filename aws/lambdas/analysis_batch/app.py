"""Lambda analysis_batch (app.handler): metrics + quality report + sample data + JSON summary
1) Run every file in sql/result/*.sql (answers) and sql/quality/*.sql (DQ, reconciliation, quarantine summary, sample) on Athena (4 queries at a time) and store results as CSV
     s3://BUCKET/reports/<run_id>/<name>.csv   results of this run (auditable later)
     s3://BUCKET/reports/latest/<name>.csv     latest results
2) Read the key CSVs (trips_by_type, monthly_trips, reconciliation, dq_latest) back and summarize them into one JSON file
     s3://BUCKET/summary/<run_id>/analysis_summary.json
     s3://BUCKET/summary/latest/analysis_summary.json
   No extra Athena queries: the summary is built from the same CSVs as reports/, so JSON numbers always match the CSVs

output: {**input, "analysis": {"status": "OK", "reports": [...], "summary": "s3://..."}}
"""
import csv
import io
from datetime import datetime, timezone

from nyc_common import BUCKET, SQL_DIR, render, require_run_id, s3, start_query, wait_query, write_json

PARALLEL = 4
EXPECTED_MONTHS = [f"2024-{m:02d}" for m in range(1, 7)]   # scope of the question: first 6 months of 2024


def read_csv(key):
    """Read an Athena result (CSV) from S3 -> list of dicts (values are strings)"""
    body = s3.get_object(Bucket=BUCKET, Key=key)["Body"].read().decode("utf-8")
    return list(csv.DictReader(io.StringIO(body)))


def num(v):
    """Convert a CSV string to a number (empty/None -> None)"""
    if v in (None, ""):
        return None
    f = float(v)
    return int(f) if f.is_integer() else f


def build_summary(run_id, event, csv_keys):
    ranking = [
        {"rank": num(r["usage_rank"]), "taxi_type": r["taxi_type"], "total_trips": num(r["total_trips"]),
         "share_pct": num(r["share_pct"]), "first_month": r["first_month"], "last_month": r["last_month"]}
        for r in read_csv(csv_keys["trips_by_type"])
    ]
    ranking.sort(key=lambda r: r["rank"])

    monthly = {}
    for r in read_csv(csv_keys["monthly_trips"]):
        monthly.setdefault(r["year_month"], {})[r["taxi_type"]] = {
            "trips": num(r["trips"]), "share_pct": num(r["share_pct"])}
    months = sorted(monthly)

    recon = read_csv(csv_keys["reconciliation"])
    status_count = {}
    for r in recon:
        status_count[r["status"]] = status_count.get(r["status"], 0) + 1

    dq = read_csv(csv_keys["dq_latest"])
    worst = max(dq, key=lambda r: num(r["rejected_pct"]) or 0, default=None)

    top = ranking[0] if ranking else None
    return {
        "question": "In H1 2024, which vehicle type was used the most (by number of trips, 1 row = 1 trip)?",
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "run_id": run_id,
        "triggered_by_month": event.get("year_month"),
        "coverage": {
            "months_in_curated": months,
            "missing_months": [m for m in EXPECTED_MONTHS if m not in monthly],
            "complete_h1_2024": all(m in monthly for m in EXPECTED_MONTHS),
        },
        "answer": None if top is None else {
            "most_used_type": top["taxi_type"], "total_trips": top["total_trips"], "share_pct": top["share_pct"]},
        "ranking": ranking,
        "monthly_trips": monthly,
        "data_quality": {
            "reconciliation_status_count": status_count,
            "all_reconciled": bool(recon) and all(r["status"] == "OK" for r in recon),
            "raw_rows": sum(num(r["raw_rows"]) or 0 for r in recon),
            "curated_rows": sum(num(r["curated_rows"]) or 0 for r in recon),
            "quarantine_rows": sum(num(r["quarantine_rows"]) or 0 for r in recon),
            "max_rejected_pct": None if worst is None else {
                "year_month": worst["year_month"], "taxi_type": worst["taxi_type"],
                "rejected_pct": num(worst["rejected_pct"])},
        },
        "source_reports": f"s3://{BUCKET}/reports/{run_id}/",
    }


def handler(event, context):
    run_id = require_run_id(event)
    names = [f"{d}/{p.stem}" for d in ("result", "quality") for p in sorted((SQL_DIR / d).glob("*.sql"))]
    out = f"s3://{BUCKET}/athena-results/reports/{run_id}/"
    reports, csv_keys = [], {}
    for i in range(0, len(names), PARALLEL):
        batch = {n: start_query(render(n), output=out) for n in names[i:i + PARALLEL]}
        for path, qid in batch.items():
            name = path.split("/")[1]
            q = wait_query(qid)
            src_key = q["ResultConfiguration"]["OutputLocation"].replace(f"s3://{BUCKET}/", "", 1)
            for dest in (f"reports/{run_id}/{name}.csv", f"reports/latest/{name}.csv"):
                s3.copy_object(Bucket=BUCKET, Key=dest, CopySource={"Bucket": BUCKET, "Key": src_key})
            csv_keys[name] = f"reports/{run_id}/{name}.csv"
            reports.append(name)

    summary = build_summary(run_id, event, csv_keys)
    for key in (f"summary/{run_id}/analysis_summary.json", "summary/latest/analysis_summary.json"):
        write_json(key, summary)

    return {**event, "analysis": {"status": "OK", "reports": reports,
                                  "location": f"s3://{BUCKET}/reports/{run_id}/",
                                  "summary": f"s3://{BUCKET}/summary/{run_id}/analysis_summary.json",
                                  "most_used_type": (summary["answer"] or {}).get("most_used_type")}}
