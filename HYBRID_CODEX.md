# Hybrid Codex 使用与维护指南

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

## 适用边界

这个补丁只解决 Multi-Agent V2 的跨 Provider 消息格式兼容问题。第三方服务仍需满足以下条件：

- 能作为 Codex `model_provider` 正常完成单模型调用；
- 支持 Codex 当前使用的 Responses API、流式响应和 Tool Calling；
- 子 Agent 使用独立角色配置，并通过 `fork_turns="none"` 接收自包含任务；
- Provider 的认证信息只保存在本机环境或凭据管理工具中。

这里的“明文”是指 Agent 间任务不再携带 OpenAI 专用的加密字段，不代表关闭 HTTPS。任务内容会对第三方 Provider 可见，因此委派内容不应包含凭据或其他敏感信息。

## 在新设备上配置

当前预构建 Release 和安装脚本只支持 macOS arm64。其他平台需要按照上游构建文档从源码编译，并自行保留 `codex-code-mode-host` 与主程序的同目录布局。

### 1. 安装 Hybrid Codex

新设备需要先安装 `git`、GitHub CLI `gh` 和 `jq`，并完成 GitHub CLI 登录：

```bash
git clone --branch hybrid https://github.com/Fnine59/hybrid-codex.git
cd hybrid-codex
gh auth status
scripts/hybrid-codex/install-release.sh latest
hybrid-codex --version
```

安装器只创建 `hybrid-codex` 入口，不会替换官方 `codex`。

### 2. 注册第三方 Provider

示例位于 [`examples/hybrid-codex/provider-config.toml.example`](examples/hybrid-codex/provider-config.toml.example)。将其中的结构按需合并进 `~/.codex/config.toml`，不要覆盖已有的登录、MCP、插件或其他 Provider 配置。

示例中的域名使用保留的 `.invalid` 顶级域，Provider 名称、模型名称和环境变量名均为虚构占位值。使用时必须替换为目标服务自己的值。Key 不写入 TOML，只在本机设置 `env_key` 所指向的环境变量。

### 3. 安装隔离 Profile 和角色文件

```bash
mkdir -p ~/.codex/agents
cp examples/hybrid-codex/hybrid.config.toml.example ~/.codex/hybrid.config.toml
cp examples/hybrid-codex/agents/sample-general.toml.example ~/.codex/agents/sample-general.toml
cp examples/hybrid-codex/agents/sample-editor.toml.example ~/.codex/agents/sample-editor.toml
cp examples/hybrid-codex/agents/sample-reader.toml.example ~/.codex/agents/sample-reader.toml
```

然后只在本机副本中完成以下替换：

- 把 `example_provider` 改为 `~/.codex/config.toml` 中注册的 Provider ID；
- 把 `example-model` 改为第三方服务实际提供的模型 ID；
- 根据任务权限调整三个角色的说明，但继续要求 `fork_turns="none"`；
- 不要把修改后的本机文件、Endpoint 或 Key 提交回这个公开仓库。

`hybrid.config.toml` 是最小覆盖层：主 Agent 继续继承基础配置，只有内置子 Agent 角色切换到示例指定的 Provider。补丁开关也只在这个 Profile 中生效，不改变普通 `codex` 会话。

### 4. 启动

```bash
hybrid-codex --profile hybrid
```

如需短命令，可以在本机 Shell 配置中自行加入：

```zsh
alias hybridcodex='hybrid-codex --profile hybrid'
```

Alias 只负责组合 Hybrid 二进制和 Profile，不应内嵌 Endpoint、Key、代理地址或其他机器专属配置。

### 5. 验收

先检查 Profile 是否能够加载：

```bash
hybrid-codex --profile hybrid debug prompt-input "配置加载检查"
```

再新开一个 `hybrid-codex --profile hybrid` 会话，执行一次最小子任务。验收时应同时确认：

- 父 Agent 仍使用预期的主 Provider；
- child rollout 使用目标第三方 Provider 和模型；
- 子 Agent 没有继承父会话历史，并且收到的任务文本非空；
- 第三方服务端存在对应调用记录；
- 不以子 Agent 自报的 Provider 或模型作为唯一证据。

如果第三方 Provider 能独立调用，却在创建子 Agent 时失败，依次检查 Profile 是否被选中、`message_delivery` 是否为 `plaintext`、`tool_namespace` 是否为 `agents`，以及委派是否显式使用 `fork_turns="none"`。

## 分支与上游更新

- `main`：保持为 `openai/codex` 的干净镜像，便于普通 Fork 同步。
- `hybrid`：默认分支，包含补丁、测试、Action 和维护脚本。
- 官方发布新版本后，`scripts/hybrid-codex/sync-upstream.sh` 会先快进 `main`，再把新的官方 Release tag 合并进 `hybrid`。没有冲突时运行补丁测试、推送并触发新 Release；发生冲突时中止合并，留给人工处理。

Release tag 使用 `hybrid-v<官方版本>-p<补丁修订>`，例如 `hybrid-v0.147.0-p1`。这让官方版本和本 Fork 的补丁迭代都能单独识别。

## 本机并存安装

```bash
scripts/hybrid-codex/install-release.sh latest
```

脚本安装到 `~/.local/share/hybrid-codex/versions/<release-tag>/`，通过 `~/.local/share/hybrid-codex/current` 选择当前版本，并只向 `PATH` 暴露一条稳定入口：

- `~/.local/bin/hybrid-codex`：指向受安装器管理的轻量启动器；启动器直接执行 `current/hybrid-codex`。

`codex-code-mode-host` 只保存在版本目录，与 `hybrid-codex` 主程序保持同目录，不再占用 `~/.local/bin/codex-code-mode-host` 这个公共名称。安装器会安全移除自己创建的旧 host 链接，但遇到非托管的同名文件或链接时会保留不动。

官方 `codex` 的 npm/Homebrew 更新路径不会被修改。切换或回滚只更新 Hybrid 自己的 `current` 链接；成功切换到新版本后，安装器仅保留当前版本和切换前的上一版本，并清理更早的托管版本。重复安装当前版本不会删除现有的回滚版本。

macOS 构建由公开仓库的标准 GitHub-hosted runner 产生，没有 OpenAI 官方代码签名；安装脚本会先校验 Release 附带的 SHA-256。

## 监测与本机验收

```bash
scripts/hybrid-codex/release-status.sh
```

这个只读命令输出 JSON，包含最新官方 tag、补丁分支是否已包含它、对应 Hybrid Release 是否存在，以及本机是否已经安装该 Release。它适合由本机 Codex Loop 定时调用。

Loop 每轮的判断和后续处理规则保存在
`scripts/hybrid-codex/LOOP_TASK.md`。它把状态分为“需要同步源码”“等待或检查构建”“安装已发布版本”和“已经是最新”四种情况；同步、构建、安装仍分别由上述可审计脚本执行。合并冲突或测试失败只通知，不会强推或绕过测试。

公开仓库只保存通用源代码、构建流程和无凭据示例。Provider 地址、API Key、实际模型 ID、修改后的 Profile、Alias 以及真实跨 Provider 验收结果全部留在本机。GitHub Actions 只做不含凭据的单元测试、模拟集成测试和二进制构建；真实验收必须由本机的新会话完成。
