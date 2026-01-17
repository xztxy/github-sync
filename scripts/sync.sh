#!/bin/bash

set -e

CONFIG_FILE="config/repos.json"
REPORT_FILE="sync_report.txt"

# �保有写入权限，初始化报告文件
echo "=== Repository Sync Report ===" > "$REPORT_FILE" || {
    echo "Error: Cannot write to $REPORT_FILE"
    REPORT_FILE="/tmp/sync_report.txt"
    echo "Using temporary file: $REPORT_FILE"
    echo "=== Repository Sync Report ===" > "$REPORT_FILE"
}
echo "Sync Time: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

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
    echo "## $REPO_NAME" >> "$REPORT_FILE"
    echo "- Source: $REPO_URL" >> "$REPORT_FILE"
    echo "- Branch: $SOURCE_BRANCH -> $TARGET_BRANCH" >> "$REPORT_FILE"
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    
    if cd "$TEMP_DIR"; then
        # 先检查远程分支是否存在
        echo "Checking remote branches..."
        AVAILABLE_BRANCHES=$(git ls-remote --heads "$REPO_URL" 2>&1 || echo "")
        
        if [ -z "$AVAILABLE_BRANCHES" ]; then
            echo "✗ Failed to access repository $REPO_NAME"
            echo "- Status: ✗ FAILED (Repository not accessible)" >> "$REPORT_FILE"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            cd /
            rm -rf "$TEMP_DIR"
            echo "" >> "$REPORT_FILE"
            echo ""
            continue
        fi
        
        # 检查指定分支是否存在
        if ! echo "$AVAILABLE_BRANCHES" | grep -q "refs/heads/$SOURCE_BRANCH"; then
            echo "✗ Branch '$SOURCE_BRANCH' not found in $REPO_NAME"
            echo "Available branches:"
            echo "$AVAILABLE_BRANCHES" | awk '{print "  - " $2}' | sed 's|refs/heads/||'
            
            # 尝试使用默认分支
            DEFAULT_BRANCH=$(echo "$AVAILABLE_BRANCHES" | head -n 1 | awk '{print $2}' | sed 's|refs/heads/||')
            echo "Attempting to use default branch: $DEFAULT_BRANCH"
            SOURCE_BRANCH="$DEFAULT_BRANCH"
        fi
        
        # 克隆源仓库
        echo "Cloning repository..."
        if git clone --depth 1 --branch "$SOURCE_BRANCH" "$REPO_URL" source_repo 2>&1; then
            cd source_repo
            
            # 获取最新提交信息
            LATEST_COMMIT=$(git log -1 --format="%H")
            COMMIT_MESSAGE=$(git log -1 --format="%s")
            COMMIT_DATE=$(git log -1 --format="%ci")
            
            echo "Latest commit: $LATEST_COMMIT"
            echo "Commit message: $COMMIT_MESSAGE"
            echo "Commit date: $COMMIT_DATE"
            
            # 添加目标仓库为远程
            git remote add target "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_REPO}.git"
            
            # 尝试推送到目标分支
            echo "Pushing to target repository..."
            if git push target "HEAD:refs/heads/$TARGET_BRANCH" --force 2>&1; then
                echo "✓ Successfully synced $REPO_NAME"
                echo "- Status: ✓ SUCCESS" >> "$REPORT_FILE"
                echo "- Source Branch: $SOURCE_BRANCH" >> "$REPORT_FILE"
                echo "- Latest Commit: $LATEST_COMMIT" >> "$REPORT_FILE"
                echo "- Commit Message: $COMMIT_MESSAGE" >> "$REPORT_FILE"
                echo "- Commit Date: $COMMIT_DATE" >> "$REPORT_FILE"
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
        
        # 清理临时目录
        cd /
        rm -rf "$TEMP_DIR"
    else
        echo "✗ Failed to create temp directory for $REPO_NAME"
        echo "- Status: ✗ FAILED (Temp dir error)" >> "$REPORT_FILE"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    echo "" >> "$REPORT_FILE"
    
done <<< "$SOURCE_REPOS"

# 生成总结
echo "========================================" | tee -a "$REPORT_FILE"
echo "Sync Summary:" | tee -a "$REPORT_FILE"
echo "- Total: $((SUCCESS_COUNT + FAIL_COUNT))" | tee -a "$REPORT_FILE"
echo "- Success: $SUCCESS_COUNT" | tee -a "$REPORT_FILE"
echo "- Failed: $FAIL_COUNT" | tee -a "$REPORT_FILE"
echo "========================================" | tee -a "$REPORT_FILE"

# 如果使用了临时文件，复制回工作目录
if [ "$REPORT_FILE" = "/tmp/sync_report.txt" ]; then
    cp "$REPORT_FILE" "$GITHUB_WORKSPACE/sync_report.txt" || true
fi

# 如果有失败，退出码为1
if [ $FAIL_COUNT -gt 0 ]; then
    echo "Some repositories failed to sync"
    exit 1
fi

echo "All repositories synced successfully!"