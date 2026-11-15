-- FinalizeIceberg: count rows published in the Iceberg tables for this month
SELECT
  (SELECT COUNT(*) FROM {{DB}}.trips_curated    WHERE year_month = '{{year_month}}') AS curated_rows,
  (SELECT COUNT(*) FROM {{DB}}.trips_quarantine WHERE year_month = '{{year_month}}') AS quarantine_rows
