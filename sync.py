#!/usr/bin/env python3
import os
import json
import shutil
import subprocess
import sys
from pathlib import Path
from github import Github

CONFIG_FILE = Path(__file__).parent / 'sync-config.json'
TEMP_DIR = Path(__file__).parent / 'temp'

def load_config():
    """加载配置文件"""
    if not CONFIG_FILE.exists():
        print(f'❌ 配置文件不存在: {CONFIG_FILE}')
        sys.exit(1)
    
    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        if not config.get('sourceRepos') or not isinstance(config['sourceRepos'], list) or len(config['sourceRepos']) == 0:
            print('❌ 配置文件中 sourceRepos 数组为空或格式错误')
            sys.exit(1)
        
        return config
    except Exception as e:
        print(f'❌ 读取配置文件失败: {e}')
        sys.exit(1)

def get_repo_info(url):
    """解析仓库URL"""
    import re
    match = re.match(r'https://github\.com/(.*?)/(.*?)(?:\.git)?$', url)
    if not match:
        raise ValueError(f'无效的 GitHub 仓库 URL: {url}')
    return {'owner': match.group(1), 'repo': match.group(2)}

def get_default_branch(github_client, owner, repo):
    """获取仓库的默认分支"""
    try:
        repo_obj = github_client.get_repo(f'{owner}/{repo}')
        return repo_obj.default_branch
    except Exception as e:
        print(f'   ❌ 获取默认分支失败: {e}')
        raise

def clone_repository(url, target_dir, branch):
    """克隆仓库"""
    try:
        subprocess.run([
            'git', 'clone', '--single-branch', '--branch', branch, url, str(target_dir)
        ], check=True, capture_output=True, text=True)
        return branch
    except subprocess.CalledProcessError as e:
        if 'not found' in e.stderr or 'does not exist' in e.stderr:
            print(f'   ⚠️  分支 {branch} 不存在，尝试获取默认分支')
            return None
        raise

def remove_workflows(repo_dir):
    """删除工作流文件"""
    workflows_dir = repo_dir / '.github' / 'workflows'
    if workflows_dir.exists():
        print('   🗑️  删除 .github/workflows 目录（避免权限问题）')
        
        try:
            result = subprocess.run([
                'git', 'ls-files', '.github/workflows'
            ], check=False, capture_output=True, text=True, cwd=str(repo_dir))
            
            if result.stdout.strip():
                subprocess.run([
                    'git', 'rm', '-r', '-f', '.github/workflows'
                ], check=True, capture_output=True, text=True, cwd=str(repo_dir))
                print('   🧹 从 Git 索引中移除工作流文件')
            else:
                print('   ℹ️  .github/workflows 目录不在 Git 索引中，直接删除')
        except subprocess.CalledProcessError as e:
            print(f'   ⚠️  清理 Git 索引时出错（可忽略）: {e}')
        
        shutil.rmtree(workflows_dir)

def sync_repository(repo_config, github_client, target_repo, github_token):
    """同步单个仓库"""
    repo_url = repo_config['repoUrl']
    source_branch = repo_config.get('sourceBranch', 'main')
    target_branch = repo_config.get('targetBranch', repo_config.get('repoName', ''))
    repo_name = repo_config['repoName']
    
    temp_dir = TEMP_DIR / repo_name
    
    print(f'\n🔄 同步仓库: {repo_name}')
    print(f'   源: {repo_url} ({source_branch})')
    print(f'   目标: {target_repo} ({target_branch})')
    
    actual_branch = source_branch
    
    try:
        actual_branch = clone_repository(repo_url, temp_dir, actual_branch)
        
        if actual_branch is None:
            repo_info = get_repo_info(repo_url)
            actual_branch = get_default_branch(github_client, repo_info['owner'], repo_info['repo'])
            print(f'   🔍 找到默认分支: {actual_branch}')
            
            clone_repository(repo_url, temp_dir, actual_branch)
        
        subprocess.run([
            'git', 'pull', 'origin', actual_branch
        ], check=True, capture_output=True, text=True, cwd=str(temp_dir))
        
        remove_workflows(temp_dir)
        
        target_url = f'https://x-access-token:{github_token}@github.com/{target_repo}.git'
        subprocess.run([
            'git', 'push', '--force', target_url, f'{actual_branch}:{target_branch}'
        ], check=True, capture_output=True, text=True, cwd=str(temp_dir))
        
        print(f'   ✅ 同步成功: {actual_branch} -> {target_branch}')
        
    except Exception as e:
        print(f'   ❌ 同步失败: {e}')
        raise
    finally:
        if temp_dir.exists():
            shutil.rmtree(temp_dir)

def main():
    """主函数"""
    config = load_config()
    source_repos = config['sourceRepos']
    target_repo = config['targetRepo']
    github_token = os.getenv('GITHUB_TOKEN')
    
    if not github_token:
        print('❌ 缺少 GITHUB_TOKEN 环境变量')
        sys.exit(1)
    
    if not target_repo:
        print('❌ 配置文件中缺少 targetRepo 字段')
        sys.exit(1)
    
    github_client = Github(github_token)
    
    print('🚀 开始同步仓库...')
    print(f'📋 目标仓库: {target_repo}')
    print(f'📦 源仓库数量: {len(source_repos)}')
    print('💡 提示: 已自动排除 .github/workflows 目录以避免权限问题')
    
    success_count = 0
    fail_count = 0
    
    for repo_config in source_repos:
        try:
            sync_repository(repo_config, github_client, target_repo, github_token)
            success_count += 1
        except Exception as e:
            fail_count += 1
            print(f'\n❌ 仓库 {repo_config["repoName"]} 同步失败，继续处理下一个仓库')
    
    print('\n📊 同步统计:')
    print(f'   ✅ 成功: {success_count}')
    print(f'   ❌ 失败: {fail_count}')
    print(f'   📦 总计: {len(source_repos)}')
    
    if fail_count > 0:
        print('\n⚠️  部分仓库同步失败')
        sys.exit(1)
    else:
        print('\n🎉 所有仓库同步成功！')

if __name__ == '__main__':
    main()