# 安装和配置方案

本文是 CraneSched-Codex 的管理员操作手册。它描述 x86_64 EL9 节点上
RPM 的安装、首次配置、验证、升级、凭据轮换、BYOK 和卸载。项目只支持
通过 DNF 管理 RPM；不会在安装过程中猜测或生成上游 endpoint、token。

## 1. 安装前提

- x86_64 Rocky Linux、AlmaLinux 或 RHEL 9；
- root 权限；
- 节点能够访问 GitHub Release 或内部 RPM 镜像；
- 已启用能够提供 `bubblewrap` 和 `ripgrep` 的 EL9 软件源。

RPM 包含固定版本的 Codex、proxy wrapper、静态 systemd unit、系统默认
配置、CraneSched 只读 execpolicy 默认规则和 CraneSched Skill。真实上游配置
不在 RPM、Git、systemd unit 或构建产物中。

## 2. 安装 RPM

从 [最新 Release](https://github.com/Nativu5/CraneSched-Codex/releases/latest)
下载 RPM，并将其传到目标节点。只在一个只包含目标 RPM 的目录中执行：

```bash
sudo dnf install ./cranesched-codex-*.el9.x86_64.rpm
```

首次安装不会创建 `/etc/codex/proxy-upstream.conf`，也不会启动 proxy。
这是预期行为：管理员必须先写入 root-only 配置，服务才能读取上游信息。

安装后可以确认固定内容：

```bash
rpm -q cranesched-codex
codex --version
test -f /etc/codex/config.toml
test -f /etc/codex/rules/cranesched-readonly.rules
test -f /etc/codex/skills/cranesched-skill/SKILL.md
```

RPM 同时安装 root 管理的默认规则文件
`/etc/codex/rules/cranesched-readonly.rules`，默认允许只读的
`cqueue`、`cacct`、`ccontrol show job` 和 `ccontrol show step` 命令前缀。
CraneSched 服务端 ACL 仍然决定用户可以查看哪些记录。该系统文件只是默认值，
用户可以在更高优先级的 Codex 配置层增加更严格的规则。

`prefix_rule` 会匹配后续的全部参数。因此 `cqueue --iterate`、范围较大的
`cacct` 历史查询、JSON 输出以及替代的 `-C/--config` 路径都会被默认允许。
`ccontrol --json show job/step` 和 `ccontrol -J show job/step` 由于 JSON 是
子命令前的全局选项，已通过单独规则覆盖。显式 `allow` 规则会跳过审批提示，
并可能绕过 Codex command sandbox；该名单应继续限制为 CraneSched 只读客户端。
如果需要严格限制参数，应使用 root 管理的 wrapper，本次变更不包含该方案。

这些参数也有可用性风险：`cqueue --iterate` 会持续刷新并保持调度器查询，
范围较大的 `cacct` 会增加 accounting backend 负载，替代配置路径可能绕过站点
为查询设置的连接和限流参数。自动化和诊断应优先使用 `--self`、明确的 job/step
ID 和有限的 `--max-lines`，避免长时间 `--iterate`；发现调度器或 accounting
延迟升高时应停止查询并联系集群管理员。ACL 负责数据授权，不能消除这些资源
消耗风险。

管理员可以在不连接调度器的情况下验证已安装策略：

```bash
codex execpolicy check \
  --rules /etc/codex/rules/cranesched-readonly.rules cqueue
codex execpolicy check \
  --rules /etc/codex/rules/cranesched-readonly.rules \
  ccontrol show job 123
codex execpolicy check \
  --rules /etc/codex/rules/cranesched-readonly.rules \
  ccontrol update jobid=123 priority=1
```

前两个检查应报告 `"decision":"allow"`；update 命令不能报告显式的 `allow`。
修改规则文件后应重新启动 Codex 进程，使系统规则重新加载。

## 3. 创建上游配置

运行时唯一需要管理员修改的文件是：

```text
/etc/codex/proxy-upstream.conf
```

它必须是 `root:root` 所有、权限 `0600` 的普通文件，不能是符号链接。
内容严格为两行，并且两行都以换行符结束：

```text
<完整的 Responses endpoint>
<bearer token>
```

例如：

```text
https://gateway.example.edu/v1/responses
<administrator-held-token>
```

第一行必须是完整的 `http` 或 `https` URL，解析后的路径必须以
`/responses` 结尾，可以包含 query，但不能包含 fragment。非 loopback
上游必须使用 HTTPS。第二行 token 必须非空、长度不超过 1016，并且只含
ASCII 字母、数字、`-`、`_`。

先创建空文件，再用 `sudoedit` 写入内容，避免把 token 放在命令行参数中：

```bash
sudo install -d -m 0755 -o root -g root /etc/codex
sudo install -m 0600 -o root -g root /dev/null \
  /etc/codex/proxy-upstream.conf
sudoedit /etc/codex/proxy-upstream.conf
sudo chown root:root /etc/codex/proxy-upstream.conf
sudo chmod 0600 /etc/codex/proxy-upstream.conf
```

不要把 token 放进 shell history、Issue、PR、日志或诊断附件。wrapper 每次
启动都会再次检查 UID、文件类型、owner、mode、URL、token 和行数；任何失败
都会拒绝启动，并且不会打印 token。

## 4. 启动和验证

只查看文件 metadata 和第一行，不输出 token：

```bash
sudo stat --format='%F %a %U:%G' /etc/codex/proxy-upstream.conf
sudo sed -n '1p' /etc/codex/proxy-upstream.conf
sudo systemctl enable --now cranesched-codex-proxy.service
```

检查服务和 loopback listener：

```bash
sudo systemctl is-enabled cranesched-codex-proxy.service
sudo systemctl is-active cranesched-codex-proxy.service
sudo ss -ltnp '( sport = :617 )'
```

listener 应只有 `127.0.0.1:617`。非 Responses 路径会被拒绝，因此 readiness
探针返回 HTTP 403 是正常结果：

```bash
curl --silent --output /dev/null --write-out '%{http_code}\n' \
  http://127.0.0.1:617/__cranesched_codex_ready
```

确认系统默认配置可加载：

```bash
codex --strict-config doctor --json
```

完成本地检查后，管理员应使用一个最小的真实 Responses 请求确认上游可达；
不要把请求正文或响应正文写入共享日志。普通用户随后直接运行：

```bash
codex
```

系统安装的 CraneSched Skill 会被所有用户发现。Codex 返回的 `admin` scope
只是 `/etc/codex/skills` 系统路径带来的 loader 分类，不代表 Skill 仅供
管理员使用，也不改变 CraneSched 自身的权限控制。用户可以按名称禁用：

```toml
[[skills.config]]
name = "cranesched-skill"
enabled = false
```

## 5. 升级

下载新 RPM，在独立目录中通过同一条 DNF 命令升级：

```bash
sudo dnf install ./cranesched-codex-*.el9.x86_64.rpm
sudo systemctl restart cranesched-codex-proxy.service
```

升级前保留上一版本 RPM，直到 listener、readiness、Codex doctor 和最小真实
请求全部通过。RPM 不会把新 endpoint 或 token 写入配置，也不会替管理员轮换
凭据。

## 6. 轮换 endpoint 或 token

轮换时编辑同一个固定文件，并保持 `root:root 0600`：

```bash
backup_path="$(sudo mktemp /etc/codex/.proxy-upstream.conf.XXXXXX)"
sudo install -m 0600 -o root -g root \
  /etc/codex/proxy-upstream.conf "${backup_path}"
sudoedit /etc/codex/proxy-upstream.conf
sudo chown root:root /etc/codex/proxy-upstream.conf
sudo chmod 0600 /etc/codex/proxy-upstream.conf
sudo systemctl restart cranesched-codex-proxy.service
```

重复第 4 节验证。验证失败时恢复安全副本并重启：

```bash
sudo install -m 0600 -o root -g root \
  "${backup_path}" /etc/codex/proxy-upstream.conf
sudo systemctl restart cranesched-codex-proxy.service
sudo rm -f -- "${backup_path}"
unset backup_path
```

验证成功后也应删除临时副本。该流程由管理员控制，没有自动回滚或凭据
同步服务。

## 7. 用户 BYOK

系统配置只是低优先级 Managed Default，不是强制策略。用户可以在自己的
`~/.codex/config.toml`、profile 或 CLI `-c` 选项中选择其他 provider：

```toml
model = "user-selected-model"
model_provider = "my_provider"

[model_providers.my_provider]
name = "My provider"
base_url = "https://user-provider.example/v1"
wire_api = "responses"
env_key = "MY_PROVIDER_API_KEY"
```

用户自己的 `MY_PROVIDER_API_KEY` 只属于用户自己的 provider。共享 proxy 不会
拦截发送到用户 endpoint 的请求。

## 8. 故障排查

### DNF 缺少依赖

确认 EL9 软件源提供 `bubblewrap` 和 `ripgrep`：

```bash
sudo dnf repolist
sudo dnf install bubblewrap ripgrep
```

### wrapper 拒绝配置

不要输出第二行；只检查类型、owner、mode 和第一行：

```bash
sudo test ! -L /etc/codex/proxy-upstream.conf
sudo stat --format='%F %a %U:%G' /etc/codex/proxy-upstream.conf
sudo sed -n '1p' /etc/codex/proxy-upstream.conf
```

确认 URL 的路径以 `/responses` 结尾，token 没有空格或其他特殊字符，并且
文件最后一行有换行符。

### proxy 没有启动

```bash
sudo systemctl status cranesched-codex-proxy.service --no-pager
sudo journalctl -u cranesched-codex-proxy.service -n 100 --no-pager
sudo ss -ltnp '( sport = :617 )'
```

日志只应包含 metadata 和格式错误，不应包含 token。另一个进程占用 617 端口
或配置文件权限错误时，服务会保持失败状态。

### Codex 没有使用 Managed Default

```bash
codex --strict-config doctor --json
test ! -f ~/.codex/config.toml || \
  rg -n '^(model|model_provider|profile)[[:space:]]*=' ~/.codex/config.toml
```

用户配置、profile 和 CLI override 的优先级高于 `/etc/codex/config.toml`。

## 9. 卸载

只使用 DNF 卸载：

```bash
sudo dnf remove cranesched-codex
```

RPM 会停止并禁用 proxy，删除 Codex、系统配置和 Skill；手工创建的
`/etc/codex/proxy-upstream.conf` 也由 `%ghost` 包路径清理。被用户修改过的
`/etc/codex/config.toml` 可能以 RPM `.rpmsave` 文件保留。

## 相关文档

- [架构和安全边界](architecture-and-security.md)
- [项目文档索引](https://github.com/Nativu5/CraneSched-Codex/tree/main/docs)
- [安全运维规则](https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/agents/security-operations.md)
