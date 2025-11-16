#!/bin/bash
# 监控指标查询脚本
# 查询ClickHouse系统指标和parts状态

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载配置
source "$PROJECT_ROOT/config/clickhouse.conf"

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

# 执行ClickHouse查询
# 参数:
#   $1 - SQL查询语句
execute_query() {
    local query="$1"
    clickhouse-client \
        --host="$CH_HOST" \
        --port="$CH_PORT" \
        --user="$CH_USER" \
        ${CH_PASSWORD:+--password="$CH_PASSWORD"} \
        --database="$CH_DATABASE" \
        --query="$query"
}

# 查询系统指标
query_metrics() {
    log_info "查询系统指标..."

    local sql_file="$PROJECT_ROOT/sql/query_metrics.sql"
    if [[ -f "$sql_file" ]]; then
        execute_query "$(cat "$sql_file")"
    else
        execute_query "
            SELECT
                metric,
                value,
                description
            FROM system.metrics
            WHERE metric IN (
                'DelayedInserts',
                'DistributedFilesToInsert',
                'PartsActive',
                'PartsCommitted'
            )
            ORDER BY metric
        "
    fi
}

# 查询parts状态
query_parts() {
    log_info "查询Parts状态..."

    local sql_file="$PROJECT_ROOT/sql/query_parts.sql"
    if [[ -f "$sql_file" ]]; then
        execute_query "$(cat "$sql_file")"
    else
        execute_query "
            SELECT
                table,
                partition,
                count() as parts_count,
                sum(rows) as total_rows
            FROM system.parts
            WHERE active AND database = currentDatabase() AND table = 'test_local'
            GROUP BY table, partition
            ORDER BY parts_count DESC
            LIMIT 10
        "
    fi
}

# 检查流控状态
check_flow_control_status() {
    log_info "检查流控状态..."

    local delayed_inserts
    delayed_inserts=$(execute_query "SELECT value FROM system.metrics WHERE metric = 'DelayedInserts'")

    if [[ "$delayed_inserts" -gt 0 ]]; then
        log_warn "检测到流控延迟! DelayedInserts = $delayed_inserts"
    fi

    local total_parts
    total_parts=$(execute_query "SELECT count() FROM system.parts WHERE active AND database = currentDatabase() AND table = 'test_local'")

    log_info "当前活跃parts数量: $total_parts"

    if [[ "$total_parts" -ge "$PARTS_TO_THROW_INSERT" ]]; then
        log_warn "Parts数量已达到或超过 parts_to_throw_insert ($PARTS_TO_THROW_INSERT)，插入将被拒绝!"
    elif [[ "$total_parts" -ge "$PARTS_TO_DELAY_INSERT" ]]; then
        log_warn "Parts数量已达到或超过 parts_to_delay_insert ($PARTS_TO_DELAY_INSERT)，插入将被延迟!"
    fi

    echo "$total_parts"
}

# 完整监控报告
full_report() {
    echo "========================================="
    echo "ClickHouse 流控监控报告"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="
    echo ""
    query_metrics
    echo ""
    query_parts
    echo ""
    check_flow_control_status
    echo "========================================="
}

# 如果直接运行此脚本，生成完整报告
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    full_report
fi
