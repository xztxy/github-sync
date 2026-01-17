# 配置说明

## 超简化配置格式

只需要 `owner/repo` 格式即可！

```json
{
  "targetRepo": "your-username/your-sync-repo",
  "removeWorkflows": true,
  "sourceRepos": [
    "owner1/repo1",
    "owner2/repo2",
    "owner3/repo3"
  ]
}
```

## 配置项说明

### targetRepo (必填)
- 类型: `string`
- 格式: `owner/repo`
- 说明: 你的同步目标仓库

### removeWorkflows (可选)
- 类型: `boolean`
- 默认: `true`
- 说明: 是否自动删除源仓库的 `.github/workflows` 目录

### sourceRepos (必填)
- 类型: `array of strings`
- 格式: `["owner/repo", ...]`
- 说明: 要同步的源仓库列表

## 分支命名规则

脚本会自动检测所有分支并生成目标分支名：

### 单分支仓库
- 源仓库: `kenzok8/openwrt-packages` (只有 `master` 分支)
- 目标分支: `openwrt-packages`

### 多分支仓库
- 源仓库: `coolsnowwolf/lede` (有 `master`, `dev`, `v1.0` 等分支)
- 目标分支: 
  - `lede-master`
  - `lede-dev`
  - `lede-v1.0`

## 示例

### 示例 1: 基础配置

```json
{
  "targetRepo": "xztxy/github-sync",
  "sourceRepos": [
    "kenzok8/small-package"
  ]
}
```

结果：
- 自动检测 `small-package` 的所有分支
- 同步到 `xztxy/github-sync` 仓库
- 分支命名: `small-package` 或 `small-package-{branch}`

### 示例 2: 多个仓库

```json
{
  "targetRepo": "xztxy/github-sync",
  "removeWorkflows": true,
  "sourceRepos": [
    "coolsnowwolf/lede",
    "immortalwrt/immortalwrt",
    "kenzok8/openwrt-packages",
    "kenzok8/small-package"
  ]
}
```

### 示例 3: 保留 Workflows

```json
{
  "targetRepo": "xztxy/github-sync",
  "removeWorkflows": false,
  "sourceRepos": [
    "your-org/your-repo"
  ]
}
```

注意：如果保留 workflows，需要确保 GitHub Token 有 `workflow` 权限。

## 添加新仓库

只需在 `sourceRepos` 数组中添加 `owner/repo` 即可：

```json
{
  "targetRepo": "xztxy/github-sync",
  "sourceRepos": [
    "existing/repo1",
    "existing/repo2",
    "new-owner/new-repo"  ← 添加这一行
  ]
}
```

提交后会自动触发同步！