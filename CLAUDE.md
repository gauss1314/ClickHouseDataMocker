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
│   ├── setup.sh              # 一键启动脚本（主入口）
│   ├── insert_data.sh        # 数据插入脚本
│   ├── monitor_metrics.sh    # 监控指标脚本
│   ├── set_flow_control.sh   # 流控参数设置脚本
│   └── generate_data.py      # 随机数据生成（Python辅助）
├── sql/                      # SQL文件
│   ├── create_local.sql      # 本地MergeTree表DDL
│   ├── create_distributed.sql  # 分布式表DDL
│   ├── query_metrics.sql     # 指标查询SQL
│   └── query_parts.sql       # Parts状态查询SQL
├── config/                   # 配置文件
│   └── clickhouse.conf       # ClickHouse连接配置（Shell格式）
├── logs/                     # 日志目录
├── README.md                 # 项目说明
└── CLAUDE.md                 # AI助手指南
```

## 技术栈

### 首选技术选型
- **脚本语言**: Bash（优先）
- **ClickHouse客户端**: clickhouse-client (CLI)
- **配置管理**: Shell变量文件（source方式加载）
- **日志**: Shell重定向 + tee命令
- **数据生成**: Python（当Bash实现复杂时使用）

### 辅助工具
- **Python 3.8+**: 仅用于复杂数据生成逻辑
- **clickhouse-client**: ClickHouse官方命令行客户端
- **常用Shell工具**: awk, sed, date, shuf等

### 为什么选择Bash + clickhouse-client
1. **直接性**: clickhouse-client是ClickHouse原生客户端，功能完整
2. **轻量级**: 无需安装额外Python依赖
3. **可移植性**: 大多数Linux系统自带Bash
4. **调试便利**: 可直接复用SQL语句进行调试
5. **系统集成**: 易于与cron、systemd等系统工具集成

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

### 随机数据生成（Python辅助脚本）

由于生成大量随机数据在Bash中实现较为复杂，使用Python辅助：

```python
#!/usr/bin/env python3
# scripts/generate_data.py
import random
import string
from datetime import datetime, timedelta

def generate_batch(batch_size: int = 100000) -> None:
    """生成一批随机数据，输出为CSV格式到stdout"""
    base_time = datetime.now()
    event_types = ['click', 'view', 'purchase', 'login']

    for _ in range(batch_size):
        id_val = random.randint(1, 10**18)
        event_time = base_time - timedelta(hours=random.randint(0, 23))
        user_id = random.randint(1, 1000000)
        event_type = random.choice(event_types)
        value = round(random.uniform(0, 10000), 2)
        status = random.randint(0, 255)
        description = ''.join(random.choices(string.ascii_letters, k=50))
        metadata = '{}'
        created_at = base_time.strftime('%Y-%m-%d %H:%M:%S')
        updated_at = created_at

        print(f"{id_val}\t{event_time.strftime('%Y-%m-%d %H:%M:%S')}\t{user_id}\t{event_type}\t{value}\t{status}\t{description}\t{metadata}\t{created_at}\t{updated_at}")

if __name__ == '__main__':
    import sys
    batch_size = int(sys.argv[1]) if len(sys.argv) > 1 else 100000
    generate_batch(batch_size)
```

### 数据插入脚本（Bash）

```bash
#!/bin/bash
# scripts/insert_data.sh
set -e

# 加载配置
source "$(dirname "$0")/../config/clickhouse.conf"

# 生成并插入数据
insert_batch() {
    local batch_size=${1:-100000}
    local start_time=$(date +%s.%N)

    # 使用Python生成数据，通过管道直接插入ClickHouse
    python3 "$(dirname "$0")/generate_data.py" "$batch_size" | \
        clickhouse-client \
            --host="$CH_HOST" \
            --port="$CH_PORT" \
            --user="$CH_USER" \
            --password="$CH_PASSWORD" \
            --database="$CH_DATABASE" \
            --query="INSERT INTO test_distributed FORMAT TabSeparated"

    local end_time=$(date +%s.%N)
    local elapsed=$(echo "$end_time - $start_time" | bc)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 已插入 $batch_size 行数据，耗时: ${elapsed}秒"
}

# 导出函数供其他脚本使用
export -f insert_batch
```

### 流控参数配置（Bash）

```bash
#!/bin/bash
# scripts/set_flow_control.sh
set -e

# 加载配置
source "$(dirname "$0")/../config/clickhouse.conf"

# 流控参数默认值
PARTS_TO_DELAY_INSERT=${PARTS_TO_DELAY_INSERT:-50}
PARTS_TO_THROW_INSERT=${PARTS_TO_THROW_INSERT:-100}
MAX_PARTITIONS_PER_INSERT_BLOCK=${MAX_PARTITIONS_PER_INSERT_BLOCK:-100}

set_flow_control_params() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 设置流控参数..."
    echo "  parts_to_delay_insert: $PARTS_TO_DELAY_INSERT"
    echo "  parts_to_throw_insert: $PARTS_TO_THROW_INSERT"

    clickhouse-client \
        --host="$CH_HOST" \
        --port="$CH_PORT" \
        --user="$CH_USER" \
        --password="$CH_PASSWORD" \
        --database="$CH_DATABASE" \
        --query="
            ALTER TABLE test_local
            MODIFY SETTING
                parts_to_delay_insert = $PARTS_TO_DELAY_INSERT,
                parts_to_throw_insert = $PARTS_TO_THROW_INSERT
        "
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 流控参数设置完成"
}

# 导出函数
export -f set_flow_control_params
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

### Bash规范
- 使用 `set -e` 遇错即停
- 使用 `set -u` 禁止未定义变量
- 使用 `set -o pipefail` 管道错误传播
- 函数添加注释说明
- 使用 `local` 声明局部变量
- 使用 `$()` 而非反引号进行命令替换
- 引用所有变量以防止词分割

```bash
#!/bin/bash
# scripts/example.sh - 示例脚本
set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/clickhouse.conf"

# 执行ClickHouse查询
# 参数:
#   $1 - SQL查询语句
# 返回:
#   查询结果输出到stdout
execute_query() {
    local query="$1"
    local result

    if ! result=$(clickhouse-client \
        --host="$CH_HOST" \
        --port="$CH_PORT" \
        --user="$CH_USER" \
        --password="$CH_PASSWORD" \
        --database="$CH_DATABASE" \
        --query="$query" 2>&1); then
        echo "[ERROR] 查询执行失败: $result" >&2
        return 1
    fi

    echo "$result"
}

# 记录日志
# 参数:
#   $1 - 日志级别 (INFO, WARN, ERROR)
#   $2 - 日志消息
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# 主函数
main() {
    log "INFO" "脚本开始执行"
    # 主逻辑
    log "INFO" "脚本执行完成"
}

main "$@"
```

### Python规范（仅用于数据生成）
- 遵循PEP 8编码风格
- 保持脚本简洁，仅负责数据生成
- 输出到stdout，便于管道传输
- 使用类型注解提高可读性

### 命名约定
- **Bash脚本**: snake_case.sh (如 `insert_data.sh`)
- **Python脚本**: snake_case.py (如 `generate_data.py`)
- **SQL文件**: snake_case.sql (如 `create_local.sql`)
- **配置文件**: snake_case.conf (如 `clickhouse.conf`)
- **Shell变量**: SCREAMING_SNAKE_CASE (如 `CH_HOST`, `BATCH_SIZE`)
- **Shell函数**: snake_case (如 `insert_batch`, `execute_query`)

### SQL规范
- 关键字使用大写
- 表名和列名使用小写下划线
- 添加注释说明复杂逻辑
- SQL文件保存在 `sql/` 目录下，便于复用和调试

## 开发工作流程

### 环境准备
```bash
# 克隆项目
git clone <repository-url>
cd ClickHouseDataMocker

# 检查系统依赖
which clickhouse-client || echo "请安装 clickhouse-client"
which python3 || echo "请安装 Python 3.8+"
which bc || echo "请安装 bc (用于浮点计算)"

# 配置ClickHouse连接
cp config/clickhouse.conf.example config/clickhouse.conf
# 编辑配置文件填入实际连接信息
vim config/clickhouse.conf

# 创建日志目录
mkdir -p logs

# 设置脚本执行权限
chmod +x scripts/*.sh
```

### 一键启动流程
```bash
#!/bin/bash
# scripts/setup.sh - 一键启动脚本
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/../config/clickhouse.conf"

LOG_FILE="$PROJECT_ROOT/logs/setup_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "1. 创建表结构..."
clickhouse-client --host="$CH_HOST" --port="$CH_PORT" \
    --user="$CH_USER" --password="$CH_PASSWORD" \
    --database="$CH_DATABASE" \
    --multiquery < "$PROJECT_ROOT/sql/create_local.sql"

clickhouse-client --host="$CH_HOST" --port="$CH_PORT" \
    --user="$CH_USER" --password="$CH_PASSWORD" \
    --database="$CH_DATABASE" \
    --multiquery < "$PROJECT_ROOT/sql/create_distributed.sql"

log "2. 设置流控参数..."
source "$SCRIPT_DIR/set_flow_control.sh"
set_flow_control_params

log "3. 开始数据插入测试..."
source "$SCRIPT_DIR/insert_data.sh"
for i in {1..60}; do
    insert_batch 100000

    # 查询监控指标
    source "$SCRIPT_DIR/monitor_metrics.sh"
    query_metrics

    sleep 1
done

log "4. 测试完成，查看日志: $LOG_FILE"
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
- 使用管道传输数据，避免临时文件
- 合理设置batch_size（默认10万条）
- 使用 `--max_insert_block_size` 控制内存使用
- Python生成数据直接通过管道传递给clickhouse-client

### 流控触发策略
- 设置较低的`parts_to_delay_insert`值（如50）
- 按小时分区会快速产生多个parts
- 每秒插入会持续增加parts数量
- 预期1分钟内（60次插入）触发流控

### 错误处理
- 使用 `set -e` 和 `set -o pipefail` 捕获错误
- 检查clickhouse-client返回码
- 记录详细的错误日志到文件
- 区分delay和throw两种流控状态

### 日志记录（Bash实现）
```bash
#!/bin/bash
# 日志记录示例

LOG_DIR="logs"
LOG_FILE="$LOG_DIR/insertion_$(date +%Y%m%d).log"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# 使用示例
log_info "已插入 $row_count 行数据"
log_warn "检测到流控延迟: $metric_value"
log_error "流控异常触发: $error_message"

# 日志轮转（可选）
# 使用logrotate或手动实现
find "$LOG_DIR" -name "*.log" -mtime +7 -delete
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

### 系统依赖（必需）
- **Bash 4.0+**: 脚本执行环境
- **clickhouse-client**: ClickHouse官方命令行客户端
- **Python 3.8+**: 仅用于数据生成脚本
- **bc**: 用于浮点数计算（计算耗时等）
- **ClickHouse Server 23.0+**: 目标数据库服务器

### 安装系统依赖

**Ubuntu/Debian:**
```bash
# 安装clickhouse-client
sudo apt-get install -y apt-transport-https ca-certificates dirmngr
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 8919F6BD2B48D754
echo "deb https://packages.clickhouse.com/deb stable main" | sudo tee /etc/apt/sources.list.d/clickhouse.list
sudo apt-get update
sudo apt-get install -y clickhouse-client

# 安装其他依赖
sudo apt-get install -y python3 bc
```

**CentOS/RHEL:**
```bash
# 安装clickhouse-client
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://packages.clickhouse.com/rpm/clickhouse.repo
sudo yum install -y clickhouse-client

# 安装其他依赖
sudo yum install -y python3 bc
```

**macOS:**
```bash
brew install clickhouse python3
```

### Python依赖
无需额外Python包，仅使用标准库：
- `random`: 随机数生成
- `string`: 字符串操作
- `datetime`: 时间处理
- `sys`: 命令行参数

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
