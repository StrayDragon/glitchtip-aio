#!/usr/bin/env python3
"""
GlitchTip AIO 分区维护脚本
替代全服务重启，只做分区管理和飞书通知
"""

import subprocess
import requests
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path


def load_env():
    """加载环境变量"""
    env_file = Path("/code/.env")
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    os.environ[key] = value.strip("\"'")
    return os.environ


def get_domain_info():
    """获取环境域名信息用于区分多环境"""
    return os.getenv("GLITCHTIP_DOMAIN", "Unknown")


def send_feishu_notification(title, content, is_success=True):
    """发送飞书通知"""
    webhook_url = os.environ.get("FEISHU_GROUP_DEVOPS_ROBOT_WEBHOOK_URL")
    if not webhook_url:
        print("⚠️ 未配置飞书webhook，跳过通知")
        return False

    # 根据成功/失败状态设置颜色和表情
    if is_success:
        emoji = "✅"
        color = "green"
    else:
        emoji = "❌"
        color = "red"

    payload = {
        "msg_type": "interactive",
        "card": {
            "config": {"wide_screen_mode": True},
            "header": {
                "title": {"tag": "plain_text", "content": f"{emoji} {title}"},
                "template": color,
            },
            "elements": [
                {"tag": "div", "text": {"tag": "lark_md", "content": content}},
                {
                    "tag": "div",
                    "text": {
                        "tag": "plain_text",
                        "content": f"📅 执行时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                    },
                },
            ],
        },
    }

    try:
        response = requests.post(
            webhook_url,
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=10,
        )

        if response.status_code == 200:
            result = response.json()
            if result.get("code") == 0:
                print(f"✅ 飞书通知发送成功")
                return True
            else:
                print(f"❌ 飞书通知发送失败: {result.get('msg', '未知错误')}")
                return False
        else:
            print(f"❌ 飞书通知请求失败: {response.status_code}")
            return False

    except Exception as e:
        print(f"❌ 飞书通知异常: {e}")
        return False


def run_partition_maintenance():
    """执行分区维护"""
    print("🔧 开始执行分区维护...")

    try:
        # 执行分区管理命令
        cmd = ["/code/bin/manage-with-env.sh", "pgpartition", "--yes"]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,  # 5分钟超时
        )

        success = result.returncode == 0
        stdout = result.stdout
        stderr = result.stderr

        # 分析执行结果
        partition_count = 0
        if success:
            # 从输出中提取分区创建数量
            for line in stdout.split("\n"):
                if "partitions will be created" in line:
                    try:
                        partition_count = int(line.split()[0])
                    except (ValueError, IndexError):
                        pass

        print(f"{'✅' if success else '❌'} 分区维护{'成功' if success else '失败'}")
        if partition_count > 0:
            print(f"📊 创建了 {partition_count} 个分区")

        return success, stdout, stderr, partition_count

    except subprocess.TimeoutExpired:
        return False, "", "分区维护超时", 0
    except Exception as e:
        return False, "", f"分区维护异常: {e}", 0


def main():
    """主函数"""
    start_time = time.time()

    print("=" * 60)
    print("🔧 GlitchTip AIO 分区维护脚本")
    print("=" * 60)

    # 加载环境变量
    load_env()

    # 执行分区维护
    success, stdout, stderr, partition_count = run_partition_maintenance()

    # 计算执行时间
    execution_time = time.time() - start_time

    # 准备飞书通知内容
    title = "GlitchTip AIO 分区维护报告"

    svc_domain = get_domain_info()

    if success:
        content = f"""**服务**: {svc_domain}
**🎯 执行状态**: 成功
**⏱️ 总耗时**: {execution_time:.2f}秒
**📊 创建分区数**: {partition_count}

**📝 执行详情**:
```
{stdout[:800]}{"..." if len(stdout) > 800 else ""}
```

**🔧 维护说明**:
- 仅执行分区维护，不重启服务
- 避免服务中断，提高可用性
- 自动创建未来分区，预防404错误
"""
    else:
        content = f"""**🎯 执行状态**: 失败
**⏱️ 总耗时**: {execution_time:.2f}秒

**❌ 错误信息**:
```
{stderr}
```

**🔧 可能原因**:
- 数据库连接失败
- 权限不足
- 分区创建冲突
"""

    # 发送飞书通知
    print("📤 发送飞书通知...")
    notification_sent = send_feishu_notification(title, content, success)

    # 输出最终结果
    print("=" * 60)
    print(f"📊 分区维护完成")
    print(f"🎯 状态: {'成功' if success else '失败'}")
    print(f"📤 通知: {'已发送' if notification_sent else '发送失败'}")
    print(f"⏱️ 耗时: {execution_time:.2f}秒")
    print("=" * 60)

    # 返回退出码
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
