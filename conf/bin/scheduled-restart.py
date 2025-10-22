#!/usr/bin/env python3
"""
定时重启脚本 - 每天临晨3:01执行
智能判断是否需要重启web和celery服务，支持飞书webhook通知

Author: Claude Code
Created: 2025-10-22
"""

import os
import sys
import json
import time
import subprocess
import logging
import psutil
import requests
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
import psycopg2
import redis
from urllib.parse import urlparse


@dataclass
class HealthCheckResult:
    """健康检查结果"""

    service: str
    status: bool
    message: str
    duration: float
    details: Dict = None


@dataclass
class SystemInfo:
    """系统信息"""

    memory_usage: float  # 百分比
    disk_usage: float  # 百分比
    cpu_usage: float  # 百分比
    load_avg: List[float]
    network_connections: int


@dataclass
class RestartInfo:
    """重启信息"""

    service: str
    old_pid: Optional[int]
    new_pid: Optional[int]
    restart_time: float
    success: bool
    message: str


@dataclass
class ExecutionReport:
    """执行报告"""

    timestamp: str
    duration: float
    health_checks: List[HealthCheckResult]
    system_info: SystemInfo
    restart_actions: List[RestartInfo]
    success: bool
    message: str


class ScheduledRestarter:
    """定时重启器"""

    def __init__(self):
        self.setup_logging()
        self.start_time = time.time()
        self.webhook_url = os.getenv("FEISHU_GROUP_DEVOPS_ROBOT_WEBHOOK_URL")
        self.db_password = os.getenv("DB_PASSWORD", "postgres")
        self.log_messages = []
        self.service_domain = os.environ.get("GLITCHTIP_DOMAIN", "<unknown_domain>")

    def setup_logging(self):
        """设置日志"""
        logging.basicConfig(
            level=logging.INFO,
            format="[%(asctime)s] SCHEDULED-RESTART: %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
            handlers=[
                logging.FileHandler("/var/log/supervisor/scheduled-restart.log"),
                logging.StreamHandler(sys.stdout),
            ],
        )
        self.logger = logging.getLogger(__name__)

    def log(self, message: str, level: str = "info"):
        """记录日志"""
        if level == "error":
            self.logger.error(message)
        elif level == "warning":
            self.logger.warning(message)
        else:
            self.logger.info(message)
        self.log_messages.append(
            f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}"
        )

    def check_postgresql(self) -> HealthCheckResult:
        """检查PostgreSQL连接"""
        start_time = time.time()
        try:
            conn = psycopg2.connect(
                host="localhost",
                port=5432,
                user="postgres",
                password=self.db_password,
                database="postgres",
                connect_timeout=10,
            )

            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            result = cursor.fetchone()[0]

            # 获取连接数信息
            cursor.execute("SELECT count(*) FROM pg_stat_activity")
            connection_count = cursor.fetchone()[0]

            cursor.close()
            conn.close()

            duration = time.time() - start_time
            details = {
                "connection_count": connection_count,
                "test_query_result": result,
            }

            self.log("✓ PostgreSQL连接正常")
            return HealthCheckResult(
                service="postgresql",
                status=True,
                message="PostgreSQL连接正常",
                duration=duration,
                details=details,
            )

        except Exception as e:
            duration = time.time() - start_time
            error_msg = f"PostgreSQL连接失败: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="postgresql", status=False, message=error_msg, duration=duration
            )

    def check_redis(self) -> HealthCheckResult:
        """检查Redis连接"""
        start_time = time.time()
        try:
            r = redis.Redis(host="localhost", port=6379, socket_timeout=10)
            pong = r.ping()

            # 获取Redis信息
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
                status=True,
                message="Redis连接正常",
                duration=duration,
                details=details,
            )

        except Exception as e:
            duration = time.time() - start_time
            error_msg = f"Redis连接失败: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="redis", status=False, message=error_msg, duration=duration
            )

    def check_django_health(self) -> HealthCheckResult:
        """检查Django应用健康状态"""
        start_time = time.time()
        try:
            # 检查Django健康端点
            response = requests.get("http://localhost:8000/_health/", timeout=10)

            duration = time.time() - start_time
            details = {
                "status_code": response.status_code,
                "response_time": duration,
                "content_length": len(response.content),
            }

            if response.status_code == 200:
                self.log("✓ Django应用健康检查通过")
                return HealthCheckResult(
                    service="django",
                    status=True,
                    message="Django应用健康检查通过",
                    duration=duration,
                    details=details,
                )
            else:
                error_msg = f"Django健康检查失败，状态码: {response.status_code}"
                self.log(f"✗ {error_msg}", "error")
                return HealthCheckResult(
                    service="django",
                    status=False,
                    message=error_msg,
                    duration=duration,
                    details=details,
                )

        except Exception as e:
            duration = time.time() - start_time
            error_msg = f"Django健康检查失败: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="django", status=False, message=error_msg, duration=duration
            )

    def check_celery_workers(self) -> HealthCheckResult:
        """检查Celery工作进程状态"""
        start_time = time.time()
        try:
            # 检查Celery进程是否运行
            celery_pids = []
            for proc in psutil.process_iter(["pid", "name", "cmdline"]):
                try:
                    cmdline = " ".join(proc.info["cmdline"] or [])
                    if "celery" in cmdline and "worker" in cmdline:
                        celery_pids.append(proc.info["pid"])
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

            duration = time.time() - start_time
            details = {"worker_pids": celery_pids, "worker_count": len(celery_pids)}

            if len(celery_pids) > 0:
                self.log(f"✓ Celery worker进程运行中 ({len(celery_pids)} 个进程)")

                # 尝试连接检查
                try:
                    # 这里可以添加celery inspect检查，但为了避免网络问题，主要依赖进程检查
                    pass
                except:
                    pass

                return HealthCheckResult(
                    service="celery",
                    status=True,
                    message=f"Celery worker进程运行中 ({len(celery_pids)} 个进程)",
                    duration=duration,
                    details=details,
                )
            else:
                error_msg = "Celery worker进程未运行"
                self.log(f"✗ {error_msg}", "error")
                return HealthCheckResult(
                    service="celery",
                    status=False,
                    message=error_msg,
                    duration=duration,
                    details=details,
                )

        except Exception as e:
            duration = time.time() - start_time
            error_msg = f"Celery worker检查失败: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return HealthCheckResult(
                service="celery", status=False, message=error_msg, duration=duration
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

    def restart_service(self, service_name: str) -> RestartInfo:
        """重启服务"""
        start_time = time.time()

        # 获取当前进程PID
        old_pid = None
        try:
            if service_name == "web":
                # web服务通常是gunicorn进程
                for proc in psutil.process_iter(["pid", "name", "cmdline"]):
                    cmdline = " ".join(proc.info["cmdline"] or [])
                    if "gunicorn" in cmdline:
                        old_pid = proc.info["pid"]
                        break
            elif service_name == "celery":
                # celery进程
                for proc in psutil.process_iter(["pid", "name", "cmdline"]):
                    cmdline = " ".join(proc.info["cmdline"] or [])
                    if "celery" in cmdline and "worker" in cmdline:
                        old_pid = proc.info["pid"]
                        break
        except:
            pass

        try:
            self.log(f"重启服务: {service_name}...")

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
                time.sleep(10)

                # 获取新进程PID
                new_pid = None
                try:
                    if service_name == "web":
                        for proc in psutil.process_iter(["pid", "name", "cmdline"]):
                            cmdline = " ".join(proc.info["cmdline"] or [])
                            if "gunicorn" in cmdline:
                                new_pid = proc.info["pid"]
                                break
                    elif service_name == "celery":
                        for proc in psutil.process_iter(["pid", "name", "cmdline"]):
                            cmdline = " ".join(proc.info["cmdline"] or [])
                            if "celery" in cmdline and "worker" in cmdline:
                                new_pid = proc.info["pid"]
                                break
                except:
                    pass

                self.log(f"✓ 服务 {service_name} 重启成功 (PID: {old_pid} → {new_pid})")

                return RestartInfo(
                    service=service_name,
                    old_pid=old_pid,
                    new_pid=new_pid,
                    restart_time=restart_time,
                    success=True,
                    message=f"服务 {service_name} 重启成功",
                )
            else:
                error_msg = f"服务 {service_name} 重启失败: {result.stderr}"
                self.log(f"✗ {error_msg}", "error")
                return RestartInfo(
                    service=service_name,
                    old_pid=old_pid,
                    new_pid=None,
                    restart_time=restart_time,
                    success=False,
                    message=error_msg,
                )

        except subprocess.TimeoutExpired:
            error_msg = f"服务 {service_name} 重启超时"
            self.log(f"✗ {error_msg}", "error")
            return RestartInfo(
                service=service_name,
                old_pid=old_pid,
                new_pid=None,
                restart_time=time.time() - start_time,
                success=False,
                message=error_msg,
            )
        except Exception as e:
            error_msg = f"服务 {service_name} 重启异常: {str(e)}"
            self.log(f"✗ {error_msg}", "error")
            return RestartInfo(
                service=service_name,
                old_pid=old_pid,
                new_pid=None,
                restart_time=time.time() - start_time,
                success=False,
                message=error_msg,
            )

    def send_feishu_notification(self, report: ExecutionReport):
        """发送飞书通知"""
        if not self.webhook_url:
            self.log("未配置飞书webhook地址，跳过通知发送", "warning")
            return

        try:
            # 构建交互式卡片消息
            status_emoji = "✅" if report.success else "❌"
            status_color = "green" if report.success else "red"

            # 构建markdown内容
            markdown_content = f"""
**环境**: {self.service_domain}
**执行时间**: {report.timestamp}
**总耗时**: {report.duration:.2f}秒
**执行状态**: {"成功" if report.success else "失败"}

---
🔍 健康检查结果
"""

            for check in report.health_checks:
                emoji = "✅" if check.status else "❌"
                markdown_content += f"- {emoji} **{check.service.upper()}**: {check.message} ({check.duration:.2f}s)\n"

            markdown_content += f"""
---
📊 系统资源信息
- **内存使用率**: {report.system_info.memory_usage:.1f}%
- **磁盘使用率**: {report.system_info.disk_usage:.1f}%
- **CPU使用率**: {report.system_info.cpu_usage:.1f}%
- **系统负载**: {", ".join(f"{x:.2f}" for x in report.system_info.load_avg)}
- **网络连接数**: {report.system_info.network_connections}

"""

            if report.restart_actions:
                markdown_content += "--- \n🔄 重启操作\n"
                for restart in report.restart_actions:
                    emoji = "✅" if restart.success else "❌"
                    pid_info = (
                        f"PID: {restart.old_pid} → {restart.new_pid}"
                        if restart.old_pid and restart.new_pid
                        else ""
                    )
                    markdown_content += f"- {emoji} **{restart.service.upper()}**: {restart.message} ({restart.restart_time:.2f}s) {pid_info}\n"
                markdown_content += "\n"

            # 添加最近的日志
            recent_logs = self.log_messages[-5:]  # 最近5条日志
            if recent_logs:
                markdown_content += "--- \n📝 最近日志\n```\n"
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
                            "content": f"{status_emoji} Glitchtip AIO 定时重启报告",
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
                self.log("✓ 飞书通知发送成功")
            else:
                self.log(
                    f"✗ 飞书通知发送失败: {response.status_code} - {response.text}",
                    "error",
                )

        except Exception as e:
            self.log(f"✗ 飞书通知发送异常: {str(e)}", "error")

    def execute(self) -> ExecutionReport:
        """执行定时重启"""
        self.log("=== 开始定时重启检查 ===")

        health_checks = []
        restart_actions = []

        try:
            # 1. 健康检查
            self.log("开始健康检查...")

            # 检查基础服务
            health_checks.append(self.check_postgresql())
            health_checks.append(self.check_redis())

            # 如果基础服务有问题，不重启应用层服务
            base_service_issues = [
                check for check in health_checks[:2] if not check.status
            ]
            if base_service_issues:
                error_messages = [issue.message for issue in base_service_issues]
                error_msg = (
                    f"检测到基础服务问题，跳过应用服务重启: {', '.join(error_messages)}"
                )
                self.log(error_msg, "error")

                system_info = self.get_system_info()
                duration = time.time() - self.start_time

                report = ExecutionReport(
                    timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    duration=duration,
                    health_checks=health_checks,
                    system_info=system_info,
                    restart_actions=[],
                    success=False,
                    message=error_msg,
                )

                # 发送异常通知
                self.send_feishu_notification(report)
                return report

            # 检查应用层服务
            health_checks.append(self.check_django_health())
            health_checks.append(self.check_celery_workers())

            # 获取系统信息
            system_info = self.get_system_info()

            # 判断是否需要重启
            app_issues = [check for check in health_checks[2:] if not check.status]
            restart_needed = len(app_issues) > 0

            if not restart_needed:
                self.log("所有服务健康检查通过，执行预防性重启(每日例行维护)")
                restart_needed = True

            # 执行重启
            if restart_needed:
                self.log("开始执行服务重启...")

                # 重启web服务
                restart_actions.append(self.restart_service("web"))

                # 等待web服务完全启动
                time.sleep(10)

                # 重启celery服务
                restart_actions.append(self.restart_service("celery"))

                # 最终验证
                self.log("执行重启后健康检查...")
                time.sleep(10)

                final_django = self.check_django_health()
                final_celery = self.check_celery_workers()

                all_services_ok = final_django.status and final_celery.status
                success_message = (
                    "所有服务重启后运行正常"
                    if all_services_ok
                    else "重启后仍有服务异常，请检查日志"
                )

                if not all_services_ok:
                    self.log(success_message, "error")
                else:
                    self.log(success_message)

                duration = time.time() - self.start_time

                report = ExecutionReport(
                    timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    duration=duration,
                    health_checks=health_checks + [final_django, final_celery],
                    system_info=system_info,
                    restart_actions=restart_actions,
                    success=all_services_ok,
                    message=success_message,
                )

                # 发送重启通知
                self.send_feishu_notification(report)

                self.log("=== 定时重启检查完成 ===")
                return report
            else:
                duration = time.time() - self.start_time
                report = ExecutionReport(
                    timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    duration=duration,
                    health_checks=health_checks,
                    system_info=system_info,
                    restart_actions=[],
                    success=True,
                    message="所有服务正常，无需重启",
                )
                self.log("=== 定时重启检查完成 ===")
                return report

        except Exception as e:
            error_msg = f"定时重启执行异常: {str(e)}"
            self.log(error_msg, "error")

            duration = time.time() - self.start_time
            report = ExecutionReport(
                timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                duration=duration,
                health_checks=health_checks,
                system_info=self.get_system_info(),
                restart_actions=restart_actions,
                success=False,
                message=error_msg,
            )

            # 发送异常通知
            self.send_feishu_notification(report)
            return report


def main():
    """主函数"""
    restarter = ScheduledRestarter()
    report = restarter.execute()

    # 退出码
    sys.exit(0 if report.success else 1)


if __name__ == "__main__":
    main()
