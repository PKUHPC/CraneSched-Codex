# 可配置上游 Endpoint 的最终方案

## 结论

CraneSched-Codex 不提供 provisioner，也不让 systemd 转交 credential。
RPM 只安装静态程序、静态 systemd unit、Codex 系统默认配置、Admin Skills
和操作文档。部署管理员以 root 身份手工维护唯一的运行时配置：

```text
/etc/codex/proxy-upstream.conf
```

这个方案不兼容旧节点，也不提供自动迁移或自动回滚。项目仍处于早期阶段，管理员按
README 完成首次配置、启动、验证和后续轮换。

## 固定与可变内容

RPM 中的固定内容：

- 官方 Codex 二进制和 `/usr/bin/codex` 链接；
- proxy wrapper；
- `cranesched-codex-proxy.service`；
- 指向 `http://127.0.0.1:617/v1` 的 `/etc/codex/config.toml`；
- `/etc/codex/skills` 下的 Admin Skills；
- README、PROVENANCE、LICENSE 和 NOTICE。

部署时唯一可变内容是 `/etc/codex/proxy-upstream.conf`。真实 endpoint 和 token
不进入 Git、RPM payload、systemd unit、进程环境或日志。

## 配置文件接口

配置文件固定为普通文件 `root:root 0600`，不能是符号链接。格式只有两行：

```text
<exact-responses-url>
<bearer-token>
```

例如：

```text
https://gateway.example.edu/v1/responses
<administrator-held-token>
```

两行都必须以换行符结束，且不能存在第三行。第一行必须是完整的 `http` 或 `https`
Responses URL，解析后的路径以 `/responses` 结尾，允许 query 但不允许 fragment；非
loopback 部署应使用 HTTPS。第二行 token 必须非空、最长 1016 字符，且只允许 ASCII
字母、数字、`-` 和 `_`。

wrapper 在每次启动时检查调用 UID、文件类型、符号链接、owner、mode 和两行内容。它用
独立文件描述符完成校验，再读取第一行并显式传入 `--upstream-url`，然后让文件描述符的
剩余内容成为 Proxy stdin。token 不进入 argv 或环境；endpoint 会出现在本机的 Proxy
argv 中。

## 启动模型

```text
ordinary-user Codex
  -> /etc/codex/config.toml
  -> http://127.0.0.1:617/v1/responses
  -> static systemd unit
  -> root-running wrapper
  -> codex responses-api-proxy
  -> administrator-selected upstream
```

配置是 `root:root 0600` 且不经 systemd credential 转交，因此 wrapper 和 `exec`
后的 Proxy 必须以 root 运行。unit 删除 `DynamicUser=` 和 `LoadCredential=`，但保留
`NoNewPrivileges=`、capability bounding、只读系统、私有临时目录、地址族限制及资源限制。

## 手工运维流程

管理员通过 DNF 安装 RPM。首次安装不创建配置，也不启动 proxy。管理员随后：

1. 用 `install` 创建 `/etc/codex/proxy-upstream.conf`，设置 `root:root 0600`；
2. 用 `sudoedit` 写入完整 endpoint 和 token；
3. 只检查文件 metadata 和第一行，不输出第二行；
4. `systemctl enable --now cranesched-codex-proxy.service`；
5. 检查 loopback listener、403 readiness 和 Codex system config；
6. 发送一个最小真实 Responses 请求。

轮换 endpoint 或 token 时，管理员保留上一份安全副本，编辑同一文件，恢复 owner/mode，
restart 后重复验证。该流程没有自动回滚；真实验证失败时由管理员恢复上一份内容并再次
restart。

卸载通过 DNF 完成。RPM 将手工创建的路径声明为 `%ghost`，所以最终卸载会停止 unit 并
删除 proxy upstream 配置。

完整命令、验证和故障排查步骤以仓库 README 及 RPM 内附 README 为准。

## 实现范围

- 删除 `packaging/rpm/cranesched-codex-provision`；
- 删除 `proxy/extract_provider_credential.py`；
- wrapper 改为直接读取固定配置；
- systemd unit 移除站点 URL、`DynamicUser=` 和 `LoadCredential=`；
- RPM 移除 provisioner、extractor 及其 Python/Bash 运行时依赖；
- 仓库管理脚本的 install 只执行 DNF，不再配置或启动；
- README 和 security operations 记录全部手工操作；
- proxy、RPM、DNF 和 installed-node 测试保护新接口。

## Public 前的独立工作

删除当前树中的真实站点 URL 不会清除 Git 可达历史和既有 Release RPM。历史重写与旧
Release 资产删除仍是公开仓库前的独立发布操作，不属于本次运行时改造。
