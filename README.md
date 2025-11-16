# ClickHouseDataMocker
Mock batch inserts to ClickHouse and watch system metrics

## 1. 编写SQL等脚步，用于创建表（使用Distributed分布式表引擎指向MergeTree表引擎，不使用sharding_key，按照小时分区，表为10列），生成随机数据用于批量插入（每次生成10万条数据插入）。

## 2. 编写脚本自动插入数据，设置ClickHouse的max_partitions_per_insert_block、parts_to_delay_insert和parts_to_throw_insert这些流控参数后，观察触发数据插入时的流控后，自动查询system.metrics表的相关指标。

## 3. 整个脚本一键式启动，启动后判断表是否创建，没有创建则创建表，然后构造数据，每隔1秒插入10万条数据，动态设置流控参数，使其1分钟内触发流控，同时查询出相关指标。
