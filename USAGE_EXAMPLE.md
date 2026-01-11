# GitHub Repository Sync - 使用示例

本文件提供了如何将指定的6个仓库配置到同步系统中的详细示例。

## 仓库列表

1. **QKeyMapper** - 按键映射工具
2. **lede** - Lean's LEDE source
3. **immortalwrt** - OpenWrt变体，面向中国大陆用户
4. **x-wrt** - OpenWrt fork
5. **fanchmwrt** - 基于OpenWrt开发的开源家庭防火墙系统
6. **openwrt-packages** - OpenWrt常用软件包

## 配置步骤

### 1. 复制配置JSON

将以下JSON内容复制，用于设置GitHub Actions的环境变量：

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

### 2. 设置GitHub Secrets

1. 进入你的GitHub仓库
2. 点击 `Settings > Secrets and variables > Actions`
3. 点击 `New repository secret`
4. 创建以下secret：

   | 变量名 | 值 |
   |--------|-----|
   | `SOURCE_REPOS` | 上面的JSON内容 |

**注意**：目标仓库默认为当前仓库，无需配置`TARGET_REPO` secret。

### 3. 配置说明

| 仓库 | 源分支 | 目标分支 | 说明 |
|------|--------|----------|------|
| QKeyMapper | main | qkeymapper | 按键映射工具 |
| lede | master | lede | Lean's LEDE source |
| immortalwrt | master | immortalwrt | OpenWrt变体 |
| x-wrt | master | x-wrt | OpenWrt fork |
| fanchmwrt | main | fanchmwrt | 家庭防火墙系统 |
| openwrt-packages | master | openwrt-packages | OpenWrt常用软件包 |
| small-package | master | small-package | OpenWrt小软件包 |

### 4. 运行同步

- **自动运行**：GitHub Actions会每天UTC时间00:00自动运行
- **手动运行**：在GitHub仓库的`Actions`选项卡中手动触发

## 预期结果

同步完成后，你的目标仓库将包含以下分支：

- `qkeymapper` - 同步自 https://github.com/Zalafina/QKeyMapper
- `lede` - 同步自 https://github.com/coolsnowwolf/lede
- `immortalwrt` - 同步自 https://github.com/immortalwrt/immortalwrt
- `x-wrt` - 同步自 https://github.com/x-wrt/x-wrt
- `fanchmwrt` - 同步自 https://github.com/fanchmwrt/fanchmwrt
- `openwrt-packages` - 同步自 https://github.com/kenzok8/openwrt-packages

每个分支都会每天自动更新，保持与源仓库的同步。

## 自定义配置

你可以根据需要修改配置：

1. **修改源分支**：将`sourceBranch`改为你想要同步的分支
2. **修改目标分支**：将`targetBranch`改为你想要的目标分支名称
3. **修改仓库名称**：将`repoName`改为你想要的显示名称
4. **添加更多仓库**：在JSON数组中添加更多仓库配置

## 注意事项

1. 确保你的GitHub Token具有足够的权限
2. 对于大型仓库，同步可能需要较长时间
3. 建议先在小仓库上测试配置
4. 查看GitHub Actions日志以获取详细的同步信息
