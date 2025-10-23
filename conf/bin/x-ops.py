#!/usr/bin/env python3
"""
Glitchtip 配置管理脚本
用于在容器内进行配置数据的导出和导入操作
支持无状态K8s部署环境下的配置备份和恢复
"""

import os
import sys
import json
import argparse
import datetime
import uuid
import django
from decimal import Decimal
from typing import Dict, List, Any, Optional
from django.core.exceptions import ValidationError
from django.db import transaction
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

from django.conf import settings
from apps.organizations_ext.models import Organization, OrganizationUser, OrganizationOwner
from apps.organizations_ext.constants import OrganizationUserRole
from apps.projects.models import Project, ProjectKey, ProjectCounter, UserProjectAlert
from apps.teams.models import Team
from apps.alerts.models import ProjectAlert, AlertRecipient
from apps.environments.models import Environment, EnvironmentProject
from apps.api_tokens.models import APIToken

User = get_user_model()

class ConfigExporter:
    """配置导出类"""

    def __init__(self):
        self.export_data = {
            'metadata': {
                'version': '1.0',
                'export_time': datetime.datetime.now().isoformat(),
                'glitchtip_url': getattr(settings, 'GLITCHTIP_URL', ''),
                'description': 'Glitchtip Configuration Export'
            },
            'data': {}
        }

    def serialize_model(self, model_instance, exclude_fields=None):
        """序列化Django模型实例"""
        if exclude_fields is None:
            exclude_fields = []

        data = {}
        for field in model_instance._meta.fields:
            field_name = field.name
            if field_name in exclude_fields:
                continue

            value = getattr(model_instance, field_name)

            # 处理特殊字段类型
            if value is None:
                data[field_name] = None
            elif isinstance(value, (int, float, str, bool)):
                data[field_name] = value
            elif isinstance(value, Decimal):
                data[field_name] = str(value)
            elif isinstance(value, datetime.datetime):
                data[field_name] = value.isoformat()
            elif isinstance(value, uuid.UUID):
                data[field_name] = str(value)
            elif hasattr(value, 'pk'):  # ForeignKey
                data[field_name] = value.pk if value else None
            elif isinstance(value, dict):  # JSONField
                data[field_name] = value
            else:
                data[field_name] = str(value)

        return data

    def export_users(self):
        """导出用户数据"""
        print("正在导出用户数据...")
        users = []
        for user in User.objects.all():
            user_data = self.serialize_model(user, exclude_fields=['password'])
            # 保持密码字段，但标记为已加密
            user_data['password_hash'] = user.password
            users.append(user_data)

        self.export_data['data']['users'] = users
        print(f"已导出 {len(users)} 个用户")

    def export_organizations(self):
        """导出组织数据"""
        print("正在导出组织数据...")
        organizations = []
        org_users = []
        org_owners = []

        for org in Organization.objects.all():
            org_data = self.serialize_model(org)
            organizations.append(org_data)

            # 导出组织用户关系
            for org_user in org.organization_users.all():
                org_user_data = self.serialize_model(org_user)
                org_user_data['user_email'] = org_user.user.email if org_user.user else org_user.email
                org_users.append(org_user_data)

            # 导出组织所有者
            if hasattr(org, 'owner') and org.owner:
                owner_data = self.serialize_model(org.owner)
                org_owners.append(owner_data)

        self.export_data['data']['organizations'] = organizations
        self.export_data['data']['organization_users'] = org_users
        self.export_data['data']['organization_owners'] = org_owners

        print(f"已导出 {len(organizations)} 个组织, {len(org_users)} 个组织用户关系")

    def export_projects(self):
        """导出项目数据"""
        print("正在导出项目数据...")
        projects = []
        project_keys = []
        project_counters = []

        for project in Project.objects.all():
            project_data = self.serialize_model(project)
            project_data['organization_slug'] = project.organization.slug
            projects.append(project_data)

            # 导出项目密钥
            for project_key in project.projectkey_set.all():
                key_data = self.serialize_model(project_key)
                # 生成当前DSN
                key_data['current_dsn'] = project_key.get_dsn()
                project_keys.append(key_data)

            # 导出项目计数器
            counter = ProjectCounter.objects.filter(project=project).first()
            if counter:
                counter_data = self.serialize_model(counter)
                project_counters.append(counter_data)

        self.export_data['data']['projects'] = projects
        self.export_data['data']['project_keys'] = project_keys
        self.export_data['data']['project_counters'] = project_counters

        print(f"已导出 {len(projects)} 个项目, {len(project_keys)} 个项目密钥")

    def export_teams(self):
        """导出团队数据"""
        print("正在导出团队数据...")
        teams = []

        for team in Team.objects.all():
            team_data = self.serialize_model(team)
            team_data['organization_slug'] = team.organization.slug
            team_data['member_emails'] = [
                org_user.user.email if org_user.user else org_user.email
                for org_user in team.members.all()
            ]
            team_data['project_slugs'] = [project.slug for project in team.projects.all()]
            teams.append(team_data)

        self.export_data['data']['teams'] = teams
        print(f"已导出 {len(teams)} 个团队")

    def export_alerts(self):
        """导出告警配置"""
        print("正在导出告警配置...")
        project_alerts = []
        alert_recipients = []

        for alert in ProjectAlert.objects.all():
            alert_data = self.serialize_model(alert)
            alert_data['project_slug'] = alert.project.slug
            project_alerts.append(alert_data)

            # 导出告警接收者
            for recipient in alert.alertrecipient_set.all():
                recipient_data = self.serialize_model(recipient)
                alert_recipients.append(recipient_data)

        self.export_data['data']['project_alerts'] = project_alerts
        self.export_data['data']['alert_recipients'] = alert_recipients

        print(f"已导出 {len(project_alerts)} 个告警规则, {len(alert_recipients)} 个告警接收者")

    def export_environments(self):
        """导出环境配置"""
        print("正在导出环境配置...")
        environments = []
        env_projects = []

        for env in Environment.objects.all():
            env_data = self.serialize_model(env)
            env_data['organization_slug'] = env.organization.slug
            environments.append(env_data)

            # 导出环境项目关联
            for env_proj in env.environmentproject_set.all():
                env_proj_data = self.serialize_model(env_proj)
                env_proj_data['project_slug'] = env_proj.project.slug
                env_proj_data['environment_name'] = env_proj.environment.name
                env_projects.append(env_proj_data)

        self.export_data['data']['environments'] = environments
        self.export_data['data']['environment_projects'] = env_projects

        print(f"已导出 {len(environments)} 个环境, {len(env_projects)} 个环境项目关联")

    def export_api_tokens(self):
        """导出API令牌"""
        print("正在导出API令牌...")
        api_tokens = []

        for token in APIToken.objects.all():
            token_data = self.serialize_model(token)
            token_data['user_email'] = token.user.email
            # 将BitField转换为权限列表
            token_data['scopes_list'] = token.get_scopes()
            api_tokens.append(token_data)

        self.export_data['data']['api_tokens'] = api_tokens
        print(f"已导出 {len(api_tokens)} 个API令牌")

    def export_user_project_alerts(self):
        """导出用户项目告警设置"""
        print("正在导出用户项目告警设置...")
        user_project_alerts = []

        for alert in UserProjectAlert.objects.all():
            alert_data = self.serialize_model(alert)
            alert_data['user_email'] = alert.user.email
            alert_data['project_slug'] = alert.project.slug
            user_project_alerts.append(alert_data)

        self.export_data['data']['user_project_alerts'] = user_project_alerts
        print(f"已导出 {len(user_project_alerts)} 个用户项目告警设置")

    def export_all(self):
        """导出所有配置数据"""
        try:
            self.export_users()
            self.export_organizations()
            self.export_projects()
            self.export_teams()
            self.export_alerts()
            self.export_environments()
            self.export_api_tokens()
            self.export_user_project_alerts()

            return True
        except Exception as e:
            print(f"导出失败: {str(e)}")
            return False

    def get_export_data(self):
        """获取导出数据"""
        return self.export_data

class ConfigImporter:
    """配置导入类"""

    def __init__(self, dry_run=False):
        self.dry_run = dry_run
        self.import_stats = {
            'users': 0,
            'organizations': 0,
            'projects': 0,
            'teams': 0,
            'alerts': 0,
            'environments': 0,
            'api_tokens': 0,
            'errors': []
        }
        self.email_to_user = {}
        self.slug_to_org = {}
        self.slug_to_project = {}

    def log_error(self, message):
        """记录错误信息"""
        error_msg = f"ERROR: {message}"
        self.import_stats['errors'].append(error_msg)
        print(error_msg)

    def log_info(self, message):
        """记录信息"""
        if not self.dry_run:
            print(f"INFO: {message}")

    def log_dry_run(self, message):
        """记录试运行信息"""
        if self.dry_run:
            print(f"DRY-RUN: {message}")

    def import_users(self, users_data):
        """导入用户数据"""
        print("正在导入用户数据...")

        for user_data in users_data:
            try:
                email = user_data['email']
                password_hash = user_data.get('password_hash', '')

                user = None

                if not self.dry_run:
                    # 检查用户是否已存在
                    if User.objects.filter(email=email).exists():
                        user = User.objects.get(email=email)
                        self.log_info(f"用户 {email} 已存在，跳过创建")
                    else:
                        # 创建用户，保持原密码哈希
                        user = User.objects.create(
                            email=email,
                            name=user_data.get('name', ''),
                            is_staff=user_data.get('is_staff', False),
                            is_superuser=user_data.get('is_superuser', False),
                            is_active=user_data.get('is_active', True),
                            password=password_hash,  # 直接使用原密码哈希
                            analytics=user_data.get('analytics'),
                            subscribe_by_default=user_data.get('subscribe_by_default', True),
                            options=user_data.get('options', {})
                        )
                        self.log_info(f"创建用户: {email}")
                else:
                    self.log_dry_run(f"Would create user: {email}")

                if user:
                    self.email_to_user[email] = user
                self.import_stats['users'] += 1

            except Exception as e:
                self.log_error(f"导入用户失败 {user_data.get('email', 'unknown')}: {str(e)}")

    def import_organizations(self, orgs_data, org_users_data, org_owners_data):
        """导入组织数据"""
        print("正在导入组织数据...")

        # 先导入组织
        for org_data in orgs_data:
            try:
                slug = org_data['slug']
                name = org_data['name']

                org = None

                if not self.dry_run:
                    # 检查组织是否已存在
                    if Organization.objects.filter(slug=slug).exists():
                        org = Organization.objects.get(slug=slug)
                        self.log_info(f"组织 {slug} 已存在，跳过创建")
                    else:
                        org = Organization.objects.create(
                            name=name,
                            slug=slug,
                            is_accepting_events=org_data.get('is_accepting_events', True),
                            event_throttle_rate=org_data.get('event_throttle_rate', 0),
                            open_membership=org_data.get('open_membership', True),
                            scrub_ip_addresses=org_data.get('scrub_ip_addresses', True)
                        )
                        self.log_info(f"创建组织: {name} ({slug})")
                else:
                    self.log_dry_run(f"Would create organization: {name} ({slug})")

                if org:
                    self.slug_to_org[slug] = org
                self.import_stats['organizations'] += 1

            except Exception as e:
                self.log_error(f"导入组织失败 {org_data.get('slug', 'unknown')}: {str(e)}")

        # 然后导入组织用户关系
        for org_user_data in org_users_data:
            try:
                user_email = org_user_data.pop('user_email', '')
                org_slug = org_user_data.get('organization_id')  # 这里存储的是slug
                role = org_user_data.get('role', OrganizationUserRole.MEMBER)

                if org_slug not in self.slug_to_org:
                    self.log_error(f"组织不存在: {org_slug}")
                    continue

                if user_email not in self.email_to_user:
                    self.log_error(f"用户不存在: {user_email}")
                    continue

                self.log_dry_run(f"Would add user {user_email} to organization {org_slug}")

                if not self.dry_run:
                    org = self.slug_to_org[org_slug]
                    user = self.email_to_user[user_email]

                    # 检查关系是否已存在
                    if OrganizationUser.objects.filter(user=user, organization=org).exists():
                        self.log_info(f"用户 {user_email} 已在组织 {org_slug} 中")
                    else:
                        org_user = OrganizationUser.objects.create(
                            user=user,
                            organization=org,
                            role=role,
                            email=org_user_data.get('email', '')
                        )
                        self.log_info(f"添加用户 {user_email} 到组织 {org_slug}")

            except Exception as e:
                self.log_error(f"导入组织用户关系失败: {str(e)}")

    def import_projects(self, projects_data, project_keys_data, project_counters_data):
        """导入项目数据"""
        print("正在导入项目数据...")

        # 先导入项目
        for project_data in projects_data:
            try:
                name = project_data['name']
                slug = project_data['slug']
                org_slug = project_data.pop('organization_slug', '')

                if org_slug not in self.slug_to_org:
                    self.log_error(f"项目 {slug} 的组织 {org_slug} 不存在")
                    continue

                self.log_dry_run(f"Would create project: {name} ({slug})")

                if not self.dry_run:
                    org = self.slug_to_org[org_slug]

                    # 检查项目是否已存在
                    if Project.objects.filter(slug=slug, organization=org).exists():
                        project = Project.objects.get(slug=slug, organization=org)
                        self.log_info(f"项目 {slug} 已存在，跳过创建")
                    else:
                        project = Project.objects.create(
                            name=name,
                            slug=slug,
                            organization=org,
                            platform=project_data.get('platform', ''),
                            scrub_ip_addresses=project_data.get('scrub_ip_addresses', True),
                            event_throttle_rate=project_data.get('event_throttle_rate', 0)
                        )
                        self.log_info(f"创建项目: {name} ({slug})")

                self.slug_to_project[slug] = project
                self.import_stats['projects'] += 1

            except Exception as e:
                self.log_error(f"导入项目失败 {project_data.get('slug', 'unknown')}: {str(e)}")

        # 然后导入项目密钥
        for key_data in project_keys_data:
            try:
                project_slug = key_data.get('project_id')  # 这里存储的是slug
                public_key = key_data.get('public_key')

                project = self.slug_to_project.get(project_slug)
                if not project:
                    self.log_error(f"项目密钥的项目 {project_slug} 不存在")
                    continue

                self.log_dry_run(f"Would create project key for {project_slug}")

                if not self.dry_run:
                    # 检查密钥是否已存在
                    if ProjectKey.objects.filter(public_key=public_key).exists():
                        self.log_info(f"项目密钥 {public_key} 已存在，跳过创建")
                    else:
                        project_key = ProjectKey.objects.create(
                            project=project,
                            public_key=public_key,
                            name=key_data.get('name', ''),
                            is_active=key_data.get('is_active', True),
                            rate_limit_count=key_data.get('rate_limit_count'),
                            rate_limit_window=key_data.get('rate_limit_window'),
                            data=key_data.get('data', {})
                        )
                        self.log_info(f"创建项目密钥: {public_key}")
                        # DSN会根据当前GLITCHTIP_URL自动生成

            except Exception as e:
                self.log_error(f"导入项目密钥失败: {str(e)}")

        # 最后导入项目计数器
        for counter_data in project_counters_data:
            try:
                project_slug = counter_data.get('project_id')  # 这里存储的是slug
                project = self.slug_to_project.get(project_slug)

                if not project:
                    self.log_error(f"项目计数器的项目 {project_slug} 不存在")
                    continue

                self.log_dry_run(f"Would create project counter for {project_slug}")

                if not self.dry_run:
                    # 检查计数器是否已存在
                    if ProjectCounter.objects.filter(project=project).exists():
                        self.log_info(f"项目计数器已存在，跳过创建")
                    else:
                        counter = ProjectCounter.objects.create(
                            project=project,
                            value=counter_data.get('value', 1)
                        )
                        self.log_info(f"创建项目计数器")

            except Exception as e:
                self.log_error(f"导入项目计数器失败: {str(e)}")

    def import_teams(self, teams_data):
        """导入团队数据"""
        print("正在导入团队数据...")

        for team_data in teams_data:
            try:
                slug = team_data['slug']
                org_slug = team_data.get('organization_slug', '')
                member_emails = team_data.pop('member_emails', [])
                project_slugs = team_data.pop('project_slugs', [])

                if org_slug not in self.slug_to_org:
                    self.log_error(f"团队 {slug} 的组织 {org_slug} 不存在")
                    continue

                self.log_dry_run(f"Would create team: {slug}")

                if not self.dry_run:
                    org = self.slug_to_org[org_slug]

                    # 检查团队是否已存在
                    if Team.objects.filter(slug=slug, organization=org).exists():
                        team = Team.objects.get(slug=slug, organization=org)
                        self.log_info(f"团队 {slug} 已存在，跳过创建")
                    else:
                        team = Team.objects.create(
                            slug=slug,
                            organization=org
                        )
                        self.log_info(f"创建团队: {slug}")

                    # 添加成员
                    for email in member_emails:
                        if email in self.email_to_user:
                            user = self.email_to_user[email]
                            org_user = OrganizationUser.objects.filter(user=user, organization=org).first()
                            if org_user:
                                team.members.add(org_user)

                    # 添加项目
                    for project_slug in project_slugs:
                        if project_slug in self.slug_to_project:
                            project = self.slug_to_project[project_slug]
                            team.projects.add(project)

                self.import_stats['teams'] += 1

            except Exception as e:
                self.log_error(f"导入团队失败 {team_data.get('slug', 'unknown')}: {str(e)}")

    def import_alerts(self, alerts_data, recipients_data):
        """导入告警配置"""
        print("正在导入告警配置...")

        # 先导入告警规则
        for alert_data in alerts_data:
            try:
                project_slug = alert_data.get('project_slug', '')
                project = self.slug_to_project.get(project_slug)

                if not project:
                    self.log_error(f"告警规则的项目 {project_slug} 不存在")
                    continue

                self.log_dry_run(f"Would create alert for project {project_slug}")

                if not self.dry_run:
                    alert = ProjectAlert.objects.create(
                        project=project,
                        name=alert_data.get('name', ''),
                        timespan_minutes=alert_data.get('timespan_minutes'),
                        quantity=alert_data.get('quantity'),
                        uptime=alert_data.get('uptime', False)
                    )
                    self.log_info(f"创建告警规则: {alert.name}")

                self.import_stats['alerts'] += 1

            except Exception as e:
                self.log_error(f"导入告警规则失败: {str(e)}")

        # 然后导入告警接收者（这里简化处理，实际可能需要更复杂的关联）
        for recipient_data in recipients_data:
            try:
                if not self.dry_run:
                    # 简化处理，实际需要根据告警规则关联
                    pass
            except Exception as e:
                self.log_error(f"导入告警接收者失败: {str(e)}")

    def import_environments(self, envs_data, env_projects_data):
        """导入环境配置"""
        print("正在导入环境配置...")

        # 先导入环境
        for env_data in envs_data:
            try:
                name = env_data['name']
                org_slug = env_data.get('organization_slug', '')

                if org_slug not in self.slug_to_org:
                    self.log_error(f"环境 {name} 的组织 {org_slug} 不存在")
                    continue

                self.log_dry_run(f"Would create environment: {name}")

                if not self.dry_run:
                    org = self.slug_to_org[org_slug]

                    # 检查环境是否已存在
                    if Environment.objects.filter(name=name, organization=org).exists():
                        env = Environment.objects.get(name=name, organization=org)
                        self.log_info(f"环境 {name} 已存在，跳过创建")
                    else:
                        env = Environment.objects.create(
                            name=name,
                            organization=org
                        )
                        self.log_info(f"创建环境: {name}")

                self.import_stats['environments'] += 1

            except Exception as e:
                self.log_error(f"导入环境失败 {env_data.get('name', 'unknown')}: {str(e)}")

        # 然后导入环境项目关联
        for env_proj_data in env_projects_data:
            try:
                project_slug = env_proj_data.get('project_slug', '')
                env_name = env_proj_data.get('environment_name', '')

                project = self.slug_to_project.get(project_slug)
                if not project:
                    self.log_error(f"环境项目关联的项目 {project_slug} 不存在")
                    continue

                env = Environment.objects.filter(name=env_name, organization=project.organization).first()
                if not env:
                    self.log_error(f"环境 {env_name} 不存在")
                    continue

                if not self.dry_run:
                    # 检查关联是否已存在
                    if EnvironmentProject.objects.filter(project=project, environment=env).exists():
                        self.log_info(f"环境项目关联已存在")
                    else:
                        env_proj = EnvironmentProject.objects.create(
                            project=project,
                            environment=env,
                            is_hidden=env_proj_data.get('is_hidden', False)
                        )
                        self.log_info(f"创建环境项目关联")

            except Exception as e:
                self.log_error(f"导入环境项目关联失败: {str(e)}")

    def import_api_tokens(self, tokens_data):
        """导入API令牌"""
        print("正在导入API令牌...")

        for token_data in tokens_data:
            try:
                user_email = token_data.get('user_email', '')
                token = token_data.get('token', '')
                label = token_data.get('label', '')
                scopes_list = token_data.get('scopes_list', [])

                if user_email not in self.email_to_user:
                    self.log_error(f"API令牌的用户 {user_email} 不存在")
                    continue

                self.log_dry_run(f"Would create API token for {user_email}")

                if not self.dry_run:
                    user = self.email_to_user[user_email]

                    # 检查令牌是否已存在
                    if APIToken.objects.filter(token=token).exists():
                        self.log_info(f"API令牌已存在，跳过创建")
                    else:
                        api_token = APIToken.objects.create(
                            token=token,
                            user=user,
                            label=label
                        )
                        # 设置权限范围
                        if scopes_list:
                            api_token.add_permissions(scopes_list)
                        self.log_info(f"创建API令牌: {label}")

                self.import_stats['api_tokens'] += 1

            except Exception as e:
                self.log_error(f"导入API令牌失败: {str(e)}")

    def import_all(self, export_data):
        """导入所有配置数据"""
        try:
            with transaction.atomic():
                if self.dry_run:
                    print("=== 试运行模式，不会实际修改数据 ===")

                data = export_data.get('data', {})

                # 按依赖顺序导入
                if 'users' in data:
                    self.import_users(data['users'])

                if 'organizations' in data and 'organization_users' in data:
                    self.import_organizations(
                        data['organizations'],
                        data['organization_users'],
                        data.get('organization_owners', [])
                    )

                if 'projects' in data:
                    self.import_projects(
                        data['projects'],
                        data.get('project_keys', []),
                        data.get('project_counters', [])
                    )

                if 'teams' in data:
                    self.import_teams(data['teams'])

                if 'environments' in data:
                    self.import_environments(
                        data['environments'],
                        data.get('environment_projects', [])
                    )

                if 'project_alerts' in data:
                    self.import_alerts(
                        data['project_alerts'],
                        data.get('alert_recipients', [])
                    )

                if 'api_tokens' in data:
                    self.import_api_tokens(data['api_tokens'])

                if self.dry_run:
                    print("=== 试运行完成，未修改任何数据 ===")
                    return True

                return True

        except Exception as e:
            self.log_error(f"导入失败: {str(e)}")
            return False

    def print_stats(self):
        """打印导入统计信息"""
        print("\n=== 导入统计 ===")
        print(f"用户: {self.import_stats['users']}")
        print(f"组织: {self.import_stats['organizations']}")
        print(f"项目: {self.import_stats['projects']}")
        print(f"团队: {self.import_stats['teams']}")
        print(f"告警: {self.import_stats['alerts']}")
        print(f"环境: {self.import_stats['environments']}")
        print(f"API令牌: {self.import_stats['api_tokens']}")

        if self.import_stats['errors']:
            print(f"错误: {len(self.import_stats['errors'])}")
            for error in self.import_stats['errors']:
                print(f"  - {error}")

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='Glitchtip 配置管理脚本')
    subparsers = parser.add_subparsers(dest='command', help='可用命令')

    # 导出命令
    export_parser = subparsers.add_parser('export', help='导出配置数据')
    export_parser.add_argument('--output', '-o', help='输出文件路径 (默认输出到标准输出)')
    export_parser.add_argument('--format', choices=['json'], default='json', help='输出格式')

    # 导入命令
    import_parser = subparsers.add_parser('import', help='导入配置数据')
    import_parser.add_argument('input_file', nargs='?', help='输入文件路径 (默认从标准输入读取)')
    import_parser.add_argument('--dry-run', action='store_true', help='试运行模式，不实际修改数据')
    import_parser.add_argument('--format', choices=['json'], default='json', help='输入格式')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    success = False

    if args.command == 'export':
        print("开始导出配置数据...")
        exporter = ConfigExporter()

        if exporter.export_all():
            export_data = exporter.get_export_data()
            output_json = json.dumps(export_data, indent=2, ensure_ascii=False)

            if args.output:
                try:
                    with open(args.output, 'w', encoding='utf-8') as f:
                        f.write(output_json)
                    print(f"配置已导出到: {args.output}")
                    success = True
                except Exception as e:
                    print(f"写入文件失败: {str(e)}")
            else:
                print(output_json)
                success = True
        else:
            print("导出失败")

    elif args.command == 'import':
        print("开始导入配置数据...")

        # 读取输入数据
        if args.input_file:
            try:
                with open(args.input_file, 'r', encoding='utf-8') as f:
                    export_data = json.load(f)
            except Exception as e:
                print(f"读取文件失败: {str(e)}")
                sys.exit(1)
        else:
            try:
                input_data = sys.stdin.read()
                if not input_data.strip():
                    print("错误: 没有输入数据")
                    sys.exit(1)
                export_data = json.loads(input_data)
            except json.JSONDecodeError as e:
                print(f"JSON格式错误: {str(e)}")
                sys.exit(1)

        # 验证导出数据格式
        if 'data' not in export_data:
            print("错误: 无效的导出数据格式")
            sys.exit(1)

        importer = ConfigImporter(dry_run=args.dry_run)
        if importer.import_all(export_data):
            importer.print_stats()
            success = True
        else:
            print("导入失败")

    if not success:
        sys.exit(1)

if __name__ == '__main__':
    main()