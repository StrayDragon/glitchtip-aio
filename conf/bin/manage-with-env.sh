#!/bin/bash
# Django 管理命令包装器 - 自动加载环境变量并验证连接
# 使用方法: ./manage-with-env.sh shell
#          ./manage-with-env.sh pgpartition --yes
#          ./manage-with-env.sh --quiet pgpartition --yes  # 安静模式，隐藏敏感信息

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 输出级别控制
VERBOSE=true
QUIET_MODE=false

# 解析命令行参数
for arg in "$@"; do
    case $arg in
        --quiet)
            QUIET_MODE=true
            VERBOSE=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
    esac
done

# 设置基础环境变量
export PYTHONPATH=/code
export PATH=/usr/local/bin:/usr/bin:/bin
export DJANGO_SETTINGS_MODULE=glitchtip.settings

# 支持通过环境变量覆盖 .env 文件路径，默认在容器中的 /code/.env
ENV_FILE="${ENV_FILE:-/code/.env}"

# 控制输出函数
log_info() {
    if [ "$QUIET_MODE" = false ]; then
        echo -e "$1"
    fi
}

log_error() {
    echo -e "$1" >&2
}

log_debug() {
    if [ "$VERBOSE" = true ] && [ "$QUIET_MODE" = false ]; then
        echo -e "$1"
    fi
}

log_info "${YELLOW}🔧 Django 管理命令启动...${NC}"

# 如果.env文件存在，则加载它
if [ -f "$ENV_FILE" ]; then
    log_info "${GREEN}✅ 已加载 /code/.env 文件${NC}"
    # 安全地加载.env文件，忽略注释和空行
    set -a
    source "$ENV_FILE"
    set +a

    # 验证关键环境变量 - 根据输出级别显示不同信息
    if [ "$QUIET_MODE" = false ]; then
        if [ "$VERBOSE" = true ]; then
            log_debug "${YELLOW}📋 环境变量验证 (详细模式):${NC}"
            # 在详细模式下，显示脱敏后的信息
            if [ -n "$DATABASE_URL" ]; then
                # 提取数据库类型，隐藏连接信息
                DB_TYPE=$(echo "$DATABASE_URL" | cut -d':' -f1)
                log_debug "   DATABASE_URL: ${DB_TYPE}://[HIDDEN]..."
            fi
            if [ -n "$VALKEY_URL" ]; then
                # 提取协议类型，隐藏连接信息
                REDIS_TYPE=$(echo "$VALKEY_URL" | cut -d':' -f1)
                log_debug "   VALKEY_URL: ${REDIS_TYPE}://[HIDDEN]"
            fi
            if [ -n "$CELERY_BROKER_URL" ]; then
                # 提取broker类型，隐藏连接信息
                BROKER_TYPE=$(echo "$CELERY_BROKER_URL" | cut -d'+' -f1)
                log_debug "   CELERY_BROKER_URL: ${BROKER_TYPE}+://[HIDDEN]"
            fi
            log_debug "   DJANGO_SETTINGS_MODULE: $DJANGO_SETTINGS_MODULE"
        else
            log_info "${YELLOW}📋 环境变量配置已加载${NC}"
        fi
    fi
else
    log_error "${RED}❌ 未找到 /code/.env 文件${NC}"
    log_error "${YELLOW}⚠️  可能导致数据库连接问题${NC}"
fi

# 切换到工作目录
# 在容器环境中总是使用 /code，在测试环境中使用当前目录
if [ -d "/code" ]; then
    cd /code
fi

# 特殊处理 shell 命令
if [ "$1" = "shell" ]; then
    log_info "${GREEN}🚀 启动 Django shell${NC}"
    if [ "$VERBOSE" = true ] && [ "$QUIET_MODE" = false ]; then
        log_info "${YELLOW}💡 提示: 可使用以下命令测试连接${NC}"
        log_info "   >>> from django.db import connection"
        log_info "   >>> cursor = connection.cursor()"
        log_info "   >>> cursor.execute('SELECT 1')"
        log_info "   >>> result = cursor.fetchone()"
        log_info "   >>> print(f'Database connection: {result}')"
        log_info ""
        log_info "${YELLOW}💡 Redis/Valkey 连接测试:${NC}"
        log_info "   >>> import redis"
        log_info "   >>> r = redis.from_url('[HIDDEN_REDIS_URL]')"
        log_info "   >>> r.ping()"
        log_info ""
    fi
fi

# 执行Django管理命令
if [ "$QUIET_MODE" = false ]; then
    log_info "${GREEN}🔨 执行: python manage.py $*${NC}"
else
    # 安静模式下只记录到日志
    log_debug "${GREEN}🔨 安静模式执行: python manage.py $*${NC}"
fi
python3 manage.py "$@"
