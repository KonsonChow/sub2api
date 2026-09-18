#!/usr/bin/env bash
set -e

# ==============================================================================
# Sub2API 自维护分支上游同步脚本
# ==============================================================================
# 作用：
# 1. 检查并确保 upstream remote 指向 Wei-Shaw/sub2api
# 2. 拉取 upstream 最新 commit 及 tags
# 3. 快进更新本地 upstream-main 分支并推送到 origin
# 4. 切换到 custom 分支，将 upstream-main 合并到 custom
# 5. 提示用户完成验证后推送到 origin/custom 触发 Docker 镜像自动构建
# ==============================================================================

echo "==> 检查 Git 远程仓库配置..."
if ! git remote | grep -q "^upstream$"; then
    echo "未找到 upstream 远程源，正在添加 https://github.com/Wei-Shaw/sub2api.git ..."
    git remote add upstream https://github.com/Wei-Shaw/sub2api.git
fi

echo "==> 正在抓取上游 (upstream) 最新代码及标签..."
git fetch upstream --tags --prune

echo "==> 正在同步 upstream-main 分支..."
# 确保本地有 upstream-main 分支
if git show-ref --verify --quiet refs/heads/upstream-main; then
    git checkout upstream-main
else
    git checkout -b upstream-main upstream/main
fi

git merge --ff-only upstream/main
echo "==> 推送 upstream-main 到 origin..."
git push origin upstream-main --tags || echo "（推送 upstream-main 跳过或需鉴权）"

echo "==> 切回 custom 分支并合并上游更新..."
git checkout custom
git merge upstream-main

echo "=================================================================="
echo "✅ 上游合并成功！"
echo "下一步建议："
echo "1. 执行本地测试以确保自定义修改与上游代码兼容。"
echo "2. 推送至 GitHub 触发自动镜像构建："
echo "   git push origin custom"
echo "=================================================================="
