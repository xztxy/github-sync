#!/bin/bash

# 不要在遇到错误时立即退出
set +e

CONFIG_FILE="config/repos.json"

# 确定报告文件位置
if [ -n "$GITHUB_WORKSPACE" ]; then
    REPORT_FILE="${GITHUB_WORKSPACE}/sync_report.txt"
else
    REPORT_FILE="$(pwd)/sync_report.txt"
fi

# 测试写入权限
if ! touch "$REPORT_FILE" 2>/dev/null; then
    echo "Warning: Cannot write to $REPORT_FILE, using /tmp"
    REPORT_FILE="/tmp/sync_report.txt"
fi

echo "Using report file: $REPORT_FILE"

# 初始化报告
{
    echo "=== Repository Sync Report ==="
    echo "Sync Time: $(date)"
    echo ""
} > "$REPORT_FILE"

# 读取配置
TARGET_REPO=$(jq -r '.targetRepo' "$CONFIG_FILE")
SOURCE_REPOS=$(jq -c '.sourceRepos[]' "$CONFIG_FILE")

echo "Target Repository: $TARGET_REPO"
echo "Starting sync process..."
echo ""

# 计数器
SUCCESS_COUNT=0
FAIL_COUNT=0

# 遍历每个源仓库
while IFS= read -r repo; do
    REPO_URL=$(echo "$repo" | jq -r '.repoUrl')
    SOURCE_BRANCH=$(echo "$repo" | jq -r '.sourceBranch')
    TARGET_BRANCH=$(echo "$repo" | jq -r '.targetBranch')
    REPO_NAME=$(echo "$repo" | jq -r '.repoName')
    
    echo "----------------------------------------"
    echo "Syncing: $REPO_NAME"
    echo "Source: $REPO_URL ($SOURCE_BRANCH)"
    echo "Target Branch: $TARGET_BRANCH"
    echo ""
    
    # 记录到报告
    {
        echo "## $REPO_NAME"
        echo "- Source: $REPO_URL"
        echo "- Branch: $SOURCE_BRANCH -> $TARGET_BRANCH"
    } >> "$REPORT_FILE"
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    ORIGINAL_DIR=$(pwd)
    
    cd "$TEMP_DIR" || {
        echo "✗ Failed to create temp directory"
        echo "- Status: ✗ FAILED (Temp dir error)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    }
    
    # 检查远程分支
    echo "Checking remote branches..."
    AVAILABLE_BRANCHES=$(git ls-remote --heads "$REPO_URL" 2>&1)
    
    if [ -z "$AVAILABLE_BRANCHES" ]; then
        echo "✗ Failed to access repository $REPO_NAME"
        echo "- Status: ✗ FAILED (Repository not accessible)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        cd "$ORIGINAL_DIR"
        rm -rf "$TEMP_DIR"
        echo ""
        continue
    fi
    
    # 检查指定分支是否存在
    if ! echo "$AVAILABLE_BRANCHES" | grep -q "refs/heads/$SOURCE_BRANCH"; then
        echo "✗ Branch '$SOURCE_BRANCH' not found in $REPO_NAME"
        echo "Available branches:"
        echo "$AVAILABLE_BRANCHES" | awk '{print "  - " $2}' | sed 's|refs/heads/||'
        
        DEFAULT_BRANCH=$(echo "$AVAILABLE_BRANCHES" | head -n 1 | awk '{print $2}' | sed 's|refs/heads/||')
        echo "Attempting to use default branch: $DEFAULT_BRANCH"
        SOURCE_BRANCH="$DEFAULT_BRANCH"
    fi
    
    # 克隆源仓库
    echo "Cloning repository..."
    if git clone --depth 1 --branch "$SOURCE_BRANCH" "$REPO_URL" source_repo 2>&1; then
        cd source_repo || {
            echo "✗ Failed to enter source_repo directory"
            echo "- Status: ✗ FAILED (Directory error)" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            cd "$ORIGINAL_DIR"
            rm -rf "$TEMP_DIR"
            continue
        }
        
        # 获取最新提交信息
        LATEST_COMMIT=$(git log -1 --format="%H")
        COMMIT_MESSAGE=$(git log -1 --format="%s")
        COMMIT_DATE=$(git log -1 --format="%ci")
        
        echo "Latest commit: $LATEST_COMMIT"
        echo "Commit message: $COMMIT_MESSAGE"
        echo "Commit date: $COMMIT_DATE"
        
        # 添加目标仓库为远程
        git remote add target "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_REPO}.git"
        
        # 推送到目标分支
        echo "Pushing to target repository..."
        if git push target "HEAD:refs/heads/$TARGET_BRANCH" --force 2>&1; then
            echo "✓ Successfully synced $REPO_NAME"
            {
                echo "- Status: ✓ SUCCESS"
                echo "- Source Branch: $SOURCE_BRANCH"
                echo "- Latest Commit: $LATEST_COMMIT"
                echo "- Commit Message: $COMMIT_MESSAGE"
                echo "- Commit Date: $COMMIT_DATE"
            } >> "$REPORT_FILE"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "✗ Failed to push $REPO_NAME"
            echo "- Status: ✗ FAILED (Push error)" >> "$REPORT_FILE"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo "✗ Failed to clone $REPO_NAME"
        echo "- Status: ✗ FAILED (Clone error)" >> "$REPORT_FILE"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    # 清理
    cd "$ORIGINAL_DIR"
    rm -rf "$TEMP_DIR"
    
    echo "" >> "$REPORT_FILE"
    echo ""
    
done <<< "$SOURCE_REPOS"

# 生成总结
{
    echo "========================================"
    echo "Sync Summary:"
    echo "- Total: $((SUCCESS_COUNT + FAIL_COUNT))"
    echo "- Success: $SUCCESS_COUNT"
    echo "- Failed: $FAIL_COUNT"
    echo "========================================"
} >> "$REPORT_FILE"

# 输出到控制台
echo "========================================"
echo "Sync Summary:"
echo "- Total: $((SUCCESS_COUNT + FAIL_COUNT))"
echo "- Success: $SUCCESS_COUNT"
echo "- Failed: $FAIL_COUNT"
echo "========================================"

# 显示完整报告
echo ""
echo "=== Full Report ==="
cat "$REPORT_FILE"

# 如果使用了临时文件，复制回工作目录
if [ "$REPORT_FILE" = "/tmp/sync_report.txt" ] && [ -n "$GITHUB_WORKSPACE" ]; then
    cp "$REPORT_FILE" "${GITHUB_WORKSPACE}/sync_report.txt"
    echo "Report copied to ${GITHUB_WORKSPACE}/sync_report.txt"
fi

# 返回适当的退出码
if [ $FAIL_COUNT -gt 0 ]; then
    echo ""
    echo "⚠️  Some repositories failed to sync"
    exit 1
fi

echo ""
echo "✅ All repositories synced successfully!"
exit 0
