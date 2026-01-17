#!/bin/bash

set -e

echo "========================================="
echo "  🧹 Cleanup Old Sync Branches"
echo "========================================="
echo ""

# 当前仓库（同步脚本所在的仓库）
CURRENT_REPO="${GITHUB_REPOSITORY:-xztxy/github-sync}"

echo "🎯 Target Repository: $CURRENT_REPO"
echo ""

# 获取所有分支
echo "🔍 Fetching all branches..."
ALL_BRANCHES=$(git ls-remote --heads "https://github.com/${CURRENT_REPO}.git" 2>&1)

if [ $? -ne 0 ] || [ -z "$ALL_BRANCHES" ]; then
    echo "❌ Failed to fetch branches"
    exit 1
fi

BRANCH_LIST=$(echo "$ALL_BRANCHES" | awk '{print $2}' | sed 's|refs/heads/||' | sort)
TOTAL_BRANCHES=$(echo "$BRANCH_LIST" | wc -l)

echo "📋 Found $TOTAL_BRANCHES branches"
echo ""

# 保护的分支（不会被删除）
PROTECTED_BRANCHES=("main" "master")

echo "🔒 Protected branches (will NOT be deleted):"
printf '   - %s\n' "${PROTECTED_BRANCHES[@]}"
echo ""

# 要删除的同步分支前缀
SYNC_PREFIXES=(
    "qkeymapper"
    "lede"
    "immortalwrt"
    "x-wrt"
    "fanchmwrt"
    "openwrt-packages"
    "small-package"
)

echo "🎯 Will delete branches with these prefixes:"
printf '   - %s*\n' "${SYNC_PREFIXES[@]}"
echo ""

# 收集要删除的分支
BRANCHES_TO_DELETE=()

while IFS= read -r BRANCH; do
    [ -z "$BRANCH" ] && continue
    
    # 检查是否是保护分支
    IS_PROTECTED=false
    for PROTECTED in "${PROTECTED_BRANCHES[@]}"; do
        if [ "$BRANCH" = "$PROTECTED" ]; then
            IS_PROTECTED=true
            break
        fi
    done
    
    if [ "$IS_PROTECTED" = true ]; then
        continue
    fi
    
    # 检查是否匹配同步前缀
    for PREFIX in "${SYNC_PREFIXES[@]}"; do
        if [[ "$BRANCH" == "$PREFIX"* ]] || [[ "$BRANCH" == "$PREFIX" ]]; then
            BRANCHES_TO_DELETE+=("$BRANCH")
            break
        fi
    done
    
done <<< "$BRANCH_LIST"

# 显示将要删除的分支
if [ ${#BRANCHES_TO_DELETE[@]} -eq 0 ]; then
    echo "✅ No sync branches found to delete"
    exit 0
fi

echo "📋 Found ${#BRANCHES_TO_DELETE[@]} sync branches to delete:"
echo ""
printf '   - %s\n' "${BRANCHES_TO_DELETE[@]}"
if [ ${#BRANCHES_TO_DELETE[@]} -gt 20 ]; then
    echo "   ... and $((${#BRANCHES_TO_DELETE[@]} - 20)) more"
fi
echo ""

echo "⚠️  WARNING: This will delete ${#BRANCHES_TO_DELETE[@]} branches from $CURRENT_REPO"
echo ""

# 如果在 GitHub Actions 中运行，自动确认
if [ -n "$GITHUB_ACTIONS" ]; then
    echo "✅ Running in GitHub Actions, proceeding with deletion..."
    CONFIRM="yes"
else
    read -p "Type 'yes' to confirm: " CONFIRM
fi

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Cleanup cancelled"
    exit 0
fi

echo ""
echo "🗑️  Deleting branches..."
echo ""

DELETED_COUNT=0
FAILED_COUNT=0

for BRANCH in "${BRANCHES_TO_DELETE[@]}"; do
    echo -n "🗑️  Deleting: $BRANCH ... "
    
    if git push "https://x-access-token:${GITHUB_TOKEN}@github.com/${CURRENT_REPO}.git" \
        --delete "$BRANCH" > /dev/null 2>&1; then
        echo "✅"
        DELETED_COUNT=$((DELETED_COUNT + 1))
    else
        echo "❌"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
    
    # 避免 API 限制
    sleep 0.3
done

echo ""
echo "========================================="
echo "📊 Summary:"
echo "   Total branches found: $TOTAL_BRANCHES"
echo "   Deleted: $DELETED_COUNT"
echo "   Failed: $FAILED_COUNT"
echo "   Remaining: $((TOTAL_BRANCHES - DELETED_COUNT))"
echo "========================================="

if [ $FAILED_COUNT -gt 0 ]; then
    echo ""
    echo "⚠️  Some branches failed to delete"
    exit 1
fi

echo ""
echo "✅ Cleanup completed successfully!"
exit 0