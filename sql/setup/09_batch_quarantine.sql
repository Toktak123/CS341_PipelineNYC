-- BATCH QUARANTINE: months that failed the quality gate as a whole (not published), with reasons
CREATE TABLE IF NOT EXISTS {{DB}}.batch_quarantine (
  run_id          string,
  quarantined_at  string,
  year_month      string,
  reason          string,
  failed_checks   string
)
LOCATION 's3://{{BUCKET}}/iceberg/batch_quarantine/'
TBLPROPERTIES (
  'table_type' = 'ICEBERG',
  'format'     = 'parquet'
)
