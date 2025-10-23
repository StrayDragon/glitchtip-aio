# Glitchtip 运维工具集

本目录包含用于管理Glitchtip AIO容器的运维脚本，特别针对K8s无状态部署环境设计。

## 脚本列表

### 核心工具

#### [`x-ops.py`](./x-ops.py) - 配置管理脚本
**功能**: 导出和导入Glitchtip的所有配置数据

**基本用法**:
```bash
# 导出配置
/code/bin/x-ops.py export -o config-backup.json

# 导入配置
/code/bin/x-ops.py import config-backup.json

# 试运行（不实际修改数据）
/code/bin/x-ops.py import config-backup.json --dry-run

# 管道操作
/code/bin/x-ops.py export | /code/bin/x-ops.py import --dry-run
```

**支持的数据**:
- 用户账户（包括加密密码）
- 组织架构和成员关系
- 项目配置和DSN密钥
- 团队设置和权限
- 告警规则和通知配置
- 环境配置
- API令牌
- 用户告警偏好

#### [`x-user-manager.py`](./x-user-manager.py) - 用户管理脚本
**功能**: 管理用户账户和组织关系

**基本用法**:
```bash
# 创建用户
/code/bin/x-user-manager.py create "用户名" "user@example.com" "password"

# 列出用户
/code/bin/x-user-manager.py list

# 创建组织
/code/bin/x-user-manager.py create-org "组织名称"

# 添加用户到组织
/code/bin/x-user-manager.py add-to-org "user@example.com" "组织名称"

# 重置密码
/code/bin/x-user-manager.py reset-password "user@example.com"
```

## K8s集成示例

### 部署前备份
```yaml
# k8s pre-deploy hook
apiVersion: batch/v1
kind: Job
metadata:
  name: glitchtip-backup
spec:
  template:
    spec:
      containers:
      - name: backup
        image: your-glitchtip-image
        command: ["/code/bin/x-ops.py"]
        args: ["export", "-o", "/data/backups/glitchtip-config-$(date +%Y%m%d-%H%M%S).json"]
        volumeMounts:
        - name: backup-storage
          mountPath: /data/backups
      volumes:
        - name: backup-storage
          persistentVolumeClaim:
            claimName: glitchtip-backup-pvc
      restartPolicy: OnFailure
```

### 启动时恢复
```yaml
# init container
initContainers:
- name: restore-config
  image: your-glitchtip-image
  command: ["/bin/sh", "-c"]
  args:
  - |
    LATEST_BACKUP=$(find /data/backups -name "glitchtip-config-*.json" | sort | tail -1)
    if [ -n "$LATEST_BACKUP" ]; then
      echo "恢复配置: $LATEST_BACKUP"
      /code/bin/x-ops.py import "$LATEST_BACKUP"
    fi
  volumeMounts:
  - name: backup-storage
    mountPath: /data/backups
```

### 定期备份CronJob
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: glitchtip-daily-backup
spec:
  schedule: "0 2 * * *"  # 每天凌晨2点
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: your-glitchtip-image
            command: ["/code/bin/x-ops.py"]
            args: ["export", "-o", "/data/backups/glitchtip-config-$(date +%Y%m%d-%H%M%S).json"]
            volumeMounts:
            - name: backup-storage
              mountPath: /data/backups
          volumes:
            - name: backup-storage
              persistentVolumeClaim:
                claimName: glitchtip-backup-pvc
          restartPolicy: OnFailure
```

## 数据安全

### 备份文件包含的信息
- ✅ **包含**: 所有配置数据、用户密码（加密格式）
- ❌ **不包含**: 实际事件数据、错误报告、性能指标

### 密码处理
- 密码以Django加密格式存储
- 导入时保持原密码不变
- 可通过x-user-manager.py重置密码

### DSN处理
- DSN根据当前`GLITCHTIP_URL`自动重新生成
- 环境变更时DSN自动适配

## 故障排除

### 常见问题

1. **权限问题**
   ```bash
   chmod +x /code/bin/*.sh
   chmod +x /code/bin/*.py
   ```

2. **数据库连接失败**
   ```bash
   # 检查数据库状态
   docker exec glitchtip-container pg_isready

   # 检查配置
   cat /code/.env | grep DATABASE
   ```

3. **备份失败**
   ```bash
   # 试运行导入操作
   /code/bin/x-ops.py import backup.json --dry-run

   # 检查磁盘空间
   df -h /data
   ```

### 调试技巧

1. **试运行模式**
   ```bash
   /code/bin/x-ops.py import backup.json --dry-run
   ```

2. **详细日志**
   ```bash
   /code/bin/x-ops.py export -o backup.json 2>&1 | tee export.log
   ```

3. **JSON验证**
   ```bash
   cat backup.json | python3 -m json.tool > /dev/null && echo "JSON有效"
   ```

## 最佳实践

1. **定期备份**: 设置定时任务执行 `/code/bin/x-ops.py export`
2. **异地存储**: 将备份文件推送到云存储
3. **定期测试**: 使用 `--dry-run` 参数验证导入功能
4. **监控告警**: 设置备份失败的告警
5. **版本管理**: 保留多个历史版本
6. **权限控制**: 限制备份文件的访问权限

## 相关文档

- [详细配置备份指南](../../docs/CONFIG_BACKUP.md)
- [Glitchtip官方文档](https://glitchtip.com/docs)

## 支持

如有问题，请：
1. 查看相关文档
2. 使用 `--dry-run` 参数诊断导入问题
3. 检查日志文件
4. 提交issue到项目仓库