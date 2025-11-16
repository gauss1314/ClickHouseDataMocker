-- 创建本地MergeTree表
-- 按小时分区，用于流控测试

CREATE TABLE IF NOT EXISTS test_local
(
    id UInt64,
    event_time DateTime,
    user_id UInt32,
    event_type String,
    value Float64,
    status UInt8,
    description String,
    metadata String,
    created_at DateTime,
    updated_at DateTime
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDDhh(event_time)
ORDER BY (event_time, id)
SETTINGS
    parts_to_delay_insert = 150,
    parts_to_throw_insert = 300;
