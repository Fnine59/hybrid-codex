# Hybrid Codex 单轮维护任务

在仓库根目录执行且每轮只处理一次：

1. 运行 `scripts/hybrid-codex/release-status.sh`，读取它输出的 JSON。
2. 如果 `source_contains_upstream` 为 `false`，运行
   `scripts/hybrid-codex/sync-upstream.sh`。它会同步官方 `main`、把最新官方 Release tag
   合并到 `hybrid`、执行补丁测试、推送并触发一个新的 Hybrid Release 构建。发生合并冲突时，默认由 Loop 自己解决：完成合并、运行 `scripts/hybrid-codex/test-patch.sh`、提交并推送，然后继续触发新的 Hybrid Release 构建。唯一的例外是冲突触及补丁核心能力（MultiAgentV2 明文跨 Provider 投递）本身，导致补丁没必要（上游已实现等价能力）或不成立、没法用（补丁依赖的 API 或机制被上游不兼容改动）：此时停止本轮并询问用户。测试失败仍必须停止本轮并通知用户，绝不绕过测试或强推。
3. 如果源码已包含最新上游版本，但 `release_current` 为 `false`，用 `gh run list` 和
   `gh run view` 检查 `hybrid-codex.yml` 的最新运行：排队或构建中则等待下一轮；失败则把失败步骤和运行链接通知用户。不要重复触发仍在运行的构建。

备注：本机跑过 `test-patch.sh` 等 cargo 命令后，`codex-rs/Cargo.lock` 会被 cargo 规范化
（workspace 内部 crate 版本从上游约定的 `0.0.0` 变成实际版本）。这是预期的本地产物，不影响
构建；同步前用 `git restore codex-rs/Cargo.lock` 丢弃即可，不要提交。

备注：`sync-upstream.sh` 中的 `git fetch upstream --tags` 遇到上游强制更新的 tag（如 alpha
tag）会因 "would clobber existing tag" 失败并中断脚本。此时先执行 `git fetch upstream
--tags --force` 再重跑脚本。

备注：本仓库是 blob:none 部分克隆，promisor 是 origin。合并新的上游 tag 时可能因 origin
尚没有该 tag 的对象而报 "could not fetch ... from promisor remote"。此时先执行
`git fetch upstream <tag> --no-tags` 从上游直接补齐对象，再重跑脚本。
4. 如果 `release_current` 为 `true` 而 `installed_current` 为 `false`，运行
   `scripts/hybrid-codex/install-release.sh latest`，然后核对 `hybrid-codex --version` 与
   `~/.local/share/hybrid-codex/current/manifest.json`。只更新 Hybrid Codex 的版本化安装和符号链接。
5. 如果三项状态都已是最新，不做写操作，只报告当前官方 tag、Hybrid Release tag 和本机安装 tag。

安全边界：绝不改动或覆盖官方 `codex`；绝不读取、打印、提交或上传 Provider 地址、API Key、Profile、Alias 和其他本机凭据；定时任务不自动执行真实 Provider 调用。自动解决合并冲突只允许调整补丁与上游的衔接，不得删除或削弱明文跨 Provider 投递这一补丁核心能力。真实跨 Provider 验收只在版本变化后由用户明确启动的新 Hybrid Codex 会话完成。
