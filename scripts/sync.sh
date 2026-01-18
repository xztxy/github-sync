#!/bin/bash

set +e

CONFIG_FILE="config/repos.json"
REPORT_FILE="${GITHUB_WORKSPACE:-$(pwd)}/sync_report.txt"
ERROR_LOG="${GITHUB_WORKSPACE:-$(pwd)}/sync_errors.log"

echo "========================================="
echo "  🚀 GitHub Repository Sync"
echo "  📦 Mirror Mode (Fast & Efficient)"
echo "========================================="
echo ""

# 初始化报告
echo "=== Repository Sync Report ===" > "$REPORT_FILE"
echo "Sync Time: $(date)" >> "$REPORT_FILE"
echo "Mode: Git mirror (sync all branches at once)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "=== Error Log ===" > "$ERROR_LOG"
echo "Sync Time: $(date)" >> "$ERROR_LOG"
echo "" >> "$ERROR_LOG"

# 读取配置
TARGET_OWNER=$(jq -r '.targetOwner' "$CONFIG_FILE")
REMOVE_WORKFLOWS=$(jq -r '.removeWorkflows // false' "$CONFIG_FILE")
SOURCE_REPOS=$(jq -r '.sourceRepos[]' "$CONFIG_FILE")

echo "🎯 Target Owner: $TARGET_OWNER"
echo "🗑️  Remove Workflows: $REMOVE_WORKFLOWS"
echo ""

# 统计
TOTAL_REPOS=0
SUCCESS_REPOS=0
FAILED_REPOS=0
TOTAL_BRANCHES=0
SUCCESS_BRANCHES=0
FAILED_BRANCHES=0
CREATED_REPOS=0

# 函数：创建目标仓库
create_target_repo() {
    local TARGET_REPO=$1
    local DESCRIPTION=$2
    
    echo "   🔍 Checking repository..."
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${TARGET_REPO}")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "   ✅ Repository exists"
        return 0
    elif [ "$HTTP_CODE" = "404" ]; then
        echo "   📝 Creating repository..."
        REPO_NAME=$(echo "$TARGET_REPO" | cut -d'/' -f2)
        CREATE_RESPONSE=$(curl -s -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/user/repos" \
            -d "{\"name\": \"${REPO_NAME}\", \"description\": \"${DESCRIPTION}\", \"private\": false, \"auto_init\": false}")
        
        if echo "$CREATE_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "   ✅ Repository created"
            CREATED_REPOS=$((CREATED_REPOS + 1))
            sleep 2
            return 0
        else
            echo "   ❌ Failed to create"
            ERROR_MSG=$(echo "$CREATE_RESPONSE" | jq -r '.message // "Unknown error"')
            echo "      Error: $ERROR_MSG"
            return 1
        fi
    else
        echo "   ❌ Failed to check (HTTP $HTTP_CODE)"
        return 1
    fi
}

# 函数：删除 workflows
remove_workflows() {
    local REPO_DIR=$1
    
    if [ "$REMOVE_WORKFLOWS" = "true" ]; then
        if [ -d "$REPO_DIR/.github/workflows" ]; then
            echo "   🗑️  Removing workflows..."
            rm -rf "$REPO_DIR/.github/workflows"
            if [ -f "$REPO_DIR/.github/dependabot.yml" ]; then
                rm -f "$REPO_DIR/.github/dependabot.yml"
            fi
            if [ -d "$REPO_DIR/.github" ] && [ -z "$(ls -A "$REPO_DIR/.github" 2>/dev/null)" ]; then
                rm -rf "$REPO_DIR/.github"
            fi
            cd "$REPO_DIR"
            git add -A
            git commit -m "chore: remove workflows for sync" --allow-empty > /dev/null 2>&1 || true
        fi
    fi
}

# 遍历每个源仓库
while IFS= read -r SOURCE_REPO; do
    [ -z "$SOURCE_REPO" ] && continue
    
    TOTAL_REPOS=$((TOTAL_REPOS + 1))
    
    SOURCE_URL="https://github.com/${SOURCE_REPO}"
    REPO_NAME=$(echo "$SOURCE_REPO" | cut -d'/' -f2)
    TARGET_REPO="${TARGET_OWNER}/${REPO_NAME}"
    
    echo "========================================="
    echo "📦 Source: $SOURCE_REPO"
    echo "🎯 Target: $TARGET_REPO"
    echo "========================================="
    
    echo "=========================================" >> "$REPORT_FILE"
    echo "## 📦 $SOURCE_REPO → $TARGET_REPO" >> "$REPORT_FILE"
    echo "- Source: $SOURCE_URL" >> "$REPORT_FILE"
    echo "- Target: https://github.com/$TARGET_REPO" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 创建目标仓库
    if ! create_target_repo "$TARGET_REPO" "Mirror of $SOURCE_REPO"; then
        echo "❌ Cannot create/access target repository"
        echo "- Status: ❌ FAILED (Cannot create target)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "[$SOURCE_REPO] Cannot create $TARGET_REPO" >> "$ERROR_LOG"
        FAILED_REPOS=$((FAILED_REPOS + 1))
        echo ""
        continue
    fi
    
    # 获取所有分支
    echo "🔍 Detecting branches..."
    REMOTE_BRANCHES=$(git ls-remote --heads "$SOURCE_URL" 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$REMOTE_BRANCHES" ]; then
        echo "❌ Failed to access source repository"
        echo "- Status: ❌ FAILED (Source not accessible)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "[$SOURCE_REPO] Cannot access source" >> "$ERROR_LOG"
        FAILED_REPOS=$((FAILED_REPOS + 1))
        echo ""
        continue
    fi
    
    BRANCH_LIST=$(echo "$REMOTE_BRANCHES" | awk '{print $2}' | sed 's|refs/heads/||' | sort)
    BRANCH_COUNT=$(echo "$BRANCH_LIST" | wc -l)
    
    if [ -z "$BRANCH_LIST" ] || [ "$BRANCH_COUNT" -eq 0 ]; then
        echo "⚠️  No branches found"
        echo "- Status: ⚠️  No branches" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "[$SOURCE_REPO] No branches" >> "$ERROR_LOG"
        FAILED_REPOS=$((FAILED_REPOS + 1))
        echo ""
        continue
    fi
    
    echo "📋 Found $BRANCH_COUNT branch(es):"
    echo "$BRANCH_LIST" | sed 's/^/   ✓ /'
    echo ""
    
    TOTAL_BRANCHES=$((TOTAL_BRANCHES + BRANCH_COUNT))
    
    echo "### Branches: $BRANCH_COUNT" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    echo "$BRANCH_LIST" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    ORIGINAL_DIR=$(pwd)
    
    cd "$TEMP_DIR" || {
        echo "❌ Temp dir error"
        echo "- Status: ❌ FAILED (Temp dir)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "[$SOURCE_REPO] Temp dir error" >> "$ERROR_LOG"
        FAILED_REPOS=$((FAILED_REPOS + 1))
        FAILED_BRANCHES=$((FAILED_BRANCHES + BRANCH_COUNT))
        cd "$ORIGINAL_DIR"
        rm -rf "$TEMP_DIR"
        continue
    }
    
    # 克隆镜像仓库
    echo "📥 Cloning mirror (all branches)..."
    CLONE_OUTPUT=$(git clone --mirror "$SOURCE_URL" mirror_repo 2>&1)
    CLONE_EXIT=$?
    
    if [ $CLONE_EXIT -eq 0 ]; then
        cd mirror_repo || {
            echo "❌ Directory error"
            echo "- Status: ❌ FAILED (Directory)" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            echo "[$SOURCE_REPO] Directory error" >> "$ERROR_LOG"
            FAILED_REPOS=$((FAILED_REPOS + 1))
            FAILED_BRANCHES=$((FAILED_BRANCHES + BRANCH_COUNT))
            cd "$ORIGINAL_DIR"
            rm -rf "$TEMP_DIR"
            continue
        }
        
        # 删除 workflows
        remove_workflows "$(pwd)"
        
        # 获取最新提交信息
        LATEST_COMMIT=$(git log -1 --format="%H" 2>/dev/null || echo "unknown")
        COMMIT_MESSAGE=$(git log -1 --format="%s" 2>/dev/null || echo "No message")
        COMMIT_DATE=$(git log -1 --format="%ci" 2>/dev/null || echo "unknown")
        
        echo "   📝 ${LATEST_COMMIT:0:8} - $COMMIT_MESSAGE"
        echo "   📅 $COMMIT_DATE"
        
        # 添加目标仓库
        git remote add target "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_REPO}.git" 2>/dev/null
        
        # 推送镜像
        echo "   📤 Pushing mirror (all branches)..."
        PUSH_OUTPUT=$(git push --mirror target 2>&1)
        PUSH_EXIT=$?
        
        if [ $PUSH_EXIT -eq 0 ]; then
            # 检查是否有更新
            if echo "$PUSH_OUTPUT" | grep -qi "Everything up-to-date"; then
                echo "   ✅ No changes detected"
                echo "   ✅ Status: Up-to-date" >> "$REPORT_FILE"
                echo "      - Commit: ${LATEST_COMMIT:0:8}" >> "$REPORT_FILE"
                echo "      - Message: $COMMIT_MESSAGE" >> "$REPORT_FILE"
                echo "      - Date: $COMMIT_DATE" >> "$REPORT_FILE"
                echo "      - Note: No changes to push" >> "$REPORT_FILE"
                SUCCESS_BRANCHES=$((SUCCESS_BRANCHES + BRANCH_COUNT))
                SUCCESS_REPOS=$((SUCCESS_REPOS + 1))
            else
                # 统计推送的分支数
                PUSHED_COUNT=$(echo "$PUSH_OUTPUT" | grep -c "^\*" || echo "$BRANCH_COUNT")
                echo "   ✅ Pushed $PUSHED_COUNT branch(es)"
                echo "   ✅ Status: Synced" >> "$REPORT_FILE"
                echo "      - Commit: ${LATEST_COMMIT:0:8}" >> "$REPORT_FILE"
                echo "      - Message: $COMMIT_MESSAGE" >> "$REPORT_FILE"
                echo "      - Date: $COMMIT_DATE" >> "$REPORT_FILE"
                echo "      - Branches pushed: $PUSHED_COUNT" >> "$REPORT_FILE"
                SUCCESS_BRANCHES=$((SUCCESS_BRANCHES + PUSHED_COUNT))
                SUCCESS_REPOS=$((SUCCESS_REPOS + 1))
            fi
        else
            echo "   ❌ Push failed (Exit: $PUSH_EXIT)"
            echo "   📄 Error output:"
            echo "$PUSH_OUTPUT" | sed 's/^/      /'
            
            # 分析错误原因
            ERROR_REASON="Unknown"
            if echo "$PUSH_OUTPUT" | grep -qi "refusing to allow.*workflow"; then
                ERROR_REASON="Workflow permission denied"
            elif echo "$PUSH_OUTPUT" | grep -qi "protected branch"; then
                ERROR_REASON="Protected branch"
            elif echo "$PUSH_OUTPUT" | grep -qi "authentication\|permission denied"; then
                ERROR_REASON="Authentication/Permission denied"
            elif echo "$PUSH_OUTPUT" | grep -qi "403"; then
                ERROR_REASON="Forbidden (403)"
            elif echo "$PUSH_OUTPUT" | grep -qi "repository not found"; then
                ERROR_REASON="Repository not found"
            elif echo "$PUSH_OUTPUT" | grep -qi "failed to push"; then
                ERROR_REASON="Push rejected"
            elif echo "$PUSH_OUTPUT" | grep -qi "could not read"; then
                ERROR_REASON="Could not read from remote"
            fi
            
            echo "      Reason: $ERROR_REASON"
            echo "   ❌ Status: $ERROR_REASON" >> "$REPORT_FILE"
            
            # 记录详细错误
            echo "=========================================" >> "$ERROR_LOG"
            echo "[$SOURCE_REPO → $TARGET_REPO]" >> "$ERROR_LOG"
            echo "Exit Code: $PUSH_EXIT" >> "$ERROR_LOG"
            echo "Error Reason: $ERROR_REASON" >> "$ERROR_LOG"
            echo "" >> "$ERROR_LOG"
            echo "Full Output:" >> "$ERROR_LOG"
            echo "$PUSH_OUTPUT" >> "$ERROR_LOG"
            echo "" >> "$ERROR_LOG"
            
            FAILED_BRANCHES=$((FAILED_BRANCHES + BRANCH_COUNT))
            FAILED_REPOS=$((FAILED_REPOS + 1))
        fi
    else
        echo "   ❌ Clone failed (Exit: $CLONE_EXIT)"
        echo "   📄 Clone output:"
        echo "$CLONE_OUTPUT" | sed 's/^/      /'
        
        echo "   ❌ Status: Clone error" >> "$REPORT_FILE"
        echo "=========================================" >> "$ERROR_LOG"
        echo "[$SOURCE_REPO]" >> "$ERROR_LOG"
        echo "Clone failed (Exit: $CLONE_EXIT)" >> "$ERROR_LOG"
        echo "" >> "$ERROR_LOG"
        echo "Output:" >> "$ERROR_LOG"
        echo "$CLONE_OUTPUT" >> "$ERROR_LOG"
        echo "" >> "$ERROR_LOG"
        
        FAILED_BRANCHES=$((FAILED_BRANCHES + BRANCH_COUNT))
        FAILED_REPOS=$((FAILED_REPOS + 1))
    fi
    
    # 清理
    cd "$ORIGINAL_DIR"
    rm -rf "$TEMP_DIR"
    
    echo ""
done <<< "$SOURCE_REPOS"

# 总结
echo "=========================================" >> "$REPORT_FILE"
echo "## 📊 Final Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "### Repositories" >> "$REPORT_FILE"
echo "- Total: $TOTAL_REPOS" >> "$REPORT_FILE"
echo "- ✅ Fully Synced: $SUCCESS_REPOS" >> "$REPORT_FILE"
echo "- ⚠️  Partial/Failed: $FAILED_REPOS" >> "$REPORT_FILE"
echo "- 🆕 Created: $CREATED_REPOS" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "### Branches" >> "$REPORT_FILE"
echo "- Total: $TOTAL_BRANCHES" >> "$REPORT_FILE"
echo "- ✅ Success: $SUCCESS_BRANCHES" >> "$REPORT_FILE"
echo "- ❌ Failed: $FAILED_BRANCHES" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
if [ $TOTAL_BRANCHES -gt 0 ]; then
    SUCCESS_RATE=$((SUCCESS_BRANCHES * 100 / TOTAL_BRANCHES))
    echo "### Success Rate: ${SUCCESS_RATE}%" >> "$REPORT_FILE"
fi
echo "" >> "$REPORT_FILE"
echo "Completed: $(date)" >> "$REPORT_FILE"
echo "=========================================" >> "$REPORT_FILE"

echo "========================================="
echo "📊 FINAL SUMMARY"
echo "========================================="
echo "Repositories:"
echo "  Source:       $TOTAL_REPOS"
echo "  ✅ Synced:    $SUCCESS_REPOS"
echo "  ⚠️  Failed:     $FAILED_REPOS"
echo "  🆕 Created:    $CREATED_REPOS"
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

if [ $CREATED_REPOS -gt 0 ]; then
    echo ""
    echo "🆕 Created $CREATED_REPOS new repositories"
    echo "   Visit: https://github.com/$TARGET_OWNER"
fi

echo ""
echo "📄 Full Report:"
echo "========================================="
cat "$REPORT_FILE"

if [ $FAILED_BRANCHES -gt 0 ]; then
    echo ""
    echo "⚠️  $FAILED_BRANCHES branches failed"
    echo ""
    echo "📄 Error Log Preview (first 50 lines):"
    echo "========================================="
    head -50 "$ERROR_LOG"
    echo "========================================="
    echo ""
    echo "💡 Download full error log from artifacts"
    exit 1
fi

echo ""
echo "✅ All branches synced successfully!"
exit 0