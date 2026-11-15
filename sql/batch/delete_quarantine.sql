-- PublishIceberg: delete this month from quarantine before rewriting
DELETE FROM {{DB}}.trips_quarantine
WHERE year_month = '{{year_month}}'
