%undefine _debugsource_packages

Name:           jev-pam
Version:        0.1.0
Release:        1%{?dist}
Summary:        PAM module that asks Jev
License:        MIT
URL:            https://github.com/psyclyx/jev-pam
Source0:        %{name}-%{version}.tar.gz

ExclusiveArch:  %{zig_arches}
BuildRequires:  zig >= 0.16
BuildRequires:  zig-rpm-macros
BuildRequires:  pam-devel
Requires:       ca-certificates

%description
A PAM module that sends the details of a login attempt to Jev, TypeSafe AI's
decision model, and lets the user in if Jev says yes.

%prep
%autosetup

%build
%zig_prep
%zig_build

%install
%zig_install

%check
%zig_build test

%files
%license LICENSE
%doc README.md
%{_libdir}/security/pam_jev.so

%changelog
* Fri Oct 02 2026 psyclyx <me@psyclyx.xyz> - 0.1.0-1
- Initial package
