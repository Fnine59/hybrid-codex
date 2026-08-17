#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

upstream_repo="${HYBRID_CODEX_UPSTREAM_REPO:-openai/codex}"
fork_repo="${HYBRID_CODEX_FORK_REPO:-Fnine59/hybrid-codex}"
patch_branch="${HYBRID_CODEX_PATCH_BRANCH:-hybrid}"
install_root="${HYBRID_CODEX_INSTALL_ROOT:-$HOME/.local/share/hybrid-codex}"

upstream_tag="$(gh api "repos/${upstream_repo}/releases/latest" --jq .tag_name)"
upstream_version="${upstream_tag#rust-v}"
release_prefix="hybrid-v${upstream_version}-p"

latest_hybrid_tag="$(
  gh release list --repo "$fork_repo" --limit 100 --json tagName \
    --jq "[.[] | select(.tagName | startswith(\"${release_prefix}\"))][0].tagName // \"\""
)"

source_contains_upstream=false
if git rev-parse --verify --quiet "$upstream_tag" >/dev/null \
  && git rev-parse --verify --quiet "$patch_branch" >/dev/null \
  && git merge-base --is-ancestor "$upstream_tag" "$patch_branch"; then
  source_contains_upstream=true
fi

installed_tag=""
if [[ -f "$install_root/current/manifest.json" ]]; then
  installed_tag="$(jq -r '.release_tag // ""' "$install_root/current/manifest.json")"
fi

release_current=false
if [[ -n "$latest_hybrid_tag" ]]; then
  release_current=true
fi

installed_current=false
if [[ -n "$latest_hybrid_tag" && "$installed_tag" == "$latest_hybrid_tag" ]]; then
  installed_current=true
fi

jq -n \
  --arg upstream_repo "$upstream_repo" \
  --arg fork_repo "$fork_repo" \
  --arg patch_branch "$patch_branch" \
  --arg upstream_tag "$upstream_tag" \
  --arg latest_hybrid_tag "$latest_hybrid_tag" \
  --arg installed_tag "$installed_tag" \
  --argjson source_contains_upstream "$source_contains_upstream" \
  --argjson release_current "$release_current" \
  --argjson installed_current "$installed_current" \
  '{
    upstream_repo: $upstream_repo,
    fork_repo: $fork_repo,
    patch_branch: $patch_branch,
    upstream_tag: $upstream_tag,
    source_contains_upstream: $source_contains_upstream,
    latest_hybrid_tag: $latest_hybrid_tag,
    release_current: $release_current,
    installed_tag: $installed_tag,
    installed_current: $installed_current
  }'
