# 文档索引

CraneSched-Codex 的文档按读者和用途分层。新部署先读安装手册；需要理解
凭据、代理或 Skill 边界时再读架构说明。

## 用户和管理员

- [安装和配置方案](installation-and-configuration.md)：安装、首次配置、
  启动、验证、升级、凭据轮换、BYOK、故障排查和卸载。
- [架构和安全边界](architecture-and-security.md)：Managed Default、proxy、
  root-only credential、Skill 所有权和系统限制。

## 贡献者和维护者

- [开发流程](agents/development-workflow.md)：Issue、分支、提交、测试和
  Standards/Spec review 规则。
- [Upgrade Train](agents/upgrade-train.md)：Codex Source Lock、Compatibility
  CI 和 RPM Release 流程。
- [安全运维](agents/security-operations.md)：credential、发布和事故处理边界。
- [领域上下文](agents/domain.md)：项目术语和 ADR 阅读入口。

## 架构决策记录

- [Managed Default 与 BYOK](adr/0001-managed-default-with-user-byok.md)
- [官方 Codex artifact](adr/0002-package-official-codex-artifacts.md)
- [只从 committed state 发布](adr/0003-release-only-from-committed-state.md)
- [高价值测试](adr/0004-prefer-high-value-tests-and-fast-feedback.md)
- [root 直接读取 proxy 配置](adr/0005-read-proxy-configuration-directly-as-root.md)
- [从 CraneSched 子模块获取 Skill](adr/0006-source-cranesched-skills-from-upstream-submodule.md)

## 上游来源

CraneSched Skill 的内容源在
[`PKUHPC/CraneSched/docs/skills/`](https://github.com/PKUHPC/CraneSched/tree/master/docs/skills)。
该目录由 CraneSched 维护并从其 MkDocs 输出中排除；本仓库只负责把锁定提交
打包进 RPM。
