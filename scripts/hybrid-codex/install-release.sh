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
launcher_tmp=""
staging_dir=""
cleanup() {
  rm -rf "$download_dir"
  if [[ -n "$launcher_tmp" ]]; then
    rm -f "$launcher_tmp"
  fi
  if [[ -n "$staging_dir" ]]; then
    rm -rf "$staging_dir"
  fi
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
installed_new_version=false
mkdir -p "$versions_dir" "$bin_dir"

if [[ -L "$version_dir" ]]; then
  echo "$version_dir 是符号链接，拒绝作为版本目录使用。" >&2
  exit 4
fi
if [[ ! -d "$version_dir" ]]; then
  staging_dir="$(mktemp -d "$versions_dir/.${release_tag}.tmp.XXXXXX")"
  tar -xzf "$download_dir/$archive" -C "$staging_dir"
  [[ -x "$staging_dir/hybrid-codex" ]]
  [[ -x "$staging_dir/codex-code-mode-host" ]]
  mv "$staging_dir" "$version_dir"
  staging_dir=""
  installed_new_version=true
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

current_link="$install_root/current"
command_link="$bin_dir/hybrid-codex"
launcher_path="$install_root/hybrid-codex-launcher"
legacy_host_link="$bin_dir/codex-code-mode-host"
previous_version_dir=""

if [[ ( -e "$current_link" || -L "$current_link" ) && ! -L "$current_link" ]]; then
  echo "$current_link 已存在且不是符号链接，拒绝覆盖。" >&2
  exit 4
fi
if [[ -L "$current_link" ]]; then
  previous_target="$(readlink "$current_link")"
  previous_name="${previous_target#"$versions_dir/"}"
  if [[ "$previous_target" == "$versions_dir/"* \
    && "$previous_name" != */* \
    && "$previous_name" =~ ^hybrid-v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?-p[1-9][0-9]*$ \
    && -d "$previous_target" \
    && ! -L "$previous_target" ]]; then
    previous_version_dir="$previous_target"
  elif [[ -e "$current_link" ]]; then
    echo "$current_link 指向非托管目录，拒绝覆盖。" >&2
    exit 4
  fi
fi

if [[ -e "$command_link" || -L "$command_link" ]]; then
  if [[ ! -L "$command_link" ]]; then
    echo "$command_link 已存在且不是符号链接，拒绝覆盖。" >&2
    exit 4
  fi
  command_target="$(readlink "$command_link")"
  if [[ "$command_target" != "$current_link/hybrid-codex" && "$command_target" != "$launcher_path" ]]; then
    echo "$command_link 不是本安装器管理的入口，拒绝覆盖。" >&2
    exit 4
  fi
fi

if [[ -e "$launcher_path" || -L "$launcher_path" ]]; then
  if [[ ! -f "$launcher_path" || -L "$launcher_path" ]] \
    || ! grep -Fqx '# Managed by the hybrid-codex installer.' "$launcher_path"; then
    echo "$launcher_path 不是本安装器管理的启动器，拒绝覆盖。" >&2
    exit 4
  fi
fi

launcher_tmp="$(mktemp "$install_root/.hybrid-codex-launcher.XXXXXX")"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# Managed by the hybrid-codex installer.'
  printf '%s\n' 'set -euo pipefail'
  printf 'exec %q "$@"\n' "$current_link/hybrid-codex"
} > "$launcher_tmp"
chmod 0755 "$launcher_tmp"
mv -f "$launcher_tmp" "$launcher_path"
launcher_tmp=""
ln -sfn "$launcher_path" "$command_link"
ln -sfn "$version_dir" "$current_link"

if ! "$command_link" --version || [[ ! -x "$current_link/codex-code-mode-host" ]]; then
  if [[ -n "$previous_version_dir" ]]; then
    ln -sfn "$previous_version_dir" "$current_link"
  else
    rm -f "$current_link"
  fi
  if [[ "$installed_new_version" == true ]]; then
    rm -rf -- "$version_dir"
  fi
  echo "新版本启动校验失败，已恢复先前版本。" >&2
  exit 5
fi

if [[ -L "$legacy_host_link" ]] \
  && [[ "$(readlink "$legacy_host_link")" == "$current_link/codex-code-mode-host" ]]; then
  rm "$legacy_host_link"
  echo "已移除旧版公共 Code Mode host 入口：$legacy_host_link"
elif [[ -e "$legacy_host_link" || -L "$legacy_host_link" ]]; then
  echo "保留非本安装器管理的同名入口：$legacy_host_link" >&2
fi

if [[ -n "$previous_version_dir" && "$previous_version_dir" != "$version_dir" ]]; then
  for candidate in "$versions_dir"/hybrid-v*-p*; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    if [[ "$candidate" == "$version_dir" || "$candidate" == "$previous_version_dir" ]]; then
      continue
    fi
    rm -rf -- "$candidate"
    echo "已清理旧版本：$candidate"
  done
fi

echo "已安装 $release_tag 到 $version_dir"
echo "官方 codex 未修改；补丁命令为 $command_link"
