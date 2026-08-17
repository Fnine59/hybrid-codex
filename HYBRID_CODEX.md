# hybrid-codex 维护说明

这个 Fork 为 Codex Multi-Agent V2 增加可选的跨 Provider 明文消息投递。官方行为仍是默认值：

```toml
[features.multi_agent_v2]
enabled = true
message_delivery = "encrypted"
```

需要让 OpenAI 主 Agent 把任务交给不支持 OpenAI 加密参数的三方 Provider 时，使用：

```toml
[features.multi_agent_v2]
enabled = true
message_delivery = "plaintext"
tool_namespace = "agents"
```

`tool_namespace` 使用非保留名称，是因为 OpenAI API 会校验保留的 `collaboration` namespace schema。明文模式会把 `spawn_agent`、`send_message` 和 `followup_task` 的 `message` 作为结构化 `input_text` 投递。若仍选择加密模式却把任务发给非 OpenAI 子 Provider，Codex 会在创建子 Agent 前停止并给出配置提示。

## 分支与上游更新

- `main`：保持为 `openai/codex` 的干净镜像，便于普通 Fork 同步。
- `hybrid`：默认分支，包含补丁、测试、Action 和维护脚本。
- 官方发布新版本后，`scripts/hybrid-codex/sync-upstream.sh` 会先快进 `main`，再把新的官方 Release tag 合并进 `hybrid`。没有冲突时运行补丁测试、推送并触发新 Release；发生冲突时中止合并，留给人工处理。

Release tag 使用 `hybrid-v<官方版本>-p<补丁修订>`，例如 `hybrid-v0.147.0-p1`。这让官方版本和本 Fork 的补丁迭代都能单独识别。

## 本机并存安装

```bash
scripts/hybrid-codex/install-release.sh latest
```

脚本安装到 `~/.local/share/hybrid-codex/versions/<release-tag>/`，并只维护 `~/.local/bin/hybrid-codex` 这一条符号链接。官方 `codex` 的 npm/Homebrew 更新路径不会被修改。切换或回滚只是把这条链接指向另一个版本目录。

macOS 构建由公开仓库的标准 GitHub-hosted runner 产生，没有 OpenAI 官方代码签名；安装脚本会先校验 Release 附带的 SHA-256。

## 监测与本机验收

```bash
scripts/hybrid-codex/release-status.sh
```

这个只读命令输出 JSON，包含最新官方 tag、补丁分支是否已包含它、对应 Hybrid Release 是否存在，以及本机是否已经安装该 Release。它适合由本机 Codex Loop 定时调用。

Loop 每轮的判断和后续处理规则保存在
`scripts/hybrid-codex/LOOP_TASK.md`。它把状态分为“需要同步源码”“等待或检查构建”“安装已发布版本”和“已经是最新”四种情况；同步、构建、安装仍分别由上述可审计脚本执行。合并冲突或测试失败只通知，不会强推或绕过测试。

公开仓库只保存通用源代码和构建流程。Provider 地址、API Key、Profile、Alias 以及真实跨 Provider 验收全部留在本机。GitHub Actions 只做不含凭据的单元测试、模拟集成测试和二进制构建；真实验收必须由本机的新会话完成。
