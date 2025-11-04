#!/usr/bin/env python3
"""
定时强制重启脚本 - 每6小时执行一次
无条件重启web和celery服务，支持飞书webhook通知
Python 3.11+ 完全优化版本

Author: Claude Code
Created: 2025-10-22
Updated: 2025-11-04 - Python 3.11+ 完全适配
"""

from __future__ import annotations

import os
import sys
import json
import time
import subprocess
import logging
import signal
import psutil
import requests
import psycopg2
import redis
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum, auto
from pathlib import Path
from typing import Any, Never
from urllib.parse import urlparse


# 获取脚本所在目录的绝对路径 (Python 3.11+ 使用 pathlib)
SCRIPT_DIR = Path(__file__).parent.parent.resolve()


class ServiceStatus(Enum):
    """服务状态枚举"""
    HEALTHY = auto()
    UNHEALTHY = auto()
    UNKNOWN = auto()


class RestartMode(Enum):
    """重启模式枚举"""
    FORCED = auto()      # 强制重启
    CONDITIONAL = auto()  # 条件重启


def load_environment_from_file() -> None:
    """从.env文件加载环境变量（仅在cron环境中需要）"""
    env_file = SCRIPT_DIR / ".env"

    if env_file.exists():
        with env_file.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    # 只设置当前环境中不存在的变量
                    if not os.getenv(key):
                        os.environ[key] = value


# 在脚本开始时加载环境变量（如果需要）
load_environment_from_file()


@dataclass
class HealthCheckResult:
    """健康检查结果"""
    service: str
    status: ServiceStatus
    message: str
    duration: float
    details: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式"""
        return {
            "service": self.service,
            "status": self.status.name,
            "message": self.message,
            "duration": self.duration,
            "details": self.details,
        }


@dataclass
class SystemInfo:
    """系统信息"""
    memory_usage: float  # 百分比
    disk_usage: float  # 百分比
    cpu_usage: float  # 百分比
    load_avg: list[float]
    network_connections: int
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式"""
        return {
            "memory_usage": self.memory_usage,
            "disk_usage": self.disk_usage,
            "cpu_usage": self.cpu_usage,
            "load_avg": self.load_avg,
            "network_connections": self.network_connections,
            "timestamp": self.timestamp.isoformat(),
        }


@dataclass
class RestartInfo:
    """重启信息"""
    service: str
    old_pid: int | None
    new_pid: int | None
    restart_time: float
    success: bool
    message: str
    error_details: str | None = None

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式"""
        return {
            "service": self.service,
            "old_pid": self.old_pid,
            "new_pid": self.new_pid,
            "restart_time": self.restart_time,
            "success": self.success,
            "message": self.message,
            "error_details": self.error_details,
        }


@dataclass
class ExecutionReport:
    """执行报告"""
    timestamp: str
    duration: float
    mode: RestartMode
    pre_checks: list[HealthCheckResult]
    post_checks: list[HealthCheckResult]
    system_info: SystemInfo
    restart_actions: list[RestartInfo]
    success: bool
    message: str

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式"""
        return {
            "timestamp": self.timestamp,
            "duration": self.duration,
            "mode": self.mode.name,
            "pre_checks": [check.to_dict() for check in self.pre_checks],
            "post_checks": [check.to_dict() for check in self.post_checks],
            "system_info": self.system_info.to_dict(),
            "restart_actions": [action.to_dict() for action in self.restart_actions],
            "success": self.success,
            "message": self.message,
        }


@contextmanager
def timeout_context(seconds: float):
    """超时上下文管理器 (Python 3.11+ 风格)"""
    def timeout_handler(signum: int, frame) -> Never:  # type: ignore[no-any-return]
        raise TimeoutError(f"Operation timed out after {seconds} seconds")

    old_handler = signal.signal(signal.SIGALRM, timeout_handler)
    try:
        _ = signal.alarm(int(seconds))
        yield
    finally:
        _ = signal.alarm(0)
        _ = signal.signal(signal.SIGALRM, old_handler)


class ScheduledRestarter:
    """定时强制重启器"""

    def __init__(self, mode: RestartMode = RestartMode.FORCED) -> None:
        self.start_time: float = time.time()
        self.mode: RestartMode = mode
        self.webhook_url: str | None = os.getenv("FEISHU_GROUP_DEVOPS_ROBOT_WEBHOOK_URL")
        self.db_password: str = os.getenv("DB_PASSWORD", "postgres")
        self.log_messages: list[str] = []
        self.service_domain: str = os.environ.get("GLITCHTIP_DOMAIN", "<unknown_domain>")
        self.logger: logging.Logger = logging.getLogger(__name__)
        self.setup_logging()

    def setup_logging(self) -> None:
        """设置日志"""
        # 确保日志目录存在
        log_dir = Path("/var/log/supervisor")
        log_dir.mkdir(parents=True, exist_ok=True)

        # 使用更现代的日志格式
        log_format = "[%(asctime)s] %(levelname)-8s SCHEDULED-RESTART: %(message)s"
        date_format = "%Y-%m-%d %H:%M:%S"

        logging.basicConfig(
            level=logging.INFO,
            format=log_format,
            datefmt=date_format,
            handlers=[
                logging.FileHandler(log_dir / "scheduled-restart.log", encoding="utf-8"),
                logging.StreamHandler(sys.stdout),
            ],
        )

    def log(self, message: str, level: str = "info") -> None:
        """记录日志"""
        log_method = getattr(self.logger, level.lower(), self.logger.info)
        log_method(message)

        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        self.log_messages.append(f"[{timestamp}] {message}")

    def check_postgresql(self) -> HealthCheckResult:
        """检查PostgreSQL连接"""
        start_time = time.time()
        try:
            with timeout_context(10):
                conn = psycopg2.connect(
                    host="localhost",
                    port=5432,
                    user="postgres",
                    password=self.db_password,
                    database="postgres",
                    connect_timeout=10,
                )

                with conn.cursor() as cursor:
                    cursor.execute("SELECT 1")
                    result = cursor.fetchone()[0]

                    # 获取连接数信息
                    cursor.execute("SELECT count(*) FROM pg_stat_activity")
                    connection_count = cursor.fetchone()[0]

                conn.close()

            duration = time.time() - start_time
            details = {
                "connection_count": connection_count,
                "test_query_result": result,
            }

            self.log("✓ PostgreSQL连接正常")
            return HealthCheckResult(
                service="postgresql",
                status=ServiceStatus.HEALTHY,
                message="PostgreSQL连接正常",
                duration=duration,
                details=details,
            )

        except TimeoutError as e:
            duration = time.time() - start_time
            error_msg = f"PostgreSQL连接超时: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="postgresql",
                status=ServiceStatus.UNHEALTHY,
                message=error_msg,
                duration=duration
            )
        except Exception as e:
            duration = time.time() - start_time
            error_msg = f"PostgreSQL连接失败: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="postgresql",
                status=ServiceStatus.UNHEALTHY,
                message=error_msg,
                duration=duration
            )

    def check_redis(self) -> HealthCheckResult:
        """检查Redis连接"""
        start_time = time.time()
        try:
            with timeout_context(10):
                r = redis.Redis(host="localhost", port=6379, socket_timeout=10, decode_responses=True)
                pong = r.ping()

                # 获取Redis信息 (同步调用)
                info = r.info()
                memory_usage = info.get("used_memory", 0)
                connected_clients = info.get("connected_clients", 0)

            duration = time.time() - start_time
            details = {
                "ping_result": pong,
                "memory_usage": memory_usage,
                "connected_clients": connected_clients,
            }

            self.log("✓ Redis连接正常")
            return HealthCheckResult(
                service="redis",
                status=ServiceStatus.HEALTHY,
                message="Redis连接正常",
                duration=duration,
                details=details,
            )

        except TimeoutError as e:
            duration = time.time() - start_time
            error_msg = f"Redis连接超时: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="redis",
                status=ServiceStatus.UNHEALTHY,
                message=error_msg,
                duration=duration
            )
        except Exception as e:
            duration = time.time() - start_time
            error_msg = f"Redis连接失败: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="redis",
                status=ServiceStatus.UNHEALTHY,
                message=error_msg,
                duration=duration
            )

    def check_django_health(self) -> HealthCheckResult:
        """检查Django应用健康状态"""
        start_time = time.time()
        try:
            with timeout_context(10):
                response = requests.get(
                    "http://localhost:8000/_health/",
                    timeout=10,
                    headers={"User-Agent": "ScheduledRestarter/1.0"}
                )

            duration = time.time() - start_time
            details = {
                "status_code": response.status_code,
                "response_time": duration,
                "content_length": len(response.content),
                "headers": dict(response.headers),
            }

            if response.status_code == 200:
                self.log("✓ Django应用健康检查通过")
                return HealthCheckResult(
                    service="django",
                    status=ServiceStatus.HEALTHY,
                    message="Django应用健康检查通过",
                    duration=duration,
                    details=details,
                )
            else:
                error_msg = f"Django健康检查失败，状态码: {response.status_code}"
                self.log(f"✗ {error_msg}", "error")
                return HealthCheckResult(
                    service="django",
                    status=ServiceStatus.UNHEALTHY,
                    message=error_msg,
                    duration=duration,
                    details=details,
                )

        except TimeoutError as e:
            duration = time.time() - start_time
            error_msg = f"Django健康检查超时: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="django",
                status=ServiceStatus.UNHEALTHY,
                message=error_msg,
                duration=duration
            )
        except Exception as e:
            duration = time.time() - start_time
            error_msg = f"Django健康检查失败: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="django",
                status=ServiceStatus.UNHEALTHY,
                message=error_msg,
                duration=duration
            )

    def check_celery_workers(self) -> HealthCheckResult:
        """检查Celery工作进程状态"""
        start_time = time.time()
        try:
            # 检查Celery进程是否运行
            celery_pids: list[int] = []
            for proc in psutil.process_iter(["pid", "name", "cmdline"]):
                try:
                    cmdline = " ".join(proc.info.get("cmdline") or [])
                    if "celery" in cmdline and "worker" in cmdline:
                        pid = proc.info.get("pid")
                        if isinstance(pid, int):
                            celery_pids.append(pid)
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

            duration = time.time() - start_time
            details = {"worker_pids": celery_pids, "worker_count": len(celery_pids)}

            if len(celery_pids) > 0:
                self.log(f"✓ Celery worker进程运行中 ({len(celery_pids)} 个进程)")
                return HealthCheckResult(
                    service="celery",
                    status=ServiceStatus.HEALTHY,
                    message=f"Celery worker进程运行中 ({len(celery_pids)} 个进程)",
                    duration=duration,
                    details=details,
                )
            else:
                error_msg = "Celery worker进程未运行"
                self.log(f"✗ {error_msg}", "error")
                return HealthCheckResult(
                    service="celery",
                    status=ServiceStatus.UNHEALTHY,
                    message=error_msg,
                    duration=duration,
                    details=details,
                )

        except Exception as e:
            duration = time.time() - start_time
            error_msg = f"Celery worker检查失败: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="celery",
                status=ServiceStatus.UNHEALTHY,
                message=error_msg,
                duration=duration
            )

    def get_system_info(self) -> SystemInfo:
        """获取系统信息"""
        try:
            # 内存使用率
            memory = psutil.virtual_memory()
            memory_usage = memory.percent

            # 磁盘使用率
            disk = psutil.disk_usage("/")
            disk_usage = disk.percent

            # CPU使用率
            cpu_usage = psutil.cpu_percent(interval=1)

            # 负载平均值
            load_avg = list(os.getloadavg())

            # 网络连接数
            network_connections = len(psutil.net_connections())

            self.log(
                f"✓ 系统资源检查完成 - 内存: {memory_usage:.1f}%, 磁盘: {disk_usage:.1f}%, CPU: {cpu_usage:.1f}%"
            )

            return SystemInfo(
                memory_usage=memory_usage,
                disk_usage=disk_usage,
                cpu_usage=cpu_usage,
                load_avg=load_avg,
                network_connections=network_connections,
            )

        except Exception as e:
            self.log(f"✗ 系统信息获取失败: {str(e)}", "error")
            return SystemInfo(
                memory_usage=0.0,
                disk_usage=0.0,
                cpu_usage=0.0,
                load_avg=[0.0, 0.0, 0.0],
                network_connections=0,
            )

    def get_service_pids(self, service_name: str) -> list[int]:
        """获取指定服务的PID列表"""
        pids: list[int] = []
        try:
            for proc in psutil.process_iter(["pid", "name", "cmdline"]):
                try:
                    cmdline = " ".join(proc.info.get("cmdline") or [])
                    pid = proc.info.get("pid")
                    if not isinstance(pid, int):
                        continue

                    if service_name == "web" and "gunicorn" in cmdline:
                        pids.append(pid)
                    elif service_name == "celery" and "celery" in cmdline and "worker" in cmdline:
                        pids.append(pid)
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
        except Exception:
            pass
        return pids

    def restart_service(self, service_name: str) -> RestartInfo:
        """重启服务"""
        start_time = time.time()
        old_pids = self.get_service_pids(service_name)

        try:
            self.log(f"🔄 重启服务: {service_name} (当前PID: {old_pids})...")

            # 使用supervisorctl重启服务
            result = subprocess.run(
                ["supervisorctl", "restart", service_name],
                capture_output=True,
                text=True,
                timeout=60,
            )

            restart_time = time.time() - start_time

            if result.returncode == 0:
                # 等待服务启动
                self.log(f"⏳ 等待 {service_name} 服务启动...")
                time.sleep(15)

                # 获取新进程PID
                new_pids = self.get_service_pids(service_name)

                success = len(new_pids) > 0
                message = f"服务 {service_name} 重启{'成功' if success else '失败'}"

                if success:
                    self.log(f"✅ 服务 {service_name} 重启成功 (PID: {old_pids} → {new_pids})")
                else:
                    self.log(f"❌ 服务 {service_name} 重启后未检测到进程", "error")

                return RestartInfo(
                    service=service_name,
                    old_pid=old_pids[0] if old_pids else None,
                    new_pid=new_pids[0] if new_pids else None,
                    restart_time=restart_time,
                    success=success,
                    message=message,
                    error_details=result.stderr if not success else None,
                )
            else:
                error_msg = f"服务 {service_name} 重启失败: {result.stderr}"
                self.log(f"❌ {error_msg}", "error")
                return RestartInfo(
                    service=service_name,
                    old_pid=old_pids[0] if old_pids else None,
                    new_pid=None,
                    restart_time=restart_time,
                    success=False,
                    message=error_msg,
                    error_details=result.stderr,
                )

        except subprocess.TimeoutExpired:
            error_msg = f"服务 {service_name} 重启超时"
            self.log(f"❌ {error_msg}", "error")
            return RestartInfo(
                service=service_name,
                old_pid=old_pids[0] if old_pids else None,
                new_pid=None,
                restart_time=time.time() - start_time,
                success=False,
                message=error_msg,
            )
        except Exception as e:
            error_msg = f"服务 {service_name} 重启异常: {str(e)}"
            self.log(f"❌ {error_msg}", "error")
            return RestartInfo(
                service=service_name,
                old_pid=old_pids[0] if old_pids else None,
                new_pid=None,
                restart_time=time.time() - start_time,
                success=False,
                message=error_msg,
            )

    def send_feishu_notification(self, report: ExecutionReport) -> None:
        """发送飞书通知"""
        if not self.webhook_url:
            self.log("📱 未配置飞书webhook地址，跳过通知发送", "warning")
            return

        try:
            # 构建交互式卡片消息
            status_emoji = "✅" if report.success else "❌"
            status_color = "green" if report.success else "red"
            mode_text = "强制重启" if report.mode == RestartMode.FORCED else "条件重启"

            # 构建markdown内容
            markdown_content = f"""**🌍 环境**: {self.service_domain}
**⏰ 执行时间**: {report.timestamp}
**🔄 重启模式**: {mode_text}
**⏱️ 总耗时**: {report.duration:.2f}秒
**🎯 执行状态**: {"成功" if report.success else "失败"}

---
🔍 **重启前健康检查**
"""

            for check in report.pre_checks:
                emoji = "✅" if check.status == ServiceStatus.HEALTHY else "❌"
                status_text = "正常" if check.status == ServiceStatus.HEALTHY else "异常"
                markdown_content += f"- {emoji} **{check.service.upper()}**: {status_text} ({check.duration:.2f}s)\n"

            if report.post_checks:
                markdown_content += "\n---\n🔍 **重启后健康检查**\n"
                for check in report.post_checks:
                    emoji = "✅" if check.status == ServiceStatus.HEALTHY else "❌"
                    status_text = "正常" if check.status == ServiceStatus.HEALTHY else "异常"
                    markdown_content += f"- {emoji} **{check.service.upper()}**: {status_text} ({check.duration:.2f}s)\n"

            markdown_content += f"""
---
📊 **系统资源信息**
- **💾 内存使用率**: {report.system_info.memory_usage:.1f}%
- **💿 磁盘使用率**: {report.system_info.disk_usage:.1f}%
- **🖥️ CPU使用率**: {report.system_info.cpu_usage:.1f}%
- **⚖️ 系统负载**: {", ".join(f"{x:.2f}" for x in report.system_info.load_avg)}
- **🌐 网络连接数**: {report.system_info.network_connections}

"""

            if report.restart_actions:
                markdown_content += "--- \n🔄 **重启操作详情**\n"
                for restart in report.restart_actions:
                    emoji = "✅" if restart.success else "❌"
                    pid_info = f"PID: {restart.old_pid} → {restart.new_pid}" if restart.old_pid and restart.new_pid else "PID变更未知"
                    markdown_content += f"- {emoji} **{restart.service.upper()}**: {restart.message} ({restart.restart_time:.2f}s) | {pid_info}\n"
                    if restart.error_details:
                        markdown_content += f"  ⚠️ 错误详情: `{restart.error_details}`\n"
                markdown_content += "\n"

            # 添加最近的日志
            recent_logs = self.log_messages[-8:]  # 最近8条日志
            if recent_logs:
                markdown_content += "--- \n📝 **最近执行日志**\n```\n"
                for log in recent_logs:
                    markdown_content += f"{log}\n"
                markdown_content += "```\n"

            # 构建飞书卡片
            card_data = {
                "msg_type": "interactive",
                "card": {
                    "schema": "2.0",
                    "config": {"update_multi": True},
                    "header": {
                        "title": {
                            "tag": "plain_text",
                            "content": f"{status_emoji} Glitchtip AIO {mode_text}报告",
                        },
                        "template": status_color,
                    },
                    "body": {
                        "elements": [{"tag": "markdown", "content": markdown_content}]
                    },
                },
            }

            # 发送请求
            response = requests.post(
                self.webhook_url,
                json=card_data,
                timeout=30,
                headers={"Content-Type": "application/json"},
            )

            if response.status_code == 200:
                self.log("✅ 飞书通知发送成功")
            else:
                self.log(
                    f"❌ 飞书通知发送失败: {response.status_code} - {response.text}",
                    "error",
                )

        except Exception as e:
            self.log(f"❌ 飞书通知发送异常: {str(e)}", "error")

    def execute(self) -> ExecutionReport:
        """执行定时强制重启"""
        mode_text = "强制重启" if self.mode == RestartMode.FORCED else "条件重启"
        self.log(f"🚀 === 开始定时{mode_text}检查 ===")

        pre_checks: list[HealthCheckResult] = []
        restart_actions: list[RestartInfo] = []
        post_checks: list[HealthCheckResult] = []

        try:
            # 第一阶段：重启前健康检查
            self.log("🔍 执行重启前健康检查...")
            pre_checks = [
                self.check_postgresql(),
                self.check_redis(),
                self.check_django_health(),
                self.check_celery_workers(),
            ]

            # 获取系统信息
            system_info = self.get_system_info()

            # 第二阶段：强制执行重启
            self.log("🔄 开始强制重启服务...")

            # 重启web服务
            restart_actions.append(self.restart_service("web"))

            # 等待web服务完全启动
            time.sleep(10)

            # 重启celery服务
            restart_actions.append(self.restart_service("celery"))

            # 第三阶段：重启后健康检查
            self.log("🔍 执行重启后健康检查...")
            time.sleep(15)  # 等待服务稳定

            post_checks = [
                self.check_django_health(),
                self.check_celery_workers(),
            ]

            # 最终基础服务检查
            post_checks.extend([
                self.check_postgresql(),
                self.check_redis(),
            ])

            # 评估执行结果
            all_services_ok = all(check.status == ServiceStatus.HEALTHY for check in post_checks)
            all_restarts_ok = all(action.success for action in restart_actions)

            success = all_services_ok and all_restarts_ok
            success_message = (
                "所有服务重启后运行正常"
                if success
                else "重启后部分服务异常，请检查日志和详情"
            )

            if not success:
                self.log(f"❌ {success_message}", "error")
            else:
                self.log(f"✅ {success_message}")

            duration = time.time() - self.start_time

            report = ExecutionReport(
                timestamp=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
                duration=duration,
                mode=self.mode,
                pre_checks=pre_checks,
                post_checks=post_checks,
                system_info=system_info,
                restart_actions=restart_actions,
                success=success,
                message=success_message,
            )

            # 发送通知
            self.send_feishu_notification(report)

            self.log(f"🏁 === 定时{mode_text}检查完成 ===")
            return report

        except Exception as e:
            error_msg = f"定时{mode_text}执行异常: {str(e)}"
            self.log(f"❌ {error_msg}", "error")

            duration = time.time() - self.start_time
            report = ExecutionReport(
                timestamp=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
                duration=duration,
                mode=self.mode,
                pre_checks=pre_checks,
                post_checks=post_checks,
                system_info=self.get_system_info(),
                restart_actions=restart_actions,
                success=False,
                message=error_msg,
            )

            # 发送异常通知
            self.send_feishu_notification(report)
            return report


def main() -> Never:
    """主函数"""
    # 使用强制重启模式
    restarter = ScheduledRestarter(mode=RestartMode.FORCED)
    report = restarter.execute()

    # 退出码
    sys.exit(0 if report.success else 1)


if __name__ == "__main__":
    main()