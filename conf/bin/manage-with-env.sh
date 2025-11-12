#!/bin/bash
# 管理命令包装器 - 自动加载.env文件
# 使用方法: ./manage-with-env.sh pgpartition --yes

# 设置环境变量
export PYTHONPATH=/code
export PATH=/usr/local/bin:/usr/bin:/bin

# 在容器中，.env文件位于 /code/.env
ENV_FILE="/code/.env"

# 如果.env文件存在，则加载它
if [ -f "$ENV_FILE" ]; then
    # 安全地加载.env文件，忽略注释和空行
    set -a
    source "$ENV_FILE"
    set +a
    echo "✅ 已加载 /code/.env 文件"
else
    echo "⚠️ 未找到 /code/.env 文件"
fi

# 执行Django管理命令
cd /code
python3 manage.py "$@"
