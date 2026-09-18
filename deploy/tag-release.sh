#!/usr/bin/env bash
set -e

# ==============================================================================
# Sub2API 自维护版本发布与打标脚本
# ==============================================================================
# Tag 规范：v<UpstreamVersion>-custom.<Revision>
# 例如：v0.2.5-custom.1
#
# 推送该 tag 到 GitHub 后，GitHub Actions 将自动构建并发布以下 GHCR 镜像标签：
# 1. ghcr.io/<repo>:v0.2.5-custom.1  (精确版本，不可变)
# 2. ghcr.io/<repo>:v0.2.5-custom    (指向该上游版本下的最新 custom 修订版)
# 3. ghcr.io/<repo>:latest           (同步更新为最新生产可用镜像)
# ==============================================================================

DRY_RUN=false
AUTO_CONFIRM=false
TARGET_TAG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -y|--yes)
      AUTO_CONFIRM=true
      shift
      ;;
    v*)
      TARGET_TAG="$1"
      shift
      ;;
    *)
      echo "未知参数: $1"
      echo "用法: $0 [vX.Y.Z-custom.N] [-n|--dry-run] [-y|--yes]"
      exit 1
      ;;
  esac
done

# 检查当前分支是否为 custom
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "custom" ]; then
  echo "⚠️ 警告: 当前不在 custom 分支 (当前是: $CURRENT_BRANCH)"
  if [ "$AUTO_CONFIRM" = false ]; then
    read -p "是否继续基于当前分支打标? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
fi

# 检查工作区状态（排除未跟踪文件）
if ! git diff-index --quiet HEAD --; then
  echo "❌ 错误: 本地存在未提交的修改，请先提交或 stash 后再打标发布。"
  git status --short
  exit 1
fi

# 若未手动指定 tag，自动计算下一个 tag
if [ -z "$TARGET_TAG" ]; then
  # 查找最新上游版本（排除含 custom 的 tag）
  LATEST_UPSTREAM=$(git tag -l 'v[0-9]*' | grep -v 'custom' | sort -V | tail -n 1)
  if [ -z "$LATEST_UPSTREAM" ]; then
    # 回退到 VERSION 文件
    if [ -f "backend/cmd/server/VERSION" ]; then
      LATEST_UPSTREAM="v$(cat backend/cmd/server/VERSION | tr -d '\r\n')"
    else
      echo "❌ 无法检测到上游版本，请显式指定 tag，例如: $0 v0.2.5-custom.1"
      exit 1
    fi
  fi

  # 查找该上游版本已有的 custom tag
  LAST_CUSTOM=$(git tag -l "${LATEST_UPSTREAM}-custom.*" | sort -V | tail -n 1)
  if [ -z "$LAST_CUSTOM" ]; then
    NEXT_REV=1
  else
    LAST_REV=$(echo "$LAST_CUSTOM" | sed -E "s/.*-custom\.([0-9]+)/\1/")
    NEXT_REV=$((LAST_REV + 1))
  fi
  TARGET_TAG="${LATEST_UPSTREAM}-custom.${NEXT_REV}"
fi

# 验证 tag 格式规范
if ! echo "$TARGET_TAG" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+-custom\.[0-9]+$'; then
  echo "❌ 错误: Tag '$TARGET_TAG' 不符合规范: v<主版本.次版本.修订号>-custom.<修订号>"
  echo "标准示例: v0.2.5-custom.1"
  exit 1
fi

# 检查 tag 是否已存在
if git rev-parse "$TARGET_TAG" >/dev/null 2>&1; then
  echo "❌ 错误: Tag '$TARGET_TAG' 已存在于当前仓库！"
  exit 1
fi

UPSTREAM_BASE=$(echo "$TARGET_TAG" | sed -E 's/-custom\.[0-9]+$//')
COMMIT_HASH=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%B | head -n 1)

echo "=================================================================="
echo "🔖 Sub2API 自维护版本发布信息"
echo "=================================================================="
echo "  发布标签 (Tag)     : $TARGET_TAG"
echo "  对应上游版本       : $UPSTREAM_BASE"
echo "  指向提交 (Commit)  : $COMMIT_HASH ($COMMIT_MSG)"
echo "  构建镜像标签 (GHCR):"
echo "    - ghcr.io/<repo>:$TARGET_TAG"
echo "    - ghcr.io/<repo>:${UPSTREAM_BASE}-custom"
echo "    - ghcr.io/<repo>:latest"
echo "=================================================================="

if [ "$DRY_RUN" = true ]; then
  echo "🔍 [Dry-Run] 仅预览，未创建或推送标签。"
  exit 0
fi

if [ "$AUTO_CONFIRM" = false ]; then
  read -p "确认创建并推送此 Release Tag 吗? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "操作已取消。"
    exit 0
  fi
fi

echo "==> 正在创建本地附注标签: $TARGET_TAG ..."
git tag -a "$TARGET_TAG" -m "Release $TARGET_TAG (based on upstream $UPSTREAM_BASE)"

echo "==> 正在推送标签至 origin ..."
git push origin "$TARGET_TAG"

echo ""
echo "🎉 标签推送成功！GitHub Actions 已开始自动构建并发布 Docker 镜像。"
echo "您可以通过以下命令查看构建进度："
echo "  gh run watch"
echo "=================================================================="
