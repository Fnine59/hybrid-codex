#!/usr/bin/env bash
set -euo pipefail

fork_repo="${HYBRID_CODEX_FORK_REPO:-Fnine59/hybrid-codex}"
upstream_repo="${HYBRID_CODEX_UPSTREAM_REPO:-openai/codex}"
install_root="${HYBRID_CODEX_INSTALL_ROOT:-$HOME/.local/share/hybrid-codex}"
bin_dir="${HYBRID_CODEX_BIN_DIR:-$HOME/.local/bin}"
requested_tag="${1:-latest}"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "当前安装脚本只支持 macOS arm64。" >&2
  exit 2
fi

if [[ "$requested_tag" == "latest" ]]; then
  upstream_tag="$(gh api "repos/${upstream_repo}/releases/latest" --jq .tag_name)"
  upstream_version="${upstream_tag#rust-v}"
  release_prefix="hybrid-v${upstream_version}-p"
  release_tag="$(
    gh release list --repo "$fork_repo" --limit 100 --json tagName \
      --jq "[.[] | select(.tagName | startswith(\"${release_prefix}\"))][0].tagName // \"\""
  )"
  if [[ -z "$release_tag" ]]; then
    echo "尚未找到对应 ${upstream_tag} 的 Hybrid Release。" >&2
    exit 2
  fi
else
  release_tag="$requested_tag"
fi

if [[ ! "$release_tag" =~ ^hybrid-v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?-p[1-9][0-9]*$ ]]; then
  echo "Release tag 格式不合法：$release_tag" >&2
  exit 2
fi

archive="hybrid-codex-aarch64-apple-darwin.tar.gz"
checksum="${archive}.sha256"
download_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$download_dir"
}
trap cleanup EXIT

gh release download "$release_tag" \
  --repo "$fork_repo" \
  --pattern "$archive" \
  --pattern "$checksum" \
  --dir "$download_dir"

(
  cd "$download_dir"
  shasum -a 256 -c "$checksum"
)

archive_entries="$(tar -tzf "$download_dir/$archive" | sed 's#^\./##; /^$/d; /\/$/d' | sort)"
expected_entries="$(printf '%s\n' codex-code-mode-host hybrid-codex manifest.json | sort)"
if [[ "$archive_entries" != "$expected_entries" ]]; then
  echo "Release 包内容不符合预期，拒绝安装。" >&2
  exit 3
fi

versions_dir="$install_root/versions"
version_dir="$versions_dir/$release_tag"
mkdir -p "$versions_dir" "$bin_dir"

if [[ ! -d "$version_dir" ]]; then
  staging_dir="$versions_dir/.${release_tag}.tmp.$$"
  mkdir -p "$staging_dir"
  tar -xzf "$download_dir/$archive" -C "$staging_dir"
  [[ -x "$staging_dir/hybrid-codex" ]]
  [[ -x "$staging_dir/codex-code-mode-host" ]]
  mv "$staging_dir" "$version_dir"
fi

if [[ ! -x "$version_dir/hybrid-codex" || ! -x "$version_dir/codex-code-mode-host" ]]; then
  echo "$version_dir 内容不完整，拒绝切换当前版本。" >&2
  exit 3
fi
if ! jq -e --arg release_tag "$release_tag" '.release_tag == $release_tag' \
  "$version_dir/manifest.json" >/dev/null; then
  echo "$version_dir 的 manifest 与 Release tag 不一致，拒绝切换。" >&2
  exit 3
fi

command_link="$bin_dir/hybrid-codex"
current_link="$install_root/current"
if [[ -e "$command_link" && ! -L "$command_link" ]]; then
  echo "$command_link 已存在且不是符号链接，拒绝覆盖。" >&2
  exit 4
fi
if [[ -e "$current_link" && ! -L "$current_link" ]]; then
  echo "$current_link 已存在且不是符号链接，拒绝覆盖。" >&2
  exit 4
fi

ln -sfn "$version_dir/hybrid-codex" "$command_link"
ln -sfn "$version_dir" "$current_link"

"$command_link" --version
echo "已安装 $release_tag 到 $version_dir"
echo "官方 codex 未修改；补丁命令为 $command_link"
