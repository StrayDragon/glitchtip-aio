#!/bin/bash

# Glitchtip 用户管理脚本
# 用于在容器内进行用户管理操作

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 显示帮助信息
show_help() {
    echo -e "${BLUE}Glitchtip 用户管理脚本${NC}"
    echo ""
    echo "用法: $0 <命令> [选项]"
    echo ""
    echo "可用命令:"
    echo -e "  ${GREEN}create${NC} <用户名> <邮箱> [密码]     创建新用户"
    echo -e "  ${GREEN}list${NC}                           列出所有用户"
    echo -e "  ${GREEN}info${NC} <用户名>                    显示用户详细信息"
    echo -e "  ${GREEN}update${NC} <用户名> [选项]           更新用户信息"
    echo -e "  ${GREEN}delete${NC} <用户名>                  删除用户"
    echo -e "  ${GREEN}superuser${NC} <用户名> [true/false]  设置/取消超级用户权限"
    echo -e "  ${GREEN}staff${NC} <用户名> [true/false]      设置/取消员工权限"
    echo -e "  ${GREEN}active${NC} <用户名> [true/false]     激活/停用用户"
    echo -e "  ${GREEN}reset-password${NC} <用户名> [新密码] 重置用户密码"
    echo -e "  ${GREEN}organizations${NC} <用户名>          显示用户的组织"
    echo -e "  ${GREEN}help${NC}                            显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 create admin admin@example.com mypassword"
    echo "  $0 list"
    echo "  $0 superuser admin true"
    echo "  $0 reset-password admin newpassword"
    echo ""
}

# 检查是否在容器内运行
check_container() {
    if [ ! -f "/.dockerenv" ] && [ ! -d "/code" ]; then
        echo -e "${RED}错误: 此脚本必须在 Glitchtip AIO 容器内运行${NC}"
        echo "请使用 'just shell' 进入容器后运行此脚本"
        exit 1
    fi
}

# 切换到代码目录
cd_to_code() {
    if [ -d "/code" ]; then
        cd /code
        # 加载环境变量
        if [ -f "/code/.env" ]; then
            export $(cat /code/.env | grep -v '^#' | xargs)
        fi
    else
        echo -e "${RED}错误: 找不到 /code 目录${NC}"
        exit 1
    fi
}

# 创建用户
create_user() {
    local username="$1"
    local email="$2"
    local password="$3"

    if [ -z "$username" ] || [ -z "$email" ]; then
        echo -e "${RED}错误: 用户名和邮箱不能为空${NC}"
        show_help
        exit 1
    fi

    if [ -z "$password" ]; then
        password=$(openssl rand -hex 16)
        echo -e "${YELLOW}未提供密码，已生成随机密码: ${password}${NC}"
    fi

    cd_to_code

    echo -e "${BLUE}正在创建用户: ${username} (${email})${NC}"

    # 创建用户
    python manage.py shell << EOF
from django.contrib.auth import get_user_model
from django.core.management.base import CommandError
import sys

username = "$username"
email = "$email"
password = "$password"

User = get_user_model()

try:
    if User.objects.filter(email=email).exists():
        print(f"邮箱 '{email}' 已存在")
        sys.exit(1)

    # Glitchtip使用email作为用户名
    user = User.objects.create_user(
        email=email,
        password=password,
        name=username  # 使用name字段存储显示名称
    )

    print(f"用户 '{username}' 创建成功")
    print(f"用户邮箱: {user.email}")
    print(f"用户ID: {user.id}")
    print(f"是否激活: {user.is_active}")
    print(f"是否超级用户: {user.is_superuser}")
    print(f"是否员工: {user.is_staff}")

except Exception as e:
    print(f"创建用户失败: {str(e)}")
    sys.exit(1)
EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}用户创建成功！${NC}"
        echo -e "${BLUE}用户名:${NC} ${username}"
        echo -e "${BLUE}邮箱:${NC} ${email}"
        echo -e "${BLUE}密码:${NC} ${password}"
    else
        echo -e "${RED}用户创建失败${NC}"
        exit 1
    fi
}

# 列出用户
list_users() {
    cd_to_code

    echo -e "${BLUE}用户列表:${NC}"
    echo "ID    显示名称        邮箱                      超级用户  员工    激活    创建时间"
    echo "----  --------------  -----------------------  --------  ------  ------  ----------"

    python manage.py shell << EOF
from django.contrib.auth import get_user_model
from django.utils import timezone

User = get_user_model()

for user in User.objects.all().order_by('id'):
    created_time = user.created.strftime('%Y-%m-%d %H:%M')
    display_name = user.name or '未设置'
    print(f"{user.id:<6} {display_name:<15} {user.email:<25} "
          f"{'是' if user.is_superuser else '否':<8} {'是' if user.is_staff else '否':<6} "
          f"{'是' if user.is_active else '否':<6} {created_time}")
EOF
}

# 显示用户信息
show_user_info() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}错误: 用户名不能为空${NC}"
        show_help
        exit 1
    fi

    cd_to_code

    python manage.py shell << EOF
from django.contrib.auth import get_user_model

User = get_user_model()

try:
    user = User.objects.get(email=username)  # Glitchtip使用email作为用户名
    print(f"用户ID: {user.id}")
    print(f"显示名称: {user.name or '未设置'}")
    print(f"邮箱: {user.email}")
    print(f"是否激活: {'是' if user.is_active else '否'}")
    print(f"是否超级用户: {'是' if user.is_superuser else '否'}")
    print(f"是否员工: {'是' if user.is_staff else '否'}")
    print(f"创建时间: {user.created.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"最后登录: {user.last_login.strftime('%Y-%m-%d %H:%M:%S') if user.last_login else '从未登录'}")

except User.DoesNotExist:
    print(f"用户 '{username}' 不存在")
    exit(1)
except Exception as e:
    print(f"获取用户信息失败: {str(e)}")
    exit(1)
EOF
}

# 更新用户
update_user() {
    local username="$1"
    shift
    local email=""
    local password=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --email)
                email="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}未知选项: $1${NC}"
                exit 1
                ;;
        esac
    done

    if [ -z "$username" ]; then
        echo -e "${RED}错误: 用户名不能为空${NC}"
        show_help
        exit 1
    fi

    cd_to_code

    python manage.py shell << EOF
from django.contrib.auth import get_user_model

User = get_user_model()

try:
    user = User.objects.get(email=username)

    if "$email":
        user.email = email
        print(f"邮箱已更新为: {email}")

    if "$password":
        user.set_password(password)
        print(f"密码已更新")

    user.save()
    print(f"用户 '{username}' 更新成功")

except User.DoesNotExist:
    print(f"用户 '{username}' 不存在")
    exit(1)
except Exception as e:
    print(f"更新用户失败: {str(e)}")
    exit(1)
EOF
}

# 删除用户
delete_user() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}错误: 用户名不能为空${NC}"
        show_help
        exit 1
    fi

    cd_to_code

    python manage.py shell << EOF
from django.contrib.auth import get_user_model

User = get_user_model()

try:
    user = User.objects.get(email=username)
    user.delete()
    print(f"用户 '{username}' 已删除")

except User.DoesNotExist:
    print(f"用户 '{username}' 不存在")
    exit(1)
except Exception as e:
    print(f"删除用户失败: {str(e)}")
    exit(1)
EOF
}

# 设置超级用户权限
set_superuser() {
    local username="$1"
    local is_superuser="$2"

    if [ -z "$username" ] || [ -z "$is_superuser" ]; then
        echo -e "${RED}错误: 用户名和权限状态不能为空${NC}"
        show_help
        exit 1
    fi

    if [ "$is_superuser" != "true" ] && [ "$is_superuser" != "false" ]; then
        echo -e "${RED}错误: 权限状态必须是 true 或 false${NC}"
        exit 1
    fi

    cd_to_code

    python manage.py shell << EOF
from django.contrib.auth import get_user_model

User = get_user_model()

try:
    user = User.objects.get(email=username)
    user.is_superuser = (is_superuser == 'true')
    user.save()
    print(f"用户 '{username}' 超级用户权限已设置为: {user.is_superuser}")

except User.DoesNotExist:
    print(f"用户 '{username}' 不存在")
    exit(1)
except Exception as e:
    print(f"设置超级用户权限失败: {str(e)}")
    exit(1)
EOF
}

# 设置员工权限
set_staff() {
    local username="$1"
    local is_staff="$2"

    if [ -z "$username" ] || [ -z "$is_staff" ]; then
        echo -e "${RED}错误: 用户名和权限状态不能为空${NC}"
        show_help
        exit 1
    fi

    if [ "$is_staff" != "true" ] && [ "$is_staff" != "false" ]; then
        echo -e "${RED}错误: 权限状态必须是 true 或 false${NC}"
        exit 1
    fi

    cd_to_code

    python manage.py shell << EOF
from django.contrib.auth import get_user_model

User = get_user_model()

try:
    user = User.objects.get(email=username)
    user.is_staff = (is_staff == 'true')
    user.save()
    print(f"用户 '{username}' 员工权限已设置为: {user.is_staff}")

except User.DoesNotExist:
    print(f"用户 '{username}' 不存在")
    exit(1)
except Exception as e:
    print(f"设置员工权限失败: {str(e)}")
    exit(1)
EOF
}

# 设置用户激活状态
set_active() {
    local username="$1"
    local is_active="$2"

    if [ -z "$username" ] || [ -z "$is_active" ]; then
        echo -e "${RED}错误: 用户名和激活状态不能为空${NC}"
        show_help
        exit 1
    fi

    if [ "$is_active" != "true" ] && [ "$is_active" != "false" ]; then
        echo -e "${RED}错误: 激活状态必须是 true 或 false${NC}"
        exit 1
    fi

    cd_to_code

    python manage.py shell << EOF
from django.contrib.auth import get_user_model

User = get_user_model()

try:
    user = User.objects.get(email=username)
    user.is_active = (is_active == 'true')
    user.save()
    print(f"用户 '{username}' 激活状态已设置为: {user.is_active}")

except User.DoesNotExist:
    print(f"用户 '{username}' 不存在")
    exit(1)
except Exception as e:
    print(f"设置激活状态失败: {str(e)}")
    exit(1)
EOF
}

# 重置密码
reset_password() {
    local username="$1"
    local new_password="$2"

    if [ -z "$username" ]; then
        echo -e "${RED}错误: 用户名不能为空${NC}"
        show_help
        exit 1
    fi

    if [ -z "$new_password" ]; then
        new_password=$(openssl rand -hex 16)
        echo -e "${YELLOW}未提供新密码，已生成随机密码: ${new_password}${NC}"
    fi

    cd_to_code

    python manage.py shell << EOF
from django.contrib.auth import get_user_model

User = get_user_model()

try:
    user = User.objects.get(email=username)
    user.set_password(new_password)
    user.save()
    print(f"用户 '{username}' 密码已重置")

except User.DoesNotExist:
    print(f"用户 '{username}' 不存在")
    exit(1)
except Exception as e:
    print(f"重置密码失败: {str(e)}")
    exit(1)
EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}密码重置成功！${NC}"
        echo -e "${BLUE}新密码:${NC} ${new_password}"
    fi
}

# 显示用户组织
show_user_organizations() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}错误: 用户名不能为空${NC}"
        show_help
        exit 1
    fi

    cd_to_code

    python manage.py shell << EOF
from django.contrib.auth import get_user_model

User = get_user_model()

try:
    user = User.objects.get(email=username)
    organizations = user.organizations.all()

    if organizations:
        print(f"用户 '{username}' 属于以下组织:")
        for org in organizations:
            print(f"  - {org.name} (ID: {org.id})")
    else:
        print(f"用户 '{username}' 不属于任何组织")

except User.DoesNotExist:
    print(f"用户 '{username}' 不存在")
    exit(1)
except Exception as e:
    print(f"获取用户组织失败: {str(e)}")
    exit(1)
EOF
}

# 主函数
main() {
    check_container

    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    case "$1" in
        create)
            create_user "$2" "$3" "$4"
            ;;
        list)
            list_users
            ;;
        info)
            show_user_info "$2"
            ;;
        update)
            update_user "$2" "${@:3}"
            ;;
        delete)
            delete_user "$2"
            ;;
        superuser)
            set_superuser "$2" "$3"
            ;;
        staff)
            set_staff "$2" "$3"
            ;;
        active)
            set_active "$2" "$3"
            ;;
        reset-password)
            reset_password "$2" "$3"
            ;;
        organizations)
            show_user_organizations "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}未知命令: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"