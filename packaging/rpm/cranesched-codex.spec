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
Source4:        extract_provider_credential.py
Source5:        cranesched-codex-provision
Source6:        LICENSE
Source7:        NOTICE
Source8:        README.md
Source9:        PROVENANCE
Source10:       skills

ExclusiveArch:  x86_64
Requires:       bash
Requires:       bubblewrap
Requires:       coreutils
Requires:       procps-ng
Requires:       python3 >= 3.9
Requires:       python3-tomli
Requires:       ripgrep
Requires:       systemd >= 247
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

%description
Installs a pinned native Codex binary, a hardened loopback Responses API proxy,
a low-priority /etc/codex/config.toml default, and administrator Skills. The
upstream bearer token is not part of the RPM and must be provisioned after
installation.

%prep

%build

%install
install -d -m 0755 %{buildroot}/etc/codex
install -d -m 0755 %{buildroot}/etc/codex/skills
install -d -m 0755 %{buildroot}/usr/bin
install -d -m 0755 %{buildroot}/usr/libexec/cranesched-codex
install -d -m 0755 %{buildroot}/usr/lib/systemd/system
install -d -m 0755 %{buildroot}/usr/sbin
install -d -m 0755 %{buildroot}/usr/share/doc/%{name}
install -d -m 0755 %{buildroot}/usr/share/licenses/%{name}

install -m 0644 %{SOURCE1} %{buildroot}/etc/codex/config.toml
cp -a %{SOURCE10}/. %{buildroot}/etc/codex/skills/
install -m 0755 %{SOURCE0} %{buildroot}/usr/libexec/cranesched-codex/codex
ln -s ../libexec/cranesched-codex/codex %{buildroot}/usr/bin/codex
install -m 0755 %{SOURCE3} %{buildroot}/usr/libexec/cranesched-codex/cranesched-codex-proxy
install -m 0755 %{SOURCE4} %{buildroot}/usr/libexec/cranesched-codex/extract_provider_credential.py
install -m 0644 %{SOURCE2} %{buildroot}/usr/lib/systemd/system/cranesched-codex-proxy.service
install -m 0755 %{SOURCE5} %{buildroot}/usr/sbin/cranesched-codex-provision
install -m 0644 %{SOURCE8} %{buildroot}/usr/share/doc/%{name}/README.md
install -m 0644 %{SOURCE9} %{buildroot}/usr/share/doc/%{name}/PROVENANCE
install -m 0644 %{SOURCE6} %{buildroot}/usr/share/licenses/%{name}/CODEX-LICENSE
install -m 0644 %{SOURCE7} %{buildroot}/usr/share/licenses/%{name}/CODEX-NOTICE

%post
systemctl daemon-reload >/dev/null 2>&1 || :
if [ "$1" -gt 1 ] && [ -s /etc/codex/proxy-api-key ] && \
        systemctl is-active --quiet cranesched-codex-proxy.service; then
    systemctl restart cranesched-codex-proxy.service >/dev/null 2>&1 || :
fi

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
%ghost %attr(0400,root,root) /etc/codex/proxy-api-key
%dir %attr(0755,root,root) /etc/codex/skills
/etc/codex/skills/*
/usr/bin/codex
%dir %attr(0755,root,root) /usr/libexec/cranesched-codex
%attr(0755,root,root) /usr/libexec/cranesched-codex/codex
%attr(0755,root,root) /usr/libexec/cranesched-codex/cranesched-codex-proxy
%attr(0755,root,root) /usr/libexec/cranesched-codex/extract_provider_credential.py
%attr(0644,root,root) /usr/lib/systemd/system/cranesched-codex-proxy.service
%attr(0755,root,root) /usr/sbin/cranesched-codex-provision
%doc /usr/share/doc/%{name}/README.md
%doc /usr/share/doc/%{name}/PROVENANCE
%license /usr/share/licenses/%{name}/CODEX-LICENSE
%license /usr/share/licenses/%{name}/CODEX-NOTICE

%changelog
* Mon Jul 27 2026 Cluster Administration <root@localhost> - %{codex_version}-%{package_release}
- Initial CraneSched-Codex RPM with pinned Codex, proxy, and Admin Skills.
