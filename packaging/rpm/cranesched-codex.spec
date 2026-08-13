%global debug_package %{nil}
# The Codex executable is an upstream release artifact. Preserve it byte for
# byte so its packaged SHA-256 remains identical to the recorded provenance.
%global __strip /bin/true

Name:           cranesched-codex
Version:        %{codex_version}
Release:        %{package_release}%{?dist}
Summary:        CraneSched-Codex proxy and system-wide defaults for shared HPC nodes
License:        LicenseRef-Unspecified
URL:            https://github.com/Nativu5/CraneSched-Codex
Source0:        codex
Source1:        config.toml
Source2:        cranesched-codex-proxy.service
Source3:        cranesched-codex-proxy
Source4:        LICENSE
Source5:        NOTICE
Source6:        README.md
Source7:        PROVENANCE
Source8:        skills
Source9:        installation-and-configuration.md
Source10:       architecture-and-security.md
Source11:       cranesched-readonly.rules

ExclusiveArch:  x86_64
Requires:       bubblewrap
Requires:       coreutils
Requires:       procps-ng
Requires:       ripgrep
Requires:       systemd >= 239
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

%description
Installs a pinned native Codex binary, a hardened loopback Responses API proxy,
low-priority /etc/codex defaults, and the CraneSched Skill. The upstream
endpoint and bearer token are not part of the RPM and must be configured
manually after installation.

%prep

%build

%install
install -d -m 0755 %{buildroot}/etc/codex
install -d -m 0755 %{buildroot}/etc/codex/rules
install -d -m 0755 %{buildroot}/etc/codex/skills
install -d -m 0755 %{buildroot}/usr/bin
install -d -m 0755 %{buildroot}/usr/libexec/cranesched-codex
install -d -m 0755 %{buildroot}/usr/lib/systemd/system
install -d -m 0755 %{buildroot}/usr/share/doc/%{name}
install -d -m 0755 %{buildroot}/usr/share/licenses/%{name}

install -m 0644 %{SOURCE1} %{buildroot}/etc/codex/config.toml
install -m 0644 %{SOURCE11} \
    %{buildroot}/etc/codex/rules/cranesched-readonly.rules
cp -a %{SOURCE8}/. %{buildroot}/etc/codex/skills/
install -m 0755 %{SOURCE0} %{buildroot}/usr/libexec/cranesched-codex/codex
ln -s ../libexec/cranesched-codex/codex %{buildroot}/usr/bin/codex
install -m 0755 %{SOURCE3} %{buildroot}/usr/libexec/cranesched-codex/cranesched-codex-proxy
install -m 0644 %{SOURCE2} %{buildroot}/usr/lib/systemd/system/cranesched-codex-proxy.service
install -m 0644 %{SOURCE6} %{buildroot}/usr/share/doc/%{name}/README.md
install -m 0644 %{SOURCE9} \
    %{buildroot}/usr/share/doc/%{name}/installation-and-configuration.md
install -m 0644 %{SOURCE10} \
    %{buildroot}/usr/share/doc/%{name}/architecture-and-security.md
install -m 0644 %{SOURCE7} %{buildroot}/usr/share/doc/%{name}/PROVENANCE
install -m 0644 %{SOURCE4} %{buildroot}/usr/share/licenses/%{name}/CODEX-LICENSE
install -m 0644 %{SOURCE5} %{buildroot}/usr/share/licenses/%{name}/CODEX-NOTICE

%post
systemctl daemon-reload >/dev/null 2>&1 || :

%preun
if [ "$1" -eq 0 ]; then
    systemctl disable --now cranesched-codex-proxy.service >/dev/null 2>&1 || :
fi

%postun
systemctl daemon-reload >/dev/null 2>&1 || :
if [ "$1" -eq 0 ]; then
    systemctl reset-failed cranesched-codex-proxy.service >/dev/null 2>&1 || :
fi

%files
%defattr(-,root,root,-)
%dir %attr(0755,root,root) /etc/codex
%config(noreplace) %attr(0644,root,root) /etc/codex/config.toml
%dir %attr(0755,root,root) /etc/codex/rules
%config(noreplace) %attr(0644,root,root) /etc/codex/rules/cranesched-readonly.rules
%ghost %attr(0600,root,root) /etc/codex/proxy-upstream.conf
%dir %attr(0755,root,root) /etc/codex/skills
/etc/codex/skills/*
/usr/bin/codex
%dir %attr(0755,root,root) /usr/libexec/cranesched-codex
%attr(0755,root,root) /usr/libexec/cranesched-codex/codex
%attr(0755,root,root) /usr/libexec/cranesched-codex/cranesched-codex-proxy
%attr(0644,root,root) /usr/lib/systemd/system/cranesched-codex-proxy.service
%doc /usr/share/doc/%{name}/README.md
%doc /usr/share/doc/%{name}/installation-and-configuration.md
%doc /usr/share/doc/%{name}/architecture-and-security.md
%doc /usr/share/doc/%{name}/PROVENANCE
%license /usr/share/licenses/%{name}/CODEX-LICENSE
%license /usr/share/licenses/%{name}/CODEX-NOTICE

%changelog
* Tue Aug 11 2026 Cluster Administration <root@localhost> - %{codex_version}-%{package_release}
- Install the default CraneSched read-only execpolicy rules.
* Mon Jul 27 2026 Cluster Administration <root@localhost> - %{codex_version}-%{package_release}
- Initial CraneSched-Codex RPM with pinned Codex, proxy, and CraneSched Skill.
