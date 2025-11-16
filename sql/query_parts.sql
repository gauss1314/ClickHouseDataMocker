-- 查询parts状态
SELECT
    table,
    partition,
    count() as parts_count,
    sum(rows) as total_rows,
    formatReadableSize(sum(bytes_on_disk)) as total_size
FROM system.parts
WHERE active AND database = currentDatabase() AND table = 'test_local'
GROUP BY table, partition
ORDER BY parts_count DESC
LIMIT 20;
