FROM glitchtip/glitchtip:v5.2

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PORT=8000

USER root

# 使用阿里云镜像源并一次性安装所有系统依赖
RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && apt-get install -y \
    supervisor \
    postgresql \
    postgresql-contrib \
    redis-server \
    curl \
    netcat-openbsd \
    sudo \
    neovim \
    wget \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# 安装 Python 依赖包并创建用户/目录配置
RUN pip install gunicorn psutil psycopg2-binary requests && \
    mkdir -p /data/postgres /data/redis /var/log/supervisor /code/bin /etc/postgresql && \
    groupadd -r glitchtip && \
    useradd -r -g glitchtip -s /bin/bash -d /code glitchtip && \
    chown -R glitchtip:glitchtip /code && \
    chown -R postgres:postgres /data/postgres && \
    chown -R redis:redis /data/redis && \
    echo "local all all trust" > /etc/postgresql/pg_hba.conf && \
    echo "host all all 127.0.0.1/32 trust" >> /etc/postgresql/pg_hba.conf && \
    echo "host all all ::1/128 trust" >> /etc/postgresql/pg_hba.conf

# 复制配置文件
COPY conf/bin/ /code/bin/
COPY conf/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY conf/etc/entrypoint.sh /entrypoint.sh
COPY conf/etc/crontab /etc/crontab
COPY conf/etc/pip.conf /etc/pip.conf
COPY conf/etc/environment.sh /code/etc/environment.sh

# 设置执行权限并复制二进制文件
RUN chmod +x /code/bin/*.sh /entrypoint.sh && \
    cp /code/bin/health-check /usr/local/bin/ && \
    cp /code/bin/process_monitor /usr/local/bin/ && \
    mkdir -p /etc/supervisor/conf.d/ && \
    chmod +x /usr/local/bin/* && \
    chmod +x /code/bin/*.py

# 暴露端口 - 只暴露 web 服务端口
EXPOSE 8000

# 健康检查 - 增加启动时间等待supervisor完全启动
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD /code/bin/health-check

WORKDIR /code

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
