# Hybrid Codex 单轮维护任务

在仓库根目录执行且每轮只处理一次：

1. 运行 `scripts/hybrid-codex/release-status.sh`，读取它输出的 JSON。
2. 如果 `source_contains_upstream` 为 `false`，运行
   `scripts/hybrid-codex/sync-upstream.sh`。它会同步官方 `main`、把最新官方 Release tag
   合并到 `hybrid`、执行补丁测试、推送并触发一个新的 Hybrid Release 构建。若发生合并冲突或测试失败，停止本轮并通知用户，不要绕过测试或强推。
3. 如果源码已包含最新上游版本，但 `release_current` 为 `false`，用 `gh run list` 和
   `gh run view` 检查 `hybrid-codex.yml` 的最新运行：排队或构建中则等待下一轮；失败则把失败步骤和运行链接通知用户。不要重复触发仍在运行的构建。
4. 如果 `release_current` 为 `true` 而 `installed_current` 为 `false`，运行
   `scripts/hybrid-codex/install-release.sh latest`，然后核对 `hybrid-codex --version` 与
   `~/.local/share/hybrid-codex/current/manifest.json`。只更新 Hybrid Codex 的版本化安装和符号链接。
5. 如果三项状态都已是最新，不做写操作，只报告当前官方 tag、Hybrid Release tag 和本机安装 tag。

安全边界：绝不改动或覆盖官方 `codex`；绝不读取、打印、提交或上传 Provider 地址、API Key、Profile、Alias 和其他本机凭据；定时任务不自动执行真实 Provider 调用。真实跨 Provider 验收只在版本变化后由用户明确启动的新 Hybrid Codex 会话完成。
