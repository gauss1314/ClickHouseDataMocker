#!/bin/bash
# 数据插入脚本
# 生成随机数据并批量插入到ClickHouse

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载配置
source "$PROJECT_ROOT/config/clickhouse.conf"

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

# 生成并插入一批数据
# 参数:
#   $1 - 批次大小（默认100000）
# 返回:
#   成功返回0，失败返回1
insert_batch() {
    local batch_size=${1:-$BATCH_SIZE}
    local start_time end_time elapsed

    start_time=$(date +%s.%N)

    # 使用Python生成数据，通过管道直接插入ClickHouse
    if ! python3 "$SCRIPT_DIR/generate_data.py" "$batch_size" | \
        clickhouse-client \
            --host="$CH_HOST" \
            --port="$CH_PORT" \
            --user="$CH_USER" \
            ${CH_PASSWORD:+--password="$CH_PASSWORD"} \
            --database="$CH_DATABASE" \
            --query="INSERT INTO test_distributed FORMAT TabSeparated" 2>&1; then
        log_error "数据插入失败"
        return 1
    fi

    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc)

    log_info "已插入 $batch_size 行数据，耗时: ${elapsed}秒"
    return 0
}

# 如果直接运行此脚本，执行单次插入
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    insert_batch "${1:-$BATCH_SIZE}"
fi
