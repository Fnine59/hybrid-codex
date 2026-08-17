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
mkdir -p "$asset_dir" "$package_dir" "$mock_bin" "$install_bin"

# These variables and command substitutions belong to the generated fixture.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:-}" in' \
  '  --version) echo "codex-cli test" ;;' \
  '  --check-host) "$(dirname "$0")/codex-code-mode-host" ;;' \
  '  *) exit 2 ;;' \
  'esac' \
  > "$package_dir/hybrid-codex"
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

old_version_dir="$install_root/versions/hybrid-v0.145.0-p1"
previous_version_dir="$install_root/versions/hybrid-v0.146.0-p1"
current_link="$install_root/current"
command_link="$install_bin/hybrid-codex"
legacy_host_link="$install_bin/codex-code-mode-host"
mkdir -p "$old_version_dir" "$previous_version_dir"
ln -s "$previous_version_dir" "$current_link"
ln -s "$current_link/hybrid-codex" "$command_link"
ln -s "$current_link/codex-code-mode-host" "$legacy_host_link"

PATH="$mock_bin:$PATH" \
HYBRID_CODEX_TEST_ASSET_DIR="$asset_dir" \
HYBRID_CODEX_INSTALL_ROOT="$install_root" \
HYBRID_CODEX_BIN_DIR="$install_bin" \
  "$installer" "$release_tag"

launcher_path="$install_root/hybrid-codex-launcher"
[[ -L "$current_link" ]]
[[ -L "$command_link" ]]
[[ "$(readlink "$current_link")" == "$install_root/versions/$release_tag" ]]
[[ "$(readlink "$command_link")" == "$launcher_path" ]]
[[ -f "$launcher_path" ]]
[[ ! -L "$launcher_path" ]]
[[ -x "$command_link" ]]
[[ ! -e "$legacy_host_link" && ! -L "$legacy_host_link" ]]
[[ "$($command_link --version)" == "codex-cli test" ]]
[[ "$($command_link --check-host)" == "code-mode-host test" ]]
[[ ! -e "$old_version_dir" ]]
[[ -d "$previous_version_dir" ]]
[[ -d "$install_root/versions/$release_tag" ]]

# Reinstalling the active version must not discard the only rollback version.
PATH="$mock_bin:$PATH" \
HYBRID_CODEX_TEST_ASSET_DIR="$asset_dir" \
HYBRID_CODEX_INSTALL_ROOT="$install_root" \
HYBRID_CODEX_BIN_DIR="$install_bin" \
  "$installer" "$release_tag"
[[ -d "$previous_version_dir" ]]
[[ "$($command_link --check-host)" == "code-mode-host test" ]]

# A same-named host entry not created by this installer must remain untouched.
foreign_host_target="$test_root/foreign-code-mode-host"
printf '%s\n' '#!/usr/bin/env bash' 'echo "foreign host"' > "$foreign_host_target"
chmod 0755 "$foreign_host_target"
ln -s "$foreign_host_target" "$legacy_host_link"
PATH="$mock_bin:$PATH" \
HYBRID_CODEX_TEST_ASSET_DIR="$asset_dir" \
HYBRID_CODEX_INSTALL_ROOT="$install_root" \
HYBRID_CODEX_BIN_DIR="$install_bin" \
  "$installer" "$release_tag"
[[ "$(readlink "$legacy_host_link")" == "$foreign_host_target" ]]

# A failed first launch must restore the previous current link and discard the
# newly extracted unusable version.
failed_release_tag="hybrid-v0.147.0-p3"
# The positional parameter belongs to the generated fixture.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "${1:-}" == "--version" ]]; then exit 9; fi' \
  'exit 2' \
  > "$package_dir/hybrid-codex"
chmod 0755 "$package_dir/hybrid-codex"
jq -n \
  --arg release_tag "$failed_release_tag" \
  --arg upstream_tag "rust-v0.147.0" \
  --arg source_commit "test" \
  --arg target "aarch64-apple-darwin" \
  '{release_tag: $release_tag, upstream_tag: $upstream_tag, source_commit: $source_commit, target: $target}' \
  > "$package_dir/manifest.json"
tar -C "$package_dir" -czf "$archive" .
(
  cd "$asset_dir"
  shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256"
)
if PATH="$mock_bin:$PATH" \
  HYBRID_CODEX_TEST_ASSET_DIR="$asset_dir" \
  HYBRID_CODEX_INSTALL_ROOT="$install_root" \
  HYBRID_CODEX_BIN_DIR="$install_bin" \
  "$installer" "$failed_release_tag"; then
  echo "Installer unexpectedly kept a version that failed first launch." >&2
  exit 1
fi
[[ "$(readlink "$current_link")" == "$install_root/versions/$release_tag" ]]
[[ ! -e "$install_root/versions/$failed_release_tag" ]]
[[ "$($command_link --check-host)" == "code-mode-host test" ]]

# Likewise, refuse to replace a Hybrid command entry owned by something else.
foreign_command_target="$test_root/foreign-hybrid-codex"
rm "$command_link"
ln -s "$foreign_command_target" "$command_link"
if PATH="$mock_bin:$PATH" \
  HYBRID_CODEX_TEST_ASSET_DIR="$asset_dir" \
  HYBRID_CODEX_INSTALL_ROOT="$install_root" \
  HYBRID_CODEX_BIN_DIR="$install_bin" \
  "$installer" "$release_tag"; then
  echo "Installer unexpectedly replaced a foreign command entry." >&2
  exit 1
fi
[[ "$(readlink "$command_link")" == "$foreign_command_target" ]]

echo "Hybrid installer launcher test passed."
