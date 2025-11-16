-- 创建分布式表
-- 指向本地MergeTree表，不使用sharding_key

CREATE TABLE IF NOT EXISTS test_distributed
AS test_local
ENGINE = Distributed('default', currentDatabase(), test_local);
