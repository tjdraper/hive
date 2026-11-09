-- What a restored dump is checked against: the sample table's row count, and every view, routine,
-- trigger and event.
SELECT 'entries rows' AS item, COUNT(*) AS value FROM entries
UNION ALL SELECT CONCAT('view ', TABLE_NAME), '' FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE()
UNION ALL SELECT CONCAT(LOWER(ROUTINE_TYPE), ' ', ROUTINE_NAME), '' FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE()
UNION ALL SELECT CONCAT('trigger ', TRIGGER_NAME), '' FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE()
UNION ALL SELECT CONCAT('event ', EVENT_NAME), '' FROM information_schema.EVENTS WHERE EVENT_SCHEMA = DATABASE()
ORDER BY 1;
