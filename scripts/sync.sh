#!/bin/bash

set +e

CONFIG_FILE="config/repos.json"
REPORT_FILE="${GITHUB_WORKSPACE:-$(pwd)}/sync_report.txt"
ERROR_LOG="${GITHUB_WORKSPACE:-$(pwd)}/sync_errors.log"

echo "========================================="
echo "  🚀 GitHub Repository Sync Tool"
echo "  📦 Sync to Separate Repositories"
echo "========================================="
echo ""

# 初始化报告和错误日志
{
    echo "=== Repository Sync Report ==="
    echo "Sync Time: $(date)"
    echo "Mode: Separate repositories for each source"
    echo ""
} > "$REPORT_FILE"

echo "=== Error Log ===" > "$ERROR_LOG"
echo "Sync Time: $(date)" >> "$ERROR_LOG"
echo "" >> "$ERROR_LOG"

# 读取配置
TARGET_OWNER=$(jq -r '.targetOwner' "$CONFIG_FILE")
REMOVE_WORKFLOWS=$(jq -r '.removeWorkflows // true' "$CONFIG_FILE")
SYNC_MODE=$(jq -r '.syncMode // "separate-repos"' "$CONFIG_FILE")

echo "🎯 Target Owner: $TARGET_OWNER"
echo "🗑️  Remove Workflows: $REMOVE_WORKFLOWS"
echo "📋 Sync Mode: $SYNC_MODE"
echo ""

# 统计变量
TOTAL_REPOS=0
SUCCESS_REPOS=0
FAILED_REPOS=0
TOTAL_BRANCHES=0
SUCCESS_BRANCHES=0
FAILED_BRANCHES=0
CREATED_REPOS=0

# 函数：创建目标仓库（如果不存在）
create_target_repo() {
    local TARGET_REPO=$1
    local DESCRIPTION=$2
    
    echo "   🔍 Checking if repository exists..."
    
    # 检查仓库是否存在
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${TARGET_REPO}")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "   ✅ Repository already exists"
        return 0
    elif [ "$HTTP_CODE" = "404" ]; then
        echo "   📝 Creating repository..."
        
        REPO_NAME=$(echo "$TARGET_REPO" | cut -d'/' -f2)
        CREATE_RESPONSE=$(curl -s -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/user/repos" \
            -d "{
                \"name\": \"${REPO_NAME}\",
                \"description\": \"${DESCRIPTION}\",
                \"private\": false,
                \"auto_init\": false
            }")
        
        if echo "$CREATE_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "   ✅ Repository created successfully"
            CREATED_REPOS=$((CREATED_REPOS + 1))
            sleep 2  # 等待仓库完全创建
            return 0
        else
            echo "   ❌ Failed to create repository"
            echo "$CREATE_RESPONSE" | jq -r '.message // "Unknown error"'
            return 1
        fi
    else
        echo "   ❌ Failed to check repository (HTTP $HTTP_CODE)"
        return 1
    fi
}

# 函数：同步仓库
sync_repository() {
    local SOURCE_REPO=$1
    local TARGET_REPO=$2
    local SOURCE_URL="https://github.com/${SOURCE_REPO}"
    TOTAL_REPOS=$((TOTAL_REPOS + 1))
    
    echo "========================================="
    echo "📦 Source: $SOURCE_REPO"
    echo "🎯 Target: $TARGET_REPO"
    echo "========================================="
    
    # 记录到报告
    {
        echo "========================================="
        echo "## 📦 $SOURCE_REPO → $TARGET_REPO"
        echo "- Source URL: $SOURCE_URL"
        echo "- Target Repo: https://github.com/$TARGET_REPO"
        echo ""
    } >> "$REPORT_FILE"
    
    # 创建目标仓库
    if ! create_target_repo "$TARGET_REPO" "Mirror of $SOURCE_REPO"; then
        echo "❌ Failed to create/access target repository"
        {
            echo "- Status: ❌ FAILED"
            echo "- Error: Cannot create/access target repository"
            echo ""
        } >> "$REPORT_FILE"
        echo "[$SOURCE_REPO] Cannot create target repo $TARGET_REPO" >> "$ERROR_LOG"
        FAILED_REPOS=$((FAILED_REPOS + 1))
        echo ""
        return 1
    fi
    
    # 获取所有远程分支
    echo "🔍 Detecting remote branches..."
    REMOTE_BRANCHES=$(git ls-remote --heads "$SOURCE_URL" 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$REMOTE_BRANCHES" ]; then
        echo "❌ Failed to access source repository"
        {
            echo "- Status: ❌ FAILED"
            echo "- Error: Source repository not accessible"
            echo ""
        } >> "$REPORT_FILE"
        echo "[$SOURCE_REPO] Cannot access source repository" >> "$ERROR_LOG"
        FAILED_REPOS=$((FAILED_REPOS + 1))
        echo ""
        return 1
    fi
    
    # 提取分支名列表
    BRANCH_LIST=$(echo "$REMOTE_BRANCHES" | awk '{print $2}' | sed 's|refs/heads/||' | sort)
    BRANCH_COUNT=$(echo "$BRANCH_LIST" | wc -l)
    
    if [ -z "$BRANCH_LIST" ] || [ "$BRANCH_COUNT" -eq 0 ]; then
        echo "⚠️  No branches found"
        {
            echo "- Status: ⚠️  WARNING"
            echo "- Error: No branches found"
            echo ""
        } >> "$REPORT_FILE"
        echo "[$SOURCE_REPO] No branches found" >> "$ERROR_LOG"
        FAILED_REPOS=$((FAILED_REPOS + 1))
        echo ""
        return 1
    fi
    
    echo "📋 Found $BRANCH_COUNT branch(es):"
    echo "$BRANCH_LIST" | sed 's/^/   ✓ /'
    echo ""
    
    {
        echo "### Branches ($BRANCH_COUNT total):"
        echo '```'
        echo "$BRANCH_LIST"
        echo '```'
        echo ""
    } >> "$REPORT_FILE"
    
    REPO_SUCCESS=0
    REPO_FAILED=0
    
    # 遍历每个分支
    while IFS= read -r BRANCH_NAME; do
        [ -z "$BRANCH_NAME" ] && continue
        
        TOTAL_BRANCHES=$((TOTAL_BRANCHES + 1))
        
        echo "-------------------------------------------"
        echo "🌿 Branch: $BRANCH_NAME"
        echo "   → Target: $TARGET_REPO/$BRANCH_NAME"
        
        # 创建临时目录
        TEMP_DIR=$(mktemp -d)
        ORIGINAL_DIR=$(pwd)
        
        cd "$TEMP_DIR" || {
            echo "   ❌ Failed to create temp directory"
            echo "   - Branch $BRANCH_NAME: ❌ FAILED (Temp dir error)" >> "$REPORT_FILE"
            echo "[$SOURCE_REPO/$BRANCH_NAME] Temp dir error" >> "$ERROR_LOG"
            FAILED_BRANCHES=$((FAILED_BRANCHES + 1))
            REPO_FAILED=$((REPO_FAILED + 1))
            continue
        }
        
        # 克隆指定分支
        echo "   📥 Cloning..."
        CLONE_OUTPUT=$(git clone --depth 1 --single-branch --branch "$BRANCH_NAME" "$SOURCE_URL" source_repo 2>&1)
        
        if [ $? -eq 0 ]; then
            cd source_repo || {
                echo "   ❌ Failed to enter directory"
                echo "   - Branch $BRANCH_NAME: ❌ FAILED (Directory error)" >> "$REPORT_FILE"
                echo "[$SOURCE_REPO/$BRANCH_NAME] Directory error" >> "$ERROR_LOG"
                FAILED_BRANCHES=$((FAILED_BRANCHES + 1))
                REPO_FAILED=$((REPO_FAILED + 1))
                cd "$ORIGINAL_DIR"
                rm -rf "$TEMP_DIR"
                continue
            }
            
            # 删除 workflows
            if [ "$REMOVE_WORKFLOWS" = "true" ]; then
                REMOVED_ITEMS=""
                
                if [ -d ".github/workflows" ]; then
                    echo "   🗑️  Removing .github/workflows..."
                    rm -rf .github/workflows
                    REMOVED_ITEMS="workflows"
                fi
                
                if [ -f ".github/dependabot.yml" ]; then
                    rm -f .github/dependabot.yml
                    REMOVED_ITEMS="${REMOVED_ITEMS:+$REMOVED_ITEMS, }dependabot"
                fi
                
                if [ -d ".github" ] && [ -z "$(ls -A .github 2>/dev/null)" ]; then
                    rm -rf .github
                fi
                
                if [ -n "$REMOVED_ITEMS" ]; then
                    git add -A
                    git commit -m "chore: remove $REMOVED_ITEMS for sync" --allow-empty > /dev/null 2>&1 || true
                fi
            fi
            
            # 获取提交信息
            LATEST_COMMIT=$(git log -1 --format="%H" 2>/dev/null || echo "unknown")
            COMMIT_MESSAGE=$(git log -1 --format="%s" 2>/dev/null || echo "No message")
            COMMIT_DATE=$(git log -1 --format="%ci" 2>/dev/null || echo "unknown")
            COMMIT_AUTHOR=$(git log -1 --format="%an" 2>/dev/null || echo "unknown")
            
            echo "   📝 ${LATEST_COMMIT:0:8} - $COMMIT_MESSAGE"
            echo "   👤 $COMMIT_AUTHOR"
            echo "   📅 $COMMIT_DATE"
            
            # 添加目标仓库
            git remote add target "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_REPO}.git" 2>/dev/null
            
            # 推送（保持原分支名）
            echo "   📤 Pushing to $TARGET_REPO/$BRANCH_NAME..."
            PUSH_OUTPUT=$(git push target "HEAD:refs/heads/$BRANCH_NAME" --force 2>&1)
            PUSH_RESULT=$?
            
            if [ $PUSH_RESULT -eq 0 ]; then
                echo "   ✅ Success"
                {
                    echo "   ✅ Branch: $BRANCH_NAME"
                    echo "      - Commit: ${LATEST_COMMIT:0:8}"
                    echo "      - Message: $COMMIT_MESSAGE"
                    echo "      - Author: $COMMIT_AUTHOR"
                    echo "      - Date: $COMMIT_DATE"
                } >> "$REPORT_FILE"
                SUCCESS_BRANCHES=$((SUCCESS_BRANCHES + 1))
                REPO_SUCCESS=$((REPO_SUCCESS + 1))
            else
                echo "   ❌ Push failed"
                
                # 分析错误
                ERROR_REASON="Unknown error"
                if echo "$PUSH_OUTPUT" | grep -q "refusing to allow.*workflow"; then
                    ERROR_REASON="Workflow permission denied"
                elif echo "$PUSH_OUTPUT" | grep -q "protected branch"; then
                    ERROR_REASON="Protected branch"
                elif echo "$PUSH_OUTPUT" | grep -q "authentication"; then
                    ERROR_REASON="Authentication failed"
                elif echo "$PUSH_OUTPUT" | grep -q "permission denied"; then
                    ERROR_REASON="Permission denied"
                fi
                
                echo "      Reason: $ERROR_REASON"
                echo "   ❌ Branch $BRANCH_NAME: $ERROR_REASON" >> "$REPORT_FILE"
                
                {
                    echo "[$SOURCE_REPO/$BRANCH_NAME → $TARGET_REPO/$BRANCH_NAME]"
                    echo "Error: $ERROR_REASON"
                    echo "Output:"
                    echo "$PUSH_OUTPUT"
                    echo ""
                } >> "$ERROR_LOG"
                
                FAILED_BRANCHES=$((FAILED_BRANCHES + 1))
                REPO_FAILED=$((REPO_FAILED + 1))
            fi
        else
            echo "   ❌ Clone failed"
            echo "   ❌ Branch $BRANCH_NAME: Clone error" >> "$REPORT_FILE"
            {
                echo "[$SOURCE_REPO/$BRANCH_NAME]"
                echo "Clone failed:"
                echo "$CLONE_OUTPUT"
                echo ""
            } >> "$ERROR_LOG"
            FAILED_BRANCHES=$((FAILED_BRANCHES + 1))
            REPO_FAILED=$((REPO_FAILED + 1))
        fi
        
        # 清理
        cd "$ORIGINAL_DIR"
        rm -rf "$TEMP_DIR"
    done <<< "$BRANCH_LIST"
    
    # 仓库总结
    echo ""
    if [ $REPO_FAILED -eq 0 ]; then
        echo "✅ Repository: All $REPO_SUCCESS branches synced successfully"
        SUCCESS_REPOS=$((SUCCESS_REPOS + 1))
    else
        echo "⚠️  Repository: $REPO_SUCCESS succeeded, $REPO_FAILED failed"
        FAILED_REPOS=$((FAILED_REPOS + 1))
    fi
    
    {
        echo ""
        echo "**Summary:** ✅ $REPO_SUCCESS / ❌ $REPO_FAILED branches"
        echo ""
    } >> "$REPORT_FILE"
    
    echo ""
}

# 主循环：处理所有仓库
SOURCE_REPOS=$(jq -r '.sourceRepos[]' "$CONFIG_FILE")

while IFS= read -r SOURCE_REPO; do
    [ -z "$SOURCE_REPO" ] && continue
    
    # 自动生成目标仓库名
    REPO_NAME=$(echo "$SOURCE_REPO" | cut -d'/' -f2)
    TARGET_REPO="${TARGET_OWNER}/${REPO_NAME}"
    
    sync_repository "$SOURCE_REPO" "$TARGET_REPO"
    
done <<< "$SOURCE_REPOS"

# 生成最终总结
{
    echo "========================================="
    echo "## 📊 Final Summary"
    echo ""
    echo "### Repositories"
    echo "- Total Source Repos: $TOTAL_REPOS"
    echo "- ✅ Fully Synced: $SUCCESS_REPOS"
    echo "- ⚠️  Partial/Failed: $FAILED_REPOS"
    echo "- 🆕 Created: $CREATED_REPOS"
    echo ""
    echo "### Branches"
    echo "- Total: $TOTAL_BRANCHES"
    echo "- ✅ Success: $SUCCESS_BRANCHES"
    echo "- ❌ Failed: $FAILED_BRANCHES"
    echo ""
    if [ $TOTAL_BRANCHES -gt 0 ]; then
        SUCCESS_RATE=$((SUCCESS_BRANCHES * 100 / TOTAL_BRANCHES))
        echo "### Success Rate"
        echo "- ${SUCCESS_RATE}% ($SUCCESS_BRANCHES/$TOTAL_BRANCHES branches)"
    fi
    echo ""
    echo "Completed at: $(date)"
    echo "========================================="
} >> "$REPORT_FILE"

# 输出到控制台
echo "========================================="
echo "📊 FINAL SUMMARY"
echo "========================================="
echo "Repositories:"
echo "  Source:       $TOTAL_REPOS"
echo "  ✅ Synced:    $SUCCESS_REPOS"
echo "  ⚠️  Failed:    $FAILED_REPOS"
echo "  🆕 Created:   $CREATED_REPOS"
echo ""
echo "Branches:"
echo "  Total:        $TOTAL_BRANCHES"
echo "  ✅ Success:   $SUCCESS_BRANCHES"
echo "  ❌ Failed:    $FAILED_BRANCHES"
echo ""
if [ $TOTAL_BRANCHES -gt 0 ]; then
    SUCCESS_RATE=$((SUCCESS_BRANCHES * 100 / TOTAL_BRANCHES))
    echo "Success Rate: ${SUCCESS_RATE}%"
fi
echo "========================================="

# 显示创建的仓库
if [ $CREATED_REPOS -gt 0 ]; then
    echo ""
    echo "🆕 Created Repositories:"
    echo "Visit: https://github.com/$TARGET_OWNER"
fi

# 显示失败信息
if [ $FAILED_BRANCHES -gt 0 ]; then
    echo ""
    echo "❌ Failed Branches:"
    echo "========================================="
    grep "❌" "$REPORT_FILE" | grep "Branch:" | head -20
    echo ""
    echo "📄 See full error log in artifacts"
fi

# 显示完整报告
echo ""
echo "📄 Full Report:"
echo "========================================="
cat "$REPORT_FILE"

# 显示错误摘要
if [ $FAILED_BRANCHES -gt 0 ]; then
    echo ""
    echo "🔍 Error Summary:"
    echo "========================================="
    grep -E "^\[.*\]$|^Error:" "$ERROR_LOG" | head -40
fi

# 返回退出码
if [ $FAILED_BRANCHES -gt 0 ]; then
    echo ""
    echo "⚠️  $FAILED_BRANCHES branches failed to sync"
    echo "💡 Tip: Check if these branches contain .github/workflows files"
    echo "💡 Solution: Ensure 'removeWorkflows: true' in config"
    exit 1
fi

echo ""
echo "✅ All branches synced successfully!"
exit 0