#!/usr/bin/env bash
set -euo pipefail

export RUST_MIN_STACK="${RUST_MIN_STACK:-8388608}"

repo_root="$(git rev-parse --show-toplevel)"
"$repo_root/scripts/hybrid-codex/test-install-release.sh"
cd "$repo_root/codex-rs"

cargo fmt -- --config imports_granularity=Item --check
just test -p codex-features
just test -p codex-core --lib multi_agent_v2
just test -p codex-core --lib direct_source_uses_configured_plaintext_namespace
just test -p codex-core --test all multi_agent_v2_spawn_sends_agent_message_to_child
