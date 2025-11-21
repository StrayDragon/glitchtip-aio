#!/bin/bash
# Django 管理命令包装器 - 自动加载环境变量并验证连接
# 使用方法: ./manage-with-env.sh shell
#          ./manage-with-env.sh pgpartition --yes

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 设置基础环境变量
export PYTHONPATH=/code
export PATH=/usr/local/bin:/usr/bin:/bin
export DJANGO_SETTINGS_MODULE=glitchtip.settings

# 在容器中，.env文件位于 /code/.env
ENV_FILE="/code/.env"

echo -e "${YELLOW}🔧 Django 管理命令启动...${NC}"

# 如果.env文件存在，则加载它
if [ -f "$ENV_FILE" ]; then
    echo -e "${GREEN}✅ 已加载 /code/.env 文件${NC}"
    # 安全地加载.env文件，忽略注释和空行
    set -a
    source "$ENV_FILE"
    set +a

    # 验证关键环境变量
    echo -e "${YELLOW}📋 环境变量验证:${NC}"
    echo "   DATABASE_URL: ${DATABASE_URL:0:20}..."
    echo "   VALKEY_URL: ${VALKEY_URL}"
    echo "   CELERY_BROKER_URL: ${CELERY_BROKER_URL}"
    echo "   DJANGO_SETTINGS_MODULE: ${DJANGO_SETTINGS_MODULE}"
else
    echo -e "${RED}❌ 未找到 /code/.env 文件${NC}"
    echo -e "${YELLOW}⚠️  可能导致数据库连接问题${NC}"
fi

# 切换到工作目录
cd /code

# 特殊处理 shell 命令
if [ "$1" = "shell" ]; then
    echo -e "${GREEN}🚀 启动 Django shell${NC}"
    echo -e "${YELLOW}💡 提示: 可使用以下命令测试连接${NC}"
    echo "   >>> from django.db import connection"
    echo "   >>> cursor = connection.cursor()"
    echo "   >>> cursor.execute('SELECT 1')"
    echo "   >>> result = cursor.fetchone()"
    echo "   >>> print(f'Database connection: {result}')"
    echo ""
    echo -e "${YELLOW}💡 Redis/Valkey 连接测试:${NC}"
    echo "   >>> import redis"
    echo "   >>> r = redis.from_url('${VALKEY_URL:-redis://localhost:6379/0}')"
    echo "   >>> r.ping()"
    echo ""
fi

# 执行Django管理命令
echo -e "${GREEN}🔨 执行: python manage.py $*${NC}"
python3 manage.py "$@"
