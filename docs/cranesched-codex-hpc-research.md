# HPC 共享集群上的 CraneSched-Codex：默认服务方案

## 摘要

本文基于工作区中的 Codex 源码，研究在 HPC 共享集群上提供一个开箱即用的 Codex 服务。修正后的需求边界是：

1. 管理员提供一个默认模型 API 服务，真实上游 API Key 不进入普通用户的进程、环境变量或文件；
2. 不需要区分或认证集群中的不同用户，所有能访问代理的用户都可以共享使用；
3. 管理员配置只是默认值，不需要锁死；用户可以覆盖配置并 BYOK；
4. 管理员在 RPM 中提供集群级默认 Skills，使用 Codex 的 Admin skill discovery 机制；Skills 默认可用，但用户可以按名称禁用。

源码基线：`submodules/codex` commit `61a44880a85d2fd0d8770908dea5733495e571c8`（2026-07-26）。官方文档交叉核验来源包括 [Config basics](https://learn.chatgpt.com/docs/config-file/config-basic)、[Managed configuration](https://learn.chatgpt.com/docs/enterprise/managed-configuration) 和 [Build skills](https://learn.chatgpt.com/docs/build-skills)。

结论很直接：

- 使用 root 或独立 service UID 运行一个无入站认证的 Responses API proxy，由代理代持并注入真实上游 Key；普通用户的 Codex 只访问代理，不获得任何 Key。
- 在 `/etc/codex/config.toml` 中配置一个无客户端认证的 custom provider，指向共享代理。System config 本来就是低优先级默认层，正好允许用户通过 `~/.codex/config.toml`、profile 或 CLI 配置 BYOK。
- 不需要修改 Codex、不需要 `/etc/codex/managed_config.toml`、不需要新增 provider requirements、不需要 token broker、Slurm 身份绑定或按 UID 签发短期 token。
- 不应使用 `auth.command` 返回真实上游 Key。该协议会把 token 经 stdout 交给用户 UID 下的 Codex；隐藏真实 Key 的正确位置是独立权限域中的代理。
- RPM 将仓库 `skills/` 完整安装到 `/etc/codex/skills/<name>/`，作为可被用户禁用的管理员默认值，不修改 Codex 加载器。

推荐架构：

```text
User Codex / curl
       |
       | HTTP(S), no client credential
       v
Shared Responses API proxy (root or service UID)
       - only accepts the required API path
       - strips any client Authorization header
       - injects the real upstream Key
       - does not dump request/response bodies
       |
       | HTTPS + real upstream Key
       v
Upstream model API
```

这个设计保证的是“用户看不到真实 Key”，不是“用户只能通过 Codex 使用共享额度”。由于不做入站认证，用户可以直接调用代理并消耗共享额度；这是修正后需求明确接受的边界。

## 1. 为什么 `/etc/codex/config.toml` 正好适合

Unix 系统配置固定路径是 `/etc/codex/config.toml`：`submodules/codex/codex-rs/config/src/loader/mod.rs:54-55,652-655`。

普通配置的相关优先级从低到高是：

1. System：`/etc/codex/config.toml`
2. Enterprise-managed config bundle
3. User：`~/.codex/config.toml`
4. User profile
5. trusted Project config
6. Session flags，例如 `-c key=value`

层级定义见 `submodules/codex/codex-rs/config/src/config_layer_source.rs:28-47`，加载顺序见 `submodules/codex/codex-rs/config/src/loader/mod.rs:225-367`。

这意味着管理员可以提供默认 provider，而用户仍可覆盖它。此前把 System 层可覆盖视为问题，是基于“必须强制端点”的旧假设；在允许 BYOK 的需求下，这是需要保留的行为。

项目配置有额外保护：repo 中的 `.codex/config.toml` 不能修改 `model_provider`、`model_providers`、`openai_base_url` 等凭据路由字段，避免恶意仓库改变凭据发送目的地；限制见 `submodules/codex/codex-rs/config/src/loader/mod.rs:60-76`。用户本人仍可在用户配置、profile 或 CLI session override 中配置 BYOK。

不需要使用 legacy `/etc/codex/managed_config.toml`。它是高优先级兼容层，会削弱“用户可以覆盖默认值”的预期，而且源码已经将其标记为 best-effort legacy 机制：`submodules/codex/codex-rs/config/src/loader/mod.rs:369-373`。

## 2. 默认 provider 配置

建议的 `/etc/codex/config.toml`：

```toml
# 当前共享服务的默认模型。
model = "gpt-5.6-sol"
model_provider = "cluster_shared"
model_reasoning_effort = "xhigh"

[model_providers.cluster_shared]
name = "PKU CraneSched-Codex Proxy"
base_url = "http://127.0.0.1:617/v1"
wire_api = "responses"
requires_openai_auth = false
```

如果使用中央代理，将 `base_url` 改为内部 HTTPS 地址：

```toml
[model_providers.cluster_shared]
name = "Cluster Shared Codex Service"
base_url = "https://codex-gateway.internal.example/v1"
wire_api = "responses"
requires_openai_auth = false
```

`ModelProviderInfo` 原生支持 `base_url`、`wire_api` 和 `requires_openai_auth`：`submodules/codex/codex-rs/model-provider-info/src/lib.rs:86-144`。这里故意不配置：

- `env_key`
- `experimental_bearer_token`
- `[model_providers.cluster_shared.auth]`

因此普通用户的 Codex 不需要登录，也不持有共享 API Key。真正的 `Authorization` header 只在高权限代理向上游发请求时生成。

如果代理要求一个无价值的固定占位 header，可以由代理直接忽略或覆盖客户端 header；没有必要把真实 Key 或等价 bearer 发给 Codex。

## 3. 用户 BYOK

用户可以在 `~/.codex/config.toml` 中选择自己的 provider：

```toml
model = "user-selected-model"
model_provider = "my_provider"

[model_providers.my_provider]
name = "My provider"
base_url = "https://user-provider.example/v1"
wire_api = "responses"
env_key = "MY_PROVIDER_API_KEY"
```

然后在自己的 shell 中设置：

```bash
export MY_PROVIDER_API_KEY="..."
codex
```

用户也可以用 profile 或 `-c` 做临时覆盖。`-c` 支持 dotted-path TOML override，实现在 `submodules/codex/codex-rs/utils/cli/src/config_override.rs:15-83`。

管理员不需要为 BYOK 做额外开发。只要集群网络策略允许用户访问其自选 provider，现有配置优先级就会自然工作。

## 4. 隐藏真实 Key 的正确边界

### 4.1 不把 Key 放进 Codex 配置或环境

以下方案都不满足“用户看不到真实 Key”：

- 在 `/etc/codex/config.toml` 中写 `experimental_bearer_token`；
- 在用户可继承的环境中设置 `OPENAI_API_KEY`；
- 把 Key 存在用户可读的 `auth.json`；
- 让 provider `auth.command` 输出真实 Key。

文件认证模式会把凭据写到 `$CODEX_HOME/auth.json`；其结构和 0600 文件写入逻辑见 `submodules/codex/codex-rs/login/src/auth/storage.rs:31-50,129-191`。0600 只能防止其他 UID，不能防止文件所有者本人读取。

命令认证会启动 helper、捕获 stdout，并把完整 stdout trim 后作为 bearer 缓存在 Codex 内存中：`submodules/codex/codex-rs/login/src/auth/external_bearer.rs:32-73,102-170`。所以它适合获取用户本来就有权看到的凭据，不适合向用户 UID 隐藏共享真实 Key。

### 4.2 由独立权限域的代理持有 Key

代理应以 root 或专用 service UID 运行，Key 只存在于：

- root/service-only 的 secret 文件、systemd credential 或外部 secret store；
- 代理进程内存；
- 代理到上游的 TLS 请求 header。

普通用户只向代理发送 prompt、模型参数和工具定义。共享 Key 不出现在用户 Codex 的配置、环境、命令行、stdin/stdout、日志或进程内存中。

代理必须覆盖而不是透传客户端 `Authorization` header，并固定上游地址。这样用户无法通过请求让代理把真实 Key 转发到其他目的地。

## 5. 源码自带的代理

仓库包含 `cranesched-codex-proxy`，与当前需求高度匹配：

- 高权限进程从 stdin 读取真实 Key；
- 只接受 `POST /v1/responses`；
- 丢弃客户端传入的 `Authorization`；
- 向固定上游注入 `Authorization: Bearer <real-key>`；
- 其他路径返回 403。

行为说明见 `submodules/codex/codex-rs/responses-api-proxy/README.md:29-40,59-80`，请求过滤和 header 替换实现见 `submodules/codex/codex-rs/responses-api-proxy/src/lib.rs:138-204`。

它还进行了针对 Key 的进程加固：

- 启动前禁用 core dump 和 ptrace attach；
- 清理危险的动态链接环境变量；
- 读取 Key 后清零临时缓冲区；
- 尝试对常驻 Key 内存执行 `mlock(2)`。

入口见 `submodules/codex/codex-rs/responses-api-proxy/src/main.rs:4-7`，Key 读取见 `submodules/codex/codex-rs/responses-api-proxy/src/read_api_key.rs:72-180`，通用进程加固见 `submodules/codex/codex-rs/process-hardening/src/lib.rs:8-54`。

### 5.1 生产使用注意事项

在当前需求下，没有入站多用户认证不是问题，但仍应遵守：

- 不启用 `--http-shutdown`，否则任意本地用户可以关闭代理；
- 不启用 `--dump-dir`，它会记录完整 request/response body；
- 固定 `--upstream-url`，不能让客户端选择；
- 代理进程和 secret 文件均不可由普通用户写入或调试；
- 代理日志不得打印 request header、真实 Key 或完整 prompt/response；
- 用固定版本、systemd restart policy 和健康检查保证服务可用性。

源码 README 明确说明 `--http-shutdown` 和 `--dump-dir` 的行为：`submodules/codex/codex-rs/responses-api-proxy/README.md:53-79`。

### 5.2 单节点代理与中央代理

| 方案 | 优点 | 代价 |
| --- | --- | --- |
| 每个 login/compute 节点运行代理 | 配置简单，可直接使用源码自带的 loopback proxy | Key 要分发到更多节点，代理实例更多 |
| 中央内部代理 | Key 副本少，升级和监控集中 | 需要内部服务地址、TLS、容量和高可用 |

源码自带代理固定绑定 `127.0.0.1`，适合单节点或每节点部署：`submodules/codex/codex-rs/responses-api-proxy/src/lib.rs:138-142`。若已有内部 API gateway，中央方案通常更易运维；由于不要求用户认证，可以仅依赖集群内部网络可达性。

无论选哪一种，所有可访问代理的用户都能直接用 `curl` 调用并消耗共享额度。隐藏 Key 与控制用量是两个不同目标；当前范围只解决前者。

## 6. 管理员默认 Skills

当前部署将仓库中的 Skills 安装为：

```text
/etc/codex/skills/
  cranesched-skill/
    SKILL.md
    agents/
      openai.yaml
    references/
```

Codex 会从 System config 所在目录派生 `/etc/codex/skills`，并将其标记为 Admin scope：`submodules/codex/codex-rs/core-skills/src/loader.rs:292-370`。官方 [Build skills](https://learn.chatgpt.com/docs/build-skills) 也将该路径列为 Admin skill location。

Skills 使用渐进式加载：

1. 启动时发现 `name`、`description` 和路径；
2. 默认把可用 Skill 的元数据放入模型上下文；
3. 用户显式 `$skill-name` 或模型匹配描述时，才读取完整 `SKILL.md`。

模型上下文构造见 `submodules/codex/codex-rs/core/src/context/available_skills_instructions.rs:1-52`，正文注入见 `submodules/codex/codex-rs/core-skills/src/injection.rs:72-126`。

用户可以通过 `[[skills.config]]` 按名称禁用某个 Skill；规则实现见 `submodules/codex/codex-rs/core-skills/src/config_rules.rs:16-88`。这适合“提供默认值但不强制”的模式，因此不需要新增 Skills requirements 或修改加载器。

```toml
[[skills.config]]
name = "cranesched-skill"
enabled = false
```

RPM 将 `/etc/codex/skills` 作为包管理内容统一升级和卸载。管理员应在本仓库 `skills/` 修改内容、提升 RPM release 并灰度发布，不应直接编辑各节点副本。构建和原始安装都会拒绝符号链接、特殊文件、组/全局可写路径以及缺少 `SKILL.md` 的顶层 Skill。

如果只是希望 Skill 更容易自动触发，应优化 `SKILL.md` 的 `description`，而不是强制每轮注入全文。Skill 中也不应包含真实 Key。

## 7. `requirements.toml` 是否需要

隐藏共享 Key 和提供默认 provider 本身不需要 `/etc/codex/requirements.toml`。

只有集群还希望统一限制下列行为时，才单独使用 requirements：

- sandbox/permission profile；
- approval policy；
- login shell；
- Codex 工具子进程的网络范围；
- deny-read 路径；
- managed hooks、MCP 或 plugin policy。

当前 requirements schema 没有 provider/base URL/Skills 强制字段：`submodules/codex/codex-rs/config/src/config_requirements.rs:873-914`。在修正后的需求里，这不再是缺口。

还需注意 Codex sandbox 约束的是 Codex 启动的工具子进程，不是用户自己的 shell，也不是 Codex 主进程的 provider HTTP 请求。因此它不是隐藏代理 Key 的必要组成部分。

## 8. 不需要实现的组件

基于修正后的需求，以下内容均不需要：

- Codex fork 或 managed build；
- provider invariant 或 App Server provider override 过滤；
- 禁止 `--oss`、`--local-provider` 或用户自定义 provider；
- legacy `/etc/codex/managed_config.toml`；
- provider `auth.command`；
- 用户级短期 token、JWT、MUNGE token 或 Slurm job token；
- Unix peer credential 检查；
- 按 UID/作业配额和审计身份；
- 阻止用户禁用 Admin Skills；
- 为了共享服务而封锁用户 BYOK 的网络出口。

如果未来新增“防止滥用共享额度”或“必须只走管理员 provider”的要求，再引入认证、配额、egress policy 或 Codex 补丁。不要为当前需求提前承担这些复杂度。

## 9. 实施步骤

1. 构建包含固定版 `codex`、代理和管理员 Skills 的 `cranesched-codex` RPM，并声明 `bubblewrap`、`ripgrep` 为 DNF 运行时依赖。
2. 在每个需要提供服务的节点运行 `cranesched-codex.sh install --rpm ...`。管理脚本使用 DNF 安装或升级 RPM，再从管理员配置中严格提取 `pku` provider 的 endpoint 和 token，验证 endpoint 后将 token 写入 root-only systemd credential 文件。
3. 以 systemd `DynamicUser` 启动代理。Key 经 credential wrapper 送入代理 stdin，不进入 argv 或环境变量；不启用 shutdown 和 dump 功能。
4. 安装 `/etc/codex/config.toml`，将 `cluster_shared` custom provider 指向 `http://127.0.0.1:617/v1`，并设置 `requires_openai_auth = false`。
5. 安装仓库 `skills/` 到 `/etc/codex/skills`，用 `skills/list` 验证其 scope 为 `admin` 且默认启用。
6. 用普通用户账号运行默认 provider、BYOK 覆盖和按名称禁用 Skill 的验收测试。
7. 通过集群镜像或配置管理在所有 login/compute 节点使用 DNF 分发固定版本，并建立统一的升级、Skills 更新和 Key 轮换流程。

`cranesched-codex.sh` 不是第二套安装器，而是 DNF 安装、产物检查、凭据注入和上游验证的薄编排层。只拿到 RPM 的管理员可以先执行 `dnf install ./cranesched-codex-*.rpm`，再运行 RPM 自带的 `cranesched-codex-provision --source-config ... --verify-upstream`；由于 Key 不进入包体，单独执行 DNF 只会安装软件和依赖，不会让共享服务在无凭据状态下启动。

## 10. 验收测试

### 真实 Key 隔离

- 普通用户的环境变量、`~/.codex/auth.json`、配置、进程参数和日志中没有共享 Key。
- 普通用户不能读取代理的 secret 文件或进程内存。
- 代理请求上游成功，客户端请求中不需要 `Authorization`。
- 客户端伪造 `Authorization` 时，代理仍覆盖它，不向上游透传。
- 代理错误、重启和健康检查日志不包含 Key。
- 未启用 request/response dump。

### 默认值和 BYOK

- 无用户配置时，Codex 默认使用 `cluster_shared`。
- 用户在 `~/.codex/config.toml` 中选择自己的 provider 后生效。
- profile 和 CLI session override 可以临时切换 provider。
- 用户 BYOK 不会改变或暴露共享代理的上游 Key。

### 部署包验证

- `proxy/tests/test.sh` 使用 dummy token 和本地 mock upstream 验证路径限制、请求转发以及客户端 `Authorization` 覆盖。
- 可选的真实上游 smoke test 只验证请求成功，不打印 token 或响应正文。
- systemd runtime test 验证 `DynamicUser`、credential wrapper、低端口监听、SELinux domain 和代理转发行为。
- system config runtime test 验证 `/etc/codex/config.toml` 的系统默认层、用户 BYOK 覆盖、Admin skill discovery 和用户禁用覆盖。

### 管理员 Skills

- RPM payload 与仓库 `skills/` 的文件、目录和内容完全一致，所有对象由 root 管理且普通用户不可写。
- 无用户配置时，`cranesched-skill` 的 scope 为 `admin`、`enabled=true`。
- 用户按名称配置 `enabled=false` 后该 Skill 停用，但系统文件不被修改。
- RPM 最终卸载时完整移除 `/etc/codex/skills`。

最终验收标准是：普通用户无需配置凭据即可使用默认共享 Codex 服务，并自动获得管理员提供的集群 Skills；真实上游 Key 始终只存在于管理员控制的代理安全域中；同时用户保留覆盖默认 provider、使用自己 Key 和禁用默认 Skill 的自由。
