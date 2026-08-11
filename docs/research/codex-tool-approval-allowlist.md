# Codex 工具免审批名单调研

## 结论

本次调研针对仓库锁定的 Codex `rust-v0.147.0`（commit
`be6e8eac029b183056b7e4402879f15d2c85f61b`）。锁定记录见
[`packaging/codex.lock.json`](../../packaging/codex.lock.json)，子模块当前也指向
该提交。

结论分工具类型：

1. **MCP 工具和 Connected Apps 工具：支持按工具设置免审批。** 原生字段是
   `approval_mode = "approve"`，不是一个统一的顶层
   `allowed_tools_without_approval` 名单。可以同时用 `enabled_tools` 做工具暴露
   allowlist，但它只决定哪些工具注册给模型，不代表这些工具免审批。
2. **shell/exec 命令：没有按“工具名”的免审批名单。** Codex 有独立的
   execpolicy 前缀规则，可以对命令 argv 设置 `decision = "allow"`；这是一份
   命令前缀策略，不是 MCP 或内置工具名称名单。
3. **本仓库当前的 `/etc/codex/config.toml` 不能单独承担管理员强制策略。** 文件
   自身明确是低优先级 system default，用户配置、profile 或 `-c` 可以覆盖它。
   Connected Apps 的按工具策略可放在 `/etc/codex/requirements.toml`，由 managed
   requirements 优先应用；普通 MCP 的按工具审批字段没有对应的 requirements
   强制字段。

## 能力和字段

### MCP 工具

`AppToolApproval` 的枚举值为 `auto`、`prompt`、`writes`、`approve`。MCP server
有 `default_tools_approval_mode`、`enabled_tools`、`disabled_tools` 和按名称索引
的 `tools.<name>.approval_mode`。源码将 `enabled_tools` 明确定义为“只注册这些
工具”的暴露 allowlist；`disabled_tools` 在其后继续过滤。

```toml
[mcp_servers.docs]
command = "docs-server"
default_tools_approval_mode = "prompt"
enabled_tools = ["search", "read"]

[mcp_servers.docs.tools.search]
approval_mode = "approve"

[mcp_servers.docs.tools.read]
approval_mode = "approve"
```

审批行为由 `requires_mcp_tool_approval_for_mode` 实现：`approve` 直接返回不需要
审批，`prompt` 总是需要审批，`writes` 对未声明 read-only 的工具要求审批，`auto`
按 MCP annotations（例如 `readOnlyHint`、`destructiveHint`、`openWorldHint`）判断。
`mcp_permission_prompt_is_auto_approved` 还会在 `approve` 模式下直接把 MCP 权限
请求视为已批准；调用审批函数在这一步直接短路，不再显示普通 MCP 审批提示。因此
这里的 `approve` 确实是 Codex 工具审批层面的免提示设置，但它不等于全局
`--dangerously-bypass-approvals-and-sandbox`，也不替代其他独立的启用、沙箱和服务端
授权检查。

若希望一个 server 下所有已暴露工具都使用同一模式，可以写：

```toml
[mcp_servers.docs]
default_tools_approval_mode = "approve"
```

这不是名单，且会把该 server 的所有暴露工具都设为同一模式。按工具覆盖优先于
server 默认值。

插件提供的 MCP server 也复用 `default_tools_approval_mode`、`enabled_tools`、
`disabled_tools` 和 `tools.<name>.approval_mode`，配置形状为
`[plugins.<plugin>.mcp_servers.<server>]`；它仍属于用户配置的 policy overlay，
不是普通 MCP 的管理员 requirements 强制层。

### Connected Apps

Apps 使用 `[apps._default]`、`[apps.<app-id>]` 和
`[apps.<app-id>.tools.<tool-name>]`。优先级是 managed tool requirements、工具级
`approval_mode`、app 级 `default_tools_approval_mode`、`apps._default` 默认值；
未配置时默认为 `auto`。官方仓库的 app-server 文档给出了完整的模式和优先级说明。

用户配置示例：

```toml
[apps.demo-app.tools."repos/list"]
approval_mode = "approve"
```

管理员 managed requirements 示例：

```toml
# /etc/codex/requirements.toml
[apps.demo-app.tools."repos/list"]
approval_mode = "approve"
```

`AppsRequirementsToml` 的解析类型只允许每个 app/tool 指定
`approval_mode`，而 `connectors::AppToolPolicyEvaluator` 在计算有效策略时先取
managed approval，再取用户配置。因此这是当前源码中适合“管理员内置按工具免审批
名单”的路径，前提是目标是 Connected Apps，而不是普通 MCP server。

`enabled`、`destructive_enabled`、`open_world_enabled` 与审批模式是不同控制面：
`approve` 不会把一个被禁用或被 hint 过滤的工具重新暴露。

### shell/exec

execpolicy 从各配置层的 `<config-folder>/rules/*.rules` 读取规则，支持
`prefix_rule(pattern=[...], decision="allow|prompt|forbidden")`。当每个解析出的
命令片段都有显式 `allow` 规则时，exec 审批层返回 `ExecApprovalRequirement::Skip`；
这适用于命令 argv 前缀，不适用于 MCP/Apps 工具名。

```starlark
prefix_rule(
    pattern = ["rg", "--files"],
    decision = "allow",
    justification = "read-only file listing",
)
```

`approval_policy = "never"` 是全局命令审批模式，不是名单：它禁止请求审批，失败
直接返回模型；危险命令仍可因启发式或 sandbox 策略被拒绝。`untrusted` 只自动放行
内置已知安全的读命令。当前 `requirements.toml` 的 `[rules]` 转换器反而明确拒绝
`decision = "allow"`，因为 managed rules 与其他配置合并时采用更严格结果；它可
用于 managed `prompt`/`forbidden` 约束，但不能用来发布管理员 allow 规则。

当前版本的 `--approve-for-me` 也不是免审批名单：CLI 测试显示它注入
`approvals_reviewer="auto_review"`、`approval_policy="on-request"` 和
`sandbox_mode="workspace-write"`，仍然走自动审查流程。

## 对本仓库的影响

根目录 [`config.toml`](../../config.toml) 的注释说明它安装为
`/etc/codex/config.toml`，是低优先级 system default，用户可以从
`~/.codex/config.toml`、profile 或 `-c` 覆盖。因此把 MCP 或 Apps 的
`approval_mode = "approve"` 写入该文件，只能提供默认值，不能表达“用户不可改”的
管理员策略。

可行性建议：

- 若需求是 Connected Apps 的少量工具免审批，使用
  `/etc/codex/requirements.toml` 的 `[apps.<app-id>.tools.<tool>]` 条目，并让
  requirements 层承担强制优先级。
- 若需求是普通 MCP server，Codex 有 per-tool `approve` 字段和
  `enabled_tools` 暴露名单，但在当前版本没有普通 MCP per-tool approval 的
  requirements 字段；系统 `config.toml` 只能作默认，不能阻止用户高优先级覆盖。
- 若需求是 shell 命令，使用 `rules/*.rules` 的命令前缀策略时要把它视为命令
  allowlist，并单独评估配置层优先级、sandbox 和危险命令启发式。不要把它描述成
  “工具名单”。

## 一手来源

以下链接固定到本仓库锁定的上游提交，避免把结论误套到未来版本：

- [上游 config schema: `AppToolApproval`、MCP tool fields](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/core/config.schema.json#L1562-L1575)；本地副本为
  [`submodules/codex/codex-rs/core/config.schema.json`](../../submodules/codex/codex-rs/core/config.schema.json)。
- [上游 MCP config types](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/config/src/mcp_types.rs#L23-L31)，以及 server 的默认审批、暴露 allowlist 和按工具设置
  [同文件](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/config/src/mcp_types.rs#L201-L231)。
- [上游 MCP approval mode 判定](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/core/src/mcp_tool_call.rs#L2179-L2190) 和 [MCP permission auto-approve](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/codex-mcp/src/mcp/mod.rs#L84-L105)。
- [上游 MCP tool filter](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/codex-mcp/src/tools.rs#L63-L103)：`enabled_tools` 和 `disabled_tools` 只控制暴露。
- [上游 plugin MCP policy fields](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/config/src/types.rs#L853-L879)：插件 MCP 复用按 server/按工具策略，但仍是用户配置 overlay；[普通 MCP requirements identity matcher](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/config/src/mcp_requirements.rs#L68-L158) 不含 per-tool approval 字段。
- [上游 app-server README](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/app-server/README.md#L2096-L2124)：Apps 审批模式、默认值和优先级。
- [上游 Apps policy evaluator](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/connectors/src/app_tool_policy.rs#L149-L196)：managed tool approval 的优先级实现；[requirements 类型和解析测试](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/config/src/config_requirements.rs#L815-L895)。
- [上游 execpolicy README](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/execpolicy/README.md#L3-L24) 和 [exec policy loading/skip](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/core/src/exec_policy.rs#L307-L429)。
- [上游 requirements execpolicy 限制](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/config/src/requirements_exec_policy.rs#L122-L183)：managed `[rules]` 禁止 `allow`。
- [上游全局审批枚举](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/protocol/src/protocol.rs#L917-L958)：`untrusted`、`on-request`、`granular`、`never` 的命令审批语义；[CLI `--approve-for-me` 解析测试](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/codex-rs/cli/src/main.rs#L2982-L2997) 证明它启用 auto-review 而非关闭审批。
- [上游配置层路径和优先级](https://github.com/openai/codex/blob/be6e8eac029b183056b7e4402879f15d2c85f61b/config/src/loader/mod.rs#L82-L111)；本仓库默认文件为 [`config.toml`](../../config.toml#L1-L5)。
