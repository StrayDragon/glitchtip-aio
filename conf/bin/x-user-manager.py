#!/usr/bin/env python3
"""
Glitchtip 用户管理脚本
用于在容器内进行用户和组织管理操作
"""

import os
import sys
import argparse
import django
from django.core.management.base import CommandError
from django.contrib.auth import get_user_model

# 加载环境变量
def load_env_file(env_file='/code/.env'):
    """从 .env 文件加载环境变量"""
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key] = value

# 加载环境变量
load_env_file()

# 初始化Django环境
sys.path.insert(0, '/code')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'glitchtip.settings')
django.setup()

from apps.organizations_ext.models import Organization, OrganizationUser
from apps.organizations_ext.constants import OrganizationUserRole

User = get_user_model()

class UserManager:
    """用户管理类"""

    @staticmethod
    def create_user(username, email, password=None):
        """创建用户"""
        if not username or not email:
            print("错误: 用户名和邮箱不能为空")
            return False

        if User.objects.filter(email=email).exists():
            print(f"邮箱 '{email}' 已存在")
            return False

        if not password:
            import secrets
            password = secrets.token_hex(16)
            print(f"未提供密码，已生成随机密码: {password}")

        try:
            user = User.objects.create_user(
                email=email,
                password=password,
                name=username
            )
            print(f"用户 '{username}' 创建成功")
            print(f"用户邮箱: {user.email}")
            print(f"用户ID: {user.id}")
            print(f"是否激活: {user.is_active}")
            print(f"是否超级用户: {user.is_superuser}")
            print(f"是否员工: {user.is_staff}")
            return True
        except Exception as e:
            print(f"创建用户失败: {str(e)}")
            return False

    @staticmethod
    def list_users():
        """列出所有用户"""
        print("用户列表:")
        print("ID    显示名称        邮箱                      超级用户  员工    激活    创建时间")
        print("----  --------------  -----------------------  --------  ------  ------  ----------")

        for user in User.objects.all().order_by('id'):
            created_time = user.created.strftime('%Y-%m-%d %H:%M')
            display_name = user.name or '未设置'
            print(f"{user.id:<6} {display_name:<15} {user.email:<25} "
                  f"{'是' if user.is_superuser else '否':<8} {'是' if user.is_staff else '否':<6} "
                  f"{'是' if user.is_active else '否':<6} {created_time}")

    @staticmethod
    def show_user_info(email):
        """显示用户信息"""
        try:
            user = User.objects.get(email=email)
            print(f"用户ID: {user.id}")
            print(f"显示名称: {user.name or '未设置'}")
            print(f"邮箱: {user.email}")
            print(f"是否激活: {'是' if user.is_active else '否'}")
            print(f"是否超级用户: {'是' if user.is_superuser else '否'}")
            print(f"是否员工: {'是' if user.is_staff else '否'}")
            print(f"创建时间: {user.created.strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"最后登录: {user.last_login.strftime('%Y-%m-%d %H:%M:%S') if user.last_login else '从未登录'}")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Exception as e:
            print(f"获取用户信息失败: {str(e)}")
            return False

    @staticmethod
    def update_user(email, new_email=None, new_password=None):
        """更新用户"""
        try:
            user = User.objects.get(email=email)

            if new_email:
                user.email = new_email
                print(f"邮箱已更新为: {new_email}")

            if new_password:
                user.set_password(new_password)
                print("密码已更新")

            user.save()
            print(f"用户 '{email}' 更新成功")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Exception as e:
            print(f"更新用户失败: {str(e)}")
            return False

    @staticmethod
    def delete_user(email):
        """删除用户"""
        try:
            user = User.objects.get(email=email)
            user.delete()
            print(f"用户 '{email}' 已删除")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Exception as e:
            print(f"删除用户失败: {str(e)}")
            return False

    @staticmethod
    def set_superuser(email, is_superuser):
        """设置超级用户权限"""
        try:
            user = User.objects.get(email=email)
            user.is_superuser = is_superuser.lower() == 'true'
            user.save()
            print(f"用户 '{email}' 超级用户权限已设置为: {user.is_superuser}")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Exception as e:
            print(f"设置超级用户权限失败: {str(e)}")
            return False

    @staticmethod
    def set_staff(email, is_staff):
        """设置员工权限"""
        try:
            user = User.objects.get(email=email)
            user.is_staff = is_staff.lower() == 'true'
            user.save()
            print(f"用户 '{email}' 员工权限已设置为: {user.is_staff}")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Exception as e:
            print(f"设置员工权限失败: {str(e)}")
            return False

    @staticmethod
    def set_active(email, is_active):
        """设置用户激活状态"""
        try:
            user = User.objects.get(email=email)
            user.is_active = is_active.lower() == 'true'
            user.save()
            print(f"用户 '{email}' 激活状态已设置为: {user.is_active}")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Exception as e:
            print(f"设置激活状态失败: {str(e)}")
            return False

    @staticmethod
    def reset_password(email, new_password=None):
        """重置密码"""
        try:
            user = User.objects.get(email=email)

            if not new_password:
                import secrets
                new_password = secrets.token_hex(16)
                print(f"未提供新密码，已生成随机密码: {new_password}")

            user.set_password(new_password)
            user.save()
            print(f"用户 '{email}' 密码已重置")
            print(f"新密码: {new_password}")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Exception as e:
            print(f"重置密码失败: {str(e)}")
            return False

    @staticmethod
    def show_user_organizations(email):
        """显示用户组织"""
        try:
            user = User.objects.get(email=email)
            org_users = user.organizations_ext_organizationuser.all()

            if org_users:
                print(f"用户 '{email}' 属于以下组织:")
                for org_user in org_users:
                    org = org_user.organization
                    print(f"  - {org.name} (ID: {org.id}, 角色: {org_user.get_role()})")
            else:
                print(f"用户 '{email}' 不属于任何组织")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Exception as e:
            print(f"获取用户组织失败: {str(e)}")
            return False

class OrganizationManager:
    """组织管理类"""

    @staticmethod
    def create_organization(name):
        """创建组织"""
        if not name:
            print("错误: 组织名称不能为空")
            return False

        try:
            if Organization.objects.filter(name=name).exists():
                print(f"组织 '{name}' 已存在")
                return False

            org = Organization.objects.create(name=name)
            print(f"组织 '{name}' 创建成功")
            print(f"组织ID: {org.id}")
            print(f"组织标识: {org.slug}")
            return True
        except Exception as e:
            print(f"创建组织失败: {str(e)}")
            return False

    @staticmethod
    def add_user_to_organization(email, org_name):
        """将用户添加到组织"""
        try:
            user = User.objects.get(email=email)
            organization = Organization.objects.get(name=org_name)

            if OrganizationUser.objects.filter(user=user, organization=organization).exists():
                print(f"用户 '{email}' 已在组织 '{org_name}' 中")
                return True

            organization.add_user(user, OrganizationUserRole.MEMBER)
            print(f"用户 '{email}' 已成功添加到组织 '{org_name}'")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Organization.DoesNotExist:
            print(f"组织 '{org_name}' 不存在")
            return False
        except Exception as e:
            print(f"添加用户到组织失败: {str(e)}")
            return False

    @staticmethod
    def remove_user_from_organization(email, org_name):
        """将用户从组织中移除"""
        try:
            user = User.objects.get(email=email)
            organization = Organization.objects.get(name=org_name)

            org_user = OrganizationUser.objects.filter(user=user, organization=organization).first()
            if not org_user:
                print(f"用户 '{email}' 不在组织 '{org_name}' 中")
                return True

            org_user.delete()
            print(f"用户 '{email}' 已从组织 '{org_name}' 中移除")
            return True
        except User.DoesNotExist:
            print(f"用户 '{email}' 不存在")
            return False
        except Organization.DoesNotExist:
            print(f"组织 '{org_name}' 不存在")
            return False
        except Exception as e:
            print(f"从组织移除用户失败: {str(e)}")
            return False

    @staticmethod
    def list_organizations():
        """列出所有组织"""
        print("组织列表:")
        print("ID    组织名称         标识                    用户数  创建时间")
        print("----  ---------------  ---------------------  ------  ----------")

        for org in Organization.objects.all().order_by('id'):
            created_time = org.created.strftime('%Y-%m-%d %H:%M')
            user_count = org.users.count()
            print(f"{org.id:<6} {org.name:<16} {org.slug:<22} {user_count:<6} {created_time}")

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='Glitchtip 用户管理脚本')
    subparsers = parser.add_subparsers(dest='command', help='可用命令')

    # 用户相关命令
    create_parser = subparsers.add_parser('create', help='创建新用户')
    create_parser.add_argument('username', help='用户名')
    create_parser.add_argument('email', help='邮箱')
    create_parser.add_argument('password', nargs='?', help='密码 (可选)')

    subparsers.add_parser('list', help='列出所有用户')

    info_parser = subparsers.add_parser('info', help='显示用户详细信息')
    info_parser.add_argument('email', help='用户邮箱')

    update_parser = subparsers.add_parser('update', help='更新用户信息')
    update_parser.add_argument('email', help='用户邮箱')
    update_parser.add_argument('--new-email', help='新邮箱')
    update_parser.add_argument('--new-password', help='新密码')

    delete_parser = subparsers.add_parser('delete', help='删除用户')
    delete_parser.add_argument('email', help='用户邮箱')

    superuser_parser = subparsers.add_parser('superuser', help='设置/取消超级用户权限')
    superuser_parser.add_argument('email', help='用户邮箱')
    superuser_parser.add_argument('is_superuser', choices=['true', 'false'], help='是否为超级用户')

    staff_parser = subparsers.add_parser('staff', help='设置/取消员工权限')
    staff_parser.add_argument('email', help='用户邮箱')
    staff_parser.add_argument('is_staff', choices=['true', 'false'], help='是否为员工')

    active_parser = subparsers.add_parser('active', help='激活/停用用户')
    active_parser.add_argument('email', help='用户邮箱')
    active_parser.add_argument('is_active', choices=['true', 'false'], help='是否激活')

    reset_password_parser = subparsers.add_parser('reset-password', help='重置用户密码')
    reset_password_parser.add_argument('email', help='用户邮箱')
    reset_password_parser.add_argument('new_password', nargs='?', help='新密码 (可选)')

    org_parser = subparsers.add_parser('organizations', help='显示用户的组织')
    org_parser.add_argument('email', help='用户邮箱')

    # 组织相关命令
    create_org_parser = subparsers.add_parser('create-org', help='创建新组织')
    create_org_parser.add_argument('name', help='组织名称')

    add_to_org_parser = subparsers.add_parser('add-to-org', help='将用户添加到组织')
    add_to_org_parser.add_argument('email', help='用户邮箱')
    add_to_org_parser.add_argument('org_name', help='组织名称')

    remove_from_org_parser = subparsers.add_parser('remove-from-org', help='将用户从组织中移除')
    remove_from_org_parser.add_argument('email', help='用户邮箱')
    remove_from_org_parser.add_argument('org_name', help='组织名称')

    subparsers.add_parser('list-orgs', help='列出所有组织')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    # 执行对应命令
    user_manager = UserManager()
    org_manager = OrganizationManager()

    success = False

    if args.command == 'create':
        success = user_manager.create_user(args.username, args.email, args.password)
    elif args.command == 'list':
        user_manager.list_users()
        success = True
    elif args.command == 'info':
        success = user_manager.show_user_info(args.email)
    elif args.command == 'update':
        success = user_manager.update_user(args.email, args.new_email, args.new_password)
    elif args.command == 'delete':
        success = user_manager.delete_user(args.email)
    elif args.command == 'superuser':
        success = user_manager.set_superuser(args.email, args.is_superuser)
    elif args.command == 'staff':
        success = user_manager.set_staff(args.email, args.is_staff)
    elif args.command == 'active':
        success = user_manager.set_active(args.email, args.is_active)
    elif args.command == 'reset-password':
        success = user_manager.reset_password(args.email, args.new_password)
    elif args.command == 'organizations':
        success = user_manager.show_user_organizations(args.email)
    elif args.command == 'create-org':
        success = org_manager.create_organization(args.name)
    elif args.command == 'add-to-org':
        success = org_manager.add_user_to_organization(args.email, args.org_name)
    elif args.command == 'remove-from-org':
        success = org_manager.remove_user_from_organization(args.email, args.org_name)
    elif args.command == 'list-orgs':
        org_manager.list_organizations()
        success = True

    if not success:
        sys.exit(1)

if __name__ == '__main__':
    main()