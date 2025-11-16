-- 查询关键流控指标
SELECT
    metric,
    value,
    description
FROM system.metrics
WHERE metric IN (
    'DelayedInserts',
    'DistributedFilesToInsert',
    'InsertedRows',
    'InsertedBytes',
    'PartsActive',
    'PartsCommitted',
    'PartsInMemory',
    'PartsMutations',
    'ReplicatedChecks',
    'ReplicatedFetch'
)
ORDER BY metric;
