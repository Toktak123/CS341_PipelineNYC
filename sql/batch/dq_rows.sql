-- Quality results for this run + month (Validate_batch uses them to decide the quality gate)
SELECT taxi_type, total_rows, rejected_rows, rejected_pct
FROM {{DB}}.dq_results
WHERE run_id = '{{run_id}}'
  AND year_month = '{{year_month}}'
