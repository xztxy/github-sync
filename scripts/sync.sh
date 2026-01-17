#!/bin/bash

set +e

CONFIG_FILE="config/repos.json"
REPORT_FILE="${GITHUB_WORKSPACE:-$(pwd)}/sync_report.txt"
ERROR_LOG="${GITHUB_WORKSPACE:-$(pwd)}/sync_errors.log"

echo "========================================="
echo "  🚀 GitHub Repository Sync Tool"
echo "  📦 Auto-detect All Branches"
echo "========================================="
echo ""

# 初始化报告和错误日志
{
    echo "=== Repository Sync Report ==="
    echo "Sync Time: $(date)"
    echo "Mode: Auto-detect all branches"
    echo ""
} > "$REPORT_FILE"

echo "=== Error Log ===" > "$ERROR_LOG"
echo "Sync Time: $(date)" >> "$ERROR_LOG"
echo "" >> "$ERROR_LOG"

# 读取配置
TARGET_REPO=$(jq -r '.targetRepo' "$CONFIG_FILE")
REMOVE_WORKFLOWS=$(jq -r '.removeWorkflows // true' "$CONFIG_FILE")
SOURCE_REPOS=$(jq -r '.sourceRepos[]' "$CONFIG_FILE")

echo "🎯 Target Repository: $TARGET_REPO"
echo "🗑️  Remove Workflows: $REMOVE_WORKFLOWS"
echo ""

# 统计变量
TOTAL_REPOS=0
SUCCESS_REPOS=0
FAILED_REPOS=0
TOTAL_BRANCHES=0
SUCCESS_BRANCHES=0
FAILED_BRANCHES=0

# 遍历每个源仓库
while IFS= read -r REPO_SHORT; do
    [ -z "$REPO_SHORT" ] && continue
    
    TOTAL_REPOS=$((TOTAL_REPOS + 1))
    
    # 构建完整URL
    REPO_URL="https://github.com/${REPO_SHORT}"
    
    # 从 owner/repo 提取信息
    REPO_OWNER=$(echo "$REPO_SHORT" | cut -d'/' -f1)
    REPO_NAME=$(echo "$REPO_SHORT" | cut -d'/' -f2)
    # 生成分支前缀
    BRANCH_PREFIX=$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    
    echo "========================================="
    echo "📦 Repository: $REPO_SHORT"
    echo "🔗 URL: $REPO_URL"
    echo "🏷️  Branch Prefix: $BRANCH_PREFIX"
    echo "========================================="
    
    # 记录到报告
    {
        echo "========================================="
        echo "## 📦 $REPO_SHORT"
        echo "- URL: $REPO_URL"
        echo "- Branch Prefix: $BRANCH_PREFIX"
        echo ""
    } >> "$REPORT_FILE"
    
    # 获取所有远程分支
    echo "🔍 Detecting remote branches..."
    REMOTE_BRANCHES=$(git ls-remote --heads "$REPO_URL" 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$REMOTE_BRANCHES" ]; then
        echo "❌ Failed to access repository"
        {
            echo "- Status: ❌ FAILED"
            echo "- Error: Repository not accessible"
            echo ""
        } >> "$REPORT_FILE"
        echo "[$REPO_SHORT] Failed to access repository" >> "$ERROR_LOG"
        FAILED_REPOS=$((FAILED_REPOS + 1))
        echo ""
        continue
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
        echo "[$REPO_SHORT] No branches found" >> "$ERROR_LOG"
        FAILED_REPOS=$((FAILED_REPOS + 1))
        echo ""
        continue
    fi
    
    echo "📋 Found $BRANCH_COUNT branch(es):"
    echo "$BRANCH_LIST" | sed 's/^/   ✓ /'
    echo ""
    
    {
        echo "### Branches ($BRANCH_COUNT total):"
        echo "$BRANCH_LIST" | sed 's/^/- /'
        echo ""
    } >> "$REPORT_FILE"
    
    REPO_SUCCESS=0
    REPO_FAILED=0
    
    # 遍历每个分支
    while IFS= read -r SOURCE_BRANCH; do
        [ -z "$SOURCE_BRANCH" ] && continue
        TOTAL_BRANCHES=$((TOTAL_BRANCHES + 1))
        
        # 生成目标分支名
        if [ "$BRANCH_COUNT" -eq 1 ]; then
            TARGET_BRANCH="$BRANCH_PREFIX"
        else
            CLEAN_BRANCH=$(echo "$SOURCE_BRANCH" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')
            TARGET_BRANCH="${BRANCH_PREFIX}-${CLEAN_BRANCH}"
        fi
        
        echo "-------------------------------------------"
        echo "🌿 Branch: $SOURCE_BRANCH"
        echo "   → Target: $TARGET_BRANCH"
        
        # 创建临时目录
        TEMP_DIR=$(mktemp -d)
        ORIGINAL_DIR=$(pwd)
        
        cd "$TEMP_DIR" || {
            echo "   ❌ Failed to create temp directory"
            echo "   - $SOURCE_BRANCH → $TARGET_BRANCH: ❌ FAILED (Temp dir error)" >> "$REPORT_FILE"
            echo "[$REPO_SHORT/$SOURCE_BRANCH] Temp dir error" >> "$ERROR_LOG"
            FAILED_BRANCHES=$((FAILED_BRANCHES + 1))
            REPO_FAILED=$((REPO_FAILED + 1))
            continue
        }
        
        # 克隆指定分支
        echo "   📥 Cloning..."
        CLONE_OUTPUT=$(git clone --depth 1 --single-branch --branch "$SOURCE_BRANCH" "$REPO_URL" source_repo 2>&1)
        
        if [ $? -eq 0 ]; then
            cd source_repo || {
                echo "   ❌ Failed to enter directory"
                echo "   - $SOURCE_BRANCH → $TARGET_BRANCH: ❌ FAILED (Directory error)" >> "$REPORT_FILE"
                echo "[$REPO_SHORT/$SOURCE_BRANCH] Directory error" >> "$ERROR_LOG"
                FAILED_BRANCHES=$((FAILED_BRANCHES + 1))
                REPO_FAILED=$((REPO_FAILED + 1))
                cd "$ORIGINAL_DIR"
                rm -rf "$TEMP_DIR"
                continue
            }
            
            # 删除 workflows 和其他可能导致问题的文件
            if [ "$REMOVE_WORKFLOWS" = "true" ]; then
                REMOVED_FILES=""
                
                # 删除 .github/workflows
                if [ -d ".github/workflows" ]; then
                    echo "   🗑️  Removing .github/workflows..."
                    rm -rf .github/workflows
                    REMOVED_FILES="workflows"
                fi
                
                # 删除 .github/dependabot.yml (也可能导致问题)
                if [ -f ".github/dependabot.yml" ]; then
                    echo "   🗑️  Removing .github/dependabot.yml..."
                    rm -f .github/dependabot.yml
                    REMOVED_FILES="${REMOVED_FILES:+$REMOVED_FILES, }dependabot"
                fi
                
                # 如果 .github 目录为空，删除它
                if [ -d ".github" ] && [ -z "$(ls -A .github 2>/dev/null)" ]; then
                    rm -rf .github
                fi
                
                # 提交更改
                if [ -n "$REMOVED_FILES" ]; then
                    git add -A
                    git commit -m "chore: remove $REMOVED_FILES for sync" --allow-empty > /dev/null 2>&1 || true
                fi
            fi
            
            # 获取提交信息
            LATEST_COMMIT=$(git log -1 --format="%H" 2>/dev/null || echo "unknown")
            COMMIT_MESSAGE=$(git log -1 --format="%s" 2>/dev/null || echo "No commit message")
            COMMIT_DATE=$(git log -1 --format="%ci" 2>/dev/null || echo "unknown")
            COMMIT_AUTHOR=$(git log -1 --format="%an" 2>/dev/null || echo "unknown")
            
            echo "   📝 ${LATEST_COMMIT:0:8} - $COMMIT_MESSAGE"
            echo "   👤 $COMMIT_AUTHOR"
            echo "   📅 $COMMIT_DATE"
            
            # 添加目标仓库
            git remote add target "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_REPO}.git" 2>/dev/null
            
            # 推送（捕获详细错误）
            echo "   📤 Pushing..."
            PUSH_OUTPUT=$(git push target "HEAD:refs/heads/$TARGET_BRANCH" --force 2>&1)
            PUSH_RESULT=$?
            
            if [ $PUSH_RESULT -eq 0 ]; then
                echo "   ✅ Success"
                {
                    echo "   ✅ $SOURCE_BRANCH → $TARGET_BRANCH"
                    echo "      - Commit: ${LATEST_COMMIT:0:8}"
                    echo "      - Message: $COMMIT_MESSAGE"
                    echo "      - Author: $COMMIT_AUTHOR"
                    echo "      - Date: $COMMIT_DATE"
                } >> "$REPORT_FILE"
                SUCCESS_BRANCHES=$((SUCCESS_BRANCHES + 1))
                REPO_SUCCESS=$((REPO_SUCCESS + 1))
            else
                echo "   ❌ Push failed"
                
                # 分析错误原因
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
                echo "   ❌ $SOURCE_BRANCH → $TARGET_BRANCH: $ERROR_REASON" >> "$REPORT_FILE"
                
                # 记录详细错误
                {
                    echo "[$REPO_SHORT/$SOURCE_BRANCH → $TARGET_BRANCH]"
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
            echo "   ❌ $SOURCE_BRANCH → $TARGET_BRANCH: Clone error" >> "$REPORT_FILE"
            {
                echo "[$REPO_SHORT/$SOURCE_BRANCH]"
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
        echo "**Summary:** ✅ $REPO_SUCCESS / ❌ $REPO_FAILED"
        echo ""
    } >> "$REPORT_FILE"
    
    echo ""
    
done <<< "$SOURCE_REPOS"

# 生成最终总结
{
    echo "========================================="
    echo "## 📊 Final Summary"
    echo ""
    echo "### Repositories"
    echo "- Total: $TOTAL_REPOS"
    echo "- ✅ Fully Synced: $SUCCESS_REPOS"
    echo "- ⚠️  Partial/Failed: $FAILED_REPOS"
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
echo "  Total:        $TOTAL_REPOS"
echo "  ✅ Success:   $SUCCESS_REPOS"
echo "  ⚠️  Failed:    $FAILED_REPOS"
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

# 显示失败的分支
if [ $FAILED_BRANCHES -gt 0 ]; then
    echo ""
    echo "❌ Failed Branches:"
    echo "========================================="
    grep "❌" "$REPORT_FILE" | grep "→" | head -20
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