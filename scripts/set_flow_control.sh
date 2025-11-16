#!/bin/bash
# 流控参数设置脚本
# 动态调整ClickHouse表的流控参数

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

# 设置流控参数
# 修改test_local表的parts_to_delay_insert和parts_to_throw_insert参数
set_flow_control_params() {
    log_info "设置流控参数..."
    log_info "  parts_to_delay_insert: $PARTS_TO_DELAY_INSERT"
    log_info "  parts_to_throw_insert: $PARTS_TO_THROW_INSERT"

    if ! clickhouse-client \
        --host="$CH_HOST" \
        --port="$CH_PORT" \
        --user="$CH_USER" \
        ${CH_PASSWORD:+--password="$CH_PASSWORD"} \
        --database="$CH_DATABASE" \
        --query="
            ALTER TABLE test_local
            MODIFY SETTING
                parts_to_delay_insert = $PARTS_TO_DELAY_INSERT,
                parts_to_throw_insert = $PARTS_TO_THROW_INSERT
        " 2>&1; then
        log_error "流控参数设置失败"
        return 1
    fi

    log_info "流控参数设置完成"
    return 0
}

# 如果直接运行此脚本，执行参数设置
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set_flow_control_params
fi
