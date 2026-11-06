-- What a restored dump is checked against: the sample table's row count, and every view and function.
SELECT 'entries rows', count(*)::text FROM entries
UNION ALL SELECT 'view ' || viewname, '' FROM pg_views WHERE schemaname = 'public'
UNION ALL SELECT 'function ' || proname, '' FROM pg_proc WHERE pronamespace = 'public'::regnamespace
ORDER BY 1;
