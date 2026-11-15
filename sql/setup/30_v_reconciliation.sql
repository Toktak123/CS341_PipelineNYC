-- TRACEABILITY: reconcile raw = curated + quarantine for every month / source
-- OK = every raw row is accounted for | NOT_PROCESSED = fetched but not yet processed / failed the gate
CREATE OR REPLACE VIEW {{DB}}.v_reconciliation AS
WITH raw AS (
  SELECT year_month, taxi_type, COUNT(*) AS raw_rows
  FROM {{DB}}.v_stage_all
  GROUP BY 1, 2
),
cur AS (
  SELECT year_month, taxi_type, COUNT(*) AS curated_rows
  FROM {{DB}}.trips_curated
  GROUP BY 1, 2
),
q AS (
  SELECT year_month, taxi_type, COUNT(*) AS quarantine_rows
  FROM {{DB}}.trips_quarantine
  GROUP BY 1, 2
)
SELECT
  r.year_month,
  r.taxi_type,
  r.raw_rows,
  COALESCE(c.curated_rows, 0)                                                AS curated_rows,
  COALESCE(q.quarantine_rows, 0)                                             AS quarantine_rows,
  r.raw_rows - COALESCE(c.curated_rows, 0) - COALESCE(q.quarantine_rows, 0)  AS unaccounted_rows,
  CASE
    WHEN c.curated_rows IS NULL AND q.quarantine_rows IS NULL THEN 'NOT_PROCESSED'
    WHEN r.raw_rows = COALESCE(c.curated_rows, 0) + COALESCE(q.quarantine_rows, 0) THEN 'OK'
    ELSE 'MISMATCH'
  END                                                                        AS status
FROM raw r
LEFT JOIN cur c ON r.year_month = c.year_month AND r.taxi_type = c.taxi_type
LEFT JOIN q   ON r.year_month = q.year_month AND r.taxi_type = q.taxi_type
