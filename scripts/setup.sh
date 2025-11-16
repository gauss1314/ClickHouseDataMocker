#!/bin/bash
# 一键启动脚本
# 创建表、设置流控参数、执行数据插入测试并监控指标

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载配置
source "$PROJECT_ROOT/config/clickhouse.conf"

# 创建日志目录
mkdir -p "$PROJECT_ROOT/logs"

# 日志文件
LOG_FILE="$PROJECT_ROOT/logs/setup_$(date +%Y%m%d_%H%M%S).log"

# 日志函数（同时输出到控制台和文件）
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$1"
}

log_warn() {
    log "WARN" "$1"
}

log_error() {
    log "ERROR" "$1"
}

# 执行ClickHouse查询
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

# 执行SQL文件
execute_sql_file() {
    local sql_file="$1"
    clickhouse-client \
        --host="$CH_HOST" \
        --port="$CH_PORT" \
        --user="$CH_USER" \
        ${CH_PASSWORD:+--password="$CH_PASSWORD"} \
        --database="$CH_DATABASE" \
        --multiquery < "$sql_file"
}

# 清理测试表（可选）
cleanup_tables() {
    log_info "清理已存在的测试表..."
    execute_query "DROP TABLE IF EXISTS test_distributed" || true
    execute_query "DROP TABLE IF EXISTS test_local" || true
}

# 创建表结构
create_tables() {
    log_info "创建本地MergeTree表..."
    execute_sql_file "$PROJECT_ROOT/sql/create_local.sql"

    log_info "创建分布式表..."
    execute_sql_file "$PROJECT_ROOT/sql/create_distributed.sql"

    log_info "表结构创建完成"
}

# 主函数
main() {
    log_info "========================================="
    log_info "ClickHouse流控测试开始"
    log_info "日志文件: $LOG_FILE"
    log_info "========================================="

    # 检查依赖
    log_info "检查系统依赖..."
    command -v clickhouse-client >/dev/null 2>&1 || { log_error "clickhouse-client 未安装"; exit 1; }
    command -v python3 >/dev/null 2>&1 || { log_error "python3 未安装"; exit 1; }
    command -v bc >/dev/null 2>&1 || { log_error "bc 未安装"; exit 1; }

    # 测试连接
    log_info "测试ClickHouse连接..."
    if ! execute_query "SELECT 1" >/dev/null 2>&1; then
        log_error "无法连接到ClickHouse服务器"
        exit 1
    fi
    log_info "连接成功"

    # 清理并创建表
    if [[ "${CLEANUP:-false}" == "true" ]]; then
        cleanup_tables
    fi
    create_tables

    # 设置流控参数
    log_info "设置流控参数..."
    source "$SCRIPT_DIR/set_flow_control.sh"
    set_flow_control_params 2>&1 | tee -a "$LOG_FILE"

    # 加载插入脚本
    source "$SCRIPT_DIR/insert_data.sh"
    source "$SCRIPT_DIR/monitor_metrics.sh"

    # 开始数据插入测试
    log_info "开始数据插入测试..."
    log_info "批次大小: $BATCH_SIZE"
    log_info "插入间隔: ${INSERT_INTERVAL}秒"
    log_info "最大插入次数: $MAX_INSERT_COUNT"

    local insert_count=0
    local flow_control_triggered=false

    for ((i=1; i<=MAX_INSERT_COUNT; i++)); do
        log_info "========== 第 $i 次插入 =========="

        # 执行插入
        if insert_batch "$BATCH_SIZE" 2>&1 | tee -a "$LOG_FILE"; then
            insert_count=$((insert_count + 1))
        else
            log_warn "插入失败，可能触发了流控"
            flow_control_triggered=true
        fi

        # 查询监控指标
        local parts_count
        parts_count=$(check_flow_control_status 2>&1 | tail -1)

        # 检查是否达到流控阈值
        if [[ "$parts_count" -ge "$PARTS_TO_THROW_INSERT" ]]; then
            log_warn "已达到 parts_to_throw_insert 阈值，停止插入"
            flow_control_triggered=true
            break
        fi

        # 等待指定间隔
        if [[ $i -lt $MAX_INSERT_COUNT ]]; then
            sleep "$INSERT_INTERVAL"
        fi
    done

    # 最终报告
    log_info "========================================="
    log_info "测试完成"
    log_info "总插入次数: $insert_count"
    log_info "流控触发: $flow_control_triggered"
    log_info "========================================="

    # 输出最终监控报告
    log_info "最终监控报告:"
    full_report 2>&1 | tee -a "$LOG_FILE"

    log_info "详细日志已保存至: $LOG_FILE"
}

# 处理Ctrl+C中断
trap 'log_warn "测试被中断"; exit 130' INT

main "$@"
