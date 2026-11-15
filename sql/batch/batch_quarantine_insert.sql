-- Quarantine_batch: record a month that failed the quality gate
INSERT INTO {{DB}}.batch_quarantine
VALUES ('{{run_id}}', '{{quarantined_at}}', '{{year_month}}', 'quality_gate_not_passed', '{{failed_checks}}')
