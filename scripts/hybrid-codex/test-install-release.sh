#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
installer="$repo_root/scripts/hybrid-codex/install-release.sh"
test_root="$(mktemp -d)"
cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

release_tag="hybrid-v0.147.0-p2"
asset_dir="$test_root/assets"
package_dir="$test_root/package"
mock_bin="$test_root/mock-bin"
install_root="$test_root/install-root"
install_bin="$test_root/install-bin"
mkdir -p "$asset_dir" "$package_dir" "$mock_bin"

printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-cli test"' > "$package_dir/hybrid-codex"
printf '%s\n' '#!/usr/bin/env bash' 'echo "code-mode-host test"' > "$package_dir/codex-code-mode-host"
chmod 0755 "$package_dir/hybrid-codex" "$package_dir/codex-code-mode-host"
jq -n \
  --arg release_tag "$release_tag" \
  --arg upstream_tag "rust-v0.147.0" \
  --arg source_commit "test" \
  --arg target "aarch64-apple-darwin" \
  '{release_tag: $release_tag, upstream_tag: $upstream_tag, source_commit: $source_commit, target: $target}' \
  > "$package_dir/manifest.json"

archive="$asset_dir/hybrid-codex-aarch64-apple-darwin.tar.gz"
tar -C "$package_dir" -czf "$archive" .
(
  cd "$asset_dir"
  shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256"
)

# These variables belong to the generated mock and must expand when it runs.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'download_dir=""' \
  'while [[ $# -gt 0 ]]; do' \
  '  if [[ "$1" == "--dir" ]]; then' \
  '    download_dir="$2"' \
  '    shift 2' \
  '  else' \
  '    shift' \
  '  fi' \
  'done' \
  '[[ -n "$download_dir" ]]' \
  'cp "$HYBRID_CODEX_TEST_ASSET_DIR"/* "$download_dir"/' \
  > "$mock_bin/gh"
# The positional parameter belongs to the generated mock.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in' \
  '  -s) echo Darwin ;;' \
  '  -m) echo arm64 ;;' \
  '  *) exit 2 ;;' \
  'esac' \
  > "$mock_bin/uname"
chmod 0755 "$mock_bin/gh" "$mock_bin/uname"

PATH="$mock_bin:$PATH" \
HYBRID_CODEX_TEST_ASSET_DIR="$asset_dir" \
HYBRID_CODEX_INSTALL_ROOT="$install_root" \
HYBRID_CODEX_BIN_DIR="$install_bin" \
  "$installer" "$release_tag"

current_link="$install_root/current"
command_link="$install_bin/hybrid-codex"
host_link="$install_bin/codex-code-mode-host"
[[ -L "$current_link" ]]
[[ -L "$command_link" ]]
[[ -L "$host_link" ]]
[[ "$(readlink "$current_link")" == "$install_root/versions/$release_tag" ]]
[[ "$(readlink "$command_link")" == "$current_link/hybrid-codex" ]]
[[ "$(readlink "$host_link")" == "$current_link/codex-code-mode-host" ]]
[[ -x "$command_link" ]]
[[ -x "$host_link" ]]
[[ "$($command_link --version)" == "codex-cli test" ]]
[[ "$($host_link)" == "code-mode-host test" ]]

echo "Hybrid installer link test passed."
