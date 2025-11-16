# CLAUDE.md - ClickHouseDataMocker

本文档为AI助手提供ClickHouseDataMocker项目的核心信息，包含项目背景、编码规范和开发工作流程。

## 项目概述

ClickHouseDataMocker是一个用于模拟ClickHouse批量数据插入并监控系统指标的工具。项目主要目标：

- 创建使用Distributed分布式表引擎指向MergeTree表引擎的表结构
- 生成随机数据用于批量插入（每次10万条）
- 测试和观察ClickHouse流控参数的行为
- 自动查询system.metrics表监控相关指标
- 提供一键式启动脚本

## 核心功能需求

### 1. 表结构创建
- 使用Distributed分布式表引擎指向MergeTree表引擎
- 不使用sharding_key
- 按小时分区
- 表包含10列

### 2. 数据插入与流控测试
- 每次生成10万条随机数据进行批量插入
- 每隔1秒执行一次插入
- 动态设置流控参数：
  - `max_partitions_per_insert_block`
  - `parts_to_delay_insert`
  - `parts_to_throw_insert`
- 在1分钟内触发流控机制

### 3. 监控指标查询
- 自动查询system.metrics表
- 观察触发流控时的相关指标变化

## 建议项目结构

```
ClickHouseDataMocker/
├── scripts/                  # 脚本文件
│   ├── setup.sh              # 一键启动脚本
│   ├── create_tables.sql     # 建表SQL
│   └── insert_data.sh        # 数据插入脚本
├── src/                      # 源代码
│   ├── generator/            # 数据生成器
│   │   └── random_data.py    # 随机数据生成
│   ├── monitor/              # 监控模块
│   │   └── metrics.py        # 指标查询
│   ├── config/               # 配置管理
│   │   └── flow_control.py   # 流控参数配置
│   └── main.py               # 主入口
├── sql/                      # SQL文件
│   ├── create_distributed.sql  # 分布式表DDL
│   ├── create_local.sql      # 本地MergeTree表DDL
│   └── query_metrics.sql     # 指标查询SQL
├── config/                   # 配置文件
│   └── clickhouse.yaml       # ClickHouse连接配置
├── logs/                     # 日志目录
├── tests/                    # 测试文件
├── requirements.txt          # Python依赖
├── README.md                 # 项目说明
└── CLAUDE.md                 # AI助手指南
```

## 技术栈

### 推荐技术选型
- **脚本语言**: Python 3.8+ 或 Bash
- **ClickHouse客户端**: clickhouse-driver (Python) 或 clickhouse-client (CLI)
- **配置管理**: YAML 或 环境变量
- **日志**: Python logging 模块
- **测试**: pytest

### 替代方案
- **Node.js**: 使用 @clickhouse/client
- **Go**: 使用 clickhouse-go
- **Shell脚本**: 纯Bash实现

## 关键实现细节

### 表结构设计

```sql
-- 本地MergeTree表
CREATE TABLE IF NOT EXISTS test_local ON CLUSTER '{cluster}'
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
PARTITION BY toYYYYMMDDhh(event_time)  -- 按小时分区
ORDER BY (event_time, id);

-- 分布式表（不使用sharding_key）
CREATE TABLE IF NOT EXISTS test_distributed ON CLUSTER '{cluster}'
AS test_local
ENGINE = Distributed('{cluster}', currentDatabase(), test_local);
```

### 随机数据生成

```python
import random
import string
from datetime import datetime, timedelta

def generate_batch(batch_size: int = 100000) -> list:
    """生成一批随机数据"""
    data = []
    base_time = datetime.now()

    for i in range(batch_size):
        row = (
            random.randint(1, 10**18),  # id
            base_time - timedelta(hours=random.randint(0, 23)),  # event_time
            random.randint(1, 1000000),  # user_id
            random.choice(['click', 'view', 'purchase', 'login']),  # event_type
            random.uniform(0, 10000),  # value
            random.randint(0, 255),  # status
            ''.join(random.choices(string.ascii_letters, k=50)),  # description
            '{}',  # metadata
            base_time,  # created_at
            base_time,  # updated_at
        )
        data.append(row)

    return data
```

### 流控参数配置

```python
# 流控参数说明
FLOW_CONTROL_SETTINGS = {
    # 单次插入允许的最大分区数
    'max_partitions_per_insert_block': 100,

    # 当parts数量超过此值时，插入开始延迟
    'parts_to_delay_insert': 150,

    # 当parts数量超过此值时，插入抛出异常
    'parts_to_throw_insert': 300,
}

def set_flow_control_params(client, settings: dict):
    """动态设置流控参数以在1分钟内触发流控"""
    # 设置较小的值以快速触发流控
    client.execute(f"""
        ALTER TABLE test_local
        MODIFY SETTING
            parts_to_delay_insert = {settings['parts_to_delay_insert']},
            parts_to_throw_insert = {settings['parts_to_throw_insert']}
    """)
```

### 监控指标查询

```sql
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
    'MergeTreeAllRangesAnnouncementsSent',
    'MergeTreeDataSelectParts',
    'PartsActive',
    'PartsCommitted',
    'PartsInMemory',
    'PartsMutations'
)
ORDER BY metric;

-- 查询parts状态
SELECT
    table,
    partition,
    count() as parts_count,
    sum(rows) as total_rows,
    sum(bytes_on_disk) as total_bytes
FROM system.parts
WHERE active AND database = currentDatabase()
GROUP BY table, partition
ORDER BY parts_count DESC;
```

## 编码规范

### Python规范
- 遵循PEP 8编码风格
- 使用类型注解
- 函数添加docstring说明
- 异常处理要具体明确

```python
def insert_batch(
    client: Client,
    table_name: str,
    data: list[tuple],
    settings: dict | None = None
) -> int:
    """
    批量插入数据到ClickHouse

    Args:
        client: ClickHouse客户端连接
        table_name: 目标表名
        data: 待插入的数据列表
        settings: 可选的查询设置

    Returns:
        插入的行数

    Raises:
        ClickHouseException: 当插入失败或触发流控时
    """
    try:
        result = client.execute(
            f'INSERT INTO {table_name} VALUES',
            data,
            settings=settings
        )
        return len(data)
    except Exception as e:
        logger.error(f"插入失败: {e}")
        raise
```

### 命名约定
- **文件**: snake_case (如 `data_generator.py`)
- **类**: PascalCase (如 `DataGenerator`)
- **函数/方法**: snake_case (如 `generate_batch`)
- **常量**: SCREAMING_SNAKE_CASE (如 `MAX_BATCH_SIZE`)
- **变量**: snake_case (如 `batch_size`)

### SQL规范
- 关键字使用大写
- 表名和列名使用小写下划线
- 添加注释说明复杂逻辑
- 使用参数化查询防止SQL注入

## 开发工作流程

### 环境准备
```bash
# 克隆项目
git clone <repository-url>
cd ClickHouseDataMocker

# 创建虚拟环境
python -m venv venv
source venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 配置ClickHouse连接
cp config/clickhouse.yaml.example config/clickhouse.yaml
# 编辑配置文件填入实际连接信息
```

### 一键启动流程
```bash
#!/bin/bash
# setup.sh - 一键启动脚本

set -e

echo "1. 检查表是否存在..."
# 检查并创建表

echo "2. 开始数据插入测试..."
# 每秒插入10万条数据

echo "3. 动态调整流控参数..."
# 设置参数使其在1分钟内触发流控

echo "4. 监控系统指标..."
# 查询并记录metrics
```

### Git工作流程
1. 从`main`分支创建功能分支
2. 使用约定式提交：
   - `feat:` 新功能
   - `fix:` 错误修复
   - `docs:` 文档更新
   - `test:` 测试相关
   - `refactor:` 代码重构
   - `chore:` 维护任务
3. 提交信息使用中文或英文，保持一致性
4. PR保持聚焦，规模适中

## 关键实现考量

### 性能优化
- 使用批量插入而非单条插入
- 合理设置batch_size（默认10万条）
- 使用连接池管理数据库连接
- 异步IO处理监控查询

### 流控触发策略
- 设置较低的`parts_to_delay_insert`值（如50）
- 按小时分区会快速产生多个parts
- 每秒插入会持续增加parts数量
- 预期1分钟内（60次插入）触发流控

### 错误处理
- 捕获流控触发的异常
- 记录详细的错误日志
- 区分delay和throw两种流控状态
- 优雅处理连接中断

### 日志记录
```python
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/insertion.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

# 记录关键事件
logger.info(f"已插入 {row_count} 行数据")
logger.warning(f"检测到流控延迟: {metric_value}")
logger.error(f"流控异常触发: {error_message}")
```

## 安全考量

- 不要在代码中硬编码数据库密码
- 使用环境变量或安全的配置文件
- 限制数据库用户权限（只需INSERT和SELECT）
- 测试完成后清理测试数据
- 不要在生产环境运行此工具

## 常见问题与解决

1. **连接超时**: 检查ClickHouse服务状态和网络配置
2. **内存不足**: 减小batch_size或增加系统内存
3. **流控未触发**: 检查分区策略是否正确，确保parts数量增长
4. **权限不足**: 确保用户有ALTER TABLE权限来修改settings
5. **分区过多**: 调整`max_partitions_per_insert_block`参数

## 依赖说明

### Python依赖 (requirements.txt)
```
clickhouse-driver>=0.2.6
PyYAML>=6.0
schedule>=1.2.0
```

### 系统依赖
- Python 3.8+
- ClickHouse Server 23.0+
- clickhouse-client (可选，用于CLI操作)

## 扩展方向

- 支持多种表引擎测试（ReplicatedMergeTree等）
- 可视化监控dashboard
- 自动生成测试报告
- 支持分布式集群测试
- 配置参数热加载
- 压力测试场景定制

## 维护者须知

使用此项目时需确认：
1. ClickHouse集群配置是否正确
2. 测试环境与生产环境隔离
3. 磁盘空间是否充足
4. 是否有备份恢复计划

---

*最后更新: 2025-11-16*
*项目状态: 初始开发*
