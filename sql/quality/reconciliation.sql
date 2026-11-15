-- Traceability: raw = curated + quarantine for every month / source
SELECT * FROM {{DB}}.v_reconciliation ORDER BY year_month, taxi_type
