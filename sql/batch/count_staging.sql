-- Verify_batch: count rows in staging for this run + month
SELECT
  (SELECT COUNT(*) FROM {{DB}}.staging_curated
    WHERE run_id = '{{run_id}}' AND year_month = '{{year_month}}')  AS curated_rows,
  (SELECT COUNT(*) FROM {{DB}}.staging_rejected
    WHERE run_id = '{{run_id}}' AND year_month = '{{year_month}}')  AS rejected_rows
