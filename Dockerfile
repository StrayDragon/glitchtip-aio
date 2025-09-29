FROM glitchtip/glitchtip:v5.1

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PORT=8000

USER root

# 使用阿里云镜像源
RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources

# 安装基础包
RUN apt-get update && apt-get install -y \
    supervisor \
    postgresql \
    postgresql-contrib \
    redis-server \
    curl \
    netcat-openbsd \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# 安装 Gunicorn
RUN pip install gunicorn

# 创建必要的目录
RUN mkdir -p /data/postgres /data/redis /var/log/supervisor /code/bin

# 创建专用用户和组
RUN groupadd -r glitchtip && \
    useradd -r -g glitchtip -s /bin/bash -d /code glitchtip

# 设置目录权限
RUN chown -R glitchtip:glitchtip /code && \
    chown -R postgres:postgres /data/postgres && \
    chown -R redis:redis /data/redis

# 配置PostgreSQL - 只允许本地访问
RUN mkdir -p /etc/postgresql && \
    chown -R postgres:postgres /data/postgres && \
    echo "host all all 127.0.0.1/32 scram-sha-256" >> /etc/postgresql/pg_hba.conf && \
    echo "host all all ::1/128 scram-sha-256" >> /etc/postgresql/pg_hba.conf

# 复制配置文件
COPY conf/bin/ /code/bin/
COPY conf/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY conf/etc/entrypoint.sh /entrypoint.sh
COPY conf/etc/pip.conf /etc/pip.conf

# 设置执行权限并复制二进制文件
RUN chmod +x /code/bin/*.sh /entrypoint.sh && \
    cp /code/bin/health-check /usr/local/bin/ && \
    cp /code/bin/process_monitor /usr/local/bin/ && \
    chmod +x /usr/local/bin/*

# 暴露端口 - 只暴露 web 服务端口
EXPOSE 8000

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD /code/bin/health-check

WORKDIR /code

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
