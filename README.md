# GitHub 仓库同步项目

自动同步多个 GitHub 公开仓库到单个仓库的不同分支。

## 功能特性

- ✅ 定时自动同步（每天凌晨 2 点 UTC）
- ✅ 支持手动触发同步
- ✅ 配置文件更新后自动同步
- ✅ 详细的同步报告
- ✅ 支持多个源仓库
- ✅ 每个源仓库同步到独立分支
- ✅ 使用 Bash 脚本，简单可靠

## 使用方法

### 1. 创建仓库

在 GitHub 上创建一个名为 `github-sync` 的仓库。

### 2. 配置权限

确保 GitHub Actions 有写入权限：
- 进入仓库 Settings → Actions → General
- 在 "Workflow permissions" 中选择 "Read and write permissions"
- 勾选 "Allow GitHub Actions to create and approve pull requests"

### 3. 上传项目文件

将所有文件上传到仓库：
```bash
git clone https://github.com/xztxy/github-sync.git
cd github-sync
# 复制所有项目文件到这里
git add .
git commit -m "Initial commit"
git push
```

### 4. 修改配置

编辑 `config/repos.json` 文件，添加或修改要同步的仓库。

### 5. 手动触发同步

- 进入仓库的 Actions 标签
- 选择 "Sync Repositories" 工作流
- 点击 "Run workflow" 按钮

## 配置说明

`config/repos.json` 文件格式：
```json
{
  "targetRepo": "用户名/仓库名",
  "sourceRepos": [
    {
      "repoUrl": "源仓库URL",
      "sourceBranch": "源分支名",
      "targetBranch": "目标分支名",
      "repoName": "仓库显示名称"
    }
  ]
}
```

## 查看同步报告

每次同步后，可以在 Actions 运行记录中：
1. 查看运行日志
2. 下载 `sync-report` 附件查看详细报告

## 定时设置

默认每天 UTC 时间 02:00 运行（北京时间 10:00）。

修改 `.github/workflows/sync.yml` 中的 cron 表达式来调整时间：
```yaml
schedule:
  - cron: '0 2 * * *'  # 分 时 日 月 周
```

## 注意事项

- 确保源仓库是公开的
- 同步会强制覆盖目标分支
- 大型仓库首次同步可能需要较长时间
- GitHub Actions 有使用限制，请合理设置同步频率

## License

MIT License