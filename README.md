# 🚀 GitHub Repository Sync

**超简化配置** - 只需 `owner/repo` 即可自动同步所有分支！

## ✨ 特性

- 📝 **超简单配置** - 只需 `owner/repo` 格式
- 🔄 **自动检测分支** - 无需手动配置任何分支
- 🏷️ **智能命名** - 自动生成合理的目标分支名
- 🗑️ **自动清理** - 可选删除 workflows 避免权限问题
- 📊 **详细报告** - 完整的同步统计
- ⚡ **快速同步** - 使用 git mirror 一次性同步所有分支

## 🎯 快速开始

### 1. 编辑配置文件

编辑 `config/repos.json`:

```json
{
  "targetRepo": "your-username/github-sync",
  "removeWorkflows": true,
  "sourceRepos": [
    "kenzok8/small-package",
    "coolsnowwolf/lede",
    "immortalwrt/immortalwrt"
  ]
}
```

### 2. 提交配置

```bash
git add config/repos.json
git commit -m "Add new repos to sync"
git push
```

### 3. 自动同步

- 配置文件更新后自动触发
- 每天 UTC 02:00 (北京时间 10:00) 自动运行
- 可手动触发: Actions → Run workflow

## 📋 分支命名规则

| 源仓库分支情况 | 目标分支命名 | 示例 |
|--------------|------------|------|
| 单个分支 | `{repo-name}` | `small-package` |
| 多个分支 | `{repo-name}-{branch}` | `lede-master`, `lede-dev` |

## 📊 同步报告示例

```
========================================
📊 FINAL SUMMARY
========================================
Repositories:
  Total:        7
  ✅ Success:   6
  ⚠️  Failed:     1
Branches:
  Total:        25
  ✅ Success:   23
  ❌ Failed:    2
Success Rate: 92%
========================================
```

## 🔧 配置选项

| 选项 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `targetRepo` | string | ✅ | - | 目标仓库 (owner/repo) |
| `removeWorkflows` | boolean | ❌ | `false` | 是否删除 .github/workflows |
| `sourceRepos` | array | ✅ | - | 源仓库列表 (owner/repo) |

## 📝 添加新仓库

只需在 `sourceRepos` 中添加一行：

```json
{
  "sourceRepos": [
    "existing/repo",
    "new-owner/new-repo"  ← 添加这里
  ]
}
```

## 🔐 权限设置

进入仓库设置：

1. Settings → Actions → General
2. Workflow permissions → **Read and write permissions**
3. ✅ 勾选 "Allow GitHub Actions to create and approve pull requests"

## ⏰ 定时任务

默认每天 UTC 02:00 (北京时间 10:00) 运行

修改时间: 编辑 `.github/workflows/sync.yml`

```yaml
schedule:
  - cron: '0 2 * *'  # 每天 UTC 02:00
```

## 🎯 手动触发

1. 进入 Actions 标签
2. 选择 "Sync Repositories"
3. 点击 "Run workflow"

## 📖 示例

### 同步单个仓库的所有分支

```json
{
  "targetRepo": "xztxy/github-sync",
  "removeWorkflows": true,
  "sourceRepos": [
    "kenzok8/small-package"
  ]
}
```

### 同步多个仓库

```json
{
  "targetRepo": "xztxy/github-sync",
  "removeWorkflows": true,
  "sourceRepos": [
    "coolsnowwolf/lede",
    "immortalwrt/immortalwrt",
    "x-wrt/x-wrt",
    "kenzok8/openwrt-packages",
    "kenzok8/small-package"
  ]
}
```

## 🐛 故障排除

### 问题: 推送失败 (workflows permission)

**解决方案**: 设置 `removeWorkflows: true`

### 问题: 仓库访问失败

**原因**: 仓库可能是私有的或不存在

**解决方案**: 确保仓库是公开的且 URL 正确

### 问题: 分支太多导致超时

**解决方案**: 
1. 分批添加仓库
2. 增加 workflow timeout (默认 6 小时)

## 📄 License

MIT License

## 🙏 致谢

感谢所有开源项目的贡献者！

## 主要特点：

1. **✅ 超简化配置** - 只需 `owner/repo` 即可自动同步所有分支！
2. **✅ 自动检测所有分支** - 无需手动配置任何分支
3. **✅ 智能分支命名**:
   - 单分支: `repo-name`
   - 多分支: `repo-name-branch`
4. **✅ 可选删除 workflows** - 避免权限问题
5. **✅ 详细的进度和报告** - 完整的同步统计
6. **✅ 完整的错误处理** - 分类错误原因并提供详细日志
7. **✅ 智能检测更新** - 自动识别 "Everything up-to-date" 和实际推送
8. **✅ 使用 git mirror** - 一次性克隆所有分支，大幅提升速度

现在你只需要在配置文件中添加 `kenzok8/small-package`，脚本就会自动检测并同步所有分支！🎉