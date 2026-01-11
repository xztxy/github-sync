# GitHub Repository Sync

一个使用GitHub Actions每天定时将指定GitHub仓库同步到目标仓库不同分支的工具。

## 功能特性

- 📅 每天自动运行（可自定义时间）
- 🔄 支持将源仓库的多个分支同步到目标仓库的不同分支
- 🎯 精确的分支映射配置
- 🔧 支持手动触发同步
- 📋 详细的日志输出

## 配置说明

### 1. 环境变量

在GitHub仓库的`Settings > Secrets and variables > Actions`中添加以下 secrets：

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `SOURCE_REPOS` | 源仓库配置（JSON格式），支持多个源仓库 | `[{"repoUrl":"https://github.com/username/repo-a.git","sourceBranch":"main","targetBranch":"repo-a"}]` |
| `GITHUB_TOKEN` | GitHub Token（自动提供，无需手动添加） | - |

**注意**：目标仓库默认为当前仓库，无需配置`TARGET_REPO`环境变量。

### 2. 源仓库配置

`SOURCE_REPOS`是一个JSON数组，用于配置多个源仓库到目标分支的映射关系。每个源仓库配置包含以下字段：

| 字段名 | 说明 | 默认值 | 示例 |
|--------|------|--------|------|
| `repoUrl` | 源仓库地址（HTTPS格式） | 必填 | `https://github.com/username/repo-a.git` |
| `sourceBranch` | 源仓库的分支 | `main` | `main` |
| `targetBranch` | 目标仓库的分支 | 源仓库名称 | `repo-a` |
| `repoName` | 仓库显示名称 | 源仓库名称 | `repo-a` |

例如，将4个开源仓库同步到目标仓库的不同分支：

```json
[
  {
    "repoUrl": "https://github.com/username/repo-a.git",
    "sourceBranch": "main",
    "targetBranch": "repo-a"
  },
  {
    "repoUrl": "https://github.com/username/repo-b.git",
    "sourceBranch": "main",
    "targetBranch": "repo-b"
  },
  {
    "repoUrl": "https://github.com/username/repo-c.git",
    "sourceBranch": "main",
    "targetBranch": "repo-c"
  },
  {
    "repoUrl": "https://github.com/username/repo-d.git",
    "sourceBranch": "main",
    "targetBranch": "repo-d"
  }
]
```

## GitHub Actions设置

### 运行时间

默认情况下，工作流每天UTC时间00:00运行。如需修改运行时间，可编辑`.github/workflows/sync.yml`文件中的cron表达式：

```yaml
on:
  schedule:
    - cron: '0 0 * * *'  # 每天UTC时间00:00运行
```

### 手动触发

工作流支持手动触发，可通过GitHub仓库的`Actions`选项卡手动运行。

## 使用步骤

1. **Fork或克隆本仓库**

2. **配置GitHub Secrets**
   - 进入仓库的`Settings > Secrets and variables > Actions`
   - 添加`SOURCE_REPOS` secret

3. **启用GitHub Actions**
   - 确保仓库的GitHub Actions已启用

4. **等待自动运行或手动触发**
   - 每天定时自动运行
   - 或在`Actions`选项卡手动触发

## 本地开发

### 安装依赖

```bash
npm ci
```

### 本地运行

```bash
# 设置环境变量
export SOURCE_REPOS='[{"repoUrl":"https://github.com/username/repo-a.git","sourceBranch":"main","targetBranch":"repo-a"},{"repoUrl":"https://github.com/username/repo-b.git","sourceBranch":"main","targetBranch":"repo-b"}]'
# TARGET_REPO 可选，如果不设置，需要在 GitHub Actions 环境中运行
export TARGET_REPO="username/target-repo"
export GITHUB_TOKEN="your-github-token"

# 运行同步脚本
node sync.js
```

## 使用示例

以下是将6个指定仓库同步到目标仓库的配置示例：

### 配置JSON

```json
[
  {
    "repoUrl": "https://github.com/Zalafina/QKeyMapper",
    "sourceBranch": "main",
    "targetBranch": "qkeymapper",
    "repoName": "QKeyMapper"
  },
  {
    "repoUrl": "https://github.com/coolsnowwolf/lede",
    "sourceBranch": "master",
    "targetBranch": "lede",
    "repoName": "lede"
  },
  {
    "repoUrl": "https://github.com/immortalwrt/immortalwrt",
    "sourceBranch": "master",
    "targetBranch": "immortalwrt",
    "repoName": "immortalwrt"
  },
  {
    "repoUrl": "https://github.com/x-wrt/x-wrt",
    "sourceBranch": "master",
    "targetBranch": "x-wrt",
    "repoName": "x-wrt"
  },
  {
    "repoUrl": "https://github.com/fanchmwrt/fanchmwrt",
    "sourceBranch": "main",
    "targetBranch": "fanchmwrt",
    "repoName": "fanchmwrt"
  },
  {
    "repoUrl": "https://github.com/kenzok8/openwrt-packages",
    "sourceBranch": "master",
    "targetBranch": "openwrt-packages",
    "repoName": "openwrt-packages"
  },
  {
    "repoUrl": "https://github.com/kenzok8/small-package",
    "sourceBranch": "master",
    "targetBranch": "small-package",
    "repoName": "small-package"
  }
]
```

### 配置说明

| 仓库 | 源分支 | 目标分支 | 说明 |
|------|--------|----------|------|
| QKeyMapper | main | qkeymapper | 按键映射工具 |
| lede | master | lede | Lean's LEDE source |
| immortalwrt | master | immortalwrt | OpenWrt变体 |
| x-wrt | master | x-wrt | OpenWrt fork |
| fanchmwrt | main | fanchmwrt | 家庭防火墙系统 |
| openwrt-packages | master | openwrt-packages | OpenWrt常用软件包 |
| small-package | master | small-package | OpenWrt小软件包 |

## 注意事项

1. **权限要求**
   - 确保GitHub Token具有源仓库的读取权限和目标仓库的写入权限
   - 对于公共仓库，默认的`GITHUB_TOKEN`通常已足够

2. **分支存在性**
   - 脚本会检查源分支是否存在，不存在的分支会跳过
   - 目标分支会自动创建（如果不存在）

3. **强制推送**
   - 脚本使用`--force`选项推送，确保目标分支与源分支完全一致
   - 请谨慎使用，避免覆盖目标分支的重要更改

4. **日志查看**
   - 同步日志可在GitHub Actions的工作流运行记录中查看
   - 包含详细的同步过程和结果

5. **大型仓库处理**
   - 对于大型仓库，同步可能需要较长时间
   - 脚本使用`--depth 1`参数克隆，只获取最新提交，提高效率

## 示例工作流运行

1. 遍历每个源仓库配置
2. 为每个仓库创建独立的临时目录
3. 克隆源仓库的指定分支
4. 拉取最新代码
5. 推送代码到目标仓库的指定分支
6. 清理临时目录

## License

MIT
