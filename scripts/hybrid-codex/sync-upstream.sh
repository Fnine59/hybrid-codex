#!/usr/bin/env bash
set -euo pipefail

upstream_repo="${HYBRID_CODEX_UPSTREAM_REPO:-openai/codex}"
fork_repo="${HYBRID_CODEX_FORK_REPO:-Fnine59/hybrid-codex}"
patch_branch="${HYBRID_CODEX_PATCH_BRANCH:-hybrid}"
upstream_remote="${HYBRID_CODEX_UPSTREAM_REMOTE:-upstream}"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "工作区不干净，拒绝自动同步。" >&2
  exit 2
fi

if ! git remote get-url "$upstream_remote" >/dev/null 2>&1; then
  git remote add "$upstream_remote" "https://github.com/${upstream_repo}.git"
fi

git fetch "$upstream_remote" --tags
git fetch origin

upstream_tag="$(gh api "repos/${upstream_repo}/releases/latest" --jq .tag_name)"
upstream_version="${upstream_tag#rust-v}"

git checkout main
git merge --ff-only "${upstream_remote}/main"
git push origin main

git checkout "$patch_branch"
if ! git merge-base --is-ancestor "$upstream_tag" HEAD; then
  if ! git merge --no-edit "$upstream_tag"; then
    git merge --abort
    echo "上游 ${upstream_tag} 与补丁发生冲突；已中止合并，需要人工修复。" >&2
    exit 3
  fi
fi

scripts/hybrid-codex/test-patch.sh
git push origin "$patch_branch"

patch_revision=1
while gh release view "hybrid-v${upstream_version}-p${patch_revision}" --repo "$fork_repo" >/dev/null 2>&1; do
  patch_revision=$((patch_revision + 1))
done
release_tag="hybrid-v${upstream_version}-p${patch_revision}"

gh workflow run hybrid-codex.yml \
  --repo "$fork_repo" \
  --ref "$patch_branch" \
  -f "upstream_tag=${upstream_tag}" \
  -f "release_tag=${release_tag}"

echo "已触发 ${release_tag} 构建。"
