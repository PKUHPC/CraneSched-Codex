# 架构和安全边界

本文说明 CraneSched-Codex 的运行时边界、凭据边界、Skill 所有权和明确的
非目标。它是设计参考，不替代[安装和配置方案](installation-and-configuration.md)。

## 目标和非目标

项目为共享 HPC 节点提供一个零用户初始化的 Managed Default：普通用户运行
Codex 时访问本机 loopback proxy，由高权限 proxy 代持管理员选择的上游
credential。用户可以覆盖默认 provider 使用自己的 BYOK。

项目不提供：

- 多用户认证、按用户限额或用量统计；
- 共享 credential 的自动分发、轮换或回滚；
- Codex fork、强制 provider 或禁止用户自定义 provider；
- 通过 MkDocs 站点发布 CraneSched Skill。

隐藏 credential 和控制共享额度是两个不同问题。任何能访问本机 proxy 的
用户都可能消耗共享上游额度，集群应通过自己的网络、账户和 CraneSched
权限机制处理授权与计费。

## 运行时组件

```text
ordinary-user Codex
    |
    | /etc/codex/config.toml (low-priority system default)
    v
http://127.0.0.1:617/v1/responses
    |
    v
cranesched-codex-proxy.service (static systemd unit, root)
    |
    v
cranesched-codex-proxy (root-only wrapper)
    |
    | endpoint in argv, token through stdin
    v
codex responses-api-proxy
    |
    v
administrator-selected upstream Responses endpoint
```

Codex 的系统配置只声明 loopback provider，不声明真实 endpoint 或 token。
proxy 只接受 `POST /v1/responses`，监听地址固定为 loopback；其他路径返回
403。systemd unit 保留文件系统、网络族、资源和 capability 限制，但不负责
传递可变 credential。

## 凭据边界

唯一的运行时配置文件是 `/etc/codex/proxy-upstream.conf`，由管理员创建为
`root:root 0600` 普通文件。它包含完整 Responses URL 和 bearer token 两行。

wrapper 在启动时：

1. 以 root 身份检查 UID、文件类型、owner 和 mode；
2. 校验 URL、token 字符集、长度、换行和行数；
3. 将 endpoint 作为 proxy 参数传入；
4. 将 token 通过 stdin 传给 proxy；
5. `exec` 进入 proxy，并清理 wrapper 中不再需要的变量。

因此 token 不进入：

- RPM payload 或 Git 历史；
- `/etc/codex/config.toml`；
- systemd unit、argv 或环境变量；
- 日志、Issue、PR、Actions 输出或测试 artifact。

endpoint 本身会出现在本机 proxy 的 argv 中，这是为支持可变上游地址而接受的
本地可见信息；真正的 bearer token 不会出现在 argv 中。非 loopback endpoint
必须使用 HTTPS，且管理员应限制 endpoint 的 DNS、网络和证书信任边界。

## Managed Default 与 BYOK

`/etc/codex/config.toml` 是低优先级系统层。它选择 `cluster_shared` provider
并设置 `requires_openai_auth = false`，所以用户不需要共享 API key 即可启动
Codex。

Codex 用户配置、profile 和 CLI override 可以选择另一个 provider。BYOK 的
credential 由用户自己管理，shared proxy 不会拦截发往用户 endpoint 的请求。
这满足“默认易用、用户可覆盖”的目标，而不是实现强制策略。

## CraneSched Skill 所有权

Skill 的唯一源文件位于 CraneSched 主仓库：

```text
PKUHPC/CraneSched/docs/skills/
```

CraneSched 的 PR 负责审查 Skill 内容；其 `mkdocs.yaml` 用 `exclude_docs` 将
`skills/**` 排除在 served site 外。CraneSched-Codex 只通过锁定的
`submodules/CraneSched` gitlink 校验并把该目录复制进 RPM：

```text
/etc/codex/skills/
```

Skill 面向所有 CraneSched 用户和一线支持人员。Codex 对 `/etc/codex/skills`
返回的 `admin` scope 只是系统安装位置的 loader 分类，不是管理员专用权限，
也不会绕过 CraneSched 自身权限控制。用户可以按名称禁用该 Skill。

## RPM 和更新边界

RPM 是唯一部署路径，包含：

- Source Lock 指定的 Codex 二进制；
- 静态 proxy wrapper 和 systemd unit；
- `/etc/codex/config.toml`；
- `/etc/codex/rules/cranesched-readonly.rules`；
- 锁定 CraneSched 提供的 Skill；
- README、安装配置文档、架构说明和 provenance。

构建 helper 会初始化子模块、检查 gitlink、拒绝 dirty checkout、校验 Skill
树，并在同一文件系统的临时目录中原子 staging。构建和 RPM payload 校验阶段
拒绝符号链接、特殊文件、可写路径和缺少 `SKILL.md` 的 Skill；安装阶段只安装
已经校验过的 payload。

Skill 更新是两仓库流程：先在 CraneSched 合并内容，再更新本仓库 gitlink，
最后由 Compatibility CI 和 RPM/DNF 测试验证。Codex 升级只更新 Codex Source
Lock 和 Codex 子模块，不移动 CraneSched gitlink。

## 运行限制

本方案有意保持简单，但管理员仍应注意：

- loopback proxy 没有入站认证；
- 任意本地用户可能调用它并消耗共享额度；
- `cqueue`、`cacct` 和作业/步骤详情查询的系统 execpolicy allow 规则会跳过
  Codex 审批，并可能绕过命令 sandbox；规则文件不是 CraneSched 授权替代品；
- `cqueue --iterate` 和范围较大的 `cacct` 查询仍可能增加调度器或 accounting
  backend 负载；站点应通过命令用法、监控和自身限流策略处理可用性；
- 不应启用 proxy 的 shutdown 或 dump body 功能；
- 代理日志和诊断输出不得包含 credential、完整请求或响应；
- 生产 endpoint 应使用 HTTPS、固定可信 DNS 和最小网络可达范围。

## 决策索引

- [Managed Default 与 BYOK](https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/adr/0001-managed-default-with-user-byok.md)
- [root 直接读取 proxy 配置](https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/adr/0005-read-proxy-configuration-directly-as-root.md)
- [从 CraneSched 子模块获取 Skill](https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/adr/0006-source-cranesched-skills-from-upstream-submodule.md)
- [安全运维](https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/agents/security-operations.md)
