"""Lambda transform_batch (app.handler): clean + combine 4 sources -> S3 staging (not yet published)

- passing rows : median imputation per source -> staging/curated/run_id=/year_month=/
- failing rows : -> staging/rejected/run_id=/year_month=/
Uses Athena UNLOAD (processing happens in Athena; ~20M rows never load into Lambda)

output: {**input, "transform": {"status": "STAGED_WRITTEN", ...}}
"""
from nyc_common import delete_prefix, render, require_month, require_run_id, run_query, staging_prefixes


def handler(event, context):
    ym = require_month(event)
    run_id = require_run_id(event)

    # UNLOAD requires an empty prefix -> clear this run's output first (in case of retry)
    for p in staging_prefixes(run_id, ym):
        delete_prefix(p)

    run_query(render("batch/unload_curated", year_month=ym, run_id=run_id))
    run_query(render("batch/unload_rejected", year_month=ym, run_id=run_id))
    return {**event, "transform": {"status": "STAGED_WRITTEN", "staging_prefixes": staging_prefixes(run_id, ym)}}
